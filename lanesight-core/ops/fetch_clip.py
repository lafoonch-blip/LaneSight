"""DEC-100 — pull retained analysis clips back down for diagnosis.

Every clip analyzed through POST /shots/analyze is kept in the private `shot-clips` bucket for the retention
window (default 7 days, newest 40 per user) and its path is recorded on the attempt row
(`analysis_attempt.clip.storage_path`). This downloads them so the exact bytes the server saw can be re-run:

    cd lanesight-core && source .venv/bin/activate
    python -m ops.fetch_clip --recent 10                # the 10 newest attempts (any user)
    python -m ops.fetch_clip --shot <shot_id>           # one attempt's clip
    python -m ops.fetch_clip --recent 5 --rerun         # download + re-run the pipeline locally

Clips land in ~/LaneSightData/diagnostics/<date>/ (never in the repo). Needs the live Supabase env the API uses
(LANESIGHT_DB_URL + service role); it reads, it never changes live data.
"""
from __future__ import annotations
import argparse, json, os, pathlib, sys, urllib.request
from datetime import date

from lanesight_api.store import get_store

OUT_ROOT = pathlib.Path(os.path.expanduser('~/LaneSightData/diagnostics'))


def _attempts(store, shot_id=None, recent=10):
    q = ('select=created_at,shot_id,user_id,source,capture_mode,status,failure_code,clip'
         '&clip->>storage_path=not.is.null&order=created_at.desc')
    q += f'&shot_id=eq.{shot_id}' if shot_id else f'&limit={recent}'
    return store._get('analysis_attempt', q)


def main(argv=None):
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--shot')
    g.add_argument('--recent', type=int)
    ap.add_argument('--rerun', action='store_true', help='re-run the analysis locally on each clip')
    a = ap.parse_args(argv)

    store = get_store()
    if store.__class__.__name__ != 'PgStore':
        sys.exit('Not connected to live Supabase (set the API env first).')
    rows = _attempts(store, shot_id=a.shot, recent=a.recent or 10)
    if not rows:
        sys.exit('No retained clips found (older than the retention window, or analyzed before DEC-100).')
    out = OUT_ROOT / date.today().isoformat()
    out.mkdir(parents=True, exist_ok=True)
    for r in rows:
        path = (r.get('clip') or {}).get('storage_path')
        dest = out / f"{r['shot_id']}.mov"
        try:
            url = store.storage_signed_download_url('shot-clips', path)
            with urllib.request.urlopen(url, timeout=300) as resp, open(dest, 'wb') as f:
                f.write(resp.read())
        except Exception as e:
            print(f"{r['shot_id']}: download failed ({e}) — purged or never retained")
            continue
        (out / f"{r['shot_id']}.attempt.json").write_text(json.dumps(r, indent=2, default=str))
        print(f"{r['created_at']}  {r['capture_mode']:<5} {r['source']:<6} {r['status']:<8} "
              f"{r.get('failure_code') or '':<28} -> {dest}")
        if a.rerun:
            _rerun(dest, r)


def _rerun(clip, row):
    """Re-run the same engine locally and print the outcome next to the live one."""
    from lanesight_core.failures import AnalysisFailure
    try:
        if row.get('capture_mode') == 'form':
            from lanesight_core.form import analyze_form_clip
            rec = analyze_form_clip(str(clip), out_prefix=str(clip.with_suffix('')), handed='R')
            ev = rec.get('events') or {}
            print(f"    rerun: form ok · view={rec.get('view')} · events={ {k: v for k, v in ev.items() if v is not None} }")
        else:
            from lanesight_runner.core import analyze_clip          # same entry point the API job uses
            rec, _probe, _t = analyze_clip(str(clip), str(clip.with_suffix('')), handed='R', timings={})
            print(f"    rerun: shot ok · {len(rec.get('metrics') or {})} metrics")
    except AnalysisFailure as f:
        print(f'    rerun: FAILED {f.code} at {f.stage} — {f.diagnostics}')
    except Exception as e:
        print(f'    rerun: error {type(e).__name__}: {e}')


if __name__ == '__main__':
    main()
