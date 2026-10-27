"""Phase-2 camera-position validation runner (CV_PHASE2_CAMERA_VALIDATION_PROTOCOL). Ingests position-tagged
clips, scores each with the Phase-1 harness + the eligibility classifier, and compares positions. Reuses
existing modules only; no production-path changes, no ML.

Data layout:
  <root>/POS_A/<clip>.mov                         recordings (position A..D)
  <root>/POS_A/calib/<clip>.plate.png             stabilized plate (ablation.py 'plate')
  <root>/POS_A/calib/<clip>.landmarks.json        verified foul+pins (+ tape 'measured' marks)
  <root>/POS_A/tape_marks.json                    optional absolute board(Z) truth

CLI:
  python -m lanesight_core.cv.calib.phase2 <root>              score all positions
  python -m lanesight_core.cv.calib.phase2 <root> --no-video  calibration/eligibility only (skip analyze)
"""
from __future__ import annotations
import os
import glob
import json
import numpy as np

from .landmarks import LandmarkSet
from .solve import homography_from_landmarks, near_field_homography, interval_consistency, CalibrationError
from .ablation import reconstruct_from_homography
from . import eligibility as elig


def score_calibration(landmark_set):
    """Solve + diagnose from verified anchors. Returns (H_iw, diag, interval_checks) or (None, None, reason)."""
    try:
        H_iw, _, diag = homography_from_landmarks(landmark_set)
    except CalibrationError as e:
        return None, None, str(e)
    return H_iw, diag, interval_consistency(H_iw, landmark_set)


def score_near_calibration(landmark_set):
    """Independent NEAR-field calibration (foul + on-plane dots/arrows). Returns (near_diag, ok, reason).
    Computed even when the far/full calibration is degenerate — that is the partial-results path."""
    try:
        _, _, near_diag = near_field_homography(landmark_set)
    except CalibrationError as e:
        return None, False, str(e)
    ok, reason = elig.near_calibration_ok(near_diag)
    return near_diag, ok, reason


def score_clip(landmarks_path, centers=None, video=None, out_prefix=None, handed="R"):
    """Score one clip: far + near calibration, (optional) reconstruction/coverage, and eligibility tier.

    The near-field calibration is run INDEPENDENTLY of the far one, so a clip whose far/full calibration is
    degenerate (the elevated ball-return cohort) still reports its recoverable near-lane metrics — the 🟡
    partial-results path, never a blanket reject.

    centers: optional [(t,cx,cy)] auto track (stabilized-frame px). If `video` is given and centers is None,
    runs pipeline.analyze to get them (slow). Returns a result dict."""
    ls = LandmarkSet.from_json(landmarks_path)
    clip = ls.clip_id
    H_iw, diag, checks = score_calibration(ls)
    near_diag, near_ok, near_reason = score_near_calibration(ls)
    near_sens = (near_diag or {}).get("sensitivity_per_px", {})

    if H_iw is None:
        # far calibration failed — still report the near-field (partial) result, which may be valid
        return dict(clip=clip, calibrated=False, far_reason=checks,
                    near_calib=dict(valid=near_ok, reason=near_reason,
                                    reproj_board_rmse=round((near_diag or {}).get("reproj_board_rmse", float("nan")), 3)
                                    if near_diag else None,
                                    sens_0ft=near_sens.get("foul_0ft", {}).get("d_board_per_px"),
                                    sens_15ft=near_sens.get("arrows_15ft", {}).get("d_board_per_px"),
                                    deepest_fiducial_z_ft=(near_diag or {}).get("deepest_fiducial_z_ft")),
                    eligibility=elig.classify(diag=None, near_calib_valid=near_ok),
                    geometry=elig.calibration_readiness(near_ok, False, False))

    if centers is None and video is not None:
        from ..pipeline import analyze
        try:
            rec = analyze(video, out_prefix or (os.path.splitext(video)[0]), handed=handed)
            centers = [(p["t"], p["x"], p["y"]) for p in rec.to_dict()["trajectory"]["pixel"]]
        except Exception as e:
            centers = None
            analyze_err = str(e)

    recon, coverage, far_ball = None, None, None
    if centers:
        recon = reconstruct_from_homography(H_iw, centers)
        if recon.get("ok") and recon.get("path"):
            coverage = elig.track_coverage(recon["path"]["z_ft"])
    far_cond_ok = diag["sensitivity_per_px"]["entry_59ft"]["d_board_per_px"] <= elig.SENS_ENTRY_MAX
    tier = elig.classify(diag=diag, interval_checks=checks, coverage=coverage, far_ball_px=far_ball,
                         near_calib_valid=near_ok)
    far_calib_ok = tier["checks"]["far_calib"]["pass"]
    return dict(clip=clip, calibrated=True,
                reproj_board_rmse=round(diag["reproj_board_rmse"], 3),
                longitudinal_zones=diag["longitudinal_zones"],
                sensitivity_entry=diag["sensitivity_per_px"]["entry_59ft"]["d_board_per_px"],
                arrows_within=f"{sum(c['within'] for c in checks if c['name'].startswith('arrow_'))}/"
                              f"{sum(1 for c in checks if c['name'].startswith('arrow_'))}",
                entry_board=(recon or {}).get("entry_board"),
                near_calib=dict(valid=near_ok, reason=near_reason,
                                reproj_board_rmse=round(near_diag["reproj_board_rmse"], 3) if near_diag else None,
                                sens_0ft=near_sens.get("foul_0ft", {}).get("d_board_per_px"),
                                sens_15ft=near_sens.get("arrows_15ft", {}).get("d_board_per_px"),
                                deepest_fiducial_z_ft=(near_diag or {}).get("deepest_fiducial_z_ft")),
                coverage=coverage, eligibility=tier,
                geometry=elig.calibration_readiness(near_ok, far_calib_ok, far_cond_ok))


