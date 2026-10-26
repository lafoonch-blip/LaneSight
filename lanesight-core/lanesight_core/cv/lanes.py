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
    h, w = bg.shape[:2]

    def _detect(m):
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
        good = []; vp = None
        if lanes:
            E = [(l['left'], l['res'][0]) for l in lanes] + [(l['right'], l['res'][1]) for l in lanes]
            A = np.array([[1, -p[0]] for p, _ in E]); b = np.array([p[1] for p, _ in E]); wt = np.array([1 / (r + 0.5) for _, r in E])
            vp = np.linalg.lstsq(A * wt[:, None], b * wt, rcond=None)[0]   # x - a*y = b
            # keep only lanes whose edges agree with the common VP (rejects ball returns / caps / glare)
            for l in lanes:
                dl = abs(vp[0] - np.polyval(l['left'], vp[1])); dr = abs(vp[0] - np.polyval(l['right'], vp[1]))
                width_near = np.polyval(l['right'], l['y_rng'][1]) - np.polyval(l['left'], l['y_rng'][1])
                l['vp_miss'] = (dl, dr)
                if max(dl, dr) < 0.08 * w and width_near > 60: good.append(l)
        return lanes, good, vp

    # Lanes are saturated wood, but pale / blonde maple reads low-saturation (this center ~S60 vs the S105
    # floor). Retry the strict pass at lower saturation floors before the gutter-edge fallback. s_min=105 runs
    # first, so well-saturated lanes detect exactly as before (same mask, same result); only a pass that finds
    # nothing drops to a looser floor.
    m = None; lanes = []; good = []; vp = None; used_s = 105
    for s_min in (105, 70, 50):
        mm = lane_mask(bg, s_min=s_min)
        ln, gd, v = _detect(mm)
        if m is None:
            m, lanes = mm, ln                       # keep the strict mask/lanes for the error path + foul default
        if gd:
            m, lanes, good, vp, used_s = mm, ln, gd, v, s_min
            break
    # Pale / low-contrast lanes: the wood is too desaturated for the saturation mask to seed a full track
    # (see the s_min gate in lane_mask). Fall back to edges from the dark gutter->wood boundary, which is
    # saturation-independent. This runs ONLY when the strict pass finds nothing, so well-saturated lanes
    # detect exactly as before.
    foul_mask = m
    if not good:
        fb = _gutter_fallback(bg, log)
        if fb:
            good = fb; foul_mask = lane_mask(bg, s_min=60)
    if not good:
        if not lanes:
            raise RuntimeError(f"lane not detected: no lane-colored wood found in the background "
                               f"({100 * m.mean():.1f}% of pixels matched). Check that the lane is in frame and lit, "
                               "and that the clip isn't HDR (HDR colors look washed out to the decoder)")
        raise RuntimeError(f"lane not detected: {len(lanes)} wood region(s) found but none had straight edges "
                           "meeting at a common vanishing point. Check framing: camera behind the approach, whole lane in view")
    if used_s != 105 and not any(l.get('fallback') for l in good):
        log(f"pale lane: detected at saturation floor s_min={used_s} (wood below the default 105)")
    loose = lane_mask(bg, s_min=min(60, used_s))
    for l in good:
        if l.get('fallback'): continue       # gutter-seeded edges + foul are already set and colour-independent
        _foul(l, foul_mask); _refine_edges(l, loose)
    if good:   # re-solve VP with refined edges
        E = [(l['left'], l['res'][0]) for l in good] + [(l['right'], l['res'][1]) for l in good]
        A = np.array([[1, -p[0]] for p, _ in E]); b = np.array([p[1] for p, _ in E]); wt = np.array([1 / (r + 0.5) for _, r in E])
        if len(good) == 1: vp = np.linalg.solve(A, b)
        else: vp = np.linalg.lstsq(A * wt[:, None], b * wt, rcond=None)[0]
    for l in good:   # (re)measure edge agreement with the final VP (fallback lanes have none yet)
        l['vp_miss'] = (abs(vp[0] - np.polyval(l['left'], vp[1])), abs(vp[0] - np.polyval(l['right'], vp[1])))
    log(f"VP ({vp[0]:.0f},{vp[1]:.0f}); {len(good)}/{len(lanes)} lanes consistent: " +
        '; '.join(f"edges±{l['res'][0]:.1f}/{l['res'][1]:.1f}px vp-miss {l['vp_miss'][0]:.0f}/{l['vp_miss'][1]:.0f}px "
                  f"foul±{l['foul_res']:.1f}px" for l in good))
    return dict(vp=vp, lanes=good, mask=m)

