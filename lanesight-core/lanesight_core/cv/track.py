"""Stage 3: ball candidates in stabilized coordinates, track linking, impact detection."""
import cv2, numpy as np
from .stabilize import frames
from .lanes import lane_x, foul_corners
from ._parallel import pmap_frames

BALL_IN, LANE_IN = 8.59, 41.5

def exp_diam(lane, y):
    xa, xb = lane_x(lane, y); return BALL_IN / LANE_IN * (xb - xa)

def contact_row(lane, top):
    """ground-contact row given the ball's top row: ct = top + D(ct), D linear in y"""
    a1, b1 = lane['left']; a2, b2 = lane['right']; k = BALL_IN / LANE_IN
    return (top + k * (b2 - b1)) / (1 - k * (a2 - a1))

def lane_roi(lane, vp, shape, pad=0.25):
    h, w = shape[:2]; yy, xx = np.mgrid[0:h, 0:w]
    xa, xb = lane_x(lane, yy); wd = xb - xa
    y_foul = foul_corners(lane)[:, 1].max()
    return (xx > xa - pad * wd) & (xx < xb + pad * wd) & (yy > vp[1] + 0.02 * (y_foul - vp[1])) & (yy < y_foul + 0.6 * (y_foul - vp[1]))

def extract_blobs(path, S, lane, vp, thr=35, log=print):
    bg = S['bg']; h, w = bg.shape[:2]
    roi = lane_roi(lane, vp, bg.shape)
    ys, xs = np.where(roi)
    if ys.size == 0:          # degenerate lane geometry (VP/foul inverted the ROI): no region to search
        raise RuntimeError("lane geometry unusable: the detected lane produced an empty search region "
                           "(awkward camera angle). Reshoot with the camera behind the lane, square to it.")
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    roic = roi[y0:y1, x0:x1]; bgc = bg[y0:y1, x0:x1].astype(np.int16)
    Hs = S['Hs']; ts = S['ts']
    # Each frame is processed independently (warp + background diff + connected components), so fan the per-frame
    # work across cores with decode kept sequential and results reassembled in frame order (pure speed-up; the
    # computation and its output are identical to the serial loop).
    def _frame(i, f):
        wf = cv2.warpPerspective(f, Hs[i], (w, h))[y0:y1, x0:x1]
        valid = wf.max(axis=2) > 0                                  # outside warped frame = no data
        d = np.abs(wf.astype(np.int16) - bgc).max(axis=2)
        m = ((d > thr) & roic & valid).astype(np.uint8)
        m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        n, lab, st, cen = cv2.connectedComponentsWithStats(m)
        bl = [dict(x=int(st[k, 0] + x0), y=int(st[k, 1] + y0), w=int(st[k, 2]), h=int(st[k, 3]), a=int(st[k, 4]))
              for k in range(1, n) if st[k, 4] >= 12]
        return dict(i=i, t=float(ts[i]), blobs=bl)
    out = [r for _, r in pmap_frames(frames(path), _frame, upto=len(Hs))]
    log(f'blobs extracted for {len(out)} frames')
    return out

def _groups(bl, lane):
    """merge fragments (ball split by glare / low contrast) whose boxes are within ~0.35 ball diameters"""
    n = len(bl); par = list(range(n))
    def f(i):
        while par[i] != i: par[i] = par[par[i]]; i = par[i]
        return i
    for i in range(n):
        Di = exp_diam(lane, contact_row(lane, bl[i]['y']))
        if Di < 8 or bl[i]['w'] > 1.6 * Di: continue
        g = 0.35 * Di
        for j in range(i + 1, n):
            a, b = bl[i], bl[j]
            if b['w'] > 1.6 * Di: continue
            if a['x'] - g < b['x'] + b['w'] and b['x'] - g < a['x'] + a['w'] and a['y'] - g < b['y'] + b['h'] and b['y'] - g < a['y'] + a['h']:
                par[f(i)] = f(j)
    G = {}
    for i in range(n): G.setdefault(f(i), []).append(bl[i])
    out = []
    for g in G.values():
        if len(g) == 1: continue
        x0 = min(b['x'] for b in g); y0 = min(b['y'] for b in g)
        x1 = max(b['x'] + b['w'] for b in g); y1 = max(b['y'] + b['h'] for b in g)
        out.append(dict(x=x0, y=y0, w=x1 - x0, h=y1 - y0, a=sum(b['a'] for b in g), merged=True))
    return out

