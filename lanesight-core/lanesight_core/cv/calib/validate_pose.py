"""Independent validation of the pose-based geometry (DEC-065) on a flat cohort of verified clips.

What it reports, per clip and aggregated — honest about what is proven vs pending:
  1. Self-calibration: the fitted focal per clip, and whether it is CONSISTENT across the cohort (a real lens
     constant -> calibratable with no mandatory user calibration). Reported as median/range/std.
  2. Near geometry (0-15 ft) — INDEPENDENT held-out check: the arrows/dots are painted lane features at known
     USBC positions that are NOT used in the pose solve, so where they land after back-projection validates
     near-lane POSITION measurement. Pass = arrows in their 12-16 ft band.
  3. Focal sensitivity of a NEAR measurement: how much a labeled near board reading moves if the focal is off
     by +/-10%. Small => the self-calibrated focal is good enough WITHOUT a checkerboard (the no-mandatory-
     calibration goal); large => a one-time calibration is needed. The number decides it, not an assumption.
  4. Far lane (40-60 ft): reported UNVALIDATED for every clip — there is no independent held-out fiducial past
     16 ft in this cohort, so far metrics stay `unavailable` until the Phase-2 mid-lane reference + a real
     ball-measurement test (DEC-065). This harness never emits a far-lane number.

Real-ball near metrics (laydown/early speed) are reconstructed WHERE a ball track is supplied; the production
tracker fails lane-detection on this elevated cohort (a separate issue), so tracks are not auto-available
here — the near GEOMETRY is validated by the arrows (real features on the same plane/region as the ball),
with the centroid-precision floor from `resolution.py`. Additive; production frozen (DEC-062); no ML.
"""
from __future__ import annotations
import os
import glob
import json
import numpy as np
import cv2

from .landmarks import LandmarkSet
from .lane_geometry import CANONICAL, LANE_WIDTH_IN, BOARDS, board_from_left
from . import pose as P


def _board_of(cal_rvec, cal_tvec, K, uv):
    """Absolute-ish board_from_left of an image point under a pose (lateral, scale-invariant part)."""
    bp = P._ray_plane_board(cal_rvec, cal_tvec, K, uv, 0.0)
    return None if bp is None else board_from_left(bp[0])


def focal_sensitivity_near(landmark_set, focal_px, probe="arrow_20", pct=0.10):
    """Re-solve the pose at focal*(1±pct) and measure how far a labeled NEAR point's board reading moves.
    Returns max |Δboard| vs the nominal focal, or None if the probe point / solve is unavailable."""
    ob = landmark_set.observations.get(probe)
    if not (ob and ob.usable):
        # fall back to any labeled arrow
        for n, o in landmark_set.observations.items():
            if n.startswith("arrow_") and o.usable:
                ob, probe = o, n
                break
    if not (ob and ob.usable):
        return None
    names, _, image = landmark_set.correspondences()
    names = list(names)
    w, h = landmark_set.image_size
    readings = []
    for f in (focal_px * (1 - pct), focal_px, focal_px * (1 + pct)):
        K = P.nominal_K(w, h, f)
        ph = P.fit_pin_height(landmark_set, f)[0] or 0.0
        r = P._pnp(P._object_points(names, ph), image, K)
        if r is None:
            return None
        b = _board_of(r[0], r[1], K, (ob.x, ob.y))
        if b is None:
            return None
        readings.append(b)
    base = readings[1]
    return float(max(abs(readings[0] - base), abs(readings[2] - base)))


def validate_clip(landmarks_path, session_focal_px=None):
    """Calibrate one clip (self-cal focal unless a session focal is given) and gather the validation signals."""
    ls = LandmarkSet.from_json(landmarks_path)
    cal = P.calibrate(ls, focal_px=session_focal_px)
    if cal is None:
        return dict(clip=ls.clip_id, ok=False, reason="pose needs foul + >=4 pins")
    out = cal.to_dict()
    out.update(clip=ls.clip_id, ok=True)
    out["focal_sens_near_board_pm10pct"] = focal_sensitivity_near(ls, cal.focal_px)
    return out


def run(root, session_aggregate=True):
    """Validate every `*.landmarks.json` under `root`. Two passes when session_aggregate: (1) per-clip fitted
    focal to measure cross-clip consistency, (2) re-validate at the session median focal (the deployable
    self-calibration — one focal per camera/session, no per-clip fitting)."""
    paths = sorted(glob.glob(os.path.join(root, "*.landmarks.json")))
    per_clip = [validate_clip(p) for p in paths]
    focals = [c["focal_px"] for c in per_clip if c.get("ok")]
    session = None
    if focals:
        session = dict(n=len(focals), median=float(np.median(focals)),
                       min=float(min(focals)), max=float(max(focals)), std=float(np.std(focals)))
    at_session = []
    if session_aggregate and session:
        at_session = [validate_clip(p, session_focal_px=session["median"]) for p in paths]
    ok = [c for c in (at_session or per_clip) if c.get("ok")]
    near_pass = sum(1 for c in ok if c.get("near_valid"))
    arrow_clips = [c for c in ok if c.get("arrows_in_band")]
    return dict(root=root, n_clips=len(per_clip), session_focal=session,
                near_geometry_valid=f"{near_pass}/{len(ok)}",
                arrows_in_band_clips=len(arrow_clips),
                far_lane="UNVALIDATED — no held-out fiducial past 16 ft; pending Phase-2 reference (DEC-065)",
                per_clip_fitted=per_clip, per_clip_session_focal=at_session)


def _print(res):
    s = res["session_focal"]
    print(f"cohort: {res['n_clips']} clips")
    if s:
        print(f"self-calibration focal: median={s['median']:.0f} px  range={s['min']:.0f}-{s['max']:.0f}  "
              f"std={s['std']:.0f}  (n={s['n']})  -> {'CONSISTENT (calibratable)' if s['std'] < 100 else 'inconsistent'}")
    print(f"near geometry valid (held-out arrows in band): {res['near_geometry_valid']}")
    print(f"far lane: {res['far_lane']}\n")
    rows = res["per_clip_session_focal"] or res["per_clip_fitted"]
    print(f"{'clip':10} {'near':>5} {'reproj_px':>9} {'arrows':>7} {'sens@15':>8} {'focalΔ±10%':>10} {'pitch':>6} {'sign':>5}")
    for c in rows:
        if not c.get("ok"):
            print(f"{c['clip']:10}  --  {c['reason']}")
            continue
        prof = c.get("sensitivity_profile", {})
        s15 = prof.get("15.0", prof.get(15.0))
        fs = c.get("focal_sens_near_board_pm10pct")
        print(f"{c['clip']:10} {('YES' if c['near_valid'] else 'no'):>5} {c['reproj_px']:>9.2f} "
              f"{str(c.get('arrows_in_band') or '-'):>7} {(f'{s15:.2f}' if s15 is not None else '-'):>8} "
              f"{(f'{fs:.2f}' if fs is not None else '-'):>10} {c['cam_pitch_deg']:>6.1f} "
              f"{('flag' if c.get('sign_caveat') else 'ok'):>5}")


if __name__ == "__main__":
    import sys
    root = sys.argv[1]
    res = run(root)
    _print(res)
    out = os.path.join(root, "pose_validation.json")
    json.dump(res, open(out, "w"), indent=1, default=float)
    print(f"\nwrote {out}")
