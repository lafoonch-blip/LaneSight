"""DEC-116: fast numba YUV420P→BGR that reproduces decode.yuv420p_to_bgr_numpy EXACTLY (float32, maxdiff 0),
so enabling it is a no-op downstream (the server's fragile impact anchor amplified the earlier INTEGER kernel's
maxdiff-2 into a 3 mph error / 15.6). Float matches numpy's float ops bit-for-bit (fastmath=False, same op order,
same 0.75/0.25 separable left-cosited chroma upsample as stabilize._up2x). ~19× parallel / ~2.4× serial vs numpy.
PARALLEL is gated by LANESIGHT_YUV_NB_PARALLEL (default serial) because numba's parallel backend diverged x86 vs
arm64 for the integer kernel — parallel is enabled only after a per-frame md5 (Job==Mac) proves it matches here."""
import os
import numpy as np
from numba import njit, prange

_PAR = os.environ.get('LANESIGHT_YUV_NB_PARALLEL') == '1'


def _kernel(parallel):
    @njit(parallel=parallel, fastmath=False, cache=True)
    def k(Y, U, V, krr, kbb, gkb, gkr, yscale, cscale, yoff, full):
        h, w = Y.shape; ch, cw = U.shape
        out = np.empty((h, w, 3), np.uint8)
        rng = prange(h) if parallel else range(h)
        for r in rng:
            rc = r >> 1
            r1 = rc; r2 = (rc - 1 if rc - 1 >= 0 else 0) if (r & 1) == 0 else (rc + 1 if rc + 1 < ch else ch - 1)
            wr1 = np.float32(0.75); wr2 = np.float32(0.25)
            for c in range(w):
                cc = c >> 1
                c1 = cc; c2 = (cc - 1 if cc - 1 >= 0 else 0) if (c & 1) == 0 else (cc + 1 if cc + 1 < cw else cw - 1)
                wc1 = np.float32(0.75); wc2 = np.float32(0.25)
                uh1 = np.float32(U[r1, c1]) * wc1 + np.float32(U[r1, c2]) * wc2
                uh2 = np.float32(U[r2, c1]) * wc1 + np.float32(U[r2, c2]) * wc2
                u = uh1 * wr1 + uh2 * wr2
                vh1 = np.float32(V[r1, c1]) * wc1 + np.float32(V[r1, c2]) * wc2
                vh2 = np.float32(V[r2, c1]) * wc1 + np.float32(V[r2, c2]) * wc2
                v = vh1 * wr1 + vh2 * wr2
                if full:
                    Yl = np.float32(Y[r, c]); Cb = u - np.float32(128.0); Cr = v - np.float32(128.0)
                else:
                    Yl = (np.float32(Y[r, c]) - yoff) * yscale
                    Cb = (u - np.float32(128.0)) * cscale; Cr = (v - np.float32(128.0)) * cscale
                R = Yl + krr * Cr; B = Yl + kbb * Cb; G = Yl - gkb * Cb - gkr * Cr
                b = int(B + np.float32(0.5)); g = int(G + np.float32(0.5)); rr = int(R + np.float32(0.5))
                out[r, c, 0] = 0 if b < 0 else (255 if b > 255 else b)
                out[r, c, 1] = 0 if g < 0 else (255 if g > 255 else g)
                out[r, c, 2] = 0 if rr < 0 else (255 if rr > 255 else rr)
        return out
    return k


_convert = _kernel(_PAR)
_f32 = np.float32


def convert(Y, U, V, Kr, Kb, rng):
    """Y (h,w), U/V (h/2,w/2) int32 or float; returns HxWx3 BGR uint8, bit-identical to yuv420p_to_bgr_numpy."""
    Kg = 1.0 - Kr - Kb
    full = rng in ('pc', 'jpeg', 'full')
    Yf = Y.astype(np.float32); Uf = U.astype(np.float32); Vf = V.astype(np.float32)
    return _convert(Yf, Uf, Vf, _f32(2.0 - 2.0 * Kr), _f32(2.0 - 2.0 * Kb),
                    _f32(Kb * (2.0 - 2.0 * Kb) / Kg), _f32(Kr * (2.0 - 2.0 * Kr) / Kg),
                    _f32(255.0 / 219.0), _f32(255.0 / 224.0), _f32(16.0), full)


try:   # warm the JIT (compile + disk-cache) so the first real frame isn't slow
    _z = np.zeros((2, 2), np.float32); _zc = np.zeros((1, 1), np.float32)
    convert(_z, _zc, _zc, 0.2126, 0.0722, 'tv')
except Exception:
    pass
