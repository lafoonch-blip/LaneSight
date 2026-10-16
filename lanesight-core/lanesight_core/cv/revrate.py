"""Rev rate from appearance periodicity: the ball's surface pattern repeats once per revolution.
Ball crops (scale-normalized, circular mask) along the track -> similarity vs time lag -> period."""
import cv2, numpy as np
from .stabilize import frames

def ball_crops(path, S, track, z_max_t=None, size=64, max_n=60):
    want = {c['i']: c for c in track[:max_n]}
    out = []; h, w = S['bg'].shape[:2]
    for i, f in frames(path):
        if i > max(want): break
        if i not in want: continue
        c = want[i]; D = c['w']; cy = c['top'] + D / 2; cx = c['cx']
        img = cv2.warpPerspective(f, S['Hs'][i], (w, h))
        x0, y0 = int(cx - 0.5 * D), int(cy - 0.5 * D)
        if x0 < 0 or y0 < 0 or x0 + int(D) > w or y0 + int(D) > h: continue
        cr = cv2.resize(img[y0:y0 + int(D), x0:x0 + int(D)], (size, size), interpolation=cv2.INTER_AREA)
        out.append((c['t'], cr))
    return out

def rev_rate(crops, fmin=4.0, fmax=10.0):
    size = crops[0][1].shape[0]; yy, xx = np.mgrid[:size, :size] - (size - 1) / 2
    mask = (xx ** 2 + yy ** 2) < (0.38 * size) ** 2              # inner disc: avoids edge/background
    V = []
    for t, cr in crops:
        g = cv2.cvtColor(cr, cv2.COLOR_BGR2HSV)[..., 0:2].astype(np.float32)   # hue/sat: pattern, not lighting
        v = g[mask].ravel(); v = (v - v.mean()) / (v.std() + 1e-6); V.append(v)
    V = np.array(V); t = np.array([c[0] for c in crops])
    sim = V @ V.T / V.shape[1]
    dt = np.median(np.diff(t)); lags = np.arange(1, len(t) // 2)
    ac = np.array([np.mean(np.diag(sim, k)) for k in lags])
    # search period on a fine grid using interpolated autocorrelation (sub-frame)
    periods = np.linspace(1 / fmax, 1 / fmin, 400); score = []
    for P in periods:
        k = P / dt
        score.append(np.mean([np.interp(m * k, lags, ac) for m in (1, 2, 3) if m * k < lags[-1]]))
    score = np.array(score); ai = int(np.argmax(score))
    # A real spin period sits inside the band; when no pattern repeats, argmax slides to the search rail
    # (shortest or longest period) and 60/P is the ceiling (or floor) value, not a measurement. Flag it so the
    # caller reports the rev rate unavailable instead of a confident wrong number (DEC-026).
    at_rail = ai < 3 or ai > len(score) - 4
    P = periods[ai]; rev = 60.0 / P
    # Honest resolution: the appearance autocorrelation only resolves whole-frame lags, so the period is known to
    # ~one frame step. The rev gap between adjacent lags is sigma = rev^2 * dt / 60 (= 60 / (L^2 * dt), L = P/dt
    # frames per rev). This scales with capture: it halves at 120 fps, quarters at 240 — so the metric reports a
    # tighter band automatically on better video. n_rev (revolutions observed) is returned for future weighting.
    sigma = rev * rev * dt / 60.0
    span = float(t[-1] - t[0]); n_rev = span / P if P > 0 else 0.0
    return rev, dict(lags=lags * dt, ac=ac, periods=periods, score=score, argmax=ai, at_rail=at_rail,
                     sigma=sigma, fps=1.0 / dt, n_rev=n_rev)
