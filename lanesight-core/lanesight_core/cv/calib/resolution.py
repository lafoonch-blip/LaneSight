"""Far-lane observability check (Shayne's additional consideration): can the ball's board be recovered to
+/-1 board near the pins? If not, no calibration helps — the answer is a capture-position recommendation
(handoff §13). Geometry-only; reads the detected lane from a stab plate.

THE RIGOROUS RESULT (scale-invariant, clip-independent). Ball diameter and board width both scale with
pixels-per-foot, so the LATERAL board error from centroiding a ball image is independent of camera distance:

    board_err ≈ k_centroid · D_px / px_per_board
              = k_centroid · (BALL_IN/LANE_IN · W_px) / (W_px / BOARDS)
              = k_centroid · (BALL_IN/LANE_IN) · BOARDS          (W_px cancels)
              = k_centroid · (8.59/41.5) · 39 ≈ k_centroid · 8.07 boards

A clean, sharp, well-segmented blob centroids to ~10-12% of its diameter (k≈0.12) → ~0.97 board. A blurred /
small / partially-occluded ball (the back half of these clips) is ~30% (k≈0.30) → ~2.4 boards. So **±1 board
at the pins is only achievable with a sharp, cleanly-segmented far ball AND valid far-lane calibration**; under
realistic back-half blur it is not. Pixel scale does NOT rescue this — it only governs whether the ball is big
enough to DETECT at all (a few px → invisible, and sub-pixel centroiding of a 3px blob is hopeless).

The per-clip numbers below are pixel-scale CONTEXT at the near (foul) and far end of the *detected* lane
region. NOTE: on foreshortened/elevated clips the detected region often stops short of the pin deck, so the
far-detected row is NOT the pins and its ball size is an OVER-estimate of the true pin-area ball — we label it
as such and never claim per-clip resolvability from it.
"""
from __future__ import annotations
import pickle
import numpy as np

from ..track import exp_diam, BALL_IN, LANE_IN
from .lane_geometry import BOARDS

K_CENTROID_CLEAN = 0.12
K_CENTROID_BLUR = 0.30
DETECT_MIN_D_PX = 6.0

# scale-invariant lateral board error (independent of clip / pixel scale)
BOARD_ERR_CLEAN = round(K_CENTROID_CLEAN * (BALL_IN / LANE_IN) * BOARDS, 2)   # ≈ 0.97
BOARD_ERR_BLUR = round(K_CENTROID_BLUR * (BALL_IN / LANE_IN) * BOARDS, 2)     # ≈ 2.42
SCALE_INVARIANT = dict(board_err_clean=BOARD_ERR_CLEAN, board_err_blur=BOARD_ERR_BLUR,
                       pm1_board_feasible_only_if="sharp, cleanly-segmented far ball + valid far calibration",
                       note="lateral board error is scale-invariant; pixel size governs detectability only")


def _row_metrics(lane, y):
    from ..lanes import lane_x
    xa, xb = lane_x(lane, y)
    w_px = float(xb - xa)
    return dict(row=round(float(y), 1), lane_width_px=round(w_px, 1),
                ball_diam_px=round(float(exp_diam(lane, y)), 2),
                px_per_board=round(w_px / BOARDS, 3) if w_px > 0 else 0.0)


def far_lane_ball_resolution(stab_path: str, log=print) -> dict:
    """Per-clip pixel-scale CONTEXT + the scale-invariant verdict. Returns an error reason on a failing clip."""
    from ..lanes import find_lanes, foul_corners
    S = pickle.load(open(stab_path, "rb"))
    bg = S["bg"]
    try:
        G = find_lanes(bg, log=lambda *a, **k: None)
    except Exception as e:
        return dict(ok=False, error=str(e), scale_invariant=SCALE_INVARIANT)
    best, best_w = None, -1
    for l in G["lanes"]:
        try:
            fw = abs(foul_corners(l)[1][0] - foul_corners(l)[0][0])
        except Exception:
            continue
        if fw > best_w:
            best, best_w = l, fw
    if best is None:
        return dict(ok=False, error="no usable lane", scale_invariant=SCALE_INVARIANT)
    lane = best
    y_near, y_far = float(lane["y_rng"][1]), float(lane["y_rng"][0])
    near = _row_metrics(lane, y_near)
    far_detected = _row_metrics(lane, y_far)
    # honest detectability note at the far end of the DETECTED region (an over-estimate vs the true pins)
    d_far_detected = far_detected["ball_diam_px"]
    out = dict(ok=True,
               scale_invariant=SCALE_INVARIANT,
               context=dict(near_foul=near, far_detected_region=far_detected,
                            caveat="far_detected_region is the end of the DETECTED lane, NOT verified as the "
                                   "pin deck; on foreshortened clips the true pin-area ball is smaller."),
               far_detected_ball_px=d_far_detected,
               far_detected_detectable=bool(d_far_detected >= DETECT_MIN_D_PX),
               verdict=("±1 board at the pins requires a sharp, cleanly-segmented far ball + valid far "
                        "calibration (clean ≈ %.2f board; blur ≈ %.2f board). Pixel scale affects only "
                        "whether the ball is detectable at all." % (BOARD_ERR_CLEAN, BOARD_ERR_BLUR)))
    log(f"far-lane: detected-region D={d_far_detected:.1f}px; scale-invariant board err "
        f"{BOARD_ERR_CLEAN}..{BOARD_ERR_BLUR}")
    return out


if __name__ == "__main__":
    import sys, json
    print(json.dumps(far_lane_ball_resolution(sys.argv[1]), indent=1))
