"""Diagnose the two real form uploads (b6cfd17c side, ee17c156 rear) that failed on device. Extracts full-clip
landmarks, reports the view classification over the FULL clip (server behaviour) vs a DELIVERY-WINDOW slice (iOS
behaviour), the delivery isolation, events, step_count, backswing_height_rel, and the per-metric statuses — so we
can see why view / step_count / E4 / E7 failed and whether the metric statuses are honest.
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from lanesight_core.form import pose as P

CACHE = os.path.expanduser('~/LaneSightData/form/lm_cache')
CLIPS = {
    'side_b6cfd17c': os.path.expanduser('~/LaneSightData/form/IMG_side_b6cfd17c.mov'),
    'rear_ee17c156': os.path.expanduser('~/LaneSightData/form/IMG_rear_ee17c156.mov'),
}


def load(name, path):
    cp = os.path.join(CACHE, name + '.npz')
    if os.path.exists(cp) and not os.environ.get('FORCE'):
        d = np.load(cp); return d['t'], d['lms']
    t, lms = P.extract_landmarks(path, log=lambda *a: None)
    np.savez_compressed(cp, t=t, lms=lms); return t, lms


def view_detail(t, lms, lo=None, hi=None):
    if lo is not None:
        m = (t >= lo) & (t <= hi); t, lms = t[m], lms[m]
    vis = lms[:, :, 3]
    ok = ((vis[:, P.L_SHOULDER] > P.MIN_VIS) & (vis[:, P.R_SHOULDER] > P.MIN_VIS)
          & (vis[:, P.L_HIP] > P.MIN_VIS) & (vis[:, P.R_HIP] > P.MIN_VIS))
    if ok.sum() < 8:
        return 'unknown', 0, 0, 0, int(ok.sum())
    f = lms[ok]
    hx = (f[:, P.L_HIP, 0] + f[:, P.R_HIP, 0]) / 2
    hy = (f[:, P.L_HIP, 1] + f[:, P.R_HIP, 1]) / 2
    dx = float(np.nanmax(hx) - np.nanmin(hx)); dy = float(np.nanmax(hy) - np.nanmin(hy))
    v = P.classify_view_from_pose(t, lms)
    return v['view'], dx, dy, (dy / max(dx, 1e-3)), int(ok.sum())


def main():
    _orig = P.extract_landmarks
    for name, path in CLIPS.items():
        if not os.path.exists(path):
            print(f'{name}: clip missing'); continue
        t, lms = load(name, path)
        P.extract_landmarks = lambda *a, _t=t, _l=lms, **k: (_t, _l)   # reuse cached (skip re-extraction in analyze)
        print(f'\n===== {name}  frames={len(t)} dur={t[-1]-t[0]:.1f}s =====')
        v, dx, dy, r, n = view_detail(t, lms)
        print(f'VIEW full-clip: {v}  dx={dx:.3f} dy={dy:.3f} dy/dx={r:.2f} okFrames={n}  (thr 0.30: <0.30=down_lane/side)')
        rec = P.analyze(path, handed='right', log=lambda *a: None)
        ex = rec['_extras']
        aw_v = (ex.get('view_info') or {}).get('view')
        ev = ex.get('events') or {}
        # delivery-window slice view (what iOS classifies over)
        fs, he = ev.get('first_step'), ev.get('hold_end')
        if fs and he:
            vw, dxw, dyw, rw, nw = view_detail(t, lms, fs - 1.6, he + 0.9)
            print(f'VIEW delivery-window [{fs-1.6:.1f},{he+0.9:.1f}]: {vw}  dy/dx={rw:.2f} okFrames={nw}')
        print(f'analyze view={aw_v}  deliv_stage={ (ex.get("stage_report") or {}).get("delivery_isolation") }')
        print('events:', {k: (round(x, 2) if x else None) for k, x in ev.items()})
        print('strikes:', [(round(s, 1), f) for s, f in (ex.get('strikes') or [])][:12], 'n=', len(ex.get('strikes') or []))
        for k in ('step_count', 'approach_time', 'swing_time', 'pushaway_time', 'rhythm_ratio',
                  'backswing_time', 'downswing_time', 'release_time', 'backswing_height_rel', 'finish_hold'):
            m = rec.get(k) or {}
            print(f'  {k:20s} {str(m.get("value")):8s} {m.get("status")}  {str(m.get("reason_code") or "")}')


if __name__ == '__main__':
    main()
