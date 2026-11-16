"""Ball-INDEPENDENT metric lane-plane solve (DEC-117 / CV-review item 1) — Python REFERENCE PROTOTYPE.

Replaces the fragile impact anchor for the on-device speed scale. Given camera intrinsics K (focal f + principal
point), the lane-direction vanishing point vpL (from the lane edges), a cross-lane direction vanishing point vpC,
and the known lane width (41.5 in), it solves the lane PLANE metrically — no ball, no pin-impact. Any image point
then maps to lane coordinates (Z ft down-lane, X in across), so speed is the slope of metric-Z(t) with no impact
anchor.

vpC options (robustness differs):
  (A) two parallel cross-lines (foul line + a far cross-line — the 15 ft arrows or the pin-deck row given by the
      lane edges at the detected head-pin row): vpC = foul_line × far_line. Preferred.
  (B) a single foul line + known f via orthogonality ((K⁻¹vpC)·(K⁻¹vpL)=0): needs f and is ILL-CONDITIONED when
      the foul line is near-horizontal (fragile — avoid).

VALIDATED by the synthetic self-test below (recovers known Z exactly). FINDINGS on IMG_8751-54 (2026-11-01,
`03_ENGINEERING/METRIC_LANE_PLANE_FINDINGS.md`): correct to ~0.3 mph of truth GIVEN an accurate focal, but the
mounted down-lane POV is ill-conditioned (foul & far line near-parallel in the image, cos_img 0.7-0.98) so the
depth scale rides on the focal (±15% f → ±16% speed). On iOS, feed AVCameraCalibrationData's exact per-frame
intrinsic matrix (DEC-117) and use two cross-lines; never an assumed focal or the single foul line.

Run the self-test:  python -m ops.metric_lane_plane
"""
from __future__ import annotations
import numpy as np

LANE_IN = 41.5


def line_from_ab(a: float, b: float) -> np.ndarray:
    """image line for x = a*y + b  ->  -x + a*y + b = 0  -> homogeneous [-1, a, b]."""
    l = np.array([-1.0, a, b]); return l / np.linalg.norm(l[:2])


def line_through(p0, p1) -> np.ndarray:
    l = np.cross(np.array([p0[0], p0[1], 1.0]), np.array([p1[0], p1[1], 1.0]))
    return l / np.linalg.norm(l[:2])


def vpC_two_lines(foul_l: np.ndarray, far_l: np.ndarray) -> np.ndarray:
    """(A) homogeneous vpC = intersection of two parallel cross-lines (may be near-infinite)."""
    return np.cross(foul_l, far_l)


def vpC_single_foul(K: np.ndarray, vpL, foul_l: np.ndarray):
    """(B) vpC on foul_l, orthogonal to vpL in camera metric (needs f). Returns (homogeneous vpC, |A| conditioning)."""
    cx, cy, f = K[0, 2], K[1, 2], K[0, 0]
    la, lb, lc = foul_l; ax, ay = vpL[0] - cx, vpL[1] - cy
    A = ax - ay * la / lb
    B = -ax * cx + ay * (-lc / lb - cy)
    vx = (-(f * f) - B) / A
    vy = -(la * vx + lc) / lb
    return np.array([vx, vy, 1.0]), abs(A)


