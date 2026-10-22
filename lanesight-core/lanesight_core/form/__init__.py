"""Form analysis (P1) — contract + pose backend + advisory spot check + capture-view classifier.

`analyze_form_clip` returns every P1 metric as `unavailable` with a reason unless a pose backend is supplied
(DEC-026, no fabricated pose numbers). The rear/bowler-side backend lives in `pose.py`:

    from lanesight_core.form import build_pose_backend, analyze_form_clip
    rec = analyze_form_clip(video, pose_backend=build_pose_backend())

It needs the MediaPipe "form" extra and the pose model (see pose.POSE_MODEL_PATH); importing this package does
NOT import MediaPipe (it is loaded lazily on first backend call), so the contract + pure decision logic (view
classifier, spot-check tips) stay dependency-light.
"""
from .analyze import FORM_VERSION, FORM_P1, VIEWS, analyze_form_clip, classify_view
from .spotcheck import spot_check
from .pose import build_backend as build_pose_backend, POSE_BACKEND_VERSION

__all__ = ['FORM_VERSION', 'FORM_P1', 'VIEWS', 'analyze_form_clip', 'classify_view', 'spot_check',
           'build_pose_backend', 'POSE_BACKEND_VERSION']
