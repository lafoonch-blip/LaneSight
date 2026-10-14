"""Next-shot recommendations: strike-ball moves (feet/target, speed, ball) and lane transition.
Moves follow the widely taught 'move toward your miss' rule with a 2-and-1 ratio (feet:target) for
angle changes and parallel moves for pure line shifts. Magnitudes are capped and rounded to whole boards."""
from __future__ import annotations
from statistics import mean
from .rules import RULES_VERSION, POCKET_RH
from .reading import read_hit, read_leave, execution_check, classify_shot

def _rec(kind, reason, evidence, confidence, **kw):
    return dict(type=kind, reason=reason, evidence=evidence, confidence=confidence, rules_version=RULES_VERSION, **kw)

def strike_adjustment(shot: dict, handed='R', intent=None, user_said=None, history=None, pattern=None):
    """shot: metrics dict (entry_board, entry_angle_deg, arrows/breakpoint boards, speed_mph, pins_standing).
    history: list of earlier shot dicts in this session (same lane/ball) for transition evidence."""
    hit = read_hit(shot.get('entry_board'), shot.get('entry_angle_deg'), handed)
    leave = read_leave(shot.get('pins_standing'), handed, shot.get('pins_uncertain'))
    actual = dict(arrows_board=shot.get('board_at_15ft'), breakpoint_board=shot.get('breakpoint_board'),
                  laydown_board=shot.get('board_at_0ft'))
    ex = execution_check(intent, actual)
    cls = classify_shot(hit, ex, user_said)
    recs = []
    left, right = ('left', 'right') if handed == 'R' else ('right', 'left')
    if cls == 'LOW_CONFIDENCE':
        recs.append(_rec('none', 'Not enough reliable measurement to recommend a move.', {}, 'low'))
    elif cls == 'EXECUTION_MISS':
        k, v = max(ex['off'].items(), key=lambda kv: abs(kv[1]))
        where = {'laydown_board': 'laydown', 'arrows_board': 'the arrows', 'breakpoint_board': 'the breakpoint'}[k]
        recs.append(_rec('execution', f"Missed your target by {abs(v):.1f} boards at {where}. Repeat the same line and hit your mark before moving.",
                         dict(intent=intent, actual=actual), 'high', move_feet=0, move_target=0))
    elif leave.get('leave') == 'X' and hit['hit'] != 'brooklyn':
        note = '' if hit['hit'] == 'pocket' else (f" You carried it {abs(hit['boards_from_pocket']):.1f} boards "
               f"{'high' if hit['hit'] == 'high' else 'light'}; if it starts leaving "
               f"{'4/7 pins or splits' if hit['hit'] == 'high' else '10/6-10 pins'}, move {left if hit['hit'] == 'high' else right} 2 and 1.")
        recs.append(_rec('none', f"Strike. No adjustment: repeat the shot.{note}", dict(entry_board=shot.get('entry_board')),
                         'high' if hit['hit'] == 'pocket' else 'medium', watch=hit['hit'] if hit['hit'] != 'pocket' else None))
    else:
        d = hit.get('boards_from_pocket', 0.0)
        if hit['hit'] in ('high', 'brooklyn'):
            n = min(4, max(1, round(abs(d) / 1.5)))
            recs.append(_rec('move', f"{hit['reason']} Move {left}: feet {2 * n}, target {n} (2-and-1).",
                             dict(entry_board=shot.get('entry_board'), boards_from_pocket=d, leave=leave.get('leave')),
                             'medium' if cls == 'REACTION_CHANGE' else 'low', direction=left, move_feet=2 * n, move_target=n,
                             note=None if cls != 'NO_INTENT' else 'Set your target line to separate a missed shot from a lane change.'))
        elif hit['hit'] == 'light':
            n = min(4, max(1, round(abs(d) / 1.5)))
            recs.append(_rec('move', f"{hit['reason']} Move {right}: feet {2 * n}, target {n} (2-and-1).",
                             dict(entry_board=shot.get('entry_board'), boards_from_pocket=d, leave=leave.get('leave')),
                             'medium' if cls == 'REACTION_CHANGE' else 'low', direction=right, move_feet=2 * n, move_target=n,
                             note=None if cls != 'NO_INTENT' else 'Set your target line to separate a missed shot from a lane change.'))
        else:   # pocket
            if leave.get('read') == 'light':
                recs.append(_rec('move', f"{hit['reason']} {leave.get('reason', '')} Move toward the miss: {right}, feet 2 and target 1.",
                                 dict(entry_board=shot.get('entry_board'), leave=leave.get('leave')), 'low',
                                 direction=right, move_feet=2, move_target=1))
            elif leave.get('read') in ('weak_or_light', 'weak', 'slightly_light') or hit.get('angle') == 'flat':
                recs.append(_rec('release', f"{hit['reason']} {leave.get('reason', '')} Keep the line; get more entry angle and drive: "
                                 "a touch less speed or a stronger release.".strip(),
                                 dict(entry_angle=shot.get('entry_angle_deg'), leave=leave.get('leave')), 'low', speed='slightly slower'))
            elif leave.get('read') in ('high', 'slightly_high'):
                recs.append(_rec('speed', f"{hit['reason']} {leave.get('reason', '')} Good line; a touch more speed or a firmer release usually carries this.",
                                 dict(leave=leave.get('leave')), 'low', speed='slightly faster'))
            else:
                recs.append(_rec('none', f"{hit['reason']} Pocket hit with an unlucky leave ({leave.get('leave')}). Repeat the shot.", {}, 'medium'))
    tr = transition(history or [], shot, handed)
    if tr: recs.append(tr)
    if pattern and pattern.get('length_ft') and shot.get('breakpoint_board') is not None:
        exp = pattern['length_ft'] - 31
        recs.append(_rec('pattern_note', f"On a {pattern['length_ft']} ft pattern the usual exit point is around board {exp:.0f}; "
                         f"your breakpoint was board {shot['breakpoint_board']:.1f}.", dict(rule='length − 31'), 'low'))
    return dict(hit=hit, leave=leave, execution=ex, classification=cls, recommendations=recs)

def transition(history, shot, handed='R', min_shots=3, drift_boards=1.0):
    """lane transition from comparable well-executed shots: breakpoint/entry drifting over time with the same line"""
    good = [h for h in history if h.get('classification') in ('EXECUTED', 'REACTION_CHANGE', 'NO_INTENT') and h.get('entry_board') is not None]
    if len(good) < min_shots: return None
    first, last = good[:max(1, len(good) // 2)], good[-max(1, len(good) // 2):] + [shot]
    d_entry = mean(s['entry_board'] for s in last if s.get('entry_board') is not None) - mean(s['entry_board'] for s in first)
    if handed != 'R': d_entry = -d_entry
    if abs(d_entry) < drift_boards: return None
    left, right = ('left', 'right') if handed == 'R' else ('right', 'left')
    if d_entry > 0:
        return _rec('transition', f"Over the last {len(good) + 1} comparable shots the ball is finishing {d_entry:.1f} boards higher: "
                    f"the lane is hooking earlier. Move {left} (feet 2, target 1) or switch to a weaker ball.",
                    dict(n=len(good) + 1, entry_drift=round(d_entry, 1)), 'medium', direction=left, move_feet=2, move_target=1)
    return _rec('transition', f"Over the last {len(good) + 1} comparable shots the ball is finishing {abs(d_entry):.1f} boards lighter: "
                f"the ball is reading the lane later. Move {right} (feet 2, target 1) or use a stronger ball.",
                dict(n=len(good) + 1, entry_drift=round(d_entry, 1)), 'medium', direction=right, move_feet=2, move_target=1)
