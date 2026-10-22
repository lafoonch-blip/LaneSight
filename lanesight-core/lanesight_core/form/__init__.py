"""Form analysis (P1) — contract + advisory spot check + capture-view classifier (DEC-047/045/049).

IMPORTANT: the Form P1 *metric values* are not implemented. They require pose estimation of the bowler,
which needs (a) a pose-estimation backend (not in deps — numpy/opencv only) and (b) the real approach
clips for validation. Until both exist, analyze_form_clip returns every P1 metric as `unavailable` with a
reason (no fabricated pose numbers, DEC-026). This module ships the contract + the pure decision logic
(view classifier, spot-check tips) so the API/app integrate the real shape now and the backend drops in later.
"""
from .analyze import FORM_VERSION, FORM_P1, VIEWS, analyze_form_clip, classify_view
from .spotcheck import spot_check

__all__ = ['FORM_VERSION', 'FORM_P1', 'VIEWS', 'analyze_form_clip', 'classify_view', 'spot_check']
