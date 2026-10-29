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


# DEC-094 Form Gate A: map the engine's swing-event codes to the ground-truth label keys (form_label.py).
FORM_EVENT_MAP = {'ball_start_s': 'E2', 'pushaway_end_s': 'E3', 'top_of_swing_s': 'E4',
                  'slide_stop_s': 'E8', 'release_s': 'E7'}


def form_event_errors(detected, labeled, tol_s=0.10):
    """Per-event timing error |detected - labeled| (seconds) for the mapped swing events, with a within-tolerance
    flag. `detected` = the form engine's events (E2…E8); `labeled` = ground truth {ball_start_s, …}. Scores only
    events present in BOTH (so a missing detection or label just drops that event). Pure + unit-tested — this is
    the Form Gate A comparison; the server Python engine is the reference, the on-device shadow is scored the same."""
    out = {}
    for lk, ek in FORM_EVENT_MAP.items():
        lv, dv = (labeled or {}).get(lk), (detected or {}).get(ek)
        if lv is None or dv is None:
            continue
        err = abs(float(dv) - float(lv))
        out[lk] = {'err_s': round(err, 3), 'within': err <= tol_s}
    return out


def _run_form_engine(path):
    """Run the Python form reference on one clip; capture detected events + runtime. Best-effort: a missing pose
    model / MediaPipe is reported as a skipped status, never a crash (the Form eval set can be assembled before
    the model is wired into this environment)."""
    out = {'path': path, 'mode': 'form'}
    if not os.path.exists(path):
        return {**out, 'status': 'missing'}
    cpu0, wall0 = time.process_time(), time.perf_counter()
    with tempfile.TemporaryDirectory() as td:
        try:
            from lanesight_core.form import analyze_form_clip
            from lanesight_core.form.pose import pose_backend
            rec = analyze_form_clip(path, os.path.join(td, 'form'), None, pose_backend())
            out.update(status='analyzed', events=(rec.get('events') or {}), view=rec.get('view'),
                       form_status=rec.get('status'))
        except Exception as e:
            out.update(status='failed', failure_code=(getattr(e, 'code', None) or type(e).__name__),
                       error=str(e)[:200])
        out['wall_s'] = round(time.perf_counter() - wall0, 2)
        out['cpu_s'] = round(time.process_time() - cpu0, 2)
    return out


def _load_labels(labels_dir, shot_id):
    p = Path(labels_dir) / f"{shot_id}.json"
    return json.load(open(p)) if p.exists() else None


RUBY_MAP = {'speed_mph': 'ball_speed', 'rev_rate_rpm': 'rev_rate', 'loft_ft': 'loft'}


def _resolve(path, base_dir):
    """First existing candidate for a manifest-relative path: as-is (cwd), then under base_dir."""
    for c in (path, os.path.join(base_dir or '', path)):
        if c and os.path.exists(c):
            return c
    return None


def secs_after_noon(t):
    """'H:MM:SS' 12-hour (all PM) -> seconds after noon (matches the Ruby session transcription)."""
    h, m, s = (int(x) for x in t.split(':'))
    return (h % 12) * 3600 + m * 60 + s


def _creation_secs(path):
    """A clip's QuickTime recording-start time, as seconds-after-noon, for video<->Ruby matching (M5-05)."""
    import subprocess
    out = subprocess.run(['ffprobe', '-v', 'quiet', '-print_format', 'json',
                          '-show_entries', 'format_tags=com.apple.quicktime.creationdate', path],
                         capture_output=True, text=True).stdout
    try:
        cd = json.loads(out)['format']['tags']['com.apple.quicktime.creationdate']
        return secs_after_noon(cd.split('T')[1][:8])
    except Exception:
        return None


def match_ruby_session(created, rshots, window=70, offset=30):
    """Greedy nearest video->Ruby-shot match by capture time (M5-05): each clip's creation-second + `offset` to
    the nearest UNUSED Ruby shot within `window` s after it; never force-matched. `created`={id: creation_secs};
    `rshots`=[{'t': secs, 'mph':.., 'rpm':..}]. Returns {id: shot}. Earliest clip first (greedy)."""
    matches, used = {}, set()
    for cid, cs in sorted(created.items(), key=lambda kv: kv[1]):
        cands = sorted((abs(r['t'] - (cs + offset)), i, r) for i, r in enumerate(rshots)
                       if 0 < r['t'] - cs <= window and i not in used)
        if cands:
            _, i, r = cands[0]; used.add(i); matches[cid] = r
    return matches


def _match_sessions(manifest, clips_dir, base_dir):
    """Timestamp-match every clip whose ground_truth points at a multi-shot Ruby SESSION file. Returns
    {id: {'mph','rpm',...}}. Single-shot Ruby files are handled directly in _gt_metrics_from_labels."""
    from collections import defaultdict
    by_file = defaultdict(list)
    for s in manifest:
        f = (s.get('ground_truth') or {}).get('file')
        if f:
            by_file[f].append(s)
    out = {}
    for ref_file, shots in by_file.items():
        rp = _resolve(ref_file, base_dir)
        if not rp:
            continue
        data = json.load(open(rp))
        if not (isinstance(data, dict) and 'shots' in data):      # not a session file
            continue
        rshots = [dict(r, t=secs_after_noon(r['time'])) for r in data['shots'] if r.get('mph') is not None]
        created = {}
        for s in shots:
            if s.get('present') is False:
                continue
            cs = _creation_secs(str(Path(clips_dir) / s['clip']))
            if cs is not None:
                created[s['id']] = cs
        out.update(match_ruby_session(created, rshots))
    return out


