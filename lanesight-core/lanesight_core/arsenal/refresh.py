"""Weekly catalog refresh helpers (runbook: data/ball_catalog/REFRESH.md).

    # 1. merge a freshly collected lineup into the brand's raw file (retires balls no longer listed)
    python -m lanesight_core.arsenal.refresh merge data/ball_catalog/raw/storm.json fresh/storm.json --today 2026-10-26
    # 2. rebuild catalog.json + seed SQL (build_seed), then summarize what changed for the PR
    python -m lanesight_core.arsenal.refresh summarize old_catalog.json data/ball_catalog/catalog.json
    # 3. check every stock-photo link still returns an image
    python -m lanesight_core.arsenal.refresh check-images data/ball_catalog/catalog.json
    # 4. after merge: compare fingerprints; if they differ, upsert only rows whose source_hash differs
    python -m lanesight_core.arsenal.refresh digest data/ball_catalog/catalog.json
    python -m lanesight_core.arsenal.refresh sync-sql data/ball_catalog/catalog.json db_hashes.json --out-dir sync/

Rules (same as the original build):
- Never delete. A ball missing from a manufacturer's current lineup becomes status 'discontinued' with
  discontinued_on; if it reappears it goes back to 'current'.
- Never guess. Fresh records follow RECORD_SPEC: unpublished values are null and listed in `missing`.
- A collection that looks broken (empty, or dropping too many current balls at once) is refused, not merged.
"""
from __future__ import annotations
import argparse, json, sys, urllib.request
from datetime import date
from pathlib import Path

from .catalog import catalog_key, validate
from .build_seed import row_values, row_hash, to_sql, HASH_EXCLUDE

MAX_RETIRE_FRACTION = 0.30     # a fresh lineup that retires >30% of a brand's current balls is treated as a bad scrape


class RefreshError(Exception):
    pass


def _key(r):
    return catalog_key(r)


def merge_brand(old: list[dict], fresh: list[dict], today: str, force: bool = False) -> tuple[list[dict], dict]:
    """old: the brand's raw records (current + previously discontinued). fresh: this week's collected current lineup.
    Returns (merged records, report). Fresh records replace old ones with the same key; old current balls absent
    from fresh are retired; previously discontinued balls present in fresh are revived."""
    if not fresh:
        raise RefreshError('fresh lineup is empty — refusing to retire the whole brand')
    bad = [(r.get('name'), errs) for r in fresh if (errs := validate(r))]
    if bad:
        raise RefreshError(f'fresh records fail validation: {bad[:5]}')
    fresh_by = {}
    for r in fresh:
        k = _key(r)
        if k in fresh_by:
            raise RefreshError(f'duplicate in fresh lineup: {k}')
        fresh_by[k] = r
    old_by = {_key(r): r for r in old}
    current_old = [k for k, r in old_by.items() if (r.get('status') or 'current') == 'current']
    retiring = [k for k in current_old if k not in fresh_by]
    if current_old and len(retiring) / len(current_old) > MAX_RETIRE_FRACTION and not force:
        raise RefreshError(f'{len(retiring)} of {len(current_old)} current balls would be retired — looks like a '
                           f'broken collection; re-collect or pass force=True after checking the site')
    merged, report = [], {'added': [], 'updated': [], 'retired': [], 'revived': [], 'unchanged': []}
    for k, r in fresh_by.items():
        rec = dict(r)
        rec['status'] = 'current'
        rec.pop('discontinued_on', None)
        if k not in old_by:
            report['added'].append(k[1])
        elif (old_by[k].get('status') or 'current') == 'discontinued':
            report['revived'].append(k[1])
        elif _comparable(old_by[k]) != _comparable(rec):
            report['updated'].append(k[1])
        else:
            report['unchanged'].append(k[1])
        merged.append(rec)
    for k, r in old_by.items():
        if k in fresh_by:
            continue
        rec = dict(r)
        if (rec.get('status') or 'current') == 'current':
            rec['status'] = 'discontinued'
            rec['discontinued_on'] = today
            note = f'not in the manufacturer\'s current lineup as of {today}'
            rec['notes'] = ((rec.get('notes') or '') + '; ' + note).lstrip('; ')
            report['retired'].append(k[1])
        merged.append(rec)
    merged.sort(key=lambda r: ((r.get('status') or 'current') != 'current', r['name'].lower()))
    return merged, report


