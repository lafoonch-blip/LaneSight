"""DEC-116: fast, deterministic YUV420P→BGR via a numba integer kernel. Replaces the pure-numpy float
conversion (the decode-once prime was ~90 s for a full clip on the server, the canon2 analysis-time
regression). Fixed-point INTEGER math → bit-identical on arm64 (Mac) and x86 (Linux), so Mac==server on the
decoded pixels is exact (stronger than the float path). ~16× faster parallel / ~2× single-thread; every output
pixel is independent so prange is deterministic. The chroma upsample reproduces stabilize._up2x's separable
left-cosited 0.75/0.25 bilinear (weights 9/3/3/1, +8>>4)."""
import numpy as np
from numba import njit, prange


@njit(parallel=True, fastmath=False, cache=True)
def _convert(Y, U, V, ya, crr, cbb, gcb, gcr, yoff, full):
    h, w = Y.shape; ch, cw = U.shape
    out = np.empty((h, w, 3), np.uint8)
    for r in prange(h):
        rc = r >> 1
        if (r & 1) == 0:
            r1 = rc; r2 = rc - 1 if rc - 1 >= 0 else 0
        else:
            r1 = rc; r2 = rc + 1 if rc + 1 < ch else ch - 1
        for c in range(w):
            cc = c >> 1
            if (c & 1) == 0:
                c1 = cc; c2 = cc - 1 if cc - 1 >= 0 else 0
            else:
                c1 = cc; c2 = cc + 1 if cc + 1 < cw else cw - 1
            u = (U[r1, c1] * 9 + U[r1, c2] * 3 + U[r2, c1] * 3 + U[r2, c2] + 8) >> 4
            v = (V[r1, c1] * 9 + V[r1, c2] * 3 + V[r2, c1] * 3 + V[r2, c2] + 8) >> 4
            yl = (Y[r, c] - yoff) * ya
            cb = u - 128; cr = v - 128
            R = (yl + crr * cr + 8192) >> 14
            B = (yl + cbb * cb + 8192) >> 14
            G = (yl - gcb * cb - gcr * cr + 8192) >> 14
            out[r, c, 0] = 0 if B < 0 else (255 if B > 255 else B)
            out[r, c, 1] = 0 if G < 0 else (255 if G > 255 else G)
            out[r, c, 2] = 0 if R < 0 else (255 if R > 255 else R)
    return out


_S = 1 << 14


def convert(Y, U, V, Kr, Kb, rng):
    """Y (h,w), U/V (h/2,w/2) int32; returns HxWx3 BGR uint8. Fixed-point BT.x matrix, limited/full range."""
    Kg = 1.0 - Kr - Kb
    full = rng in ('pc', 'jpeg', 'full')
    if full:
        yoff = 0; yscale = 1.0; csc = 1.0
    else:
        yoff = 16; yscale = 255.0 / 219.0; csc = 255.0 / 224.0
    ya = int(round(yscale * _S))
    crr = int(round((2 - 2 * Kr) * csc * _S)); cbb = int(round((2 - 2 * Kb) * csc * _S))
    gcb = int(round(Kb * (2 - 2 * Kb) / Kg * csc * _S)); gcr = int(round(Kr * (2 - 2 * Kr) / Kg * csc * _S))
    return _convert(Y, U, V, ya, crr, cbb, gcb, gcr, yoff, full)


# Warm the JIT at import (compile + disk-cache) on a 2×2 dummy so the first real frame isn't slow. On a fresh
# Cloud Run instance /tmp is ephemeral, so this pays ~1-2 s once per cold start (vs the ~90 s it removes).
try:
    _z = np.zeros((2, 2), np.int32); _zc = np.zeros((1, 1), np.int32)
    convert(_z, _zc, _zc, 0.2126, 0.0722, 'tv')
except Exception:
    pass
