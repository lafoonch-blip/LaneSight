"""Stage 2: automatic lane geometry from the background plate.
Lane surface = saturated wood (approach wood is paler, so the foul line is the lane mask's near boundary).
Edges come from per-row wood runs tracked across rows; all lanes share one vanishing point."""
import cv2, numpy as np

def lane_mask(bgr, s_min=105):
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    H, S, V = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    m = ((H >= 5) & (H <= 25) & (S > s_min) & (V > 70)).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    return cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))

def _fit(P, it=8):
    """robust x = a*y + b"""
    P = np.asarray(P, float); keep = np.ones(len(P), bool)
    for _ in range(it):
        p = np.polyfit(P[keep, 1], P[keep, 0], 1); r = P[:, 0] - np.polyval(p, P[:, 1])
        keep = np.abs(r) < max(2.5 * r[keep].std(), 1.5)
    return p, float(r[keep].std()), int(keep.sum())

def find_lanes(bg, log=print, min_run=40, min_rows=120):
    h, w = bg.shape[:2]; m = lane_mask(bg)
    # 1. runs per row, linked into tracks by overlap
    tracks = []      # each: list of (y, a, b)
    active = []
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
        # foul line: near (bottom) boundary of the lane surface, measured across the lane
        y_near = T[:, 0].max()
        lanes.append(dict(left=pl, right=pr, res=(sl, sr), y_rng=(T[:, 0].min(), y_near), npts=len(T), track=T))
    # 2. common vanishing point from all edges (each edge is a line x = a*y + b)
    E = [(l['left'], l['res'][0]) for l in lanes] + [(l['right'], l['res'][1]) for l in lanes]
    A = np.array([[1, -p[0]] for p, _ in E]); b = np.array([p[1] for p, _ in E]); wt = np.array([1 / (r + 0.5) for _, r in E])
    vp = np.linalg.lstsq(A * wt[:, None], b * wt, rcond=None)[0] if len(E) >= 2 else None   # x - a*y = b
    vp_res = np.abs(A @ vp - b)
    # keep only lanes whose edges agree with the common VP (rejects ball returns / caps / glare)
    good = []
    for i, l in enumerate(lanes):
        dl = abs(vp[0] - np.polyval(l['left'], vp[1])); dr = abs(vp[0] - np.polyval(l['right'], vp[1]))
        width_near = np.polyval(l['right'], l['y_rng'][1]) - np.polyval(l['left'], l['y_rng'][1])
        l['vp_miss'] = (dl, dr)
        if max(dl, dr) < 0.08 * w and width_near > 60: good.append(l)
    for l in good: _foul(l, m)
    loose = lane_mask(bg, s_min=60)
    for l in good: _refine_edges(l, loose)
    if good:   # re-solve VP with refined edges
        E = [(l['left'], l['res'][0]) for l in good] + [(l['right'], l['res'][1]) for l in good]
        A = np.array([[1, -p[0]] for p, _ in E]); b = np.array([p[1] for p, _ in E]); wt = np.array([1 / (r + 0.5) for _, r in E])
        if len(good) == 1: vp = np.linalg.solve(A, b)
        else: vp = np.linalg.lstsq(A * wt[:, None], b * wt, rcond=None)[0]
    log(f"VP ({vp[0]:.0f},{vp[1]:.0f}); {len(good)}/{len(lanes)} lanes consistent: " +
        '; '.join(f"edges±{l['res'][0]:.1f}/{l['res'][1]:.1f}px vp-miss {l['vp_miss'][0]:.0f}/{l['vp_miss'][1]:.0f}px "
                  f"foul±{l['foul_res']:.1f}px" for l in good))
    return dict(vp=vp, lanes=good, mask=m)

def _refine_edges(l, loose):
    h, w = loose.shape
    fc = foul_corners(l); y_foul = fc[:, 1].max()
    T = l['track']; cen = {int(y): (a + b) / 2 for y, a, b in T}
    for it in range(3):
        L, R = [], []
        for y in range(int(y_foul) - 4, int(l['y_rng'][0]) - 250, -2):
            if y < 0: break
            xa, xb = lane_x(l, y)
            xc = cen.get(y, (xa + xb) / 2) if it == 0 else (xa + xb) / 2
            xc = int(xc)
            if not (0 < xc < w - 1) or not loose[y, xc]: continue
            a = xc
            while a > 0 and loose[y, a - 1]: a -= 1
            b = xc
            while b < w - 1 and loose[y, b + 1]: b += 1
            tol = np.inf if it == 0 else 0.1 * (xb - xa) + 3
            if a > 1 and abs(a - xa) < tol: L.append((a, y))
            if b < w - 2 and abs(b - xb) < tol: R.append((b, y))
        if len(L) > 30: l['left'], sl, _ = _fit(L); l['res'] = (sl, l['res'][1])
        if len(R) > 30: l['right'], sr, _ = _fit(R); l['res'] = (l['res'][0], sr)

def _foul(l, m):
    h, w = m.shape; pts = []
    xl = lambda y: np.polyval(l['left'], y); xr = lambda y: np.polyval(l['right'], y)
    y0 = int(l['y_rng'][0] + 0.5 * (l['y_rng'][1] - l['y_rng'][0]))
    for f in np.linspace(0.1, 0.9, 41):
        last = None; gap = 0
        for y in range(y0, h):
            x = int(round(xl(y) + f * (xr(y) - xl(y))))
            if not (0 <= x < w): break
            if m[y, x]: last = (x, y); gap = 0
            else:
                gap += 1
                if last is not None and gap > 25: break
        if last and last[1] < h - 3: pts.append(last)
    P = np.array(pts, float); keep = np.ones(len(P), bool)
    for _ in range(8):
        c = np.polyfit(P[keep, 0], P[keep, 1], 1); r = P[:, 1] - np.polyval(c, P[:, 0])
        keep = np.abs(r) < max(2.5 * r[keep].std(), 2)
    l['foul'] = c; l['foul_res'] = float(r[keep].std()); l['foul_n'] = int(keep.sum())

def lane_x(l, y): return np.polyval(l['left'], y), np.polyval(l['right'], y)

def foul_corners(l):
    c, d = l['foul']; out = []
    for a, b in (l['left'], l['right']):
        y = (c * b + d) / (1 - c * a); out.append((a * y + b, y))
    return np.array(out)
