#!/usr/bin/env python3
"""DEC-092 reproducible analysis benchmark + regression gate.

Runs `analyze_clip` over a manifest of local clips and writes ONE JSON report per run: total and per-stage
wall time (probe / window / convert / analyze + the nested cv.* sub-stages + decode passes/frames/seconds),
peak RSS, CPU-seconds, the failure code (if any), and every headline metric value.

Compare mode diffs a new report against a saved reference and applies the DEC-092 tolerances
(speed ±0.2 mph, boards ±0.5, same pin read, same pass/fail) so an optimization can be gated:
kept only if it's faster, holds every metric in tolerance, and adds no new failures.

Videos are NOT committed — only the manifest (paths + expected outcome). Clips live in
~/LaneSightData/training_videos by default.

    python -m ops.perf_benchmark --manifest ops/perf_manifest.json --out ops/perf_reports/run.json
    python -m ops.perf_benchmark ... --save-reference
    python -m ops.perf_benchmark ... --reference ops/perf_reports/reference.json   # gate a new run
    python -m ops.perf_benchmark ... --clips IMG_8751,IMG_8831                       # subset
"""
from __future__ import annotations
import argparse, json, os, resource, time, tempfile
from pathlib import Path

TOL = {'ball_speed': 0.2, 'entry_board': 0.5, 'entry_angle': 0.5, 'rev_rate': 25.0,
       'breakpoint_board': 0.5, 'laydown_board': 0.5}        # per-metric tolerance for the regression gate
_METRICS = list(TOL) + ['pocket', 'breakpoint_distance']


def _mv(metrics, k):
    v = (metrics or {}).get(k)
    return v.get('value') if isinstance(v, dict) else v


def run_manifest(manifest: list[dict], clips_dir: Path, only: set | None) -> dict:
    results = []
    for entry in manifest:
        name = entry['clip']
        if only and name.split('.')[0] not in only:
            continue
        path = str(clips_dir / name)
        print(f'[perf] {name} …', flush=True)
        # thread the timings dict out of analyze_clip even on failure by calling the lower level
        r = _run_capturing_timings(path)
        r['expected'] = entry.get('expected')
        r['expected_failure_code'] = entry.get('failure_code')
        results.append(r)
        print(f'[perf]   {r.get("status")} in {r.get("wall_s")}s'
              + (f' decode×{r.get("timings",{}).get("decode",{}).get("passes")}' if r.get('timings') else ''),
              flush=True)
    return {'results': results}


def _run_capturing_timings(path: str) -> dict:
    """Like run_clip but keeps the timings dict (passed in) so failures still report per-stage times."""
    from lanesight_runner.core import analyze_clip
    out = {'clip': os.path.basename(path), 'path': path}
    if not os.path.exists(path):
        return {**out, 'status': 'missing'}
    timings: dict = {}
    cpu0 = time.process_time(); wall0 = time.perf_counter()
    with tempfile.TemporaryDirectory() as td:
        try:
            rec, probe, timings = analyze_clip(path, os.path.join(td, 'bench'), timings=timings)
            m = rec.get('metrics') or {}
            out.update(status='analyzed',
                       metrics={k: _mv(m, k) for k in _METRICS if _mv(m, k) is not None},
                       pins_read=((rec.get('pins') or {}).get('readable')),
                       far_lane=(rec.get('capture_quality') or {}).get('far_lane'))
        except Exception as e:
            out.update(status='failed', failure_code=(getattr(e, 'code', None) or type(e).__name__),
                       error=str(e)[:200])
        out['wall_s'] = round(time.perf_counter() - wall0, 2)
        out['cpu_s'] = round(time.process_time() - cpu0, 2)
        rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        out['peak_rss_mb'] = round(rss / (1024 * 1024 if os.uname().sysname == 'Darwin' else 1024), 1)
        out['timings'] = timings
    return out


def compare(new: dict, ref: dict) -> dict:
    """Regression gate: per-clip metric deltas vs tolerance + pass/fail parity + time deltas."""
    refmap = {r['clip']: r for r in ref.get('results', [])}
    rows, regressions = [], []
    for r in new.get('results', []):
        base = refmap.get(r['clip'])
        if not base:
            continue
        row = {'clip': r['clip'], 'status': r.get('status'), 'ref_status': base.get('status'),
               'wall_s': r.get('wall_s'), 'ref_wall_s': base.get('wall_s')}
        if r.get('status') != base.get('status'):
            row['REGRESSION'] = f"pass/fail changed: {base.get('status')} → {r.get('status')}"
            regressions.append(row['REGRESSION'] + f" ({r['clip']})")
        md = {}
        for k, tol in TOL.items():
            a, b = (r.get('metrics') or {}).get(k), (base.get('metrics') or {}).get(k)
            if a is not None and b is not None:
                d = round(a - b, 3); md[k] = d
                if abs(d) > tol:
                    regressions.append(f"{r['clip']} {k} moved {d:+} (> ±{tol})")
        if r.get('pins_read') != base.get('pins_read'):
            regressions.append(f"{r['clip']} pin read changed: {base.get('pins_read')} → {r.get('pins_read')}")
        row['metric_deltas'] = md
        rows.append(row)
    return {'rows': rows, 'regressions': regressions, 'gate_pass': not regressions}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifest', default='ops/perf_manifest.json')
    ap.add_argument('--clips-dir', default=os.path.expanduser('~/LaneSightData/training_videos'))
    ap.add_argument('--out', default=None)
    ap.add_argument('--reference', default=None)
    ap.add_argument('--save-reference', action='store_true')
    ap.add_argument('--clips', default=None, help='comma-separated clip stems to run (subset)')
    a = ap.parse_args()

    manifest = json.load(open(a.manifest))['clips']
    only = set(a.clips.split(',')) if a.clips else None
    report = run_manifest(manifest, Path(a.clips_dir), only)
    report['generated_wall'] = round(time.time(), 0)
    report['clips_dir'] = a.clips_dir

    out = a.out or f'ops/perf_reports/run_{int(time.time())}.json'
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(report, open(out, 'w'), indent=2)
    print(f'[perf] wrote {out} ({len(report["results"])} clips)')

    if a.reference and os.path.exists(a.reference):
        cmp = compare(report, json.load(open(a.reference)))
        print('[perf] GATE:', 'PASS' if cmp['gate_pass'] else 'FAIL')
        for reg in cmp['regressions']:
            print('  REGRESSION:', reg)
    if a.save_reference:
        ref_path = 'ops/perf_reports/reference.json'
        json.dump(report, open(ref_path, 'w'), indent=2)
        print(f'[perf] saved reference → {ref_path}')


if __name__ == '__main__':
    main()
