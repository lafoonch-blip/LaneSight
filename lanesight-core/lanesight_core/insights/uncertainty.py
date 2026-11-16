"""DEC-094 §5/§6 — the uncertainty contract between measurement and coaching.

Each coaching adjustment declares the metrics it depends on and the quality bar each must meet. Before an
adjustment is shown, `gate()` checks every metric it needs against that bar using the shot's per-metric quality
(`status` / `uncertainty` / `confidence`, carried on `shot['_quality']`). If any metric falls short the
adjustment is suppressed and the shot card shows a plain-language reason. A predicted / estimated value is never
used for a move unless the adjustment explicitly approves estimates for that metric.

This is the single owner-editable table (user-hidden), the same pattern as the fundamentals rules. The bar is
keyed on the calibrated `status` (ok vs low_confidence / unavailable / *_estimate), which already encodes
"too uncertain to act on" via the confidence→status mapping (`models.shot.m`, min_conf 0.5). A NUMERIC per-metric
uncertainty threshold (e.g. arrows-board ±0.5 board) is supported by the gate but left unset in the table until
per-board uncertainty is calibrated in Phase-2 (DEC-094 step 2) — wiring a hard board threshold to today's
uncalibrated residual would suppress good shots. When a metric carries a real `uncertainty` (e.g. rev_rate), a
`max_uncertainty` in the table is enforced.

Degrades gracefully: a shot with no `_quality` map (older callers, unit tests that build a metrics dict directly)
is never suppressed — the contract only tightens behaviour when quality is present and says a metric is
unavailable / low-confidence / too uncertain.
"""
from __future__ import annotations

# status values safe to ACT ON for a precise board move / line advice.
MEASURED = frozenset({'ok'})
# statuses that additionally count when an adjustment approves estimates for a metric.
ESTIMATE_OK = frozenset({'ok', 'best_effort', 'calibrated_estimate'})

_LABELS = {
    'entry_board': 'entry board', 'entry_angle': 'entry angle', 'board_at_15ft': 'the arrows',
    'arrows_board': 'the arrows', 'breakpoint_board': 'the breakpoint', 'board_at_0ft': 'laydown',
    'ball_speed': 'ball speed', 'rev_rate': 'rev rate',
}

# adjustment type -> list of (metric, max_uncertainty | None, allow_estimate)
# max_uncertainty is in the metric's own unit; None = status-only check (the Phase-2-calibrated path).
# Keys are MEASUREMENT names (as emitted by the CV pipeline + carried on `_quality`): entry_board, arrows_board,
# entry_angle, …  — not the shot_view aliases (board_at_15ft / entry_angle_deg).
REQUIREMENTS: dict[str, list[tuple]] = {
    'move':       [('entry_board', None, False), ('arrows_board', None, False)],   # a feet/target board move
    'release':    [('entry_angle', None, False)],
    'speed':      [('entry_board', None, False)],
    'transition': [('entry_board', None, False)],
    # 'execution' (hit your mark first), 'none' (strike/repeat/no move) and 'pattern_note' depend on no far-lane
    # metric a bad read could corrupt, so they declare nothing and are never suppressed by this contract.
}


def _label(metric: str) -> str:
    return _LABELS.get(metric, metric.replace('_', ' '))


def metric_ok(shot: dict, metric: str, max_uncertainty=None, allow_estimate: bool = False) -> tuple[bool, str | None]:
    """(ok, reason). Degrades to ok when the shot carries no quality for this metric (older caller / test)."""
    q = (shot.get('_quality') or {}).get(metric)
    if not q:
        return True, None
    status = q.get('status')
    allowed = ESTIMATE_OK if allow_estimate else MEASURED
    if status and status not in allowed:
        if status == 'unavailable':
            return False, f"{_label(metric)} wasn't measured on this shot"
        return False, f"{_label(metric)} is {status.replace('_', ' ')} on this shot"
    u = q.get('uncertainty')
    if max_uncertainty is not None and u is not None and u > max_uncertainty:
        return False, f"{_label(metric)} is only accurate to ±{u:.1f} this shot (a move needs ±{max_uncertainty})"
    return True, None


def gate(rec: dict, shot: dict) -> tuple[bool, str | None]:
    """(ok, reason) — does the shot meet every quality requirement this recommendation type declares?"""
    for metric, max_u, allow_est in REQUIREMENTS.get(rec.get('type'), []):
        ok, why = metric_ok(shot, metric, max_u, allow_est)
        if not ok:
            return False, why
    return True, None


def quality_map(measurements) -> dict:
    """{metric: {status, uncertainty, confidence}} from a list of Measurement objects — the contract's input,
    attached to the shot dict the insights layer sees. Additive; never changes a measured value."""
    return {m.metric: {'status': m.status, 'uncertainty': m.uncertainty, 'confidence': m.confidence}
            for m in measurements}
