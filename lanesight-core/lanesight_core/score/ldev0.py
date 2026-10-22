"""L-dev-0 — dev/Beta LaneSight Score (DEC-048). No pinfall.

L = round(10 * (0.40*S' + 0.25*A + 0.25*C + 0.10*P')), each component 0-100.
  S' performance  = 0.6*pocket% + 0.4*angle%   (entry board in the pocket range; entry angle in range)
  A  accuracy     = DEC-031 (execution vs intent at the arrows and the breakpoint)
  C  consistency  = DEC-032 (robust spread of speed / rev / arrows / breakpoint vs targets)
  P' power        = normalized entry speed / rev / entry angle / weight vs OWNER-EDITABLE reference ranges

No fabricated numbers: a component with too little data, or P' with no reference ranges configured, is
returned unavailable and the overall score stays "building" (all four parts are required, DEC-048). The
DEC-048 weights are never silently rebalanced. Params default to the values seeded in migration 007
(score_formula_version 'L-dev-0'); the runner passes the live row so the owner can edit them.
"""
from __future__ import annotations
import numpy as np

SCORE_VERSION = 'L-dev-0'

# Mirror of the migration-007 seed. power_ref_ranges is None on purpose — PENDING Shayne (HANDOFF §7);
# until it is set, P' (and therefore the overall score) is unavailable rather than guessed.
DEFAULT_LDEV0_PARAMS = {
    'weights': {'s_perf': 0.40, 'a_acc': 0.25, 'c_cons': 0.25, 'p_power': 0.10},
    's_perf': {'pocket_weight': 0.6, 'angle_weight': 0.4,
               'pocket_board_range': [16, 19], 'pocket_board_range_left_mirror': True,
               'entry_angle_range_deg': [4, 6]},
    'power_ref_ranges': None,   # {'entry_speed_mph':[lo,hi], 'rev_rate_rpm':[lo,hi], 'entry_angle_deg':[lo,hi], 'weight_lb':[lo,hi]}
    'eligibility_floors': {'s_perf': 20, 'a_acc': 20, 'c_cons': 10, 'p_power': 10},
    'window_days': 90,
    'tier_ranges': {'bronze': [0, 399], 'silver': [400, 549], 'gold': [550, 699],
                    'platinum': [700, 849], 'onyx': [850, 1000]},
    'tier_hysteresis': {'points_below_floor': 15, 'consecutive_sessions': 2},
    'label': 'Beta · dev formula',
}

# DEC-031 / DEC-032 scales (provisional, validate before release).
_A_ARROW_SCALE, _A_BP_SCALE, _A_ARROW_W, _A_BP_W = 5.0, 8.0, 0.60, 0.40
_C_TARGETS = {'ball_speed': 0.5, 'rev_rate': 30.0, 'arrows_board': 1.0, 'breakpoint_board': 2.0}
_C_MIN_N = 5   # need at least this many comparable values to estimate a spread


def _val(shot, metric):
    """Measured value for a metric, or None unless it passed the confidence gate."""
    m = shot.get('metrics', {}).get(metric)
    if not m or m.get('value') is None or m.get('status') not in ('ok', 'calibrated_estimate'):
        return None
    return m['value']


def _vals(shots, metric):
    return [v for v in (_val(s, metric) for s in shots) if v is not None]


def _robust_sd(xs) -> float | None:
    a = np.asarray(xs, float)
    if a.size < _C_MIN_N:
        return None
    return float(1.4826 * np.median(np.abs(a - np.median(a))))


# --------------------------------------------------------------------------- Accuracy (DEC-031)
def _shot_accuracy(actual_arrows, actual_bp, int_arrows, int_bp):
    if actual_arrows is None or int_arrows is None:
        return None
    arrow_err = abs(actual_arrows - int_arrows)
    arrow_score = 100 * max(0.0, 1 - min(arrow_err / _A_ARROW_SCALE, 1))
    if actual_bp is not None and int_bp is not None:
        bp_err = abs(actual_bp - int_bp)
        bp_score = 100 * max(0.0, 1 - min(bp_err / _A_BP_SCALE, 1))
        a = _A_ARROW_W * arrow_score + _A_BP_W * bp_score
        on_target = arrow_err <= 1 and bp_err <= 2
    else:   # arrows only
        a = arrow_score
        on_target = arrow_err <= 1
    return dict(a=round(a), arrow_err=round(arrow_err, 1),
                bp_err=round(abs(actual_bp - int_bp), 1) if (actual_bp is not None and int_bp is not None) else None,
                on_target=on_target)


