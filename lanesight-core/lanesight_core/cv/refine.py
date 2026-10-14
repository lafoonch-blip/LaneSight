"""Stage 3b: re-measure every track point with a ball-colour model (learned per video from clean detections).
Removes glare/fragment errors and fills short gaps; ball top + upper-half centroid give contact point & lateral."""
import cv2, numpy as np
from .stabilize import frames
from .track import exp_diam, contact_row
from .lanes import lane_x

def _circle_mask(shape, cx, cy, r):
    yy, xx = np.ogrid[:shape[0], :shape[1]]; return (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r

def refine(path, S, lane, track, t_end, log=print):
    h, w = S['bg'].shape[:2]
    T = [c for c in track if c['t'] <= t_end + 0.02]
    clean = [c for c in T if not c.get('merged') and c['D'] > 24][:40]
    tt = np.array([c['t'] for c in T])
    # smooth predictors for position (image space) over time
    pcx = np.polyfit(tt, [c['cx'] for c in T], min(4, len(T) // 8 + 1))
    ptop = np.polyfit(tt, [c['top'] for c in T], min(4, len(T) // 8 + 1))
    want = {c['i'] for c in clean}
    by_i = {c['i']: c for c in T}
    t0, t1 = tt.min(), t_end
    hist_b = np.zeros((30, 32)); hist_l = np.zeros((30, 32)); out = []
    buf = []
    for i, f in frames(path):
        if i >= len(S['Hs']): break
        t = S['ts'][i]
        if t < t0 - 0.02: continue
        if t > t1 + 0.02: break
        buf.append((i, t, cv2.warpPerspective(f, S['Hs'][i], (w, h))))
    # 1. colour model
    for i, t, img in buf:
        if i not in want: continue
        c = next(c for c in clean if c['i'] == i); r = 0.42 * c['D']; cy = c['top'] + c['D'] / 2
        x0, x1 = int(c['cx'] - 2 * c['D']), int(c['cx'] + 2 * c['D']); y0, y1 = int(c['top'] - c['D']), int(c['top'] + 2.5 * c['D'])
        crop = img[max(y0, 0):y1, max(x0, 0):x1]; hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
        mb = _circle_mask(crop.shape, c['cx'] - max(x0, 0), cy - max(y0, 0), r).astype(np.uint8)
        ring = (~_circle_mask(crop.shape, c['cx'] - max(x0, 0), cy - max(y0, 0), 1.3 * r)).astype(np.uint8)
        hist_b += cv2.calcHist([hsv], [0, 1], mb, [30, 32], [0, 180, 0, 256])
        hist_l += cv2.calcHist([hsv], [0, 1], ring, [30, 32], [0, 180, 0, 256])
    pb = hist_b / hist_b.sum(); pl = hist_l / hist_l.sum()
    ratio = (pb + 1e-6) / (pb + pl + 2e-6); ratio = cv2.GaussianBlur(ratio.astype(np.float32), (3, 3), 0)
    # 2. per-frame measurement around the predicted position
    for i, t, img in buf:
        cxp, topp = np.interp(t, tt, [c['cx'] for c in T]), np.interp(t, tt, [c['top'] for c in T])
        D = exp_diam(lane, contact_row(lane, topp))
        if D < 6: continue
        x0, x1 = int(cxp - 1.6 * D), int(cxp + 1.6 * D); y0, y1 = int(topp - 1.2 * D), int(topp + 1.6 * D)
        if x0 < 0 or y0 < 0 or x1 > w or y1 > h: continue
        hsv = cv2.cvtColor(img[y0:y1, x0:x1], cv2.COLOR_BGR2HSV)
        hb = (hsv[..., 0].astype(int) * 30 // 180); sb = (hsv[..., 1].astype(int) * 32 // 256)
        P = ratio[hb, sb]
        P = cv2.GaussianBlur(P, (0, 0), max(0.8, D / 25))
        m = (P > (0.6 if D > 30 else 0.5)).astype(np.uint8)
        n, lab, st, cen = cv2.connectedComponentsWithStats(m)
        if n < 2: continue
        # component nearest the prediction with a plausible size
        best = None
        for k in range(1, n):
            bx, by, bw, bh, ba = st[k]
            if not (0.55 * D < bw < 1.5 * D) or ba < 0.25 * D * D: continue
            d = np.hypot(bx + bw / 2 - (cxp - x0), by - (topp - y0))
            if d < 0.6 * D and (best is None or d < best[0]): best = (d, k)
        if best is None: continue
        k = best[1]; bx, by, bw, bh, ba = st[k]
        top = by + y0
        rows = (lab == k)[by:by + int(0.9 * D)]                     # ball body (exclude reflection below)
        ys, xs = np.nonzero(rows); cx = xs.mean() + x0
        raw = by_i.get(i)
        if raw is None or abs(cx - raw['cx']) > 0.5 * raw['D'] or abs(top - raw['top']) > 0.5 * raw['D']:
            continue          # refinement may only correct a raw detection, never invent or replace it with something else
        ct = contact_row(lane, top); Dm = exp_diam(lane, ct); xa, xb = lane_x(lane, ct)
        out.append(dict(t=t, i=i, cx=cx, top=top, ct=ct, D=Dm, w=bw, frac=(cx - xa) / (xb - xa), refined=True,
                        u=1.0 / max(ct - S.get('vp_y', 0), 1)))
    log(f'refine: {len(out)} colour-measured points ({len(T)} raw)')
    return out
