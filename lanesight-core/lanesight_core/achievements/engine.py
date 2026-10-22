"""Achievement rule-type evaluators (SCORE_TIERS §5).

Each evaluator is pure: (params, context) -> progress dict with:
  status: 'locked' | 'in_progress' | 'not_trackable' | 'unlocked'
  current_value, target_value, best_value, qualifying_count, sample_count, unavailable_reason, unlocked
The caller supplies already-aggregated context (counts, windows, streak state) and persists the result.
"""
from __future__ import annotations
import numpy as np

ACHIEVEMENT_VERSION = 'achievements-0.1.0'
RULE_TYPES = ('one_time', 'cumulative', 'count_qualifying', 'window_ratio', 'window_spread',
              'best_measured', 'streak', 'weekly_streak', 'baseline_delta', 'first_tier')


def _p(status, unlocked=False, **kw):
    return dict(status=status, unlocked=unlocked, **kw)


def update_streak(prev: dict | None, attempt: dict) -> dict:
    """Advance a streak (SCORE_TIERS §5 streak rule). attempt: {qualifies, is_real_attempt, analyzable}.
    An unanalyzable shot is SKIPPED (streak untouched, logged). A real analyzable attempt that doesn't
    qualify BREAKS the streak. Returns {live, best, skipped}."""
    st = dict(live=(prev or {}).get('live', 0), best=(prev or {}).get('best', 0),
              skipped=(prev or {}).get('skipped', 0))
    if not attempt.get('analyzable', True):
        st['skipped'] += 1
        return st
    if attempt.get('qualifies'):
        st['live'] += 1
        st['best'] = max(st['best'], st['live'])
    elif attempt.get('is_real_attempt', True):
        st['live'] = 0
    # a non-real, analyzable attempt (e.g. no intent) leaves the streak unchanged
    return st


def _one_time(params, ctx):
    met = bool(ctx.get('condition_met'))
    return _p('unlocked' if met else 'locked', unlocked=met, current_value=int(met), target_value=1)


def _cumulative(params, ctx):
    n, target = ctx.get('count', 0), params['target']
    return _p('unlocked' if n >= target else 'in_progress', unlocked=n >= target,
              current_value=n, target_value=target)


def _count_qualifying(params, ctx):
    n, target = ctx.get('qualifying_count', 0), params['target']
    return _p('unlocked' if n >= target else 'in_progress', unlocked=n >= target,
              current_value=n, target_value=target, qualifying_count=n)


def _window_ratio(params, ctx):
    window = ctx.get('window') or []           # list of bools (qualifying) over the comparable window
    min_sample, target = params.get('min_sample', 30), params['target_ratio']
    if len(window) < min_sample:
        return _p('not_trackable', unavailable_reason=f'{len(window)}/{min_sample} qualifying shots',
                  sample_count=len(window), target_value=target)
    ratio = float(np.mean(window))
    return _p('unlocked' if ratio >= target else 'in_progress', unlocked=ratio >= target,
              current_value=round(ratio, 3), target_value=target, sample_count=len(window))


def _window_spread(params, ctx):
    vals = [v for v in (ctx.get('values') or []) if v is not None]
    min_sample = params.get('min_sample', 30)
    if len(vals) < min_sample:
        return _p('not_trackable', unavailable_reason=f'{len(vals)}/{min_sample} comparable shots',
                  sample_count=len(vals))
    a = np.asarray(vals, float)
    if params.get('spread_kind') == 'cv':
        spread = float(np.std(a) / np.mean(a)) if np.mean(a) else None
        limit = params['max_cv']
    else:
        spread = float(np.std(a)); limit = params['max_sd']
    if spread is None:
        return _p('not_trackable', unavailable_reason='mean is zero', sample_count=len(vals))
    return _p('unlocked' if spread <= limit else 'in_progress', unlocked=spread <= limit,
              current_value=round(spread, 4), target_value=limit, sample_count=len(vals))


def _best_measured(params, ctx):
    best, unc = ctx.get('best_value'), ctx.get('uncertainty', 0.0) or 0.0
    thr, direction = params['threshold'], params.get('direction', 'above')
    if best is None:
        return _p('not_trackable', unavailable_reason='no measured value yet', target_value=thr)
    cleared = (best - unc >= thr) if direction == 'above' else (best + unc <= thr)
    return _p('unlocked' if cleared else 'in_progress', unlocked=cleared,
              current_value=best, best_value=best, target_value=thr)


def _streak(params, ctx):
    best = ctx.get('best', 0); live = ctx.get('live', 0); target = params['target']
    return _p('unlocked' if best >= target else 'in_progress', unlocked=best >= target,
              current_value=live, best_value=best, target_value=target)


def _weekly_streak(params, ctx):
    weeks, target = ctx.get('consecutive_weeks', 0), params['target_weeks']
    return _p('unlocked' if weeks >= target else 'in_progress', unlocked=weeks >= target,
              current_value=weeks, target_value=target)


def _baseline_delta(params, ctx):
    cur, base, delta = ctx.get('current'), ctx.get('baseline'), params['delta']
    if cur is None or base is None:
        return _p('not_trackable', unavailable_reason='no qualified baseline score yet', target_value=delta)
    gained = cur - base
    return _p('unlocked' if gained >= delta else 'in_progress', unlocked=gained >= delta,
              current_value=round(gained, 1), target_value=delta)


def _first_tier(params, ctx):
    reached = bool(ctx.get('reached'))
    return _p('unlocked' if reached else 'locked', unlocked=reached,
              current_value=ctx.get('tier'), target_value=params['tier'])


_EVALUATORS = {
    'one_time': _one_time, 'cumulative': _cumulative, 'count_qualifying': _count_qualifying,
    'window_ratio': _window_ratio, 'window_spread': _window_spread, 'best_measured': _best_measured,
    'streak': _streak, 'weekly_streak': _weekly_streak, 'baseline_delta': _baseline_delta,
    'first_tier': _first_tier,
}


def evaluate(definition: dict, ctx: dict) -> dict:
    """definition: {id, rule_type, params, ...}. Returns the progress record for (user, achievement, level).
    Raises ValueError on an unknown rule_type so a bad definition fails loudly, not silently."""
    rt = definition.get('rule_type')
    if rt not in _EVALUATORS:
        raise ValueError(f'unknown rule_type: {rt!r}')
    out = _EVALUATORS[rt](definition.get('params', {}), ctx or {})
    out['achievement_id'] = definition.get('id')
    out['rule_type'] = rt
    return out