def candidates(B, lane, vp):
    """per frame: blobs (and merged fragments) whose width matches the expected ball size at that depth"""
    C = []
    for r in B:
        bl = r['blobs']; cs = []
        for b in bl + _groups(bl, lane):
            ct = contact_row(lane, b['y']); D = exp_diam(lane, ct)
            if D < 8: continue
            ratio = b['w'] / D
            if 0.7 < ratio < 1.35 and b['h'] < 3.2 * D and b['a'] > 0.25 * D * D:
                xa, xb = lane_x(lane, ct)
                cs.append(dict(t=r['t'], i=r['i'], cx=b['x'] + b['w'] / 2, top=b['y'], ct=ct, D=D, w=b['w'],
                               frac=(b['x'] + b['w'] / 2 - xa) / (xb - xa), merged=b.get('merged', False)))
        C.append(cs)
    return C

def link(C, vp, min_span=0.4, iters=4000, seed=0):
    """RANSAC trajectory: u = 1/(ct - vp_y) is projectively linear in lane distance, so for a rolling ball
    u(t) is ~quadratic (nearly linear) in time; lateral fraction is smooth. Returns inliers, one per frame."""
    P = [c for cs in C for c in cs]
    if len(P) < 5: return []
    # drop static artifacts: a candidate that reappears at the same spot over >0.5 s is not a rolling ball
    tt = np.array([c['t'] for c in P]); xy = np.array([[c['cx'], c['ct']] for c in P]); DD = np.array([c['D'] for c in P])
    static = np.zeros(len(P), bool)
    for k in range(len(P)):
        near = (np.abs(tt - tt[k]) > 0.25) & (np.abs(tt - tt[k]) < 1.5) & (np.hypot(*(xy - xy[k]).T) < 0.25 * DD[k])
        static[k] = near.sum() >= 6
    P = [c for c, s_ in zip(P, static) if not s_]
    if len(P) < 5: return []
    for c in P: c['u'] = 1.0 / max(c['ct'] - vp[1], 1.0)
    t = np.array([c['t'] for c in P]); u = np.array([c['u'] for c in P]); fr = np.array([c['frac'] for c in P])
    ct = np.array([c['ct'] for c in P]); D = np.array([c['D'] for c in P])
    rng = np.random.default_rng(seed); best = (0, None)
    def inliers(pu, pf, tol_f):
        upred = np.polyval(pu, t); ok = upred > 0
        ctp = np.where(ok, vp[1] + 1 / np.where(ok, upred, 1), 1e9)
        return ok & (np.abs(ct - ctp) < 0.35 * D) & (np.abs(fr - np.polyval(pf, t)) < tol_f)
    for _ in range(iters):
        i, j = rng.choice(len(P), 2, replace=False)
        if t[i] == t[j]: continue
        if t[i] > t[j]: i, j = j, i
        if u[j] <= u[i] or not (0.1 <= t[j] - t[i] <= 2.5) or ct[i] - ct[j] < 1.5 * D[j]: continue
        pu = np.polyfit([t[i], t[j]], [u[i], u[j]], 1); pf = np.polyfit([t[i], t[j]], [fr[i], fr[j]], 1)
        inl = inliers(pu, pf, 0.12)
        if inl.sum() < 4: continue
        span = t[inl].max() - t[inl].min()
        sc = len(set(t[inl])) * (span >= min_span) * (span <= 5.0)
        if sc > best[0]: best = (sc, inl)
    if best[1] is None: return []
    inl = best[1]
    for _ in range(3):   # refine with smoother models
        pu = np.polyfit(t[inl], u[inl], 2 if inl.sum() > 8 else 1); pf = np.polyfit(t[inl], fr[inl], min(3, max(1, inl.sum() // 6)))
        inl = inliers(pu, pf, 0.08)
    # one detection per frame: closest to the model
    upred = np.polyval(pu, t); err = np.abs(ct - (vp[1] + 1 / np.maximum(upred, 1e-6))) / D
    keep = {}
    for k in np.where(inl)[0]:
        if P[k]['t'] not in keep or err[k] < err[keep[P[k]['t']]]: keep[P[k]['t']] = k
    T = [P[k] for k in sorted(keep.values(), key=lambda k: t[k])]
    # trim stray end segments separated by gaps
    segs = [[T[0]]]
    for c in T[1:]:
        (segs[-1].append(c) if c['t'] - segs[-1][-1]['t'] < 0.25 else segs.append([c]))
    def _rest(k): return sum(len(s) for s in segs[:k])
    # drop a trailing segment that is tiny, or that follows a long gap AND is small next to the main track
    # (post-impact debris); a long gap followed by the bulk of the track is an occlusion, not debris
    while len(segs) > 1 and (len(segs[-1]) < 4 or (segs[-1][0]['t'] - segs[-2][-1]['t'] > 0.4 and len(segs[-1]) < 0.25 * _rest(len(segs) - 1))):
        segs.pop()
    while len(segs) > 1 and len(segs[0]) < 2: segs.pop(0)
    return [c for sg in segs for c in sg]

def detect_impact(path, S, lane, track, log=print):
    """first frame the pins move. ROI = far end of the lane (pin deck .. pit) with the ball and its reflection
    masked out using the track, re-aligned to a pre-arrival reference by phase correlation to cancel jitter."""
    u = np.array([c['u'] for c in track]); tt = np.array([c['t'] for c in track])
    far = track[int(np.argmax(u))]; D = far['D']
    y_a, y_b = int(far['ct'] - 4.0 * D), int(far['ct'] + 4.0 * D)
    xa, xb = lane_x(lane, far['ct']); pad = 0.4 * (xb - xa); xa, xb = int(xa - pad), int(xb + pad)
    h, w = S['bg'].shape[:2]; y_a = max(y_a, 0); xa = max(xa, 0)
    # first time the ball itself is inside the ROI rows: reference must come from before that
    inside = [c['t'] for c in track if c['ct'] - 1.0 * c['D'] < y_b]
    t_enter = inside[0] if inside else far['t'] - 0.5
    cx_t = np.array([c['cx'] for c in track]); ct_t = np.array([c['ct'] for c in track]); D_t = np.array([c['D'] for c in track])
    refs = []; series = []
    yy, xx = np.mgrid[y_a:y_b, xa:xb]
    for i, f in frames(path):
        if i >= len(S['Hs']): break
        t = S['ts'][i]
        if t < t_enter - 0.5: continue
        if t > far['t'] + 0.6: break
        G = cv2.cvtColor(cv2.warpPerspective(f, S['Hs'][i], (w, h))[y_a:y_b, xa:xb], cv2.COLOR_BGR2GRAY).astype(np.float32)
        if t < t_enter - 0.05: refs.append(G); continue
        if isinstance(refs, list): refs = np.median(np.stack(refs), 0).astype(np.float32)
        (dx, dy), _ = cv2.phaseCorrelate(refs, G)
        G = cv2.warpAffine(G, np.float32([[1, 0, -dx], [0, 1, -dy]]), (G.shape[1], G.shape[0]))
        dif = np.abs(G - refs)
        # mask ball + reflection at its interpolated position (or last known position after the track ends)
        k = np.clip(np.searchsorted(tt, t), 1, len(tt) - 1)
        a = (t - tt[k - 1]) / max(tt[k] - tt[k - 1], 1e-6); a = np.clip(a, 0, 1)
        bx = cx_t[k - 1] + a * (cx_t[k] - cx_t[k - 1]); by = ct_t[k - 1] + a * (ct_t[k] - ct_t[k - 1]); bd = D_t[k]
        # moving forward band: just beyond the ball's top (where the pins it is about to hit stand)
        r0 = int(by - 2.2 * bd) - y_a; r1 = int(by - 1.15 * bd) - y_a
        c0 = int(bx - 1.3 * bd) - xa; c1 = int(bx + 1.3 * bd) - xa
        band = dif[max(r0, 0):max(r1, 1), max(c0, 0):max(c1, 1)]
        series.append((t, float(np.percentile(band, 95)) if band.size > 20 else 0.0, float((band > 40).mean()) if band.size else 0.0))
    E = np.array(series)
    pre = E[(E[:, 0] < t_enter + 0.6)]
    base, sd = np.median(pre[:, 1]), 1.4826 * np.median(np.abs(pre[:, 1] - np.median(pre[:, 1]))) + 2.0
    hot = E[:, 1] > base + 5 * sd
    t_imp = None
    for k in range(len(E) - 4):        # 3 of the next 4 frames hot (pins keep moving once struck)
        if hot[k] and hot[k:k + 4].sum() >= 3: t_imp = float(E[k, 0]); break
    # The measurement impact is when the ball reaches the pins — i.e. its farthest tracked point `far`. On a
    # glossy / pale lane the pin-ROI hotness can fire a diameter or more early (a reflection ahead of the ball),
    # which would truncate the track mid-lane and shrink the distance scale (~2.5x on shot 5). The ball cannot
    # strike before it arrives, so never place impact before far['t']. On well-tracked clips far['t'] already
    # equals the hotness time (impact lands at 0.0 diameters from far), so this is a no-op there.
    if t_imp is not None and far['t'] > t_imp: t_imp = float(far['t'])
    log(f'impact t={t_imp} (ROI rows {y_a}-{y_b}, ball enters ROI {t_enter:.2f}s, baseline {base:.4f}±{sd:.4f})')
    return t_imp, E

def extend_back(B, track, lane, max_frames=20, log=print):
    """walk backwards from the first linked point through airborne frames (loft makes the ball look smaller/farther,
    so the strict size gate misses it). Relaxed gate: same column band, similar width, ball moving toward camera."""
    if not track: return track
    byi = {r['i']: r for r in B}; first = track[0]; out = []
    cur = dict(first); misses = 0
    for i in range(first['i'] - 1, first['i'] - 1 - max_frames, -1):
        r = byi.get(i)
        if r is None: break
        best = None
        for b in r['blobs']:
            cx = b['x'] + b['w'] / 2
            if abs(cx - cur['cx']) > 0.45 * cur['w'] + 4: continue
            if not (0.8 * cur['w'] < b['w'] < 1.35 * cur['w']): continue      # no hand/arm merge (that blob is wider)
            if b['h'] > 1.3 * b['w']: continue                      # airborne ball is round; hand/arm attached is taller
            if not (cur['top'] - 0.3 * cur['w'] < b['y'] < cur['top'] + 0.6 * cur['w']): continue
            d = abs(cx - cur['cx']) + abs(b['y'] - cur['top'])
            if best is None or d < best[0]: best = (d, b)
        if best is None:
            misses += 1
            if misses >= 2: break
            continue
        b = best[1]; misses = 0
        ct = contact_row(lane, b['y']); xa, xb = lane_x(lane, ct)
        cur = dict(t=r['t'], i=i, cx=b['x'] + b['w'] / 2, top=b['y'], ct=ct, D=exp_diam(lane, ct), w=b['w'],
                   frac=(b['x'] + b['w'] / 2 - xa) / (xb - xa), airborne_candidate=True, u=first['u'])
        out.append(cur)
    if out: log(f'extended track back {len(out)} frames to t={out[-1]["t"]:.3f}s (loft/airborne)')
    return out[::-1] + track

def extend_forward(C, track, lane, vp, max_gap=0.3, max_add=40, log=print):
    """Walk forward from the last linked point through far candidates the strict RANSAC refine dropped. The ball
    stays detected near the pins (blobs exist), but the small far ball jitters more than 0.35*D after trim-degraded
    stabilisation, so the linker rejects real detections and the track stops short — inflating speed_avg and
    truncating entry board/angle. Fit u(t), frac(t) from the track tail, extrapolate frame by frame, and append the
    nearest candidate within a depth-relaxed gate (u must keep increasing = ball moving away toward the pins)."""
    if len(track) < 6: return track
    def fit(pts):
        tt = np.array([c['t'] for c in pts]);
        if len(set(tt)) < 2: return None, None
        uu = np.array([1.0 / max(c['ct'] - vp[1], 1.0) for c in pts]); ff = np.array([c['frac'] for c in pts])
        return np.polyfit(tt, uu, 1), np.polyfit(tt, ff, 1)
    pu, pf = fit(track[-8:])
    if pu is None: return track
    byt = {}
    for cs in C:
        for c in cs:
            byt.setdefault(round(c['t'], 4), []).append(c)
    out = list(track); added = 0
    for tq in sorted(byt):
        if tq <= out[-1]['t'] + 1e-6: continue
        if tq - out[-1]['t'] > max_gap or added >= max_add: break
        upred = float(np.polyval(pu, tq))
        if upred <= out[-1].get('u', 1.0 / max(out[-1]['ct'] - vp[1], 1.0)): continue    # must move away
        ctp = vp[1] + 1.0 / max(upred, 1e-6); frp = float(np.polyval(pf, tq)); best = None
        for c in byt[tq]:
            if abs(c['frac'] - frp) > 0.12: continue
            if abs(c['ct'] - ctp) > max(0.6 * c['D'], 8.0): continue
            d = abs(c['ct'] - ctp)
            if best is None or d < best[1]: best = (c, d)
        if best is None: continue
        c = dict(best[0]); c['u'] = 1.0 / max(c['ct'] - vp[1], 1.0); out.append(c); added += 1
        r = fit(out[-8:])
        if r[0] is not None: pu, pf = r
    if added: log(f'extended track forward {added} pts toward the pins (far-lane recovery)')
    return out

def touchdown(B, track, max_pts=20):
    """touchdown = first sharp rise in blob height/width after >=2 flat 'round' airborne frames
    (an airborne ball is a separate round blob; on the lane its reflection/shadow joins it)."""
    byi = {r['i']: r for r in B}; ratios = []
    for c in track[:max_pts]:
        r = byi.get(c['i'])
        if r is None or not r['blobs']: ratios.append((c['t'], np.nan)); continue
        b = min(r['blobs'], key=lambda b: abs(b['x'] + b['w'] / 2 - c['cx']) + abs(b['y'] - c['top']))
        ratios.append((c['t'], b['h'] / max(b['w'], 1)))
    for k in range(2, len(ratios) - 2):
        prev = [q for _, q in ratios[:k]]
        if len(prev) < 2 or np.isnan(prev).any(): continue
        if ratios[k][0] - ratios[k - 1][0] > 0.03: return None            # gap (occlusion): touchdown unseen
        if max(prev) - min(prev) > 0.08: continue
        base = np.median(prev); nxt = [q for _, q in ratios[k:k + 3]]
        if nxt[0] - prev[-1] >= 0.07 and min(nxt) >= base + 0.05:
            return ratios[k][0] - 0.5 / 60
    return None
