"""Pose-based lane geometry (DEC-065, Shayne 2026-10-26): a full 3D camera POSE (solvePnP) from foul+pins,
self-calibrating the focal length from the labels so NO mandatory user calibration is required. Phase 1
tested only a single-plane homography (degenerate here); §3.4/§3.6 of CV_PHASE1_VALIDATION_REPORT showed the
pose recovers the near-to-mid lane once the focal is right.

What this is used for:
- `calibrate()` -> a `PoseCalibration` (pose + lane-plane homography + validity flags), the geometry a
  pose-based reconstruction consumes. Self-calibrating: focal source is explicit > EXIF (hook) > FITTED.
- `reconstruct_near()` -> near-lane ball metrics via the pose; far-lane metrics stay `unavailable` with a
  reason until the far geometry AND real ball measurements pass validation (DEC-065; Phase-2 reference).

Honest caveats baked in (reported, never hidden):
- The fitted focal is a per-clip FIT, trustworthy only when consistent across a camera's clips and
  cross-validated against held-out fiducials; it is evidence the focal is calibratable, not a calibration.
  Every pose-derived number carries its focal sensitivity.
- Coplanar foul+pins give a planar-PnP sign ambiguity (recovered camera height can read negative); lane
  coordinates are reproduced correctly but the pose sign is flagged, not asserted.
- Far-lane (40-60 ft) has no independent held-out fiducial in this cohort, so `far_valid` stays False.

Additive / off the production path (production CV frozen, DEC-062). Units: all 3D in INCHES (Z = feet*12).
Nothing here is ML.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional
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


def fit_focal(landmark_set, lo=900.0, hi=3200.0, coarse=50.0):
    """Jointly fit the focal length and pin height that MINIMIZE PnP reprojection over the verified foul+pins.
    The phone's effective focal after on-device stabilization/trim is unknown (open decision #2); here we
    treat it as a free parameter and recover the value that best explains the labels. Returns
    dict(focal_px, pin_height_in, reproj_px, rvec, tvec) or None if <4 anchors / solve fails.

    IMPORTANT: this is a per-clip FIT, not an independent calibration. Its value is only trustworthy if the
    fitted focal is CONSISTENT across clips of the same camera (a real lens constant) and is cross-validated
    against held-out fiducials (`interval_backprojection`). A good cross-clip agreement is evidence the focal
    is calibratable; it is NOT a substitute for a one-time intrinsics calibration."""
    names, _, image = landmark_set.correspondences()
    names = list(names)
    if sum(1 for n in names if n.startswith("pin_")) < 4 or not any(n.startswith("foul_") for n in names):
        return None
    w, h = landmark_set.image_size
    best = None
    f = lo
    while f <= hi:
        K = nominal_K(w, h, f)
        ph = fit_pin_height(landmark_set, f)[0] or 0.0
        obj = _object_points(names, ph)
        r = _pnp(obj, image, K)
        if r is not None and (best is None or r[2] < best[2]):
            best = (f, ph, r[2], r[0], r[1])
        f += coarse
    if best is None:
        return None
    # fine search ±coarse around the coarse minimum
    f0 = best[0]
    f = max(lo, f0 - coarse)
    while f <= min(hi, f0 + coarse):
        K = nominal_K(w, h, f)
        ph = fit_pin_height(landmark_set, f)[0] or 0.0
        obj = _object_points(names, ph)
        r = _pnp(obj, image, K)
        if r is not None and r[2] < best[2]:
            best = (f, ph, r[2], r[0], r[1])
        f += coarse / 10.0
    return dict(focal_px=round(float(best[0]), 1), pin_height_in=round(float(best[1]), 2),
                reproj_px=round(float(best[2]), 2), rvec=best[3], tvec=best[4])


def interval_backprojection(landmark_set, rvec, tvec, K, geometry=CANONICAL):
    """Back-project every verified USBC-interval fiducial (arrow/dot/approach_dot/downlane_target) to the lane
    plane Y=0 and report its recovered Z (ft) and whether it lands in that landmark's permitted band. The
    interval fiducials are HELD OUT of the pose solve (which uses only foul+pins), so this is an independent
    cross-check of the recovered geometry. Returns {family: {'in_band': k, 'n': m, 'z': [..]}}."""
    intervals = geometry.interval_landmarks()
    out = {}
    for name, ob in landmark_set.observations.items():
        if not ob.usable or name not in intervals:
            continue
        x_in, z_min, z_max = intervals[name]
        bp = _ray_plane_board(rvec, tvec, K, (ob.x, ob.y), Y=0.0)
        if bp is None:
            continue
        fam = name.rsplit("_", 1)[0]
        d = out.setdefault(fam, {"in_band": 0, "n": 0, "z": [], "band": [z_min, z_max]})
        d["n"] += 1
        d["z"].append(round(bp[1], 1))
        if z_min <= bp[1] <= z_max:
            d["in_band"] += 1
    return out


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


# ---------------------------------------------------------------- pose-based calibration (DEC-065)
NEAR_REPROJ_PX_MAX = 4.0       # pose reprojection over foul+pins (real clips: ~0.6-1.7 px)
NEAR_SENS_BOARD_MAX = 1.5      # near conditioning: boards of error per pixel at the arrows (15 ft)
ARROW_IN_BAND_MIN = 0.6        # when arrows are labeled, fraction that must land in their USBC band
# Far-lane stays unavailable until BOTH the far geometry and real ball measurements pass a reference test.
FAR_UNVALIDATED_REASON = ("far-lane geometry unvalidated — no independent held-out fiducial past 16 ft in "
                          "this cohort; pending the Phase-2 mid-lane tape/cross-camera reference + a real "
                          "ball-measurement test (DEC-065). Far metrics (entry/breakpoint/late speed) are "
                          "reported `unavailable`, never estimated.")


def plane_homography(rvec, tvec, K):
    """Image <-> lane-plane (Y=0) homography induced by the camera pose, in the canonical (X inches, Z feet)
    frame used by `ablation.reconstruct_from_homography`. A lane-plane point is [X_in, 0, Z_ft*12]; its
    projection is a 3x3 homography with columns K@R[:,0] (per inch of X), K@R[:,2]*12 (per foot of Z), K@t.
    Returns H_img_to_world (the inverse). Lets the tested reconstruction core run on a pose, unchanged."""
    R, _ = cv2.Rodrigues(np.asarray(rvec, float))
    t = np.asarray(tvec, float).reshape(3)
    H_wi = K @ np.column_stack([R[:, 0], R[:, 2] * IN_PER_FT, t])
    return np.linalg.inv(H_wi)


@dataclass
class PoseCalibration:
    clip_id: str
    focal_px: float
    focal_source: str            # 'given' | 'exif' | 'fitted'
    pin_height_in: float
    reproj_px: float
    cam_height_in: float
    cam_standoff_ft: float
    cam_lateral_in: float
    cam_pitch_deg: float
    rvec: np.ndarray
    tvec: np.ndarray
    K: np.ndarray
    H_iw: np.ndarray             # image -> lane-plane (X in, Z ft) homography for reconstruction
    near_valid: bool
    near_reason: str
    far_valid: bool
    far_reason: str
    sensitivity_profile: dict = field(default_factory=dict)      # {z_ft: board/px}
    arrows_in_band: Optional[str] = None                         # "k/n" when arrows are labeled (held-out)
    sign_caveat: bool = False    # recovered camera height negative (planar-PnP chirality) -> flagged

    def to_dict(self):
        return dict(clip_id=self.clip_id, focal_px=round(self.focal_px, 1), focal_source=self.focal_source,
                    pin_height_in=self.pin_height_in, reproj_px=round(self.reproj_px, 2),
                    cam_height_in=round(self.cam_height_in, 1), cam_standoff_ft=round(self.cam_standoff_ft, 1),
                    cam_lateral_in=round(self.cam_lateral_in, 1), cam_pitch_deg=round(self.cam_pitch_deg, 1),
                    near_valid=self.near_valid, near_reason=self.near_reason,
                    far_valid=self.far_valid, far_reason=self.far_reason,
                    sensitivity_profile={k: round(v, 3) for k, v in self.sensitivity_profile.items()},
                    arrows_in_band=self.arrows_in_band, sign_caveat=self.sign_caveat)


def sensitivity_profile(rvec, tvec, K, z_list_ft=(0.0, 7.0, 15.0, 40.0, None)):
    """Board error per pixel of ball/landmark localization, probed down-lane at board-20 center. `None` in
    the list means the entry reference (z_impact_ft). Shows WHERE the geometry is well-conditioned."""
    out = {}
    for z in z_list_ft:
        zf = CANONICAL.z_impact_ft if z is None else z
        world = np.array([[LANE_WIDTH_IN / 2.0, 0.0, zf * IN_PER_FT]])
        uv0 = cv2.projectPoints(world, rvec, tvec, K, None)[0].reshape(2)
        base = _ray_plane_board(rvec, tvec, K, uv0)
        if base is None:
            continue
        dmax = 0.0
        for du, dv in ((1, 0), (0, 1)):
            bp = _ray_plane_board(rvec, tvec, K, uv0 + [du, dv])
            if bp is not None:
                dmax = max(dmax, abs((bp[0] - LANE_WIDTH_IN / 2.0) / LANE_WIDTH_IN * BOARDS))
        out[round(zf, 1)] = float(dmax)
    return out


def calibrate(landmark_set, focal_px=None, focal_source=None):
    """Pose-based lane calibration from verified foul+pins, self-calibrating the focal (fit from the labels)
    unless one is supplied. Returns a `PoseCalibration` or None (too few anchors / solve failed).

    focal_px: explicit focal (source 'given'); if None, fit it (`fit_focal`, source 'fitted'). An EXIF-derived
    focal should be passed in with focal_source='exif'. No mandatory user calibration — the fitted focal is the
    default path; its trustworthiness is reported via `sensitivity_profile` and (when arrows are labeled)
    `arrows_in_band`."""
    names, _, image = landmark_set.correspondences()
    names = list(names)
    if sum(1 for n in names if n.startswith("pin_")) < 4 or not any(n.startswith("foul_") for n in names):
        return None
    w, h = landmark_set.image_size
    if focal_px is None:
        fit = fit_focal(landmark_set)
        if fit is None:
            return None
        focal_px, pin_h, reproj = fit["focal_px"], fit["pin_height_in"], fit["reproj_px"]
        rvec, tvec = fit["rvec"], fit["tvec"]
        focal_source = focal_source or "fitted"
    else:
        focal_source = focal_source or "given"
        pin_h = fit_pin_height(landmark_set, focal_px)[0] or 0.0
        K0 = nominal_K(w, h, focal_px)
        r = _pnp(_object_points(names, pin_h), image, K0)
        if r is None:
            return None
        rvec, tvec, reproj = r
    K = nominal_K(w, h, focal_px)
    R, _ = cv2.Rodrigues(rvec)
    C = (-R.T @ tvec).ravel()
    axis = R.T @ np.array([0.0, 0.0, 1.0])            # camera optical axis in world
    horiz = float(np.hypot(axis[0], axis[2]))
    pitch = float(np.degrees(np.arctan2(-axis[1], horiz))) if horiz > 1e-9 else 0.0
    H_iw = plane_homography(rvec, tvec, K)
    prof = sensitivity_profile(rvec, tvec, K)

    # near-geometry validity: pose fits foul+pins tightly AND near conditioning is good. When arrows are
    # labeled (validation clips), additionally require them to land in band — the independent held-out check.
    s15 = prof.get(15.0)
    xb = interval_backprojection(landmark_set, rvec, tvec, K).get("arrow")
    arrows_str, arrows_ok = None, True
    if xb and xb["n"]:
        arrows_str = f"{xb['in_band']}/{xb['n']}"
        arrows_ok = (xb["in_band"] / xb["n"]) >= ARROW_IN_BAND_MIN
    why = []
    if reproj > NEAR_REPROJ_PX_MAX:
        why.append(f"pose reproj {round(reproj,2)} px > {NEAR_REPROJ_PX_MAX}")
    if s15 is None or s15 > NEAR_SENS_BOARD_MAX:
        why.append(f"near conditioning {s15} > {NEAR_SENS_BOARD_MAX} board/px")
    if not arrows_ok:
        why.append(f"held-out arrows only {arrows_str} in USBC band")
    near_valid = not why

    return PoseCalibration(
        clip_id=landmark_set.clip_id, focal_px=float(focal_px), focal_source=focal_source,
        pin_height_in=float(pin_h), reproj_px=float(reproj),
        cam_height_in=float(C[1]), cam_standoff_ft=float(-C[2] / IN_PER_FT), cam_lateral_in=float(C[0]),
        cam_pitch_deg=pitch, rvec=rvec, tvec=tvec, K=K, H_iw=H_iw,
        near_valid=near_valid, near_reason=("ok" if near_valid else "; ".join(why)),
        far_valid=False, far_reason=FAR_UNVALIDATED_REASON,
        sensitivity_profile=prof, arrows_in_band=arrows_str, sign_caveat=bool(C[1] < 0))


def reconstruct_near(cal, centers_img, geometry=CANONICAL):
    """Reconstruct the ball track through the pose's lane-plane homography and return NEAR-lane metrics only.
    Far-lane outputs (entry/breakpoint) are forced `unavailable` with `cal.far_reason` until validated
    (DEC-065). Reuses the tested `ablation.reconstruct_from_homography` core (a pose induces exactly this
    plane homography). Speed is intentionally not computed here — it needs reliable timing endpoints."""
    from .ablation import reconstruct_from_homography
    r = reconstruct_from_homography(cal.H_iw, centers_img, geometry)
    if not r.get("ok"):
        return r
    for k in ("entry_board", "breakpoint_board", "breakpoint_ft"):
        r[k] = None
    r["far_unavailable_reason"] = cal.far_reason
    r["near_valid"] = cal.near_valid
    r["focal_source"] = cal.focal_source
    return r