def accuracy(shots, intents) -> dict:
    """DEC-031. intents: {shot_id: {'arrows_board':.., 'breakpoint_board':..}}.
    Per-shot A over shots with an intended line set; component value = mean. No intent -> None (never 0)."""
    intents = intents or {}
    per = []
    for s in shots:
        intent = intents.get(s.get('shot_id'))
        if not intent:
            continue
        a = _shot_accuracy(_val(s, 'arrows_board'), _val(s, 'breakpoint_board'),
                           intent.get('arrows_board'), intent.get('breakpoint_board'))
        if a is not None:
            per.append(a)
    if not per:
        return dict(value=None, n=0, status='no_intent',
                    why='Set a target line on the capture screen to measure accuracy.')
    return dict(value=round(float(np.mean([p['a'] for p in per]))), n=len(per), status='ok',
                on_target_pct=round(100 * np.mean([p['on_target'] for p in per])), per_shot=per)


# --------------------------------------------------------------------------- Consistency (DEC-032)
def consistency(shots) -> dict:
    """DEC-032. Equal-weight mean of available component scores; a component with too little data (or rev
    whose capture band exceeds its target, DEC-028) is excluded, never counted as zero spread."""
    comps, excluded = {}, {}
    for metric, target in _C_TARGETS.items():
        vals = _vals(shots, metric)
        if metric == 'rev_rate':   # exclude rev when its reported uncertainty is wider than the target
            bands = [s['metrics']['rev_rate'].get('uncertainty') for s in shots
                     if _val(s, 'rev_rate') is not None]
            if bands and max(b for b in bands if b is not None) > target:
                excluded[metric] = f'capture band > {target:g} rpm (needs 120 fps)'
                continue
        sd = _robust_sd(vals)
        if sd is None:
            excluded[metric] = f'only {len(vals)} comparable shots (need {_C_MIN_N})'
            continue
        comps[metric] = round(100 * max(0.0, 1 - sd / (3 * target)))
    if not comps:
        return dict(value=None, n_components=0, status='building', components={}, excluded=excluded)
    return dict(value=round(float(np.mean(list(comps.values())))), n_components=len(comps),
                status='ok', components=comps, excluded=excluded)


# --------------------------------------------------------------------------- Performance S' (DEC-048)
def performance(shots, params=DEFAULT_LDEV0_PARAMS, handed='R') -> dict:
    """S' = 0.6*pocket% + 0.4*angle%. pocket% uses the (handedness-mirrored) pocket board range; angle%
    uses the entry-angle range. Only Measured shots count."""
    sp = params['s_perf']
    lo, hi = sp['pocket_board_range']
    alo, ahi = sp['entry_angle_range_deg']
    boards = _vals(shots, 'entry_board')
    angles = _vals(shots, 'entry_angle')

    def mirror(b):   # 1=right gutter .. 39=left gutter
        return b if handed == 'R' else (40 - b)
    pocket = [1 for b in boards if lo <= mirror(b) <= hi]
    in_angle = [1 for a in angles if alo <= a <= ahi]
    if not boards and not angles:
        return dict(value=None, status='building', n_board=0, n_angle=0,
                    why='No measured entry board or angle yet.')
    pocket_pct = (sum(pocket) / len(boards) * 100) if boards else None
    angle_pct = (sum(in_angle) / len(angles) * 100) if angles else None
    # each sub-part needs its own measured shots; if one is missing the component is still building
    if pocket_pct is None or angle_pct is None:
        return dict(value=None, status='building', n_board=len(boards), n_angle=len(angles),
                    pocket_pct=None if pocket_pct is None else round(pocket_pct),
                    angle_pct=None if angle_pct is None else round(angle_pct),
                    why='Need both entry board and entry angle measured.')
    value = sp['pocket_weight'] * pocket_pct + sp['angle_weight'] * angle_pct
    return dict(value=round(value), status='ok', n_board=len(boards), n_angle=len(angles),
                pocket_pct=round(pocket_pct), angle_pct=round(angle_pct))