def _comparable(r: dict) -> str:
    skip = {'notes', 'status', 'discontinued_on'}
    return json.dumps({k: v for k, v in r.items() if k not in skip}, sort_keys=True, ensure_ascii=False)


FIELDS_SHOWN = ('rg', 'diff', 'int_diff', 'coverstock', 'cover_type', 'core_name', 'factory_finish', 'recommended_oil',
                'image_url', 'ls_hook', 'ls_length', 'ls_backend', 'reaction_shape', 'performance_tier', 'status')


def summarize(old_rows: list[dict], new_rows: list[dict]) -> dict:
    """Diff two built catalogs (catalog.json 'balls') by ball and by column."""
    o = {_key(r): row_values(r) for r in old_rows}
    n = {_key(r): row_values(r) for r in new_rows}
    out = {'added': [], 'retired': [], 'revived': [], 'changed': {}}
    for k, v in n.items():
        if k not in o:
            out['added'].append(' '.join(k))
            continue
        was, now = o[k].get('status') or 'current', v.get('status') or 'current'
        if was == 'current' and now == 'discontinued':
            out['retired'].append(' '.join(k))
        elif was == 'discontinued' and now == 'current':
            out['revived'].append(' '.join(k))
        diffs = {c: [o[k].get(c), v.get(c)] for c in v if c not in HASH_EXCLUDE | {'status', 'discontinued_on'}
                 and o[k].get(c) != v.get(c)}
        if diffs:
            out['changed'][' '.join(k)] = diffs
    missing = [' '.join(k) for k in o if k not in n]
    if missing:
        out['dropped_from_raw'] = missing          # should never happen: raw keeps retired balls
    return out


def summary_markdown(s: dict, report: dict | None = None) -> str:
    lines = [f"**{len(s['added'])} new · {len(s['changed'])} changed · {len(s['retired'])} retired · "
             f"{len(s['revived'])} back in lineup**", '']
    for title, key in (('New', 'added'), ('Retired', 'retired'), ('Back in lineup', 'revived')):
        if s[key]:
            lines += [f'### {title}'] + [f'- {x}' for x in sorted(s[key])] + ['']
    if s['changed']:
        lines.append('### Changed')
        for ball, diffs in sorted(s['changed'].items()):
            shown = {c: d for c, d in diffs.items() if c in FIELDS_SHOWN}
            other = len(diffs) - len(shown)
            parts = [f'{c}: {d[0]!r} → {d[1]!r}' for c, d in shown.items()]
            if other:
                parts.append(f'+{other} other field(s)')
            lines.append(f'- **{ball}** — ' + '; '.join(parts))
        lines.append('')
    if s.get('dropped_from_raw'):
        lines += ['### ⚠ Removed from raw (should not happen — balls must be retired, not deleted)'] + \
                 [f'- {x}' for x in s['dropped_from_raw']] + ['']
    return '\n'.join(lines)


def check_images(rows: list[dict], timeout: float = 15.0) -> list[tuple[str, str, str]]:
    """(ball, url, problem) for every current ball whose image_url doesn't return an image."""
    bad = []
    for r in rows:
        if (r.get('status') or 'current') != 'current':
            continue
        url = r.get('image_url')
        name = f"{r['manufacturer']} {r['name']}"
        if not url:
            bad.append((name, '', 'no image_url'))
            continue
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'LaneSight-catalog-check/1.0'})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                ctype = resp.headers.get('Content-Type', '')
                if resp.status != 200 or not ctype.startswith('image/'):
                    bad.append((name, url, f'{resp.status} {ctype}'))
        except Exception as e:                       # report every failure; never silently pass
            bad.append((name, url, f'{type(e).__name__}: {e}'))
    return bad


def rows_to_sync(rows: list[dict], db_hashes: dict[str, str]) -> list[dict]:
    """db_hashes: {'Manufacturer|Name': source_hash or None} from Supabase. Rows missing or differing get upserted."""
    return [r for r in rows if db_hashes.get(f"{r['manufacturer']}|{r['name']}") != (r.get('source_hash') or row_hash(r))]


def sync_chunks(rows: list[dict], retrieved_at: str, max_bytes: int = 50_000) -> list[str]:
    """Split the upsert SQL for `rows` into transaction-sized chunks small enough for one execute_sql call."""
    chunks, cur = [], []
    for r in rows:
        trial = to_sql(cur + [r], retrieved_at)
        if cur and len(trial.encode()) > max_bytes:
            chunks.append(to_sql(cur, retrieved_at))
            cur = [r]
        else:
            cur.append(r)
    if cur:
        chunks.append(to_sql(cur, retrieved_at))
    return chunks