def run(root, use_video=True):
    results = {}
    for pos_dir in sorted(glob.glob(os.path.join(root, "POS_*"))):
        pos = os.path.basename(pos_dir)
        clips = []
        for jp in sorted(glob.glob(os.path.join(pos_dir, "calib", "*.landmarks.json"))):
            clip = os.path.basename(jp)[:-len(".landmarks.json")]
            video = os.path.join(pos_dir, f"{clip}.mov")
            clips.append(score_clip(jp, video=video if (use_video and os.path.exists(video)) else None,
                                    out_prefix=os.path.join(pos_dir, "calib", clip)))
        tiers = [c["eligibility"]["tier"] for c in clips]
        results[pos] = dict(n=len(clips),
                            tiers={t: tiers.count(t) for t in (elig.GREEN, elig.YELLOW, elig.RED)},
                            clips=clips)
    return results


def _print(results):
    print(f"{'pos':5} {'n':>2} {'green':>5} {'yellow':>6} {'red':>3}   median sens@entry / reproj")
    for pos, r in results.items():
        cal = [c for c in r["clips"] if c.get("calibrated")]
        ms = np.median([c["sensitivity_entry"] for c in cal]) if cal else float("nan")
        mr = np.median([c["reproj_board_rmse"] for c in cal]) if cal else float("nan")
        t = r["tiers"]
        print(f"{pos:5} {r['n']:>2} {t[elig.GREEN]:>5} {t[elig.YELLOW]:>6} {t[elig.RED]:>3}   "
              f"sens={ms:.2f} b/px  reproj={mr:.2f} b")


def run_flat(root, use_video=False):
    """Score every `*.landmarks.json` directly under `root` (a flat cohort, not the POS_* layout) — the
    Phase-1 ball-return clips in `10-25 training videos/calib_landmarks/`. Defaults to calibration/eligibility
    only (no video): this is a GEOMETRY study of what the near vs far calibration supports; the per-shot
    ball-track gate is reported separately (`geometry`), not asserted. Returns {clip: result}."""
    results = {}
    for jp in sorted(glob.glob(os.path.join(root, "*.landmarks.json"))):
        clip = os.path.basename(jp)[:-len(".landmarks.json")]
        video = os.path.join(root, f"{clip}.MOV")
        if not os.path.exists(video):
            video = os.path.join(root, f"{clip}.mov")
        results[clip] = score_clip(jp, video=video if (use_video and os.path.exists(video)) else None,
                                   out_prefix=os.path.join(root, clip))
    return results


def _fmt(v, spec="{:.2f}"):
    return spec.format(v) if isinstance(v, (int, float)) else "-"


def _print_flat(results):
    """Per-clip near vs far calibration + geometry tier — the partial-results picture for the cohort."""
    print(f"{'clip':10} {'geo':>3} {'far_calib':>9} {'sens@entry':>10} {'near_calib':>10} "
          f"{'near_reproj':>11} {'near_sens15':>11} {'deepestZ':>8}")
    tiers = {elig.GREEN: 0, elig.YELLOW: 0, elig.RED: 0}
    near_valid = 0
    for clip, r in results.items():
        geo = r.get("geometry", {})
        tier = geo.get("geometry_tier", elig.RED)
        tiers[tier] = tiers.get(tier, 0) + 1
        nc = r.get("near_calib", {}) or {}
        if nc.get("valid"):
            near_valid += 1
        far_ok = "ok" if (r.get("calibrated") and r["eligibility"]["checks"]["far_calib"]["pass"]) else "FAIL"
        print(f"{clip:10} {geo.get('emoji','?'):>3} {far_ok:>9} "
              f"{_fmt(r.get('sensitivity_entry')):>10} {('VALID' if nc.get('valid') else 'no'):>10} "
              f"{_fmt(nc.get('reproj_board_rmse')):>11} {_fmt(nc.get('sens_15ft')):>11} "
              f"{_fmt(nc.get('deepest_fiducial_z_ft'), '{:.0f}'):>8}")
    n = len(results)
    print(f"\n{n} clips: geometry tier 🟢 {tiers[elig.GREEN]}  🟡 {tiers[elig.YELLOW]}  🔴 {tiers[elig.RED]}")
    print(f"near-field calibration VALID on {near_valid}/{n} clips "
          f"(these support the 🟡 partial set: laydown, board@7/arrows, early speed, launch).")


if __name__ == "__main__":
    import sys
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    root = args[0]
    use_video = "--no-video" not in sys.argv
    if "--flat" in sys.argv:
        res = run_flat(root, use_video=("--video" in sys.argv))
        _print_flat(res)
        out = os.path.join(root, "phase2_nearfield_results.json")
    else:
        res = run(root, use_video=use_video)
        _print(res)
        out = os.path.join(root, "phase2_results.json")
    json.dump(res, open(out, "w"), indent=1, default=float)
    print(f"\nwrote {out}")
