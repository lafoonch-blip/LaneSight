"""Compare view classification over the FULL clip (current server method) vs the APPROACH WINDOW (first_step →
hold_start) for every cached clip, against the ground-truth label. The full-clip dy/dx is polluted by the bowler
walking around between shots (dx huge) which flips real rear clips to down_lane; the approach window is the clean
travel-direction domain. Goal: a window that keeps all 7 labeled clips correct AND fixes the 2 new real uploads."""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from lanesight_core.form import pose as P

CACHE = os.path.expanduser('~/LaneSightData/form/lm_cache')
# ground truth (down_lane == side). New two from the delivery-frame inspection (opposite of the IDs' filenames).
TRUTH = {'IMG_8824': 'down_lane', 'IMG_8825': 'down_lane', 'IMG_8826': 'down_lane', 'IMG_8980': 'down_lane',
         'IMG_8846': 'rear', 'IMG_8847': 'rear', 'IMG_8848': 'rear',
         'side_b6cfd17c': 'rear', 'rear_ee17c156': 'down_lane'}


def ratio(t, lms, lo=None, hi=None):
    if lo is not None:
        m = (t >= lo) & (t <= hi); t, lms = t[m], lms[m]
    vis = lms[:, :, 3]
    ok = ((vis[:, P.L_SHOULDER] > P.MIN_VIS) & (vis[:, P.R_SHOULDER] > P.MIN_VIS)
          & (vis[:, P.L_HIP] > P.MIN_VIS) & (vis[:, P.R_HIP] > P.MIN_VIS))
    if ok.sum() < 8:
        return None, None, 0
    f = lms[ok]
    hx = (f[:, P.L_HIP, 0] + f[:, P.R_HIP, 0]) / 2
    hy = (f[:, P.L_HIP, 1] + f[:, P.R_HIP, 1]) / 2
    dx = float(np.nanmax(hx) - np.nanmin(hx)); dy = float(np.nanmax(hy) - np.nanmin(hy))
    return dy / max(dx, 1e-3), (dx, dy), int(ok.sum())


def verdict(r):
    return 'down_lane' if (r is not None and r < 0.30) else ('rear' if r is not None else 'unknown')


def main():
    _orig = P.extract_landmarks
    rows = []
    for name, truth in TRUTH.items():
        p = os.path.join(CACHE, name + '.npz')
        if not os.path.exists(p):
            print(f'{name}: no cache'); continue
        d = np.load(p); t, lms = d['t'], d['lms']
        P.extract_landmarks = lambda *a, _t=t, _l=lms, **k: (_t, _l)
        rec = P.analyze(name, handed='right', log=lambda *a: None)
        ev = (rec['_extras'].get('events') or {})
        fs, hs, ss = ev.get('first_step'), ev.get('hold_start'), ev.get('slide_stop')
        rf, _, nf = ratio(t, lms)                                   # full clip
        aend = hs or ss
        ra, _, na = (ratio(t, lms, fs, aend) if (fs and aend) else (None, None, 0))   # approach window
        rows.append((name, truth, rf, ra, fs, aend, nf, na))
    P.extract_landmarks = _orig
    print(f'{"clip":16s} {"truth":9s} {"full r":>7s} {"->":>10s} {"appr r":>7s} {"->":>10s}  okA')
    nfull = napp = 0
    for name, truth, rf, ra, fs, aend, nf, na in rows:
        vf, va = verdict(rf), verdict(ra)
        okf, oka = (vf == truth), (va == truth)
        nfull += okf; napp += oka
        print(f'{name:16s} {truth:9s} {rf if rf else 0:7.3f} {vf:>10s} {ra if ra else 0:7.3f} {va:>10s}  {na}'
              f'  {"FULL✗" if not okf else "":5s} {"APPR✗" if not oka else ""}')
    print(f'\nfull-clip correct: {nfull}/{len(rows)}   approach-window correct: {napp}/{len(rows)}')


if __name__ == '__main__':
    main()
