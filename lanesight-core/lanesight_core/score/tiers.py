"""Tier evaluation (DEC-051). Evaluated at SESSION END only, so the badge never flickers mid-session.

- Promotion: session-end L >= the next tier's floor.
- Demotion (hysteresis): session-end L more than `points_below_floor` under the current tier's floor on
  `consecutive_sessions` sessions in a row (both owner-editable).
- First time reaching a tier -> promotion event with first_time=True (full-screen celebration + Status
  achievement, handled upstream). Regaining -> first_time=False (banner). Demotion -> quiet event.
Achievements never change the score or tier (DEC-039); this module reads score only.
"""
from __future__ import annotations

_ORDER = ['bronze', 'silver', 'gold', 'platinum', 'onyx']


def tier_for(score, params) -> str | None:
    if score is None:
        return None
    for name, (lo, hi) in params['tier_ranges'].items():
        if lo <= score <= hi:
            return name
    return _ORDER[-1] if score > params['tier_ranges']['onyx'][1] else _ORDER[0]


def _idx(tier):
    return _ORDER.index(tier) if tier in _ORDER else -1


def evaluate_tier(prev_state: dict | None, snapshot: dict, params) -> dict:
    """prev_state: {tier, best_score, first_qualified_score, below_floor_sessions} (None on first ever).
    snapshot: a SESSION-END score snapshot from ldev0.compute (needs 'eligible' + 'score').
    Returns {state, event, personal_best}. event is None when nothing changed."""
    prev = dict(prev_state or {})
    state = {
        'tier': prev.get('tier'),
        'best_score': prev.get('best_score'),
        'first_qualified_score': prev.get('first_qualified_score'),
        'below_floor_sessions': prev.get('below_floor_sessions', 0) or 0,
    }
    score = snapshot.get('score')
    if not snapshot.get('eligible') or score is None:
        return dict(state=state, event=None, personal_best=False)   # not eligible -> no tier movement

    if state['first_qualified_score'] is None:
        state['first_qualified_score'] = score
    personal_best = state['best_score'] is None or score > state['best_score']
    if personal_best:
        state['best_score'] = score

    hyst = params['tier_hysteresis']
    cur = state['tier']
    cur_i = _idx(cur)
    score_tier = tier_for(score, params)
    score_i = _idx(score_tier)
    event = None

    if cur is None or score_i > cur_i:
        # promotion (also the first qualified score -> first tier)
        best_prev_i = _idx(tier_for(prev.get('best_score'), params)) if prev.get('best_score') is not None else -1
        first_time = score_i > best_prev_i
        event = dict(kind='promotion', from_tier=cur, to_tier=score_tier, first_time=first_time, score=score)
        state['tier'] = score_tier
        state['below_floor_sessions'] = 0
    else:
        cur_floor = params['tier_ranges'][cur][0]
        if cur_floor - score > hyst['points_below_floor']:
            state['below_floor_sessions'] += 1
            if state['below_floor_sessions'] >= hyst['consecutive_sessions']:
                event = dict(kind='demotion', from_tier=cur, to_tier=score_tier, first_time=False, score=score)
                state['tier'] = score_tier
                state['below_floor_sessions'] = 0
            # else: pending demotion, no event yet
        else:
            state['below_floor_sessions'] = 0   # recovered within the band

    return dict(state=state, event=event, personal_best=personal_best)
