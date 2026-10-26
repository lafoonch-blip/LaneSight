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
from .solve import homography_from_landmarks, interval_consistency, CalibrationError
from .ablation import reconstruct_from_homography
from . import eligibility as elig


def score_calibration(landmark_set):
    """Solve + diagnose from verified anchors. Returns (H_iw, diag, interval_checks) or (None, None, reason)."""
    try:
        H_iw, _, diag = homography_from_landmarks(landmark_set)
    except CalibrationError as e:
        return None, None, str(e)
    return H_iw, diag, interval_consistency(H_iw, landmark_set)


def score_clip(landmarks_path, centers=None, video=None, out_prefix=None, handed="R"):
    """Score one clip: calibration + (optional) reconstruction/coverage + eligibility tier.

    centers: optional [(t,cx,cy)] auto track (stabilized-frame px). If `video` is given and centers is None,
    runs pipeline.analyze to get them (slow). Returns a result dict."""
    ls = LandmarkSet.from_json(landmarks_path)
    clip = ls.clip_id
    H_iw, diag, checks = score_calibration(ls)
    if H_iw is None:
        return dict(clip=clip, calibrated=False, reason=checks,
                    eligibility=elig.classify(diag=None))

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
    tier = elig.classify(diag=diag, interval_checks=checks, coverage=coverage, far_ball_px=far_ball)
    return dict(clip=clip, calibrated=True,
                reproj_board_rmse=round(diag["reproj_board_rmse"], 3),
                longitudinal_zones=diag["longitudinal_zones"],
                sensitivity_entry=diag["sensitivity_per_px"]["entry_59ft"]["d_board_per_px"],
                arrows_within=f"{sum(c['within'] for c in checks if c['name'].startswith('arrow_'))}/"
                              f"{sum(1 for c in checks if c['name'].startswith('arrow_'))}",
                entry_board=(recon or {}).get("entry_board"),
                coverage=coverage, eligibility=tier)


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


if __name__ == "__main__":
    import sys
    root = sys.argv[1]
    res = run(root, use_video=("--no-video" not in sys.argv))
    _print(res)
    out = os.path.join(root, "phase2_results.json")
    json.dump(res, open(out, "w"), indent=1, default=float)
    print(f"\nwrote {out}")
