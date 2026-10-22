"""Build the ball catalog from collected per-brand JSON files.

    python -m lanesight_core.arsenal.build_seed data/ball_catalog/raw \
        --out data/ball_catalog/catalog.json --sql lanesight_core/models/seed_ball_catalog.sql

- validates every record (catalog.validate) — invalid rows are reported and skipped, never patched
- adds the normalized reaction (catalog.normalize)
- writes one merged catalog.json and an idempotent upsert SQL keyed on (manufacturer, name)
- never deletes: a ball a manufacturer drops stays in raw/ with status 'discontinued' (user arsenals point at it)
- every row carries `source_hash` (sha256 of its column values, excluding retrieval date) so a sync can upsert only
  the rows that changed (see refresh.py)
"""
from __future__ import annotations
import argparse, hashlib, json, re, sys
from datetime import datetime, timezone
from pathlib import Path

from .catalog import normalize, validate, catalog_key, CATALOG_VERSION, NORMALIZER_VERSION, _num

COLUMNS = [  # ball_models column <- catalog record key
    ('manufacturer', 'manufacturer'), ('name', 'name'), ('parent_company', 'parent_company'),
    ('product_line', 'product_line'), ('performance_tier', 'performance_tier'), ('release_date', 'release_date'),
    ('release_year', None), ('status', 'status'), ('discontinued_on', 'discontinued_on'), ('colors', 'colors'), ('coverstock', 'coverstock_name'),
    ('cover_type', 'cover_type'), ('core_name', 'core_name'), ('core_type', 'core_type'), ('rg', 'rg_15'),
    ('diff', 'diff_15'), ('int_diff', 'int_diff_15'), ('factory_finish', 'factory_finish'),
    ('recommended_oil', 'recommended_oil'), ('image_url', 'image_url'), ('image_source', 'image_source'),
    ('product_url', 'product_url'), ('spec_source_urls', 'spec_source_urls'), ('mfr_ratings', 'mfr_ratings'),
    ('retailer_ratings', 'retailer_ratings'), ('motion_chart', 'motion_chart'), ('reaction_description', 'reaction_description'),
    ('ls_hook', 'ls_hook'), ('ls_length', 'ls_length'), ('ls_backend', 'ls_backend'), ('ls_oil', 'ls_oil'), ('ls_oil_min', 'ls_oil_min'), ('ls_oil_max', 'ls_oil_max'),
    ('reaction_shape', 'reaction_shape'), ('reaction_basis', 'reaction_basis'),
    ('reaction_confidence', 'reaction_confidence'), ('missing_fields', 'missing'),
    ('catalog_version', None), ('normalizer_version', 'normalizer_version'), ('retrieved_at', None),
    ('source_hash', 'source_hash'),
]
HASH_EXCLUDE = {'retrieved_at', 'source_hash'}
JSONB = {'mfr_ratings', 'retailer_ratings', 'motion_chart', 'reaction_basis'}
ARRAYS = {'spec_source_urls', 'missing_fields'}
NUMERIC = {'rg', 'diff', 'int_diff', 'ls_hook', 'ls_length', 'ls_backend', 'release_year'}


MOTION_RE = re.compile(r'Ball Motion Comparison Chart[^;]*?oil\s+(\d+(?:\.\d+)?)[^;]*?shape\s+(\d+(?:\.\d+)?)', re.I)
FCC_RE = re.compile(r'FCC Rating:\s*Total-?\s*([\d.]+),\s*Finish-?\s*([\d.]+),\s*Core-?\s*([\d.]+),\s*Cover-?\s*([\d.]+)', re.I)


def lift_note_ratings(rec: dict) -> dict:
    """Collectors recorded two published ratings in `notes`; lift them into structured fields (never overwrite).
    motion_chart: Brunswick Ball Motion Comparison Chart position; fcc: bowling.com FCC rating (stored only —
    its scale isn't documented, so the normalizer does not use it)."""
    r = dict(rec)
    notes = r.get('notes') or ''
    if not r.get('motion_chart') and (m := MOTION_RE.search(notes)):
        r['motion_chart'] = {'oil': float(m.group(1)), 'oil_scale': '1 light - 16 heavy',
                             'shape': float(m.group(2)), 'shape_scale': '1 smooth - 18 angular',
                             'source': 'Brunswick Ball Motion Comparison Chart'}
    if (m := FCC_RE.search(notes)):
        rr = dict(r.get('retailer_ratings') or {})
        rr.setdefault('fcc', {'total': float(m.group(1)), 'finish': float(m.group(2)),
                              'core': float(m.group(3)), 'cover': float(m.group(4))})
        r['retailer_ratings'] = rr
    return r


