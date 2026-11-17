"""Probe view-classification geometry for the two real uploads (side b6cfd17c, rear ee17c156) over the FULL clip
vs the delivery window, to find a discriminator that separates side from rear robustly (dy/dx alone is marginal:
side 0.25 vs rear 0.29). Also reports shoulder-width shrink (a rear walk-away shrinks the body) and the hip
vertical direction, which are orthogonal depth cues."""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from lanesight_core.form import pose as P

CACHE = os.path.expanduser('~/LaneSightData/form/lm_cache')
CLIPS = {'side_b6cfd17c': 'side', 'rear_ee17c156': 'rear'}


def feats(t, lms):
    vis = lms[:, :, 3]
    ok = ((vis[:, P.L_SHOULDER] > P.MIN_VIS) & (vis[:, P.R_SHOULDER] > P.MIN_VIS)
          & (vis[:, P.L_HIP] > P.MIN_VIS) & (vis[:, P.R_HIP] > P.MIN_VIS))
    f = lms[ok]
    hx = (f[:, P.L_HIP, 0] + f[:, P.R_HIP, 0]) / 2
    hy = (f[:, P.L_HIP, 1] + f[:, P.R_HIP, 1]) / 2
    dx = float(np.nanmax(hx) - np.nanmin(hx)); dy = float(np.nanmax(hy) - np.nanmin(hy))
    sw = np.abs(f[:, P.L_SHOULDER, 0] - f[:, P.R_SHOULDER, 0])
    sw0, sw1 = float(np.nanmedian(sw[:max(3, len(sw)//5)])), float(np.nanmedian(sw[-max(3, len(sw)//5):]))
    # per-frame travel direction: fraction of hip motion that is vertical
    dhx = np.abs(np.diff(hx)); dhy = np.abs(np.diff(hy))
    vfrac = float(np.nansum(dhy) / max(np.nansum(dhx) + np.nansum(dhy), 1e-6))
    return dict(n=int(ok.sum()), dx=dx, dy=dy, ratio=dy / max(dx, 1e-3),
                sw0=sw0, sw1=sw1, sw_shrink=sw0 / max(sw1, 1e-3), vfrac=vfrac)


def main():
    for name, truth in CLIPS.items():
        d = np.load(os.path.join(CACHE, name + '.npz'))
        t, lms = d['t'], d['lms']
        full = feats(t, lms)
        v = P.classify_view_from_pose(t, lms)['view']
        print(f'\n{name}  (truth={truth})  frames={len(t)} dur={t[-1]-t[0]:.1f}s')
        print(f'  classify_view_from_pose -> {v}  (down_lane shows as "Side view")')
        print(f'  full-clip: dx={full["dx"]:.3f} dy={full["dy"]:.3f} dy/dx={full["ratio"]:.3f} '
              f'vert-frac={full["vfrac"]:.3f} sw_shrink={full["sw_shrink"]:.2f} '
              f'(sw {full["sw0"]:.3f}->{full["sw1"]:.3f}) ok={full["n"]}')


if __name__ == '__main__':
    main()
