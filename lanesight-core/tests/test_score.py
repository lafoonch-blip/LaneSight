"""L-dev-0 score engine + tiers (DEC-048/051)."""
import copy
from lanesight_core.score import (
    performance, accuracy, consistency, power_component, compute,
    tier_for, evaluate_tier, DEFAULT_LDEV0_PARAMS,
)

P = DEFAULT_LDEV0_PARAMS


def _m(value, status='ok', uncertainty=None):
    d = {'value': value, 'status': status}
    if uncertainty is not None:
        d['uncertainty'] = uncertainty
    return d


def shot(i=0, entry_board=17, entry_angle=5.0, speed=16.0, rev=400.0, rev_unc=20.0,
         arrows=15.0, bp=10.0):
    metrics = {}
    if entry_board is not None: metrics['entry_board'] = _m(entry_board)
    if entry_angle is not None: metrics['entry_angle'] = _m(entry_angle)
    if speed is not None:
        metrics['ball_speed'] = _m(speed)      # headline speed (DEC-032 consistency keys on this)
        metrics['speed_late'] = _m(speed)      # pocket speed (P' power input)
    if rev is not None: metrics['rev_rate'] = _m(rev, 'calibrated_estimate', uncertainty=rev_unc)
    if arrows is not None: metrics['arrows_board'] = _m(arrows)
    if bp is not None: metrics['breakpoint_board'] = _m(bp)
    return {'shot_id': f's{i}', 'metrics': metrics}


# --------------------------------------------------------------------------- Performance S'
def test_performance_pocket_and_angle_pct():
    shots = ([shot(i, entry_board=17, entry_angle=5.0) for i in range(6)]       # 6 in pocket, in angle
             + [shot(i, entry_board=10, entry_angle=9.0) for i in range(6, 10)])  # 4 out, out of angle
    s = performance(shots, P)
    assert s['pocket_pct'] == 60 and s['angle_pct'] == 60
    assert s['value'] == round(0.6 * 60 + 0.4 * 60)   # 60

def test_performance_left_hander_mirror():
    # board 23 is the left-hand pocket (40-23=17 -> RH pocket); RH range [16,19] must NOT match 23
    shots = [shot(i, entry_board=23, entry_angle=5.0) for i in range(5)]
    assert performance(shots, P, handed='R')['pocket_pct'] == 0
    assert performance(shots, P, handed='L')['pocket_pct'] == 100

def test_performance_building_without_both_inputs():
    shots = [shot(i, entry_angle=None) for i in range(5)]   # no angle measured
    assert performance(shots, P)['value'] is None


# --------------------------------------------------------------------------- Accuracy (DEC-031)
def test_accuracy_formula_and_on_target():
    shots = [shot(0, arrows=16.0, bp=12.0)]
    intents = {'s0': {'arrows_board': 15.0, 'breakpoint_board': 10.0}}
    a = accuracy(shots, intents)
    # arrow err 1 -> 80; bp err 2 -> 75; A = .6*80 + .4*75 = 78
    assert a['value'] == 78 and a['on_target_pct'] == 100

def test_accuracy_no_intent_is_none_not_zero():
    a = accuracy([shot(0)], intents={})
    assert a['value'] is None and a['status'] == 'no_intent'


# --------------------------------------------------------------------------- Consistency (DEC-032)
def test_consistency_zero_spread_is_100():
    shots = [shot(i) for i in range(10)]   # all identical -> zero spread
    c = consistency(shots)
    assert c['value'] == 100
    assert set(c['components']) == {'ball_speed', 'rev_rate', 'arrows_board', 'breakpoint_board'}

def test_consistency_excludes_wide_rev_band():
    shots = [shot(i, rev_unc=40.0) for i in range(10)]   # band 40 > 30 target
    c = consistency(shots)
    assert 'rev_rate' in c['excluded'] and 'rev_rate' not in c['components']

def test_consistency_building_under_min_n():
    shots = [shot(i) for i in range(3)]
    assert consistency(shots)['value'] is None

def test_consistency_rev_uncertainty_none_does_not_crash():
    # real records may have rev_rate value but no uncertainty -> must not raise (regression)
    shots = [shot(i, rev_unc=None) for i in range(6)]
    c = consistency(shots)
    assert 'rev_rate' in c['components']   # included (no band to exclude on)