# --------------------------------------------------------------------------- Power P' (DEC-048)
def _norm(x, lo, hi):
    return max(0.0, min(1.0, (x - lo) / (hi - lo))) if (x is not None and hi > lo) else None


def power_component(shots, params=DEFAULT_LDEV0_PARAMS, weight_lb=None) -> dict:
    """P' = mean of normalized entry speed / rev / entry angle / weight vs owner-editable reference ranges.
    Carry excluded. Returns unavailable (never a guess) until power_ref_ranges is configured (HANDOFF §7)."""
    ranges = params.get('power_ref_ranges')
    if not ranges:
        return dict(value=None, status='unavailable',
                    why='Power reference ranges are not configured yet (owner-set, HANDOFF §7).')
    parts = {}
    speed = _vals(shots, 'speed_late') or _vals(shots, 'ball_speed')
    if speed and 'entry_speed_mph' in ranges:
        parts['entry_speed'] = _norm(float(np.mean(speed)), *ranges['entry_speed_mph'])
    revs = _vals(shots, 'rev_rate')
    if revs and 'rev_rate_rpm' in ranges:
        parts['rev_rate'] = _norm(float(np.mean(revs)), *ranges['rev_rate_rpm'])
    angles = _vals(shots, 'entry_angle')
    if angles and 'entry_angle_deg' in ranges:
        parts['entry_angle'] = _norm(float(np.mean(angles)), *ranges['entry_angle_deg'])
    if weight_lb is not None and 'weight_lb' in ranges:
        parts['weight'] = _norm(weight_lb, *ranges['weight_lb'])
    parts = {k: v for k, v in parts.items() if v is not None}
    if not parts:
        return dict(value=None, status='building', components={}, why='No measured power inputs yet.')
    return dict(value=round(100 * float(np.mean(list(parts.values())))), status='ok',
                components={k: round(v, 3) for k, v in parts.items()})


# --------------------------------------------------------------------------- Composite L-dev-0
def compute(shots, intents=None, params=None, handed='R', weight_lb=None, shot_ids=None) -> dict:
    """Compute L-dev-0 over the given (already 90-day-windowed) shots.
    Returns a snapshot dict matching the score_snapshot columns: score/s_perf/a_acc/c_cons/p_power/
    eligibility/inputs/tier/eligible. Score is None (eligible False) until every part meets its floor
    AND is computable; weights are never rebalanced to fill a gap."""
    params = params or DEFAULT_LDEV0_PARAMS
    floors = params['eligibility_floors']
    S = performance(shots, params, handed)
    A = accuracy(shots, intents)
    C = consistency(shots)
    P = power_component(shots, params, weight_lb)

    counts = {'s_perf': min(S.get('n_board', 0), S.get('n_angle', 0)),
              'a_acc': A.get('n', 0),
              'c_cons': max((len(_vals(shots, m)) for m in _C_TARGETS), default=0),
              'p_power': len(_vals(shots, 'speed_late') or _vals(shots, 'ball_speed'))}
    eligibility = {k: {'have': counts[k], 'need': floors[k],
                       'met': counts[k] >= floors[k] and locals_ok}
                   for k, locals_ok in (('s_perf', S['value'] is not None),
                                        ('a_acc', A['value'] is not None),
                                        ('c_cons', C['value'] is not None),
                                        ('p_power', P['value'] is not None))}
    eligible = all(e['met'] for e in eligibility.values())

    comps = {'s_perf': S['value'], 'a_acc': A['value'], 'c_cons': C['value'], 'p_power': P['value']}
    score, tier = None, None
    if eligible:
        w = params['weights']
        score = round(10 * (w['s_perf'] * S['value'] + w['a_acc'] * A['value']
                            + w['c_cons'] * C['value'] + w['p_power'] * P['value']))
        from .tiers import tier_for
        tier = tier_for(score, params)
    return dict(
        formula_version=SCORE_VERSION, label=params.get('label'),
        eligible=eligible, score=score, tier=tier,
        s_perf=S['value'], a_acc=A['value'], c_cons=C['value'], p_power=P['value'],
        components={'s_perf': S, 'a_acc': A, 'c_cons': C, 'p_power': P},
        eligibility=eligibility,
        inputs={'n_shots': len(shots), 'shot_ids': shot_ids or [s.get('shot_id') for s in shots],
                'window_days': params.get('window_days')},
    )
