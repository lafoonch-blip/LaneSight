import numpy as np
def loess(x, y, xq, bw=8.0, deg=2, iters=3):
    """robust local polynomial regression (tricube kernel, bisquare robustness weights)"""
    x = np.asarray(x, float); y = np.asarray(y, float)
    ok = np.isfinite(x) & np.isfinite(y); x, y = x[ok], y[ok]; rw = np.ones_like(x)
    def fit_at(q, w_extra):
        d = np.abs(x - q) / bw; w = np.where(d < 1, (1 - d ** 3) ** 3, 0) * w_extra
        if (w > 0).sum() < deg + 2: return np.nan, np.nan
        A = np.vander(x - q, deg + 1); W = np.sqrt(w)
        c = np.linalg.lstsq(A * W[:, None], y * W, rcond=None)[0]
        return c[-1], c[-2]                       # value, slope at q
    for _ in range(iters):
        fitted = np.array([fit_at(q, rw)[0] for q in x]); r = np.nan_to_num(y - fitted, nan=0.0)
        s = np.median(np.abs(r)) * 6 + 1e-9; u = np.clip(r / s, -1, 1); rw = (1 - u ** 2) ** 2
    out = np.array([fit_at(q, rw) for q in xq])
    return out[:, 0], out[:, 1]