def _ransac_edge(P, tol=3.5, min_inliers=40, min_span=200, iters=3000):
    """Fit one straight lane edge x = a*y + b to gutter-boundary points that are fragmented and salted with
    outliers (approach bleed, mid-lane streaks). Seeded deterministically so a re-run is reproducible."""
    P = np.asarray(P, float)
    if len(P) < min_inliers: return None
    y, x = P[:, 1], P[:, 0]; best = (0, None); rng = np.random.default_rng(0)
    for _ in range(iters):
        i, j = rng.choice(len(P), 2, replace=False)
        if abs(y[i] - y[j]) < min_span: continue
        a = (x[i] - x[j]) / (y[i] - y[j]); b = x[i] - a * y[i]
        inl = np.abs(x - (a * y + b)) < tol
        span = y[inl].max() - y[inl].min() if inl.sum() > 2 else 0
        sc = inl.sum() * (span >= min_span)
        if sc > best[0]: best = (sc, inl)
    if best[1] is None: return None
    inl = best[1]
    for _ in range(3):
        p = np.polyfit(y[inl], x[inl], 1); inl = np.abs(x - np.polyval(p, y)) < tol
    if inl.sum() < min_inliers or (y[inl].max() - y[inl].min()) < min_span: return None
    p = np.polyfit(y[inl], x[inl], 1)
    return p, float((x[inl] - np.polyval(p, y[inl])).std()), (float(y[inl].min()), float(y[inl].max()))

