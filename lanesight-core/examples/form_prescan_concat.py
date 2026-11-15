"""DEC-131 — validate the swing-aware prescan's CONCATENATED findDelivery (the device approach): coarse-subsample
the candidate windows, concatenate, run _find_delivery ONCE, and check the winning burst lands on the delivery.
Hand-specified (delivery, distractor[, distractor2]) windows per clip; reuses lm_cache/*.npz.
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from lanesight_core.form import pose as P

CACHE = os.path.expanduser('~/LaneSightData/form/lm_cache')
LEAD, TAIL = 1.6, 0.9

# clip -> (release_approx, [candidate bursts (t0,t1)]) — delivery first, then the distractor(s) the device sees
CASES = {
    'IMG_8980': (16.96, [(15.1, 17.2), (21.1, 22.1), (10.5, 12.5)]),
    'IMG_8847': (16.77, [(15.5, 17.4), (20.8, 21.9), (5.5, 8.5)]),
    'IMG_8848': (14.67, [(13.5, 15.0), (18.5, 20.5), (0.5, 5.5)]),
    'IMG_8825': (18.84, [(17.8, 19.4), (0.2, 2.6), (24.0, 26.5)]),
    'IMG_8826': (17.57, [(16.4, 17.7), (0.3, 4.7), (28.0, 31.0)]),
    'IMG_8824': (4.29, [(1.9, 5.2)]),
    'IMG_8846': (14.80, [(13.6, 15.5)]),
    'IMG_0103': (None, [(20.6, 21.6), (2.0, 5.2), (28.1, 30.0)]),
}
STRIDE = 2


def main():
    ok = 0
    tot = 0
    for name, (rel, cands) in CASES.items():
        cp = os.path.join(CACHE, name + '.npz')
        if not os.path.exists(cp):
            print(f'{name}: no cache'); continue
        d = np.load(cp); t, lms = d['t'], d['lms']
        # coarse-subsample the union of candidate windows, concatenated (contiguous array, time gaps between windows)
        windows = [(max(0, a - LEAD), b + TAIL) for a, b in cands]
        mask = np.zeros(len(t), bool)
        for (w0, w1) in windows:
            mask |= (t >= w0) & (t <= w1)
        idx = np.where(mask)[0][::STRIDE]
        tc, lc = t[idx], lms[idx]
        Rx, Ry = P._point(lc, P.R_FOOT_PTS, 0), P._point(lc, P.R_FOOT_PTS, 1)
        Lx, Ly = P._point(lc, P.L_FOOT_PTS, 0), P._point(lc, P.L_FOOT_PTS, 1)
        Rs, Ls = P._speed(Rx, Ry, tc), P._speed(Lx, Ly, tc)
        win = P._find_delivery(tc, lc, Rs, Ls)
        tot += 1
        if win is None:
            print(f'{name}: findDelivery -> None  BAD'); continue
        b0 = win[0][0] + 0.4
        if rel is not None:
            good = abs(b0 - rel) <= 2.5 or (win[0][0] - 0.5 <= rel <= win[0][1] + 1.0)
        else:
            good = b0 >= 10.0        # 01:03: not pre-shot
        ok += 1 if good else 0
        print(f'{name}: rel={rel} picked burst~{b0:.1f}s (win {win[0][0]:.1f}-{win[0][1]:.1f})  {"OK " if good else "BAD"}')
    print(f'\n{ok}/{tot} pick the delivery (concatenated coarse findDelivery, stride {STRIDE})')


if __name__ == '__main__':
    main()
