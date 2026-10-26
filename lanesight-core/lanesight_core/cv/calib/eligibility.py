"""Metric eligibility + 🟢/🟡/🔴 classification from ACTUAL calibration & observability checks (not camera
height). Realizes the Phase-3 capture-quality tiers and the product rule "never reject a whole video — return
partial results" (Shayne, 2026-10-26). Thresholds below are provisional (handoff §8 development targets) and
are fixed from Phase-2 data (CV_PHASE2_CAMERA_VALIDATION_PROTOCOL).

Inputs are the outputs the Phase-1 harness already produces:
  diag            = solve.calibration_diagnostics(...)   (reproj_board_rmse, longitudinal_zones, sensitivity_per_px)
  interval_checks = solve.interval_consistency(...)       (arrows/dots within their USBC band)
  coverage        = track_coverage(centers_or_track)      (near_ft / far_ft tracked)
  far_ball_px     = resolution.far_lane_ball_resolution(...)['far_detected_ball_px']   (optional)

Nothing here runs on or modifies the production path.
"""
from __future__ import annotations

# --- provisional thresholds (TUNE from Phase 2) ---
REPROJ_BOARD_MAX = 0.75        # calibration reprojection residual ceiling (boards)
SENS_ENTRY_MAX = 1.5           # far-lane conditioning: boards of entry error per pixel
MIN_ZONES = 3                  # distinct ~5-ft longitudinal anchor bands
ARROW_WITHIN_MIN = 0.6         # fraction of verified arrows that must land in their USBC band
TRACK_FAR_FT = 55.0            # ball must be tracked to at least here for far-lane metrics
TRACK_MID_FT = 45.0            # breakpoint region coverage
TRACK_NEAR_FT = 7.0            # track must start at/below here for near-lane metrics
FAR_BALL_MIN_PX = 6.0          # far ball must be this big to be detectable/centroidable

GREEN, YELLOW, RED = "full", "partial", "reposition"
TIER_EMOJI = {GREEN: "🟢", YELLOW: "🟡", RED: "🔴"}

# --- near-field (partial-results) calibration gate ---
NEAR_REPROJ_BOARD_MAX = 0.75   # near homography must fit its coplanar fiducials this tightly
NEAR_SENS_MAX = 1.5            # near conditioning at the arrows (boards of error per pixel)
NEAR_BRACKET_MIN_FT = 12.0     # deepest labeled near fiducial must reach ~the arrows so 0-15 ft is
                              # INTERPOLATED (trustworthy), not extrapolated beyond the fiducials (biased)
NEAR_SHALLOW_MAX_FT = 2.0      # shallowest fiducial must reach ~the foul so laydown (0 ft) is bracketed too
TRACK_REQS = ("near_track", "mid_track", "far_track")   # per-shot gates, separate from the geometry gate


def near_calibration_ok(near_diag):
    """Geometry gate for the NEAR lane (0-15 ft) from solve.near_field_homography's diagnostics. Valid only
    when the near homography (a) fits its coplanar fiducials tightly, (b) is well-conditioned at the arrows,
    AND (c) the fiducials bracket the near region so 0-15 ft is interpolated not extrapolated. Returns
    (ok: bool, reason: str). Fails closed on a missing diag."""
    if not near_diag:
        return (False, "near calibration failed / not computed")
    resid = near_diag.get("reproj_board_rmse")
    s15 = near_diag.get("sensitivity_per_px", {}).get("arrows_15ft", {}).get("d_board_per_px")
    deepest = near_diag.get("deepest_fiducial_z_ft")
    shallowest = near_diag.get("shallowest_fiducial_z_ft")
    why = []
    if resid is None or resid > NEAR_REPROJ_BOARD_MAX:
        why.append(f"near reproj {resid} > {NEAR_REPROJ_BOARD_MAX} board" if resid is not None else "no near residual")
    if s15 is None or s15 > NEAR_SENS_MAX:
        why.append(f"near conditioning {s15} > {NEAR_SENS_MAX} board/px" if s15 is not None else "no near conditioning")
    if deepest is None or deepest < NEAR_BRACKET_MIN_FT:
        why.append(f"fiducials reach only {deepest} ft (< {NEAR_BRACKET_MIN_FT}); 0-15 ft would be extrapolated")
    if shallowest is None or shallowest > NEAR_SHALLOW_MAX_FT:
        why.append(f"shallowest fiducial at {shallowest} ft (> {NEAR_SHALLOW_MAX_FT}); laydown (0 ft) unbracketed "
                   "(label the foul line)")
    return (not why, "ok" if not why else "; ".join(why))