DB_HASH_QUERY = "select manufacturer || '|' || name as key, source_hash from ball_models;"
DB_DIGEST_QUERY = ("select count(*) n, md5(string_agg(manufacturer || '|' || name || '|' || coalesce(source_hash,''), "
                   "E'\\n' order by manufacturer || '|' || name collate \"C\")) digest from ball_models;")


def catalog_digest(rows: list[dict]) -> tuple[int, str]:
    """Same fingerprint as DB_DIGEST_QUERY: equal digests mean Supabase already matches the catalog."""
    import hashlib
    keyed = sorted(((f"{r['manufacturer']}|{r['name']}").encode(), f"{r['manufacturer']}|{r['name']}|{r.get('source_hash') or ''}")
                   for r in rows)
    return len(keyed), hashlib.md5('\n'.join(line for _, line in keyed).encode()).hexdigest()


def main(argv=None):
    ap = argparse.ArgumentParser(prog='python -m lanesight_core.arsenal.refresh')
    sub = ap.add_subparsers(dest='cmd', required=True)
    m = sub.add_parser('merge'); m.add_argument('raw', type=Path); m.add_argument('fresh', type=Path)
    m.add_argument('--today', default=date.today().isoformat()); m.add_argument('--force', action='store_true')
    s = sub.add_parser('summarize'); s.add_argument('old', type=Path); s.add_argument('new', type=Path)
    s.add_argument('--markdown', action='store_true')
    c = sub.add_parser('check-images'); c.add_argument('catalog', type=Path)
    y = sub.add_parser('sync-sql'); y.add_argument('catalog', type=Path); y.add_argument('db_hashes', type=Path)
    y.add_argument('--out-dir', type=Path, required=True); y.add_argument('--max-bytes', type=int, default=50_000)
    g = sub.add_parser('digest'); g.add_argument('catalog', type=Path)
    a = ap.parse_args(argv)

    if a.cmd == 'digest':
        n, h = catalog_digest(json.loads(a.catalog.read_text())['balls'])
        print(json.dumps({'n': n, 'digest': h, 'db_query': DB_DIGEST_QUERY}))
        return 0

    if a.cmd == 'merge':
        old = json.loads(a.raw.read_text()) if a.raw.exists() else []
        try:
            merged, rep = merge_brand(old, json.loads(a.fresh.read_text()), a.today, a.force)
        except RefreshError as e:
            print(f'REFUSED {a.raw.name}: {e}', file=sys.stderr)
            return 2
        a.raw.write_text(json.dumps(merged, indent=1, ensure_ascii=False) + '\n')
        print(json.dumps({k: (v if k != 'unchanged' else len(v)) for k, v in rep.items()}, ensure_ascii=False))
        return 0
    if a.cmd == 'summarize':
        old = json.loads(a.old.read_text())['balls'] if a.old.exists() else []
        res = summarize(old, json.loads(a.new.read_text())['balls'])
        print(summary_markdown(res) if a.markdown else json.dumps(res, indent=1, ensure_ascii=False, default=str))
        return 1 if res.get('dropped_from_raw') else 0
    if a.cmd == 'check-images':
        bad = check_images(json.loads(a.catalog.read_text())['balls'])
        for b in bad:
            print('\t'.join(b))
        print(f'{len(bad)} image problem(s)', file=sys.stderr)
        return 1 if bad else 0
    if a.cmd == 'sync-sql':
        cat = json.loads(a.catalog.read_text())
        raw_hashes = json.loads(a.db_hashes.read_text())
        db = {h['key']: h.get('source_hash') for h in raw_hashes} if isinstance(raw_hashes, list) else raw_hashes
        rows = rows_to_sync(cat['balls'], db)
        a.out_dir.mkdir(parents=True, exist_ok=True)
        for old in a.out_dir.glob('sync_*.sql'):
            old.unlink()
        chunks = sync_chunks(rows, cat.get('retrieved_at') or date.today().isoformat(), a.max_bytes)
        for i, sql in enumerate(chunks):
            (a.out_dir / f'sync_{i:02d}.sql').write_text(sql)
        print(f'{len(rows)} row(s) to upsert in {len(chunks)} chunk(s); {len(cat["balls"]) - len(rows)} already in sync')
        return 0


if __name__ == '__main__':
    sys.exit(main())
