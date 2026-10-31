"""DEC-113 Standard-tier regression: re-run the IMG_8751-54 validation clips through the local engine and
compare ball_speed to ops/regression_reference.json. Exit 0 if every clip is within tol_mph AND no clip that
should analyze now fails; exit 1 otherwise (deploy/commit blocker). On any breach it prints an ESCALATE line —
the spec says a Standard breach auto-escalates to a Full (whole-library) run before promoting a CV change.

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
    clips_dir = os.environ.get('LANESIGHT_CLIPS_DIR', os.path.expanduser('~/LaneSightData/training_videos'))
    present = [(n, c) for n, c in ref['clips'].items() if os.path.exists(os.path.join(clips_dir, n))]
    if not present:
        print(f'[regression] SKIP — no validation clips under {clips_dir} (nothing to check)')
        return 0
    from lanesight_runner.core import analyze_clip
    rows, failures = [], []
    for name, exp in present:
        path = os.path.join(clips_dir, name)
        t = time.time()
        try:
            rec, _, _ = analyze_clip(path, os.path.join(tempfile.mkdtemp(), 'o'), handed='R', timings={})
            d = rec.to_dict() if hasattr(rec, 'to_dict') else rec
            got = ((d.get('metrics') or {}).get('ball_speed') or {}).get('value')
        except Exception as e:
            got = None
            rows.append((name, exp['ball_speed'], None, f'ANALYZE FAIL {type(e).__name__}', round(time.time() - t, 1)))
            failures.append(f'{name}: analyze failed ({type(e).__name__})')
            continue
        if got is None:
            rows.append((name, exp['ball_speed'], None, 'NO SPEED', round(time.time() - t, 1)))
            failures.append(f'{name}: no ball_speed')
            continue
        delta = got - exp['ball_speed']
        ok = abs(delta) <= tol
        rows.append((name, exp['ball_speed'], round(got, 3), f'{"OK" if ok else "BREACH"} Δ{delta:+.3f}', round(time.time() - t, 1)))
        if not ok:
            failures.append(f'{name}: ball_speed {got:.3f} vs ref {exp["ball_speed"]} (Δ{delta:+.3f} > ±{tol})')
    print('[regression] IMG_8751-54 ball_speed vs reference:')
    for n, e, g, v, s in rows:
        print(f'  {n:14s} ref={e:<7} got={str(g):<7} {v:18s} {s}s')
    if failures:
        print('[regression] FAIL:')
        for f in failures:
            print(f'  - {f}')
        print('[regression] ESCALATE -> run the Full (whole-library) benchmark before promoting this CV change.')
        return 1
    print(f'[regression] PASS — all {len(present)} clips within ±{tol} mph')
    return 0


if __name__ == '__main__':
    sys.exit(main())