# --------------------------------------------------------------------------- Power P'
def test_power_unavailable_without_ranges():
    assert power_component([shot(i) for i in range(10)], P)['value'] is None

def test_power_with_ranges():
    params = copy.deepcopy(P)
    params['power_ref_ranges'] = {'entry_speed_mph': [14, 20], 'rev_rate_rpm': [300, 500],
                                  'entry_angle_deg': [3, 7], 'weight_lb': [14, 16]}
    p = power_component([shot(i) for i in range(10)], params, weight_lb=15.0)
    # speed .333, rev .5, angle .5, weight .5 -> mean .458 -> 46
    assert p['value'] == 46 and p['status'] == 'ok'


# --------------------------------------------------------------------------- Composite
def test_compute_building_when_power_ranges_missing():
    shots = [shot(i) for i in range(25)]
    intents = {f's{i}': {'arrows_board': 15.0, 'breakpoint_board': 10.0} for i in range(25)}
    r = compute(shots, intents, P, weight_lb=15.0)
    assert r['eligible'] is False and r['score'] is None
    assert r['eligibility']['p_power']['met'] is False   # P' unavailable blocks eligibility

def test_compute_eligible_and_scored():
    params = copy.deepcopy(P)
    params['power_ref_ranges'] = {'entry_speed_mph': [14, 20], 'rev_rate_rpm': [300, 500],
                                  'entry_angle_deg': [3, 7], 'weight_lb': [14, 16]}
    shots = [shot(i) for i in range(25)]
    intents = {f's{i}': {'arrows_board': 15.0, 'breakpoint_board': 10.0} for i in range(25)}
    r = compute(shots, intents, params, weight_lb=15.0)
    assert r['eligible'] is True
    # S'=100, A=100, C=100, P'=46 -> 10*(40+25+25+4.6)=946
    assert r['s_perf'] == 100 and r['a_acc'] == 100 and r['c_cons'] == 100 and r['p_power'] == 46
    assert r['score'] == 946 and r['tier'] == 'onyx'


# --------------------------------------------------------------------------- Tiers
def test_tier_for_boundaries():
    assert tier_for(0, P) == 'bronze' and tier_for(399, P) == 'bronze'
    assert tier_for(400, P) == 'silver' and tier_for(550, P) == 'gold'
    assert tier_for(849, P) == 'platinum' and tier_for(850, P) == 'onyx' and tier_for(1000, P) == 'onyx'

def test_tier_first_promotion_celebrates():
    snap = {'eligible': True, 'score': 560}
    out = evaluate_tier(None, snap, P)
    assert out['event']['kind'] == 'promotion' and out['event']['to_tier'] == 'gold'
    assert out['event']['first_time'] is True and out['personal_best'] is True
    assert out['state']['tier'] == 'gold' and out['state']['first_qualified_score'] == 560

def test_tier_regain_is_not_first_time():
    prev = {'tier': 'silver', 'best_score': 600, 'first_qualified_score': 500, 'below_floor_sessions': 0}
    out = evaluate_tier(prev, {'eligible': True, 'score': 560}, P)   # gold again, held gold before (best 600)
    assert out['event']['kind'] == 'promotion' and out['event']['first_time'] is False

def test_tier_demotion_needs_two_sessions():
    prev = {'tier': 'gold', 'best_score': 700, 'first_qualified_score': 600, 'below_floor_sessions': 0}
    s1 = evaluate_tier(prev, {'eligible': True, 'score': 530}, P)    # 550-530=20 > 15: pending
    assert s1['event'] is None and s1['state']['below_floor_sessions'] == 1 and s1['state']['tier'] == 'gold'
    s2 = evaluate_tier(s1['state'], {'eligible': True, 'score': 530}, P)
    assert s2['event']['kind'] == 'demotion' and s2['state']['tier'] == 'silver'

def test_tier_not_eligible_no_movement():
    prev = {'tier': 'gold', 'best_score': 700, 'first_qualified_score': 600, 'below_floor_sessions': 1}
    out = evaluate_tier(prev, {'eligible': False, 'score': None}, P)
    assert out['event'] is None and out['state']['tier'] == 'gold'
