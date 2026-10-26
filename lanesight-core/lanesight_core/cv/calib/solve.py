"""Point-based lane-plane calibration from hand-labeled landmarks, with honest diagnostics.

PR1 scope (DEC-062, Phase 1): a robust *homography* (image <-> lane plane) from >=4 labeled landmark
correspondences spanning real depth — enough to run ablation Runs B/C and quantify far-lane sensitivity.
Full PnP + intrinsics + distortion + point/line nonlinear refinement (handoff §5.2.5) is deliberately
deferred until we confirm iPhone intrinsics survive the on-device trim (open decision #2); doing it from one
flat frame with unknown focal+distortion is exactly what §5.2.6 warns against.

Nothing here runs on the production path. A calibration that is mathematically fine but physically
under-constrained is reported as such (diagnostics) rather than silently trusted (handoff §5.3).
"""
from __future__ import annotations
import numpy as np
import cv2

from .lane_geometry import LaneGeometry, CANONICAL, LANE_WIDTH_IN, BOARDS

MIN_CORRESPONDENCES = 4


class CalibrationError(RuntimeError):
    pass


def homography_from_landmarks(landmark_set, geometry: LaneGeometry = CANONICAL, ransac_px: float = 3.0):
    """Returns (H_img_to_world, H_world_to_img, diagnostics).

    world coords are (X inches from left edge, Z feet from foul line). Raises CalibrationError with a clear
    reason when there are too few correspondences or the fit is degenerate — never returns a bad matrix silently.
    """
    names, world, image = landmark_set.correspondences(geometry)
    n = len(names)
    if n < MIN_CORRESPONDENCES:
        raise CalibrationError(
            f"only {n} labeled+known landmark(s) ({', '.join(names) or 'none'}); need >= {MIN_CORRESPONDENCES} "
            f"spanning real depth. Label more foul/arrow/pin-spot points on this clip.")

    # Solve world -> image so the RANSAC reprojection threshold is in PIXELS (meaningful). Solving the other
    # direction would threshold in mixed world units (inches X vs feet Z) — nonsense. For a small, clean
    # hand-labeled set use exact/least-squares (method 0); only switch to robust USAC when there are enough
    # points for outlier rejection to mean something (handoff §5.2.2). Deterministic for a fixed input.
    method = 0 if n <= 8 else getattr(cv2, "USAC_MAGSAC", cv2.RANSAC)
    H_wi, mask = cv2.findHomography(world.astype(np.float64), image.astype(np.float64), method, ransac_px)
    if H_wi is None:
        raise CalibrationError("findHomography failed — landmark points are collinear or degenerate.")
    try:
        H_iw = np.linalg.inv(H_wi)
    except np.linalg.LinAlgError:
        raise CalibrationError("homography is singular (not invertible) — landmarks do not constrain a plane.")

    diag = calibration_diagnostics(H_iw, world, image, names, geometry, inlier_mask=mask)
    return H_iw, H_wi, diag


def _apply(H, pts):
    pts = np.asarray(pts, float).reshape(-1, 2)
    h = np.c_[pts, np.ones(len(pts))] @ H.T
    return h[:, :2] / h[:, 2:3]


# Approximate Z (ft) for on-plane interval fiducials, used ONLY for a NEAR-field calibration (partial
# results). Band midpoints from the USBC ranges — approximate, fine for near conditioning; never for an
# exact far anchor. A center's measured positions should override these.
NEAR_Z_DEFAULTS = {"approach_dot": -12.0, "dot": 7.0, "arrow": 14.0}


def near_field_homography(landmark_set, z_overrides=None, geometry: LaneGeometry = CANONICAL):
    """Build a NEAR-field lane-plane homography from the on-plane fiducials a human verified — foul (exact
    Z=0) + approach dots / guide dots / arrows at approximate band-midpoint Z. These are all painted on the
    surface (Y=0), so unlike the pins they are coplanar. Returns (H_iw, H_wi, diag) or raises CalibrationError.

    Purpose: recover the NEAR lane (laydown / early boards / early speed) from a camera position whose FAR
    lane is unrecoverable — the "return partial results, never reject the video" path. The diagnostics'
    per-region sensitivity shows where it's trustworthy: metrics at/under the deepest labeled fiducial are
    INTERPOLATED (precise + accurate); beyond are EXTRAPOLATED (locally smooth but biased)."""
    z_overrides = z_overrides or NEAR_Z_DEFAULTS
    names, world, image = [], [], []
    for n in ("foul_l", "foul_r"):
        ob = landmark_set.observations.get(n)
        if ob and ob.usable:
            names.append(n); world.append(list(geometry.world_point(n))); image.append([ob.x, ob.y])
    for n, ob in landmark_set.observations.items():
        if not ob.usable:
            continue
        grp = n.rsplit("_", 1)[0]
        if grp in z_overrides and geometry.landmarks.get(n) and geometry.landmarks[n].x_in is not None:
            names.append(n); world.append([geometry.landmarks[n].x_in, z_overrides[grp]]); image.append([ob.x, ob.y])
    if len(names) < 4:
        raise CalibrationError(f"near-field: only {len(names)} on-plane fiducials; need >=4 (foul + dots/arrows)")
    world = np.asarray(world, float); image = np.asarray(image, float)
    if len(set(round(z, 1) for z in world[:, 1])) < 2:
        raise CalibrationError("near-field: on-plane fiducials span only one depth (degenerate)")
    Hwi, _ = cv2.findHomography(world, image, 0)
    if Hwi is None:
        raise CalibrationError("near-field: findHomography failed (degenerate)")
    H_iw = np.linalg.inv(Hwi)
    diag = calibration_diagnostics(H_iw, world, image, names, geometry)
    # Which depths the near fiducials actually bracket — the near lane is only INTERPOLATED (trustworthy)
    # up to the deepest labeled fiducial; past it the same homography extrapolates (biased). The eligibility
    # gate uses this so we never call an extrapolated region "recovered".
    diag["deepest_fiducial_z_ft"] = float(world[:, 1].max())
    diag["shallowest_fiducial_z_ft"] = float(world[:, 1].min())
    diag["fiducial_z_span_ft"] = [float(world[:, 1].min()), float(world[:, 1].max())]
    return H_iw, Hwi, diag


