"""Perturbation-robustness gate (DEC-117 / CV-review item 4). The headline speed must not move when the DECODE
produces slightly different pixels — that is the server-vs-Mac platform gap turned into a measurable property, and
the guard that the iOS AVFoundation decode can't recreate it. Perturbs the per-frame BGR at the decode boundary
(brightness ±5%, gamma 0.9/1.1, Gaussian σ=2, JPEG q85, ±2-level channel shift) and runs the FULL pipeline on
IMG_8751-54, reporting the ball_speed SPREAD per clip. Target: < 0.2 mph.

This is SLOW (one full analysis per perturbation) — run it on CV-path changes, not every commit:
  LANESIGHT_FFMPEG_DECODE=1 LANESIGHT_FRAME_CACHE_MB=5500 python -m ops.perturb_robustness            # quick subset
  LANESIGHT_FFMPEG_DECODE=1 LANESIGHT_FRAME_CACHE_MB=5500 python -m ops.perturb_robustness --full      # all perts
Exit 0 iff every clip present is within the threshold (default 0.2 mph; --tol to change). Clips absent → SKIP.
"""
from __future__ import annotations
import os, sys, json, tempfile, argparse
import numpy as np

CLIPS = ['IMG_8751', 'IMG_8752', 'IMG_8753', 'IMG_8754']

def _perts(full):
    import cv2
    rng = np.random.RandomState(12345)
    P = {
        'baseline': lambda b: b,
        'bright-5%': lambda b: np.clip(b.astype(np.float32) * 0.95, 0, 255).astype(np.uint8),
        'gamma0.9': lambda b: np.clip(((b.astype(np.float32) / 255.) ** 0.9) * 255., 0, 255).astype(np.uint8),
        'noise s2': lambda b: np.clip(b.astype(np.float32) + rng.normal(0, 2., b.shape), 0, 255).astype(np.uint8),
    }
    if full:
        P.update({
            'bright+5%': lambda b: np.clip(b.astype(np.float32) * 1.05, 0, 255).astype(np.uint8),
            'gamma1.1': lambda b: np.clip(((b.astype(np.float32) / 255.) ** 1.1) * 255., 0, 255).astype(np.uint8),
            'jpeg85': lambda b: cv2.imdecode(cv2.imencode('.jpg', b, [cv2.IMWRITE_JPEG_QUALITY, 85])[1], cv2.IMREAD_COLOR),
            'chan+2': lambda b: np.clip(b.astype(np.int16) + 2, 0, 255).astype(np.uint8),
            'chan-2': lambda b: np.clip(b.astype(np.int16) - 2, 0, 255).astype(np.uint8),
        })
    return P


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--full', action='store_true'); ap.add_argument('--tol', type=float, default=0.2)
    a = ap.parse_args()
    os.environ.setdefault('LANESIGHT_FFMPEG_DECODE', '1'); os.environ.setdefault('LANESIGHT_FRAME_CACHE_MB', '5500')
    clips_dir = os.environ.get('LANESIGHT_CLIPS_DIR', os.path.expanduser('~/LaneSightData/training_videos'))
    def find(cid):
        for ext in ('.mov', '.MOV', '.mp4', '.MP4'):
            p = os.path.join(clips_dir, cid + ext)
            if os.path.exists(p): return p
        return None
    present = [(c, find(c)) for c in CLIPS if find(c)]
    if not present:
        print(f'[perturb] SKIP — no clips under {clips_dir}'); return 0
    from lanesight_core.cv import decode as dec
    perts = _perts(a.full)
    active = [lambda b: b]
    orig = dec.yuv420p_to_bgr
    dec.yuv420p_to_bgr = lambda buf, w, h, cs='bt709', rng='tv': active[0](orig(buf, w, h, cs, rng))
    from lanesight_runner.core import analyze_clip
    rows, failures = [], []
    for clip, path in present:
        vals = {}
        for name, fn in perts.items():
            active[0] = fn
            try:
                rec, _, _ = analyze_clip(path, os.path.join(tempfile.mkdtemp(), 'o'), handed='R', timings={})
                d = rec.to_dict() if hasattr(rec, 'to_dict') else rec
                vals[name] = ((d.get('metrics') or {}).get('ball_speed') or {}).get('value')
            except Exception as e:
                vals[name] = None
        nums = [v for v in vals.values() if isinstance(v, (int, float))]
        spread = (max(nums) - min(nums)) if len(nums) > 1 else None
        nones = [k for k, v in vals.items() if v is None]
        rows.append((clip, spread, len(nums), nones, vals))
        if spread is None or spread > a.tol:
            failures.append(f'{clip}: spread {spread} > ±{a.tol} mph' + (f'; failed perts {nones}' if nones else ''))
        elif nones:
            failures.append(f'{clip}: analysis returned no speed under {nones}')
    print(f'[perturb] ball_speed spread vs decode perturbations (tol ±{a.tol} mph):')
    for clip, spread, n, nones, vals in rows:
        print(f'  {clip:10} spread={("%.3f" % spread) if spread is not None else "n/a":7} over {n} perts' +
              (f'  FAILED:{nones}' if nones else ''))
    dec.yuv420p_to_bgr = orig
    if failures:
        print('[perturb] FAIL:'); [print(f'  - {f}') for f in failures]; return 1
    print(f'[perturb] PASS — all {len(present)} clips within ±{a.tol} mph'); return 0


if __name__ == '__main__':
    sys.exit(main())