def _gutter_fallback(bg, log=print):
    """Seed lanes from the dark gutter->wood boundary instead of the wood colour, for pale lanes the saturation
    mask can't fill. Every wood-run boundary that has a dark (gutter) pixel just outside it is an edge point;
    the distinct straight edge lines are extracted (iterated RANSAC), and every adjacent pair enclosing real
    wood and forming a VP-consistent wedge that widens toward the camera becomes a candidate lane. All are
    returned so the caller's ball-track step picks the one the ball is on. [] -> caller raises a framing error."""
    h, w = bg.shape[:2]
    hsv = cv2.cvtColor(bg, cv2.COLOR_BGR2HSV); V = hsv[..., 2]
    dark = V < 62                                                   # gutter / shadow (saturation-independent)
    wood = (hsv[..., 0] >= 5) & (hsv[..., 0] <= 28) & (V > 70)      # wood hue + bright, any saturation
    gm = 20; pts = []                                              # a real gutter run beside the edge, not a speck
    for y in range(h - 1, int(0.18 * h), -2):
        row = wood[y].astype(int); d = np.diff(np.r_[0, row, 0])
        for a, b in zip(np.where(d == 1)[0], np.where(d == -1)[0] - 1):
            if b - a < 25: continue
            if a > 2 and dark[y, max(0, a - gm):a].sum() >= 10: pts.append((a, y))        # wood left edge at a gutter
            if b < w - 3 and dark[y, b + 1:min(w, b + gm)].sum() >= 10: pts.append((b, y))  # wood right edge at a gutter
    P = np.array(pts, float)
    if len(P) < 80: return []
    # extract distinct straight edge lines, peeling off each line's inliers before the next
    lines = []; rem = P
    while len(rem) >= 40 and len(lines) < 8:
        r = _ransac_edge(rem)
        if r is None: break
        p, res, yr = r
        on = np.abs(rem[:, 0] - np.polyval(p, rem[:, 1])) < 4.0
        lines.append((p, res, yr)); rem = rem[~on]
    if len(lines) < 2: return []
    lines.sort(key=lambda L: np.polyval(L[0], h * 0.5))              # left to right at mid-height
    out = []
    for (pl, sl, yl), (pr, sr, yr) in zip(lines, lines[1:]):
        o_lo, o_hi = max(yl[0], yr[0]), min(yl[1], yr[1])          # region where BOTH edges were observed
        if o_hi - o_lo < 150: continue
        # width is validated where both edges are seen; the lane itself spans top-of-either to the foul line
        # (the longer edge's bottom = where the gutter ends), reached by extrapolating the shorter edge.
        y_lo, y_hi = min(yl[0], yr[0]), max(yl[1], yr[1])
        w_o0 = np.polyval(pr, o_lo) - np.polyval(pl, o_lo); w_o1 = np.polyval(pr, o_hi) - np.polyval(pl, o_hi)
        w_hi = np.polyval(pr, y_hi) - np.polyval(pl, y_hi)
        vpy = (pl[1] - pr[1]) / (pr[0] - pl[0]) if abs(pr[0] - pl[0]) > 1e-6 else -1e9
        if max(sl, sr) > 4.0 or not (60 < w_o0 < w_o1) or not (0 < w_hi < 1.6 * w) or not (vpy < y_lo): continue
        # the enclosed strip must be mostly wood (rejects a gutter interior framed by two edge lines)
        frac = np.mean([wood[int(y), int(np.clip((np.polyval(pl, y) + np.polyval(pr, y)) / 2, 0, w - 1))]
                        for y in np.linspace(o_lo, o_hi, 40)])
        if frac < 0.5: continue
        out.append(dict(left=pl, right=pr, res=(sl, sr), y_rng=(y_lo, y_hi), npts=0, track=np.empty((0, 3)),
                        foul=np.array([0.0, y_hi]), foul_res=0.0, foul_n=2, fallback=True))
    if out:
        log(f"gutter fallback: pale lane, {len(out)} candidate lane(s) from gutter edges "
            + "; ".join(f"res {l['res'][0]:.1f}/{l['res'][1]:.1f}px" for l in out))
    return out

def _refine_edges(l, loose):
    h, w = loose.shape
    fc = foul_corners(l); y_foul = fc[:, 1].max()
    T = l['track']; cen = {int(y): (a + b) / 2 for y, a, b in T}
    for it in range(3):
        L, R = [], []
        for y in range(int(y_foul) - 4, int(l['y_rng'][0]) - 250, -2):
            if y < 0: break
            if y >= h: continue                 # foul line can extrapolate below the frame; skip off-image rows
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
    P = np.array(pts, float)
    if len(P) < 6:          # no foul line in view: the lane runs off the bottom of the frame (camera too low/close).
        raise RuntimeError("lane not detected: foul line not found — the lane runs off the bottom of the frame "
                           "(the foul line must be in view; raise or pull back the camera)")
    keep = np.ones(len(P), bool)
    for _ in range(8):
        c = np.polyfit(P[keep, 0], P[keep, 1], 1); r = P[:, 1] - np.polyval(c, P[:, 0])
        keep = np.abs(r) < max(2.5 * r[keep].std(), 2)
        if keep.sum() < 2: keep = np.abs(r) < max(2.5 * r.std(), 2); break    # don't let the trim collapse the fit
    l['foul'] = c; l['foul_res'] = float(r[keep].std()); l['foul_n'] = int(keep.sum())

def lane_x(l, y): return np.polyval(l['left'], y), np.polyval(l['right'], y)

def foul_corners(l):
    c, d = l['foul']; out = []
    for a, b in (l['left'], l['right']):
        y = (c * b + d) / (1 - c * a); out.append((a * y + b, y))
    return np.array(out)