def solve_plane(K: np.ndarray, vpL, vpC_h, left_ab, right_ab, foul_yL: float):
    """Metric plane from K + vpL + vpC + edges + foul row. Returns a dict with Zof/Xof(px,py)->lane coords, the
    plane basis (D down-lane, C cross, n normal), the scale c, and cos_img (image conditioning of vpC; →1 ill)."""
    Ki = np.linalg.inv(K); cx, cy = K[0, 2], K[1, 2]
    D = Ki @ np.array([vpL[0], vpL[1], 1.0])
    if D[2] < 0: D = -D
    D /= np.linalg.norm(D)
    C = Ki @ np.asarray(vpC_h, float); C /= np.linalg.norm(C)
    n = np.cross(D, C); n /= np.linalg.norm(n)

    def ray(px, py):
        r = Ki @ np.array([px, py, 1.0])
        return -r if r[2] < 0 else r

    xa = left_ab[0] * foul_yL + left_ab[1]; xb = right_ab[0] * foul_yL + right_ab[1]

    def onp(r, c): return (c / np.dot(n, r)) * r
    wl = onp(ray(xa, foul_yL), 1.0); wr = onp(ray(xb, foul_yL), 1.0)
    sep = abs(np.dot(wr - wl, C))
    if not np.isfinite(sep) or sep < 1e-9:
        return None
    c = LANE_IN / sep
    origin = onp(ray((xa + xb) / 2, foul_yL), c)

    def Zof(px, py):
        r = ray(px, py); den = np.dot(n, r)
        if abs(den) < 1e-9: return float('nan')
        return float(np.dot((c / den) * r - origin, D)) / 12.0

    def Xof(px, py):
        r = ray(px, py); return float(np.dot((c / np.dot(n, r)) * r - origin, C))

    vpC2 = np.asarray(vpC_h, float)
    vpC2 = vpC2[:2] / vpC2[2] if abs(vpC2[2]) > 1e-9 else vpC2[:2] * 1e6
    dL = np.array([vpL[0] - cx, vpL[1] - cy]); dC = vpC2 - np.array([cx, cy])
    cos_img = abs(float(np.dot(dL / np.linalg.norm(dL), dC / np.linalg.norm(dC)))) if np.linalg.norm(dC) > 0 else 1.0
    return dict(D=D, C=C, n=n, c=c, Zof=Zof, Xof=Xof, cos_img=cos_img, origin=origin)


# ------------------------------------------------------------------ synthetic self-test (ground truth) ----------
def _self_test():
    def make(f, W=1080, H=1920): return np.array([[f, 0, W / 2.], [0, f, H / 2.], [0, 0, 1.]])

    def scene(f, pitch, height, shift):
        K = make(f); th = np.radians(pitch)
        R = np.array([[1, 0, 0], [0, np.cos(th), -np.sin(th)], [0, np.sin(th), np.cos(th)]])
        return K, R, -R @ np.array([0., height, -shift])

    def proj(K, R, t, P): p = K @ (R @ P + t); return p[:2] / p[2]

    def edge_ab(K, R, t, x):
        pts = np.array([proj(K, R, t, np.array([x, 0., z])) for z in np.linspace(0, 2000, 60)])
        a, b = np.polyfit(pts[:, 1], pts[:, 0], 1); return a, b

    def cross(K, R, t, z):
        return line_through(proj(K, R, t, np.array([-200, 0., z])), proj(K, R, t, np.array([200, 0., z])))

    ok = True
    for f, pitch in [(1594, 12), (1594, 25), (1100, 18), (2400, 12)]:
        K, R, t = scene(f, pitch, 42, 70)
        lab = edge_ab(K, R, t, -LANE_IN / 2); rab = edge_ab(K, R, t, +LANE_IN / 2)
        vpL_h = np.cross(line_from_ab(*lab), line_from_ab(*rab)); vpL = vpL_h[:2] / vpL_h[2]
        foul = cross(K, R, t, 0.0); arrow = cross(K, R, t, 15 * 12.)
        foul_yL = proj(K, R, t, np.array([0., 0., 0.]))[1]
        s = solve_plane(K, vpL, vpC_two_lines(foul, arrow), lab, rab, foul_yL)
        truth = [5, 15, 30, 45, 59.44]
        rec = [s['Zof'](*proj(K, R, t, np.array([0., 0., z * 12.]))) for z in truth]
        err = max(abs(a - b) for a, b in zip(truth, rec))
        print(f"f={f} pitch={pitch}: recovered Z={[round(r,2) for r in rec]} maxerr={err:.3f} ft  {'OK' if err < 0.05 else 'FAIL'}")
        ok = ok and err < 0.05
    print("SELF-TEST", "PASS" if ok else "FAIL")
    return ok


if __name__ == '__main__':
    import sys
    sys.exit(0 if _self_test() else 1)
