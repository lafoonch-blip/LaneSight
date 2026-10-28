#!/usr/bin/env python3
"""DEC-094 §2 — CV accuracy evaluation harness (shadow-comparison ready).

Runs a candidate pipeline over the eval split and reports, per lane region (0-15 / 15-40 / 40-60 ft) and per
camera class:
  - detection recall, positional error, false positives, observations per region   (needs labels)
  - trajectory lateral (boards) + down-lane (ft) error, observed-vs-predicted       (needs labels)
  - metric accuracy vs ground truth: MAE / median / p90 / bias                       (needs labels/ruby)
  - coverage: share of shots where each metric is available                          (no labels needed)
  - **plausible-but-wrong rate**: a metric shown measured/ok whose error exceeds its tolerance — the headline
  - runtime: wall / CPU-seconds / peak RSS

This measures accuracy against ground truth, and is SEPARATE from `ops/perf_benchmark.py` (the don't-regress gate).
Clips + labels are not committed. Label files are `validation/cv_eval/labels/<id>.json` (schema in the README).
Until a shot has labels, only the label-free sections (coverage, observations-per-region from the engine's own
track, runtime, failure code) are reported, and the shot is listed under "labels needed".

    python -m ops.cv_eval --manifest validation/cv_eval/manifest.json --out ops/perf_reports/cv_eval.json

The default candidate is the current production engine (the baseline). A future detector/tracker plugs in behind
`--engine` and is promoted only under DEC-094's promotion rule (per-region / per-metric allowed).
"""
from __future__ import annotations
import argparse, json, os, resource, time, tempfile
from pathlib import Path

DEFAULT_REGIONS = [(0, 15), (15, 40), (40, 60)]


# ---------------- pure helpers (unit-tested; no clip needed) ----------------

def region_index(z_ft, regions=DEFAULT_REGIONS):
    """Index of the lane region a down-lane distance falls in, or None if outside all regions."""
    if z_ft is None:
        return None
    for i, (lo, hi) in enumerate(regions):
        if lo <= z_ft < hi:
            return i
    return None


def region_label(regions=DEFAULT_REGIONS):
    return [f"{lo}-{hi}ft" for lo, hi in regions]


def observations_per_region(traj_lane, regions=DEFAULT_REGIONS):
    """Count the engine's OBSERVED track points per region (predicted/interpolated points must not be in
    traj_lane). traj_lane = [{'z_ft':..}, ...]."""
    counts = [0] * len(regions)
    for p in traj_lane or []:
        i = region_index((p or {}).get('z_ft'), regions)
        if i is not None:
            counts[i] += 1
    return dict(zip(region_label(regions), counts))


def coverage(results, metrics):
    """Share of ANALYZED shots where each metric has a value."""
    analyzed = [r for r in results if r.get('status') == 'analyzed']
    n = len(analyzed) or 1
    return {k: round(sum(1 for r in analyzed if (r.get('metrics') or {}).get(k) is not None) / n, 3)
            for k in metrics}


def _agg(errors):
    """MAE / median / p90 / bias from signed errors."""
    if not errors:
        return None
    a = sorted(abs(e) for e in errors)
    import statistics
    p90 = a[min(len(a) - 1, int(0.9 * (len(a) - 1)))]
    return {'n': len(errors), 'mae': round(statistics.mean(abs(e) for e in errors), 3),
            'median': round(statistics.median(abs(e) for e in errors), 3),
            'p90': round(p90, 3), 'bias': round(statistics.mean(errors), 3)}


def metric_errors(results, tolerances):
    """Per-metric signed-error aggregates + the plausible-but-wrong list, comparing the engine's measured value
    to each shot's ground-truth value. A shot contributes to plausible-but-wrong when the metric is shown
    measured (value present) yet |error| exceeds its tolerance."""
    tol = tolerances.get('metrics', {})
    per = {k: [] for k in tol}
    plausible_wrong = []
    for r in results:
        gt = r.get('gt_metrics') or {}
        mv = r.get('metrics') or {}
        for k, t in tol.items():
            a, b = mv.get(k), gt.get(k)
            if a is None or b is None:
                continue
            e = a - b
            per[k].append(e)
            if abs(e) > t:
                plausible_wrong.append({'clip': r.get('id'), 'metric': k, 'measured': a, 'truth': b,
                                        'error': round(e, 3), 'tol': t})
    return {k: _agg(v) for k, v in per.items() if v}, plausible_wrong


def thin_camera_classes(manifest, min_per_class=6):
    """Camera classes with fewer than min_per_class shots in the manifest — what Shayne should film more of."""
    from collections import Counter
    c = Counter(s.get('camera_class', 'unknown') for s in manifest)
    return {k: v for k, v in c.items() if v < min_per_class}


# ---------------- engine run ----------------

def _run_engine(path):
    """Run the current production engine on one clip; capture metrics, trajectory, pins, failure, runtime."""
    from lanesight_runner.core import analyze_clip
    out = {'path': path}
    if not os.path.exists(path):
        return {**out, 'status': 'missing'}
    cpu0, wall0 = time.process_time(), time.perf_counter()
    with tempfile.TemporaryDirectory() as td:
        try:
            rec, _probe, _timings = analyze_clip(path, os.path.join(td, 'ev'))
            m = rec.get('metrics') or {}
            mv = {k: (v.get('value') if isinstance(v, dict) else v) for k, v in m.items()}
            traj = (rec.get('trajectory') or {}).get('lane') or []
            out.update(status='analyzed', metrics=mv, trajectory_lane=traj,
                       observations=observations_per_region(traj),
                       pins_standing=((rec.get('pins') or {}).get('standing')),
                       far_lane=(rec.get('capture_quality') or {}).get('far_lane'),
                       lane=(rec.get('capture_quality') or {}).get('lane'))
        except Exception as e:
            out.update(status='failed', failure_code=(getattr(e, 'code', None) or type(e).__name__),
                       error=str(e)[:200])
        out['wall_s'] = round(time.perf_counter() - wall0, 2)
        out['cpu_s'] = round(time.process_time() - cpu0, 2)
        rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        out['peak_rss_mb'] = round(rss / (1024 * 1024 if os.uname().sysname == 'Darwin' else 1024), 1)
    return out


