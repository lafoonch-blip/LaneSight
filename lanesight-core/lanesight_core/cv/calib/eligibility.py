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

# metric -> the conditions it requires. Conditions are keys into the computed `checks` dict.
METRIC_REQUIREMENTS = {
    "laydown_board":      ["calib_valid", "near_track"],
    "board_at_7ft":       ["calib_valid", "near_track"],
    "launch_angle":       ["calib_valid", "near_track"],
    "speed_early":        ["near_track"],
    "speed_release":      ["near_track"],
    "arrows_board":       ["calib_valid", "mid_track"],
    "breakpoint_board":   ["calib_valid", "far_conditioning", "mid_track"],
    "breakpoint_distance":["calib_valid", "far_conditioning", "mid_track"],
    "entry_board":        ["calib_valid", "far_conditioning", "far_track"],
    "entry_angle":        ["calib_valid", "far_conditioning", "far_track"],
    "speed_late":         ["far_track"],
    "ball_speed":         ["far_track"],      # 60 ft foul->pins average needs the ball to the pins
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


def classify(diag=None, interval_checks=None, coverage=None, far_ball_px=None):
    """Return {tier, emoji, checks, metrics:{name:{eligible,reason}}}. Any input may be None (treated as
    'not established' → the dependent checks fail closed)."""
    checks = {}
    # calibration validity
    if diag is None:
        checks["calib_valid"] = (False, "no calibration")
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
        checks["calib_valid"] = (ok, "ok" if ok else "; ".join(why))
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

    far_full = checks["calib_valid"][0] and checks["far_conditioning"][0] and checks["far_track"][0]
    near_ok = checks["near_track"][0] and (checks["calib_valid"][0] or far is not None)
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
