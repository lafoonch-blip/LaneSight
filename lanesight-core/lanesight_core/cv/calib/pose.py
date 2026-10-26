"""Phase-1 follow-up prototype (Shayne 2026-10-26): does a full 3D camera POSE (solvePnP) recover the lane
geometry where the single-plane homography failed? Phase 1 only tested a homography; the review warns a 2D
warp isn't a 3D pose. This treats pins as 3D points (X lateral, Z downlane, Y height above the lane) so the
foul line (Y=0) + pins (Y=pin_height) give real 3D structure.

Honest caveats baked in:
- iPhone intrinsics aren't confirmed post-trim (open decision #2), so K is a NOMINAL assumption; we report
  sensitivity to the focal length and never claim accuracy we can't back.
- Pins are small/far, so even a valid pose may leave the far lane ill-conditioned — that would be a property
  of the camera POSITION, not the method, which is exactly the question. We measure it, not assert it.

Additive / off the production path. Units: all 3D in INCHES (Z = feet*12). Nothing here is ML.
"""
from __future__ import annotations
import numpy as np
import cv2

from .lane_geometry import CANONICAL, LANE_WIDTH_IN, BOARDS

IN_PER_FT = 12.0
# A pin stands ~15 in tall; the labelable body/midpoint is above the lane plane. We FIT this height (below)
# and also test a few hypotheses, because mislabeling pins as Y=0 is what broke the homography.
PIN_HEIGHT_HYPOTHESES_IN = (0.0, 7.5, 15.0)


def nominal_K(w, h, focal_px=None):
    """Nominal pinhole intrinsics. Default focal ≈ 1.2·max(w,h) px (typical phone main lens); PARAMETER —
    we report sensitivity to it. Principal point = image center, zero skew."""
    f = focal_px if focal_px is not None else 1.2 * max(w, h)
    return np.array([[f, 0, w / 2.0], [0, f, h / 2.0], [0, 0, 1.0]], float)


def _object_points(names, pin_height_in):
    """3D world points (inches) for named landmarks: foul at Y=0,Z=0; pins at Y=pin_height, Z=row, X=board."""
    obj = []
    for n in names:
        lm = CANONICAL.landmarks.get(n)
        if n.startswith("foul_"):
            obj.append([lm.x_in, 0.0, 0.0])
        elif n.startswith("pin_"):
            obj.append([lm.x_in, pin_height_in, lm.z_ft * IN_PER_FT])
        else:
            return None            # only foul + pins are exact 3D anchors here
    return np.asarray(obj, np.float64)


def _pnp(object_pts, image_pts, K):
    """solvePnP (SQPNP, robust to config) -> (rvec, tvec, reproj_px_rmse) or None."""
    if len(object_pts) < 4:
        return None
    flag = getattr(cv2, "SOLVEPNP_SQPNP", cv2.SOLVEPNP_ITERATIVE)
    ok, rvec, tvec = cv2.solvePnP(object_pts.astype(np.float64), image_pts.astype(np.float64),
                                  K, None, flags=flag)
    if not ok:
        return None
    proj, _ = cv2.projectPoints(object_pts, rvec, tvec, K, None)
    rmse = float(np.sqrt(np.mean(np.sum((proj.reshape(-1, 2) - image_pts) ** 2, axis=1))))
    return rvec, tvec, rmse


def _ray_plane_board(rvec, tvec, K, uv, Y=0.0):
    """Back-project image point uv to the lane plane Y=Y (inches). Returns (X_in, Z_ft) or None.
    Camera center C = -R^T t; ray dir d = R^T K^-1 [u,v,1]; intersect Y = C_y + s d_y."""
    R, _ = cv2.Rodrigues(rvec)
    Kinv = np.linalg.inv(K)
    d = R.T @ (Kinv @ np.array([uv[0], uv[1], 1.0]))
    C = (-R.T @ tvec).ravel()
    if abs(d[1]) < 1e-9:
        return None
    s = (Y - C[1]) / d[1]
    if s <= 0:
        return None
    P = C + s * d
    return float(P[0]), float(P[2] / IN_PER_FT)


def fit_pin_height(landmark_set, focal_px=None):
    """Find the pin height (in) that minimizes PnP reprojection — a diagnostic: if a consistent Y>0 fits well,
    the pins really were labeled above the lane plane (why the homography broke). Returns best (height, rmse)."""
    names, _, image = landmark_set.correspondences()
    names = list(names)
    w, h = landmark_set.image_size
    K = nominal_K(w, h, focal_px)
    best = (None, np.inf)
    for ph in np.linspace(0.0, 20.0, 41):
        obj = _object_points(names, ph)
        if obj is None:
            continue
        r = _pnp(obj, image, K)
        if r and r[2] < best[1]:
            best = (round(float(ph), 2), round(r[2], 2))
    return best


def pose_report(landmark_set, focal_px=None, pin_height_in=None):
    """Solve pose from foul+pins, report reprojection + far-lane board sensitivity under PnP, and camera
    height/standoff. Compares the far sensitivity against the eligibility threshold."""
    names, _, image = landmark_set.correspondences()
    names = list(names)
    w, h = landmark_set.image_size
    K = nominal_K(w, h, focal_px)
    if pin_height_in is None:
        pin_height_in = fit_pin_height(landmark_set, focal_px)[0] or 0.0
    obj = _object_points(names, pin_height_in)
    if obj is None:
        return dict(ok=False, error="only foul+pins usable as 3D anchors")
    r = _pnp(obj, image, K)
    if r is None:
        return dict(ok=False, error="solvePnP failed")
    rvec, tvec, rmse = r
    # camera center in world (inches)
    R, _ = cv2.Rodrigues(rvec)
    C = (-R.T @ tvec).ravel()
    # far-lane board sensitivity: project a lane point at entry, perturb ±1px, back-project
    entry_world = np.array([[LANE_WIDTH_IN / 2.0, 0.0, CANONICAL.z_impact_ft * IN_PER_FT]])
    uv0, _ = cv2.projectPoints(entry_world, rvec, tvec, K, None)
    uv0 = uv0.reshape(2)
    base = _ray_plane_board(rvec, tvec, K, uv0)
    sens = None
    if base is not None:
        dmax = 0.0
        for du, dv in ((1, 0), (0, 1)):
            bp = _ray_plane_board(rvec, tvec, K, uv0 + [du, dv])
            if bp is not None:
                dmax = max(dmax, abs((bp[0] - LANE_WIDTH_IN / 2.0) / LANE_WIDTH_IN * BOARDS))
        sens = round(dmax, 3)
    return dict(ok=True, pin_height_in=pin_height_in, reproj_px_rmse=round(rmse, 2),
                cam_height_in=round(float(C[1]), 1), cam_standoff_ft=round(float(-C[2] / IN_PER_FT), 1),
                cam_lateral_in=round(float(C[0]), 1),
                entry_board_sensitivity_per_px=sens, focal_px=round(float(K[0, 0]), 1))