def _load_labels(labels_dir, shot_id):
    p = Path(labels_dir) / f"{shot_id}.json"
    return json.load(open(p)) if p.exists() else None


def _gt_metrics_from_labels(labels, inline_gt):
    """Map labels / inline ground truth to the engine's metric names where a direct comparison exists.
    Conservative: only fields with an unambiguous mapping (speed from ruby / manual) are surfaced."""
    gt = {}
    if labels:
        ruby = labels.get('ruby') or {}
        if ruby.get('speed_mph') is not None:
            gt['ball_speed'] = ruby['speed_mph']
    if inline_gt:
        if inline_gt.get('speed_foul_to_pins_mph') is not None:
            gt.setdefault('ball_speed', inline_gt['speed_foul_to_pins_mph'])
    return gt


# ---------------- main ----------------

def run(manifest, clips_dir, labels_dir, tolerances, only=None):
    results = []
    for s in manifest:
        if only and s['id'] not in only:
            continue
        if s.get('present') is False:
            results.append({'id': s['id'], 'status': 'not_present', 'camera_class': s.get('camera_class')})
            continue
        print(f"[cv_eval] {s['id']} …", flush=True)
        r = _run_engine(str(Path(clips_dir) / s['clip']))
        r['id'] = s['id']; r['camera_class'] = s.get('camera_class'); r['split'] = s.get('split')
        labels = _load_labels(labels_dir, s['id'])
        r['has_labels'] = labels is not None
        r['gt_metrics'] = _gt_metrics_from_labels(labels, s.get('ground_truth'))
        results.append(r)
        print(f"[cv_eval]   {r.get('status')} in {r.get('wall_s')}s"
              + (f" · obs {r.get('observations')}" if r.get('observations') else ''), flush=True)
    return results


def summarize(results, manifest, tolerances):
    metric_names = list((tolerances.get('metrics') or {}).keys())
    agg, plausible_wrong = metric_errors([r for r in results if r.get('gt_metrics')], tolerances)
    analyzed = [r for r in results if r.get('status') == 'analyzed']
    labeled = [r for r in results if r.get('has_labels')]
    # plausible-but-wrong rate = plausible-wrong metric-instances / measured metric-instances that had a truth
    measured_with_truth = sum(1 for r in results for k in (tolerances.get('metrics') or {})
                              if (r.get('metrics') or {}).get(k) is not None and (r.get('gt_metrics') or {}).get(k) is not None)
    return {
        'n_shots': len(results),
        'n_analyzed': len(analyzed),
        'n_failed': sum(1 for r in results if r.get('status') == 'failed'),
        'n_missing': sum(1 for r in results if r.get('status') in ('missing', 'not_present')),
        'n_labeled': len(labeled),
        'coverage': coverage(results, metric_names),
        'metric_accuracy': agg,
        'plausible_but_wrong': plausible_wrong,
        'plausible_but_wrong_rate': (round(len(plausible_wrong) / measured_with_truth, 3) if measured_with_truth else None),
        'labels_needed': [r['id'] for r in results if r.get('status') == 'analyzed' and not r.get('has_labels')],
        'thin_camera_classes': thin_camera_classes(manifest),
        'runtime': {'total_wall_s': round(sum(r.get('wall_s', 0) for r in results), 1),
                    'total_cpu_s': round(sum(r.get('cpu_s', 0) for r in results), 1)},
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifest', default='validation/cv_eval/manifest.json')
    ap.add_argument('--clips-dir', default=os.path.expanduser('~/LaneSightData/training_videos'))
    ap.add_argument('--labels-dir', default='validation/cv_eval/labels')
    ap.add_argument('--tolerances', default='validation/cv_eval/tolerances.json')
    ap.add_argument('--out', default=None)
    ap.add_argument('--clips', default=None, help='comma-separated shot ids (subset)')
    a = ap.parse_args()

    manifest = json.load(open(a.manifest))['clips']
    tolerances = json.load(open(a.tolerances))
    only = set(a.clips.split(',')) if a.clips else None
    results = run(manifest, a.clips_dir, a.labels_dir, tolerances, only)
    report = {'results': results, 'summary': summarize(results, manifest, tolerances)}

    out = a.out or f'ops/perf_reports/cv_eval_{int(time.time())}.json'
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(report, open(out, 'w'), indent=2)
    s = report['summary']
    print(f"\n[cv_eval] {s['n_analyzed']}/{s['n_shots']} analyzed, {s['n_failed']} failed, "
          f"{s['n_missing']} missing · {s['n_labeled']} labeled")
    print(f"[cv_eval] coverage: " + ', '.join(f"{k} {v:.0%}" for k, v in s['coverage'].items()))
    print(f"[cv_eval] plausible-but-wrong: "
          + (f"{len(s['plausible_but_wrong'])} instances, rate {s['plausible_but_wrong_rate']}"
             if s['plausible_but_wrong_rate'] is not None else "n/a — no ground-truth metrics yet (add labels)"))
    if s['labels_needed']:
        print(f"[cv_eval] labels needed for: {', '.join(s['labels_needed'])}")
    if s['thin_camera_classes']:
        print(f"[cv_eval] thin camera classes (film more): {s['thin_camera_classes']}")
    print(f"[cv_eval] wrote {out}")


if __name__ == '__main__':
    main()