def build(raw_dir: Path) -> tuple[list[dict], list[str]]:
    rows, problems, seen = [], [], {}
    for f in sorted(raw_dir.glob('*.json')):
        try:
            recs = json.loads(f.read_text())
        except json.JSONDecodeError as e:
            problems.append(f'{f.name}: invalid JSON ({e})')
            continue
        for i, rec in enumerate(recs):
            rec = lift_note_ratings(rec)
            errs = validate(rec)
            if errs:
                problems.append(f"{f.name}[{i}] {rec.get('manufacturer')} {rec.get('name')}: {'; '.join(errs)}")
                continue
            key = catalog_key(rec)
            if key in seen:
                problems.append(f'{f.name}[{i}] duplicate of {seen[key]}: {key}')
                continue
            seen[key] = f'{f.name}[{i}]'
            row = dict(rec)
            for k in ('rg_15', 'diff_15', 'int_diff_15'):
                row[k] = _num(row.get(k))
            rows.append(row)
    share_colorway_ratings(rows)
    for row in rows:
        row.update(normalize(row).to_dict())
        row['status'] = row.get('status') or 'current'
        row['source_hash'] = row_hash(row)
    rows.sort(key=lambda r: (r['manufacturer'].lower(), r['name'].lower()))
    return rows, problems


def _model_key(r):
    """Colorways of one ball share cover, core, finish and 15 lb RG/diff; only the color differs."""
    k = (r['manufacturer'], (r.get('coverstock_name') or '').lower(), (r.get('core_name') or '').lower(),
         (r.get('factory_finish') or '').lower(), r.get('rg_15'), r.get('diff_15'))
    return k if all(x not in (None, '') for x in k) else None


def _has(d, keys):
    return any((d or {}).get(k) not in (None, '') for k in keys)


def share_colorway_ratings(rows):
    """A colorway sold without published ratings takes them from a rated colorway of the same ball, and says so."""
    groups = {}
    for r in rows:
        if (k := _model_key(r)):
            groups.setdefault(k, []).append(r)
    for members in groups.values():
        if len(members) < 2:
            continue
        for field, keys in (('mfr_ratings', ('hook', 'length', 'backend', 'reaction_shape')),
                            ('retailer_ratings', ('hook_potential', 'hook_potential_label', 'length', 'length_label')),
                            ('motion_chart', ('oil', 'shape'))):
            donor = next((m for m in members if _has(m.get(field), keys)), None)
            if not donor:
                continue
            for m in members:
                if m is not donor and not _has(m.get(field), keys):
                    m[field] = dict(donor[field], from_colorway=donor['name'])
                    m['notes'] = ((m.get('notes') or '') + f'; {field} shared from colorway {donor["name"]}').lstrip('; ')
        oil = next((m.get('recommended_oil') for m in members if m.get('recommended_oil')), None)
        for m in members:
            if oil and not m.get('recommended_oil'):
                m['recommended_oil'] = oil


def row_values(r: dict, retrieved_at: str | None = None) -> dict:
    """ball_models column -> value for one catalog row (what the upsert writes)."""
    rd = r.get('release_date') or ''
    computed = {'release_year': int(rd[:4]) if rd[:4].isdigit() else None,
                'catalog_version': CATALOG_VERSION, 'retrieved_at': retrieved_at}
    return {col: (computed[col] if key is None else r.get(key)) for col, key in COLUMNS}


def row_hash(r: dict) -> str:
    vals = {k: v for k, v in row_values(r).items() if k not in HASH_EXCLUDE}
    vals['status'] = vals.get('status') or 'current'
    return hashlib.sha256(json.dumps(vals, sort_keys=True, ensure_ascii=False, default=str).encode()).hexdigest()


def _lit(col, v):
    if v is None:
        return 'null'
    if col in JSONB:
        return "'" + json.dumps(v, sort_keys=True).replace("'", "''") + "'::jsonb"
    if col in ARRAYS:
        return 'array[' + ','.join("'" + str(x).replace("'", "''") + "'" for x in v) + ']::text[]' if v else "'{}'::text[]"
    if col in NUMERIC:
        return repr(float(v)) if not isinstance(v, int) else str(v)
    return "'" + str(v).replace("'", "''") + "'"


def to_sql(rows: list[dict], retrieved_at: str) -> str:
    cols = [c for c, _ in COLUMNS]
    out = [f'-- Generated by lanesight_core.arsenal.build_seed ({CATALOG_VERSION}, {NORMALIZER_VERSION}). Do not edit by hand.',
           f'-- {len(rows)} balls. Run after migrations 002 + 005 with the service role. Upserts only; never deletes.', 'begin;']
    for r in rows:
        vals = [_lit(col, v) for col, v in row_values(r, retrieved_at).items()]
        updates = ', '.join(f'{c} = excluded.{c}' for c in cols if c not in ('manufacturer', 'name'))
        out.append(f"insert into ball_models ({', '.join(cols)}) values ({', '.join(vals)})\n"
                   f"  on conflict (manufacturer, name) do update set {updates}, updated_at = now();")
    out.append('commit;')
    return '\n'.join(out) + '\n'


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('raw_dir', type=Path)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--sql', type=Path, required=True)
    ap.add_argument('--retrieved-at', default=datetime.now(timezone.utc).date().isoformat())
    a = ap.parse_args(argv)
    rows, problems = build(a.raw_dir)
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps({'catalog_version': CATALOG_VERSION, 'normalizer_version': NORMALIZER_VERSION,
                                 'retrieved_at': a.retrieved_at, 'count': len(rows), 'balls': rows}, indent=1))
    a.sql.write_text(to_sql(rows, a.retrieved_at))
    print(f'{len(rows)} balls written; {len(problems)} rejected')
    for p in problems:
        print('  REJECTED', p, file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