def calibration_readiness(near_calib_valid, far_calib_valid, far_conditioning_ok):
    """Per-metric GEOMETRY readiness, ignoring the per-shot ball-track gate — for the Phase-1 calibration
    study where no ball track is re-run. A metric is 'geometry_ready' when its calibration requirements
    (near_calib / far_calib / far_conditioning) are met; the track requirements are reported separately and
    are NOT asserted here. Returns {geometry_tier, emoji, metrics:{name:{geometry_ready, needs}}}."""
    cal = {"near_calib": bool(near_calib_valid), "far_calib": bool(far_calib_valid),
           "far_conditioning": bool(far_conditioning_ok), "calib_valid": bool(far_calib_valid)}
    metrics = {}
    for name, reqs in METRIC_REQUIREMENTS.items():
        cal_reqs = [r for r in reqs if r not in TRACK_REQS]
        failed = [r for r in cal_reqs if not cal.get(r, False)]
        metrics[name] = {"geometry_ready": not failed, "needs": failed,
                         "track_gated": [r for r in reqs if r in TRACK_REQS]}
    geom_tier = GREEN if (far_calib_valid and far_conditioning_ok) else (YELLOW if near_calib_valid else RED)
    return {"geometry_tier": geom_tier, "emoji": TIER_EMOJI[geom_tier], "metrics": metrics,
            "geometry_ready_count": sum(1 for m in metrics.values() if m["geometry_ready"])}

# metric -> the conditions it requires. Conditions are keys into the computed `checks` dict. Near-lane
# metrics need only the NEAR-field calibration (foul + on-plane dots/arrows) — recoverable even when the far
# lane is not (the partial-results path). Far-lane metrics need the far calibration + far conditioning + track.
METRIC_REQUIREMENTS = {
    "laydown_board":      ["near_calib", "near_track"],
    "board_at_7ft":       ["near_calib", "near_track"],
    "launch_angle":       ["near_calib", "near_track"],
    "speed_early":        ["near_calib", "near_track"],
    "speed_release":      ["near_calib", "near_track"],
    "arrows_board":       ["near_calib", "near_track"],
    "breakpoint_board":   ["far_calib", "far_conditioning", "mid_track"],
    "breakpoint_distance":["far_calib", "far_conditioning", "mid_track"],
    "entry_board":        ["far_calib", "far_conditioning", "far_track"],
    "entry_angle":        ["far_calib", "far_conditioning", "far_track"],
    "speed_late":         ["far_calib", "far_track"],
    "ball_speed":         ["far_calib", "far_track"],   # 60 ft foul->pins average needs the ball to the pins
}


def track_coverage(centers_or_track):
    """near_ft (min tracked lane distance) / far_ft (max). Accepts (t,cx,cy)+world is unknown here, so pass a
    list of lane-plane Z values, or a list of dicts with 'z_ft', or a (near_ft, far_ft) tuple."""
    if isinstance(centers_or_track, (tuple, list)) and len(centers_or_track) == 2 \
            and all(isinstance(v, (int, float)) for v in centers_or_track):
        return {"near_ft": float(centers_or_track[0]), "far_ft": float(centers_or_track[1])}
    zs = []
    for c in centers_or_track:
        if isinstance(c, dict) and "z_ft" in c:
            zs.append(c["z_ft"])
        elif isinstance(c, (int, float)):
            zs.append(c)
    if not zs:
        return {"near_ft": None, "far_ft": None}
    return {"near_ft": float(min(zs)), "far_ft": float(max(zs))}


