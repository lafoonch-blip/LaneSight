"""Phase-1 geometry-proof harness (DEC-062).

Additive, OFF the production path: nothing here is imported by `cv.pipeline.analyze`. The purpose is to
prove whether *correct lane geometry alone* makes the failing training clips physically measurable, before
any ML investment (the A/B/C/D ablation in `03_ENGINEERING/CV_REARCHITECTURE_RESPONSE_2026-10-25.md`).

- `lane_geometry`  canonical, cited lane/board/arrow/pin-spot template (no magic constants in algorithms)
- `landmarks`      schema for hand-labeled image landmarks + an overlay renderer + an unlabeled template
- `solve`          point(+line) homography from labeled landmarks + calibration diagnostics
- `ablation`       the A/B/C runner that reconstructs board(Z)/entry from a given homography + ball centers
"""
from .lane_geometry import LaneGeometry, CANONICAL
from .landmarks import LandmarkSet, LandmarkObservation
from .solve import homography_from_landmarks, calibration_diagnostics

# autofill / resolution import cv.lanes (heavy) lazily inside their functions; expose the entry points.
from .autofill import autofill
from .resolution import far_lane_ball_resolution, SCALE_INVARIANT

__all__ = [
    "LaneGeometry", "CANONICAL",
    "LandmarkSet", "LandmarkObservation",
    "homography_from_landmarks", "calibration_diagnostics",
    "autofill", "far_lane_ball_resolution", "SCALE_INVARIANT",
]