def interval_consistency(H_iw, landmark_set, geometry: LaneGeometry = CANONICAL):
    """Validate a calibration (solved from exact anchors) against the USBC interval landmarks (arrows/dots).
    For each interval landmark that the human VERIFIED in the image, map it to the lane plane and check the
    mapped Z falls within its permitted band. These are consistency CHECKS, never calibration anchors.
    Returns a list of {name, z_mapped, z_min, z_max, within, margin_ft}."""
    intervals = geometry.interval_landmarks()
    out = []
    for name, ob in landmark_set.observations.items():
        if not ob.usable or name not in intervals:
            continue
        x_in, z_min, z_max = intervals[name]
        w = _apply(H_iw, [[ob.x, ob.y]])[0]
        z = float(w[1])
        within = bool(z_min <= z <= z_max)
        margin = 0.0 if within else float(min(abs(z - z_min), abs(z - z_max)))
        out.append(dict(name=name, z_mapped=round(z, 2), z_min=z_min, z_max=z_max,
                        within=within, margin_ft=round(margin, 2)))
    return out


def calibration_diagnostics(H_iw, world, image, names, geometry: LaneGeometry = CANONICAL, inlier_mask=None):
    """Residuals + spread + a per-region board/feet sensitivity to a 1-px landmark perturbation (handoff §5.3).

    Low reprojection loss does NOT imply accurate far-lane depth, so we also report held-out (leave-one-out)
    residuals and how much a 1-px wobble moves the mapped coordinate in each longitudinal region.
    """
    world = np.asarray(world, float).reshape(-1, 2)
    image = np.asarray(image, float).reshape(-1, 2)
    n = len(names)

    # reprojection residuals: map labeled image points to world, compare to the known world coords
    w_pred = _apply(H_iw, image)
    res_in = w_pred[:, 0] - world[:, 0]           # inches (lateral X)
    res_ft = w_pred[:, 1] - world[:, 1]           # feet (longitudinal Z)
    res_board = res_in / LANE_WIDTH_IN * BOARDS

    # leave-one-out: refit without each point and measure its own error (honest generalization signal)
    loo = []
    if n > MIN_CORRESPONDENCES:
        for k in range(n):
            keep = [j for j in range(n) if j != k]
            Hwi_k, _ = cv2.findHomography(world[keep].astype(np.float64), image[keep].astype(np.float64), 0)
            if Hwi_k is None:
                continue
            try:
                Hk = np.linalg.inv(Hwi_k)
            except np.linalg.LinAlgError:
                continue
            p = _apply(Hk, image[k:k + 1])[0]
            loo.append(dict(name=names[k], d_board=float((p[0] - world[k, 0]) / LANE_WIDTH_IN * BOARDS),
                            d_ft=float(p[1] - world[k, 1])))

    # geometric sensitivity: at probe depths, how far does the mapped point move under a +1px image wobble?
    H_wi = np.linalg.inv(H_iw)
    sensitivity = {}
    for label, z in (("foul_0ft", 0.0), ("arrows_15ft", 15.0), ("breakpoint_40ft", 40.0),
                     ("entry_59ft", geometry.z_impact_ft)):
        base_img = _apply(H_wi, [[LANE_WIDTH_IN / 2.0, z]])[0]
        d_board, d_ft = 0.0, 0.0
        for dx, dy in ((1, 0), (0, 1)):
            w = _apply(H_iw, [base_img + [dx, dy]])[0]
            d_board = max(d_board, abs((w[0] - LANE_WIDTH_IN / 2.0) / LANE_WIDTH_IN * BOARDS))
            d_ft = max(d_ft, abs(w[1] - z))
        sensitivity[label] = dict(d_board_per_px=round(float(d_board), 3), d_ft_per_px=round(float(d_ft), 3))

    z_vals = world[:, 1]
    return dict(
        n_correspondences=int(n),
        n_inliers=int(inlier_mask.sum()) if inlier_mask is not None else int(n),
        reproj_board_rmse=float(np.sqrt(np.mean(res_board ** 2))),
        reproj_ft_rmse=float(np.sqrt(np.mean(res_ft ** 2))),
        reproj_board_max=float(np.max(np.abs(res_board))),
        longitudinal_spread_ft=float(z_vals.max() - z_vals.min()),
        longitudinal_zones=int(len(np.unique(np.round(z_vals / 5.0)))),   # distinct ~5-ft depth bands
        lateral_spread_in=float(world[:, 0].max() - world[:, 0].min()),
        leave_one_out=loo,
        sensitivity_per_px=sensitivity,
        residuals=[dict(name=names[k], d_board=round(float(res_board[k]), 3), d_ft=round(float(res_ft[k]), 3))
                   for k in range(n)],
    )
