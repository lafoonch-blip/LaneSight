"""Debug the delivery segmentation on one form clip (DEC-131 — the 2026-11-04 01:03 UTC bad upload).
Runs the pose backend, dumps the delivery window, swing events, foot strikes, and the wrist/foot signals around
the chosen events so we can see WHY segmentation failed. No per-clip tuning — this is a diagnostic."""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from lanesight_core.form import pose as P

CLIP = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/LaneSightData/form/IMG_bad_0103.mov')


def main():
    t, lms = P.extract_landmarks(CLIP, log=print)
    fps = 1.0 / np.median(np.diff(t)) if len(t) > 1 else 30.0
    print(f'\nframes={len(t)} dur={t[-1]-t[0]:.1f}s fps~{fps:.2f}')
    Rx, Ry = P._point(lms, P.R_FOOT_PTS, 0), P._point(lms, P.R_FOOT_PTS, 1)
    Lx, Ly = P._point(lms, P.L_FOOT_PTS, 0), P._point(lms, P.L_FOOT_PTS, 1)
    Rs, Ls = P._speed(Rx, Ry, t), P._speed(Lx, Ly, t)
    slow = P._looks_slowmo(t, lms, Rs, Ls)
    print(f'looks_slowmo={slow}')
    # foot-visibility over time (coarse) + the combined foot motion peaks
    footvis = np.nan_to_num(lms[:, [P.L_ANKLE, P.R_ANKLE, P.L_FOOT, P.R_FOOT], 3], nan=0.0).mean(1)
    Ms = P._smooth(np.fmax(np.nan_to_num(Rs, nan=9.0), np.nan_to_num(Ls, nan=9.0)), 9)
    # list the motion bursts find_delivery would see
    hot = np.nan_to_num(Ms, nan=0.0) > P.BURST_MOTION
    i = 0
    print('\nmotion bursts (BURST_MOTION=%.2f):' % P.BURST_MOTION)
    while i < len(t):
        if hot[i]:
            j = i
            while j < len(t) and hot[j]:
                j += 1
            t0, t1 = t[i], t[min(j-1, len(t)-1)]
            vis = float(footvis[(t >= t0) & (t <= t1)].mean())
            dur = t1 - t0
            tag = 'OK' if (P.BURST_MIN_S <= dur <= P.BURST_MAX_S and vis >= P.FOOTVIS_MIN) else 'skip'
            print(f'  [{t0:6.2f},{t1:6.2f}] dur={dur:4.2f}s footvis={vis:.2f}  {tag}')
            i = j
        else:
            i += 1
    # per-burst swing amplitude (bowling-arm arc) + footvis — the selector's inputs
    wy_l = P._smooth(P._point(lms, (P.L_WRIST,), 1), 5)
    wy_r = P._smooth(P._point(lms, (P.R_WRIST,), 1), 5)
    def amp(t0, t1):
        m = (t >= t0 - 1.5) & (t <= t1 + 1.0)
        a = []
        for wy in (wy_l, wy_r):
            v = wy[m][~np.isnan(wy[m])]
            if len(v) >= 4:
                a.append(float(np.max(v) - np.min(v)))
        return max(a) if a else 0.0
    print('\nqualifying-burst swing amps (footvis>=FOOTVIS_MIN):')
    i = 0
    while i < len(t):
        if hot[i]:
            j = i
            while j < len(t) and hot[j]:
                j += 1
            t0, t1 = t[i], t[min(j-1, len(t)-1)]
            dur = t1 - t0
            vis = float(footvis[(t >= t0) & (t <= t1)].mean())
            if P.BURST_MIN_S <= dur <= P.BURST_MAX_S and vis >= P.FOOTVIS_MIN:
                print(f'  [{t0:6.2f},{t1:6.2f}] footvis={vis:.2f} swing_amp={amp(t0,t1):.3f}')
            i = j
        else:
            i += 1
    delivery = P._find_delivery(t, lms, Rs, Ls)
    print('\n_find_delivery ->', None if delivery is None else
          f'approach_win={tuple(round(x,2) for x in delivery[0])} hold={tuple(round(x,2) for x in delivery[1])}')
    rec = P.analyze(CLIP, handed='right', log=lambda *a: None)
    ex = rec['_extras']
    print('\nview:', (ex.get('view_info') or {}).get('view'), ' swing_source:', ex.get('swing_source'))
    print('events:', {k: (round(v, 3) if v is not None else None) for k, v in (ex.get('events') or {}).items()})
    print('strikes:', ex.get('strikes'))
    print('step_intervals:', ex.get('step_intervals_values'))
    print('slowmo:', ex.get('slowmo'))
    print('\nmetrics:')
    for k in ('step_count', 'approach_time', 'swing_time', 'pushaway_time', 'backswing_time',
              'downswing_time', 'release_time', 'rhythm_ratio', 'finish_hold'):
        m = rec.get(k) or {}
        print(f'  {k:16s} {str(m.get("value")):8s} {m.get("status")}')


if __name__ == '__main__':
    main()
