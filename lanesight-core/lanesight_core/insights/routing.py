"""Target-vs-actual and execution routing (DEC-049, DEC-005/006).

Shot card draws the intended line (feet -> arrows -> breakpoint, entered on the capture screen) against
the actual line (laydown -> arrows -> breakpoint -> entry) and reports the miss at each point plus the
execution class. The "Did you hit your mark?" prompt is gone — the target is known, so we never pass
user_said. When a shot is an execution miss AND a form finding explains the direction, route it to the
Execution Coach: a form cue, never a lane move (DEC-005/006).
"""
from __future__ import annotations
from .reading import read_hit, execution_check, classify_shot
from .rules import RULES_VERSION


def _mk(engine, type_, reason, confidence, **kw):
    return dict(engine=engine, type=type_, reason=reason, confidence=confidence,
                rules_version=RULES_VERSION, **kw)


def target_vs_actual(intent: dict | None, actual: dict, handed: str = 'R') -> dict:
    """intent: {'feet_board','arrows_board','breakpoint_board'} (user). actual: measured boards/angle
    ('laydown_board','arrows_board','breakpoint_board','entry_board','entry_angle'). Returns the shot-card
    target/actual payload with per-point miss and the execution class. No 'hit your mark' prompt."""
    hit = read_hit(actual.get('entry_board'), actual.get('entry_angle'), handed)
    execution = execution_check(intent, actual)                 # misses at laydown/arrows/breakpoint
    classification = classify_shot(hit, execution)              # DEC-049: no user_said
    misses = {}
    if intent:
        for pt in ('arrows_board', 'breakpoint_board'):
            if intent.get(pt) is not None and actual.get(pt) is not None:
                misses[pt] = round(actual[pt] - intent[pt], 1)
    return dict(
        intended=None if not intent else {k: intent.get(k) for k in ('feet_board', 'arrows_board', 'breakpoint_board')},
        actual={k: actual.get(k) for k in ('laydown_board', 'arrows_board', 'breakpoint_board', 'entry_board', 'entry_angle')},
        misses=misses,
        execution=execution,
        hit=hit,
        classification=classification,
        on_target=(execution.get('status') == 'hit'),
        has_target=bool(intent),
    )


def route_recommendation(classification: str, lane_recs: list[dict] | None,
                         form_finding: dict | None = None) -> dict:
    """Decide what the shot card recommends.
    - EXECUTION_MISS + a form finding that explains the miss -> the form cue only (no lane move).
    - otherwise -> the top lane recommendation as primary + the next as a secondary option.
    Returns {primary, secondary, routed_to}. Never emits a lane move for an execution miss that form explains."""
    recs = [r for r in (lane_recs or []) if r.get('type') != 'none']
    if classification == 'EXECUTION_MISS' and form_finding and form_finding.get('explains_miss'):
        cue = _mk('form', 'execution', form_finding.get('reason', 'Execution miss — fix the delivery, not the line.'),
                  form_finding.get('confidence', 'medium'),
                  cue=form_finding.get('cue'), drill_ref=form_finding.get('drill_ref'),
                  rule_id=form_finding.get('rule_id'), rule_version=form_finding.get('rule_version'))
        return dict(primary=cue, secondary=None, routed_to='form')
    moves = [r for r in recs if r.get('type') in ('move', 'speed', 'release', 'pattern_note', 'transition')]
    primary = moves[0] if moves else (recs[0] if recs else None)
    secondary = next((r for r in moves if r is not primary), None)
    return dict(primary=primary, secondary=secondary, routed_to='lane' if primary else 'none')
