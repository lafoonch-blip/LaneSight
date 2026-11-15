"""DEC-131 step 2 — measure per-burst selector features on a form clip, to design a landmark-robust delivery
selector. For every qualifying motion burst prints: raw wrist-arc amplitude, the same amplitude normalized by the
bowler's own body scale (torso length + shoulder width, median over the window), the body-center vertical travel
(toward-lane vs toward-camera), and the apparent-scale change (shrinks = moving away from a rear camera). No pose
analysis is run (fast) — just the landmark signals the burst picker sees.

Usage: python examples/form_burst_features.py [clip.mov]   (default: the 01:03 bad clip)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from lanesight_core.form import pose as P


def main():
    clip = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/LaneSightData/form/IMG_bad_0103.mov')
    t, lms = P.extract_landmarks(clip, log=lambda *a: None)
    n = len(t)
    Rx, Ry = P._point(lms, P.R_FOOT_PTS, 0), P._point(lms, P.R_FOOT_PTS, 1)
    Lx, Ly = P._point(lms, P.L_FOOT_PTS, 0), P._point(lms, P.L_FOOT_PTS, 1)
    Rs, Ls = P._speed(Rx, Ry, t), P._speed(Lx, Ly, t)
    footvis = np.nan_to_num(lms[:, [P.L_ANKLE, P.R_ANKLE, P.L_FOOT, P.R_FOOT], 3], nan=0.0).mean(1)
    Ms = P._smooth(np.fmax(np.nan_to_num(Rs, nan=9.0), np.nan_to_num(Ls, nan=9.0)), 9)
    hot = np.nan_to_num(Ms, nan=0.0) > P.BURST_MOTION

    wy_l = P._smooth(P._point(lms, (P.L_WRIST,), 1), 5)
    wy_r = P._smooth(P._point(lms, (P.R_WRIST,), 1), 5)
    sh_mid_y = (P._point(lms, (P.L_SHOULDER,), 1) + P._point(lms, (P.R_SHOULDER,), 1)) / 2
    hip_mid_y = (P._point(lms, (P.L_HIP,), 1) + P._point(lms, (P.R_HIP,), 1)) / 2
    sh_mid_x = (P._point(lms, (P.L_SHOULDER,), 0) + P._point(lms, (P.R_SHOULDER,), 0)) / 2
    torso = np.abs(hip_mid_y - sh_mid_y)                                   # vertical torso length / frame
    shoulder_w = np.abs(P._point(lms, (P.L_SHOULDER,), 0) - P._point(lms, (P.R_SHOULDER,), 0))
    body_cy = (sh_mid_y + hip_mid_y) / 2                                   # torso-center y (image coords, down=+)

    def med(a, m):
        v = a[m]; v = v[~np.isnan(v)]
        return float(np.median(v)) if len(v) else float('nan')

    def edge(a, m):                                                        # mean over first/last ~0.3 s of a mask
        idx = np.where(m)[0]
        if len(idx) < 4:
            return float('nan'), float('nan')
        k = max(2, len(idx) // 5)
        a0 = np.nanmean(a[idx[:k]]); a1 = np.nanmean(a[idx[-k:]])
        return float(a0), float(a1)

    ank_x = (P._point(lms, (P.L_ANKLE,), 0) + P._point(lms, (P.R_ANKLE,), 0)) / 2
    ank_y = (P._point(lms, (P.L_ANKLE,), 1) + P._point(lms, (P.R_ANKLE,), 1)) / 2
    print(f'\n{os.path.basename(clip)}  frames={n} dur={t[-1]-t[0]:.1f}s')
    print(f'{"burst":>14} {"foot":>4} {"raw":>5} {"/torso":>6} {"/shW":>5} '
          f'{"bodyDX":>7} {"bodyDY":>7} {"ankDX":>6} {"ankDY":>6} {"|trav|":>6} {"scale%":>6}')
    i = 0
    while i < n:
        if hot[i]:
            j = i
            while j < n and hot[j]:
                j += 1
            t0, t1 = t[i], t[min(j - 1, n - 1)]
            dur = t1 - t0
            vis = float(footvis[(t >= t0) & (t <= t1)].mean())
            if P.BURST_MIN_S <= dur <= P.BURST_MAX_S and vis >= P.FOOTVIS_MIN:
                wm = (t >= t0 - 1.5) & (t <= t1 + 1.0)                     # swing window
                raw = max([float(np.nanmax(w[wm]) - np.nanmin(w[wm]))
                           for w in (wy_l, wy_r) if np.sum(~np.isnan(w[wm])) >= 4] or [0.0])
                tm, sm = med(torso, wm), med(shoulder_w, wm)
                nt = raw / tm if tm and not np.isnan(tm) and tm > 1e-6 else float('nan')
                ns = raw / sm if sm and not np.isnan(sm) and sm > 1e-6 else float('nan')
                bm = (t >= t0 - 0.4) & (t <= t1 + 0.4)                     # travel window (burst + lead/tail)
                bx0, bx1 = edge(sh_mid_x, bm); by0, by1 = edge(body_cy, bm)
                ax0, ax1 = edge(ank_x, bm); ay0, ay1 = edge(ank_y, bm)
                sc0, sc1 = edge(shoulder_w, bm)
                bdx, bdy = bx1 - bx0, by1 - by0
                adx, ady = ax1 - ax0, ay1 - ay0
                trav = float(np.hypot(bdx, bdy))
                scp = (sc1 - sc0) / sc0 if sc0 and not np.isnan(sc0) and sc0 > 1e-6 else float('nan')
                print(f'[{t0:5.1f},{t1:5.1f}] {vis:4.2f} {raw:5.3f} {nt:6.2f} {ns:5.2f} '
                      f'{bdx:+7.3f} {bdy:+7.3f} {adx:+6.3f} {ady:+6.3f} {trav:6.3f} {scp:+6.2f}')
            i = j
        else:
            i += 1


if __name__ == '__main__':
    main()
