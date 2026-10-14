"""Shot reading: pocket position, entry quality, leave diagnosis, execution vs intent."""
from __future__ import annotations
from .rules import POCKET_RH, POCKET_WINDOW, BROOKLYN_RH, GOOD_ENTRY_DEG, LEAVE_READS_RH, mirror_board
from ..scoring.pins import leave_key, mirror, classify_leave

def _rh(board, handed): return board if handed == 'R' else mirror_board(board)

def read_hit(entry_board, entry_angle=None, handed='R'):
    if entry_board is None: return dict(hit='unknown', reason='Entry board unavailable.')
    e = _rh(entry_board, handed); d = e - POCKET_RH
    if e >= BROOKLYN_RH - 1.0: hit = 'brooklyn'
    elif d > POCKET_WINDOW: hit = 'high'
    elif d < -POCKET_WINDOW: hit = 'light'
    else: hit = 'pocket'
    out = dict(hit=hit, boards_from_pocket=round(d, 1))
    if entry_angle is not None:
        out['angle'] = 'flat' if entry_angle < GOOD_ENTRY_DEG[0] else ('strong' if entry_angle > GOOD_ENTRY_DEG[1] else 'good')
    side = {'high': 'left of', 'light': 'right of', 'brooklyn': 'across to the 1-2 side of', 'pocket': 'in'}
    if handed != 'R': side.update(high='right of', light='left of')
    out['reason'] = (f"Entered on board {entry_board:.1f}, {abs(d):.1f} boards {side[hit]} the pocket" if hit != 'pocket'
                     else f"Entered on board {entry_board:.1f}, in the pocket") + \
                    (f" at {entry_angle:.1f}° ({out['angle']} angle)." if entry_angle is not None else '.')
    return out

def read_leave(standing, handed='R', uncertain=None):
    if standing is None: return dict(leave='unknown')
    if not standing: return dict(leave='X', type='strike', read='strike')
    s = set(standing) if handed == 'R' else mirror(standing)
    key_rh = leave_key(s); r = LEAVE_READS_RH.get(key_rh)
    out = dict(leave=leave_key(standing), type=classify_leave(standing))
    if uncertain: out['hidden'] = sorted(uncertain); out['note'] = f"pin(s) {leave_key(uncertain)} may also be standing (hidden from a rear view)"
    if r: out.update(read=r[0], reason=r[1] if handed == 'R' else r[1] + ' (mirrored for a left-hander)')
    return out

def execution_check(intent: dict | None, actual: dict, tol=1.5):
    """intent/actual: {'arrows_board', 'breakpoint_board', 'laydown_board'}. Returns per-checkpoint misses."""
    if not intent: return dict(status='no_intent')
    miss = {}
    for k in ('laydown_board', 'arrows_board', 'breakpoint_board'):
        if intent.get(k) is not None and actual.get(k) is not None:
            miss[k] = round(actual[k] - intent[k], 1)
    if not miss: return dict(status='no_intent')
    big = {k: v for k, v in miss.items() if abs(v) > tol}
    return dict(status='missed' if big else 'hit', misses=miss, off=big)

def classify_shot(hit, execution, user_said=None):
    """EXECUTED / EXECUTION_MISS / REACTION_CHANGE / MIXED / LOW_CONFIDENCE (Master Context §11)"""
    if hit.get('hit') == 'unknown': return 'LOW_CONFIDENCE'
    ex = execution.get('status')
    if user_said == 'no': ex = 'missed'
    if ex == 'missed':
        early_ok = all(abs(execution['misses'].get(k, 0)) <= 1.5 for k in ('laydown_board', 'arrows_board'))
        return 'MIXED' if (early_ok and hit['hit'] != 'pocket') else 'EXECUTION_MISS'
    if ex == 'hit' and hit['hit'] != 'pocket': return 'REACTION_CHANGE'
    if ex == 'hit': return 'EXECUTED'
    return 'EXECUTED' if hit['hit'] == 'pocket' else 'NO_INTENT'      # can't separate execution from reaction
