"""DEC-128 lane-detector parity: dump the SERVER's RAW lanes (pre-good-filter) + raw VP at a given saturation
floor, replicating find_lanes._detect exactly, so they can be compared against the device's raw lanes.

  LANESIGHT_FFMPEG_DECODE=1 python3 ops/parity_dump_lanes.py <clip.mov> [s_min]
"""
import os, sys, json
import numpy as np
from lanesight_core.cv.stabilize import stabilize
from lanesight_core.cv.lanes import lane_mask, _fit


def _detect(m, w, h, min_run=40, min_rows=120):
    tracks = []; active = []
    for y in range(h - 1, 0, -2):
        row = m[y]; d = np.diff(np.r_[0, row, 0].astype(int))
        st = np.where(d == 1)[0]; en = np.where(d == -1)[0] - 1
        runs = [(a, b) for a, b in zip(st, en) if b - a >= min_run * (0.3 + 0.7 * y / h)]
        new_active = []
        for a, b in runs:
            hit = None
            for t in active:
                _, pa, pb = t[-1]
                if min(b, pb) - max(a, pa) > 0.5 * min(b - a, pb - pa): hit = t; break
            if hit is None: hit = []; tracks.append(hit)
            hit.append((y, a, b)); new_active.append(hit)
        active = new_active
    tracks = [t for t in tracks if len(t) * 2 >= min_rows]
    lanes = []
    for t in tracks:
        T = np.array(t, float)
        L = T[T[:, 1] > 2][:, [1, 0]]; R = T[T[:, 2] < w - 3][:, [2, 0]]
        if len(L) < 30 or len(R) < 30: continue
        pl, sl, nl = _fit(L); pr, sr, nr = _fit(R)
        y_near = T[:, 0].max()
        lanes.append(dict(left=pl, right=pr, res=(sl, sr), y_rng=(T[:, 0].min(), y_near), npts=len(T)))
    vp = None
    if lanes:
        E = [(l['left'], l['res'][0]) for l in lanes] + [(l['right'], l['res'][1]) for l in lanes]
        A = np.array([[1, -p[0]] for p, _ in E]); b = np.array([p[1] for p, _ in E]); wt = np.array([1 / (r + 0.5) for _, r in E])
        AA = A * wt[:, None]; bb = b * wt
        if np.all(np.isfinite(AA)) and np.all(np.isfinite(bb)):
            try:
                vp = np.linalg.lstsq(AA, bb, rcond=None)[0]
            except np.linalg.LinAlgError:
                vp = None
    return lanes, vp


def main():
    path = sys.argv[1]
    s_min = int(sys.argv[2]) if len(sys.argv) > 2 else 70
    S = stabilize(path)
    bg = S['bg']; h, w = bg.shape[:2]
    m = lane_mask(bg, s_min=s_min)
    lanes, vp = _detect(m, w, h)
    print('SERVER_LANES', json.dumps({'clip': os.path.basename(path), 's_min': s_min, 'w': w, 'h': h,
                                      'rawVP': [round(float(vp[0]), 1), round(float(vp[1]), 1)] if vp is not None else None,
                                      'n_raw': len(lanes)}))
    for l in lanes:
        yn = l['y_rng'][1]
        lx = np.polyval(l['left'], yn); rx = np.polyval(l['right'], yn)
        dl = abs(vp[0] - np.polyval(l['left'], vp[1])) if vp is not None else None
        dr = abs(vp[0] - np.polyval(l['right'], vp[1])) if vp is not None else None
        good = (vp is not None and max(dl, dr) < 0.08 * w and (rx - lx) > 60)
        print('  raw lane: center_x=%.0f width=%.0f dl=%.1f dr=%.1f res=(%.1f,%.1f) -> %s'
              % ((lx + rx) / 2, rx - lx, dl or -1, dr or -1, l['res'][0], l['res'][1], 'GOOD' if good else 'REJECT'))


if __name__ == '__main__':
    main()