def _gt_metrics_from_labels(labels, inline_gt, base_dir=None):
    """Map labels / Ruby reference / inline ground truth to the engine's metric names where a direct comparison
    exists. Conservative: only unambiguous mappings are surfaced (speed/rev/loft from Ruby; manual speed)."""
    gt = {}
    # Ruby reference file named in the manifest entry (validation clips) — the independent speed/rev/loft truth.
    ref_file = (inline_gt or {}).get('file')
    if ref_file:
        rp = _resolve(ref_file, base_dir)
        if rp:
            ruby = json.load(open(rp))
            for rk, mk in RUBY_MAP.items():
                if ruby.get(rk) is not None:
                    gt[mk] = ruby[rk]
    if labels:
        ruby = labels.get('ruby') or {}
        for rk, mk in RUBY_MAP.items():
            if ruby.get(rk) is not None:
                gt.setdefault(mk, ruby[rk])
    if inline_gt and inline_gt.get('speed_foul_to_pins_mph') is not None:
        gt.setdefault('ball_speed', inline_gt['speed_foul_to_pins_mph'])
    return gt


# ---------------- main ----------------

def run(manifest, clips_dir, labels_dir, tolerances, only=None, base_dir=None):
    ruby_match = _match_sessions(manifest, clips_dir, base_dir)   # cohort clips -> Ruby shot by capture time
    if ruby_match:
        print(f"[cv_eval] Ruby session match: {len(ruby_match)} clip(s) paired by timestamp "
              f"({', '.join(sorted(ruby_match))})", flush=True)
    results = []
    for s in manifest:
        if only and s['id'] not in only:
            continue
        if s.get('present') is False:
            results.append({'id': s['id'], 'status': 'not_present', 'camera_class': s.get('camera_class')})
            continue
        print(f"[cv_eval] {s['id']} …", flush=True)
        if s.get('mode') == 'form':                  # DEC-094 Form Gate A: event-timing vs the form labels
            r = _run_form_engine(str(Path(clips_dir) / s['clip']))
            r['id'] = s['id']; r['camera_class'] = s.get('camera_class'); r['split'] = s.get('split')
            labels = _load_labels(labels_dir, s['id'])
            r['has_labels'] = labels is not None
            tol = (tolerances.get('form_event_tol_s') or 0.10)
            if labels and r.get('events'):
                r['event_errors'] = form_event_errors(r['events'], labels.get('events'), tol_s=tol)
            results.append(r)
            print(f"[cv_eval]   {r.get('status')} (form) in {r.get('wall_s')}s"
                  + (f" · events scored {len(r.get('event_errors') or {})}/5" if r.get('event_errors') else ''),
                  flush=True)
            continue
        r = _run_engine(str(Path(clips_dir) / s['clip']))
        r['id'] = s['id']; r['camera_class'] = s.get('camera_class'); r['split'] = s.get('split')
        labels = _load_labels(labels_dir, s['id'])
        r['has_labels'] = labels is not None
        gt = _gt_metrics_from_labels(labels, s.get('ground_truth'), base_dir)
        rs = ruby_match.get(s['id'])
        if rs:                                       # timestamp-matched Ruby session shot
            if rs.get('mph') is not None:
                gt.setdefault('ball_speed', rs['mph'])
            if rs.get('rpm') is not None:
                gt.setdefault('rev_rate', rs['rpm'])
            r['ruby_matched'] = {'time': rs.get('time'), 'mph': rs.get('mph'), 'rpm': rs.get('rpm')}
        r['gt_metrics'] = gt
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
    # DEC-094 Form Gate A: per-event timing error + within-tolerance (pass) rate over labeled form clips.
    form_results = [r for r in results if r.get('mode') == 'form']
    scored = [r['event_errors'] for r in form_results if r.get('event_errors')]
    form_gate = None
    if form_results:
        per = {}
        for lk in FORM_EVENT_MAP:
            errs = [d[lk]['err_s'] for d in scored if lk in d]
            if errs:
                per[lk] = {'n': len(errs), 'mae_s': round(sum(errs) / len(errs), 3),
                           'within_rate': round(sum(1 for d in scored if d.get(lk, {}).get('within')) / len(errs), 3)}
        form_gate = {'n_form': len(form_results), 'n_scored': len(scored), 'tol_s': 0.10, 'per_event': per,
                     'form_labels_needed': [r['id'] for r in form_results
                                            if r.get('status') == 'analyzed' and not r.get('has_labels')]}
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
        'form_gate': form_gate,
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
    base_dir = str(Path(a.manifest).resolve().parents[2])   # .../validation/cv_eval/manifest.json -> repo root
    results = run(manifest, a.clips_dir, a.labels_dir, tolerances, only, base_dir)
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