def classify(diag=None, interval_checks=None, coverage=None, far_ball_px=None, near_calib_valid=None):
    """Return {tier, emoji, checks, metrics:{name:{eligible,reason}}}. Any input may be None (treated as
    'not established' → the dependent checks fail closed).

    `diag` is the FAR/full calibration (foul+pins). `near_calib_valid` (bool) is whether the separate
    NEAR-field calibration (solve.near_field_homography) is valid — pass it to enable near-lane metrics even
    when the far calibration is degenerate (the partial-results path). None → near falls back to far."""
    checks = {}
    # far / full calibration validity
    if diag is None:
        checks["far_calib"] = (False, "no calibration")
    else:
        resid = diag.get("reproj_board_rmse")
        zones = diag.get("longitudinal_zones", 0)
        arrows = [c for c in (interval_checks or []) if c["name"].startswith("arrow_")]
        arr_ok = (sum(c["within"] for c in arrows) / len(arrows) >= ARROW_WITHIN_MIN) if arrows else True
        ok = (resid is not None and resid <= REPROJ_BOARD_MAX and zones >= MIN_ZONES and arr_ok)
        why = []
        if resid is None or resid > REPROJ_BOARD_MAX:
            why.append(f"reproj {resid} > {REPROJ_BOARD_MAX} board" if resid is not None else "no residual")
        if zones < MIN_ZONES:
            why.append(f"only {zones} depth zone(s) < {MIN_ZONES}")
        if not arr_ok:
            why.append("arrows fail USBC-band check")
        checks["far_calib"] = (ok, "ok" if ok else "; ".join(why))
    # near-field calibration — explicit flag if given, else mirror the far calibration
    if near_calib_valid is None:
        checks["near_calib"] = checks["far_calib"]
    else:
        checks["near_calib"] = (bool(near_calib_valid),
                                "near-field calibration ok" if near_calib_valid else "near-field calibration invalid")
    checks["calib_valid"] = checks["far_calib"]        # backward-compat alias
    # far-lane conditioning
    sens = None if diag is None else diag.get("sensitivity_per_px", {}).get("entry_59ft", {}).get("d_board_per_px")
    checks["far_conditioning"] = ((sens is not None and sens <= SENS_ENTRY_MAX),
                                  "ok" if (sens is not None and sens <= SENS_ENTRY_MAX)
                                  else f"sensitivity {sens} > {SENS_ENTRY_MAX} board/px")
    # tracking coverage
    near = (coverage or {}).get("near_ft")
    far = (coverage or {}).get("far_ft")
    checks["near_track"] = ((near is not None and near <= TRACK_NEAR_FT),
                            "ok" if (near is not None and near <= TRACK_NEAR_FT) else f"track starts at {near} ft")
    checks["mid_track"] = ((far is not None and far >= TRACK_MID_FT),
                           "ok" if (far is not None and far >= TRACK_MID_FT) else f"track ends at {far} ft")
    far_ball_ok = far_ball_px is None or far_ball_px >= FAR_BALL_MIN_PX
    checks["far_track"] = ((far is not None and far >= TRACK_FAR_FT and far_ball_ok),
                           "ok" if (far is not None and far >= TRACK_FAR_FT and far_ball_ok)
                           else f"track ends at {far} ft / far ball {far_ball_px}px")

    # per-metric eligibility
    metrics = {}
    for name, reqs in METRIC_REQUIREMENTS.items():
        failed = [r for r in reqs if not checks[r][0]]
        metrics[name] = {"eligible": not failed,
                         "reason": "ok" if not failed else "needs " + ", ".join(
                             f"{r} ({checks[r][1]})" for r in failed)}

    far_full = checks["far_calib"][0] and checks["far_conditioning"][0] and checks["far_track"][0]
    near_ok = checks["near_track"][0] and checks["near_calib"][0]
    if far_full:
        tier = GREEN
    elif near_ok:
        tier = YELLOW
    else:
        tier = RED
    return {"tier": tier, "emoji": TIER_EMOJI[tier], "checks": {k: {"pass": v[0], "why": v[1]} for k, v in checks.items()},
            "metrics": metrics,
            "eligible_count": sum(1 for m in metrics.values() if m["eligible"]),
            "total_metrics": len(metrics)}
