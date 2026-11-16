"""DEC-113 Standard-tier regression: re-run the IMG_8751-54 validation clips through the local engine and
compare the speed metric to ops/regression_reference.json. Exit 0 if every clip is within tol_mph AND no clip
that should analyze now fails; exit 1 otherwise (deploy/commit blocker). On any breach it prints an ESCALATE
line — the spec says a Standard breach auto-escalates to a Full (whole-library) run before promoting a CV change.

Compares against Shayne's LABELED TRUTH where it exists (a clip's `truth`, from the 59.44 ft foul_cross ->
first_pin_contact labels in validation/labels/pin_anchor_truth.json), NOT old engine output — so a change that
moves the engine CLOSER to truth passes instead of being flagged (2026-11-01: this is why the IMG_8752
brightness-relative-threshold change d47bc12 — 18.308 -> 17.891, truth 18.00 — had to be bypassed before).
A clip with no `truth` (e.g. an unlabeled new clip) falls back to its recorded `baseline` engine value. The
metric compared is `ref['metric']` (default ball_speed).

Clips live on the Mac (never in the repo): default dir ~/LaneSightData/training_videos, override with
LANESIGHT_CLIPS_DIR. Runs with the canonical decode env so it matches production:
  LANESIGHT_FFMPEG_DECODE=1 LANESIGHT_FRAME_CACHE_MB=5500 python3 ops/regression_tier.py
If the clips aren't present (e.g. CI without them) it SKIPS with exit 0 and a clear note (never a false block).
"""
import os, sys, json, time, tempfile

REF = os.path.join(os.path.dirname(__file__), 'regression_reference.json')


def main():
    os.environ.setdefault('LANESIGHT_FFMPEG_DECODE', '1')
    os.environ.setdefault('LANESIGHT_FRAME_CACHE_MB', '5500')
    ref = json.load(open(REF))
    tol = ref['tol_mph']
    metric = ref.get('metric', 'ball_speed')
    clips_dir = os.environ.get('LANESIGHT_CLIPS_DIR', os.path.expanduser('~/LaneSightData/training_videos'))
    present = [(n, c) for n, c in ref['clips'].items() if os.path.exists(os.path.join(clips_dir, n))]
    if not present:
        print(f'[regression] SKIP — no validation clips under {clips_dir} (nothing to check)')
        return 0
    from lanesight_runner.core import analyze_clip
    rows, failures, warnings_ = [], [], []
    for name, exp in present:
        # compare against labeled TRUTH where it exists; otherwise the recorded engine baseline
        target = exp.get('truth', exp.get('baseline', exp.get('ball_speed')))
        basis = 'truth' if 'truth' in exp else ('baseline' if 'baseline' in exp else 'legacy')
        path = os.path.join(clips_dir, name)
        t = time.time()
        try:
            rec, _, _ = analyze_clip(path, os.path.join(tempfile.mkdtemp(), 'o'), handed='R', timings={})
            d = rec.to_dict() if hasattr(rec, 'to_dict') else rec
            got = ((d.get('metrics') or {}).get(metric) or {}).get('value')
        except Exception as e:
            got = None
            rows.append((name, target, basis, None, f'ANALYZE FAIL {type(e).__name__}', round(time.time() - t, 1)))
            failures.append(f'{name}: analyze failed ({type(e).__name__})')
            continue
        if got is None:
            rows.append((name, target, basis, None, f'NO {metric}', round(time.time() - t, 1)))
            failures.append(f'{name}: no {metric}')
            continue
        delta = got - target
        ok = abs(delta) <= tol
        # A clip with a documented `known_issue` (an accepted, tracked regression vs truth) does not hard-block,
        # but is reported LOUDLY and is CAPPED: if it drifts further than tol beyond the recorded known delta it
        # fails again (so it can't silently get worse). Clear the known_issue once the clip is fixed.
        ki = exp.get('known_issue')
        if not ok and ki:
            known_val = target + ki['delta']
            if abs(got - known_val) <= tol:
                warnings_.append(f'{name}: KNOWN ISSUE {metric} {got:.3f} vs truth {target} (Δ{delta:+.3f}) — {ki["reason"]}')
                rows.append((name, target, basis, round(got, 3), f'KNOWN Δ{delta:+.3f}', round(time.time() - t, 1)))
                continue
            # worse than the known regression → real new breach
            rows.append((name, target, basis, round(got, 3), f'WORSE Δ{delta:+.3f}', round(time.time() - t, 1)))
            failures.append(f'{name}: {metric} {got:.3f} worse than the known issue ({known_val:.3f}±{tol}) — {ki["reason"]}')
            continue
        rows.append((name, target, basis, round(got, 3), f'{"OK" if ok else "BREACH"} Δ{delta:+.3f}', round(time.time() - t, 1)))
        if not ok:
            failures.append(f'{name}: {metric} {got:.3f} vs {basis} {target} (Δ{delta:+.3f} > ±{tol})')
    print(f'[regression] IMG_8751-54 {metric} vs labeled truth (±{tol} mph):')
    for n, e, b, g, v, s in rows:
        print(f'  {n:14s} {b:8s}={e:<7} got={str(g):<7} {v:18s} {s}s')
    if warnings_:
        print('[regression] KNOWN ISSUES (tracked, not blocking — clear once fixed):')
        for w in warnings_:
            print(f'  ! {w}')
    if failures:
        print('[regression] FAIL:')
        for f in failures:
            print(f'  - {f}')
        print('[regression] ESCALATE -> run the Full (whole-library) benchmark before promoting this CV change.')
        return 1
    extra = f' ({len(warnings_)} known issue{"s" if len(warnings_) != 1 else ""})' if warnings_ else ''
    print(f'[regression] PASS — all {len(present)} clips within ±{tol} mph of truth or a tracked known issue{extra}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
