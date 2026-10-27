"""Achievement engine (SCORE_TIERS §5, DEC-039/051)."""
import pytest
from lanesight_core.achievements import evaluate, update_streak


def ev(rule_type, params, ctx):
    return evaluate({'id': 'ACH-X', 'rule_type': rule_type, 'params': params}, ctx)


def test_one_time():
    assert ev('one_time', {}, {'condition_met': True})['unlocked'] is True
    assert ev('one_time', {}, {'condition_met': False})['status'] == 'locked'

def test_cumulative_and_count_qualifying():
    assert ev('cumulative', {'target': 100}, {'count': 100})['unlocked'] is True
    r = ev('cumulative', {'target': 100}, {'count': 40})
    assert r['unlocked'] is False and r['current_value'] == 40 and r['status'] == 'in_progress'
    assert ev('count_qualifying', {'target': 10}, {'qualifying_count': 10})['unlocked'] is True

def test_window_ratio_needs_sample_floor():
    few = ev('window_ratio', {'target_ratio': 0.8, 'min_sample': 30}, {'window': [True] * 10})
    assert few['status'] == 'not_trackable' and 'qualifying' in few['unavailable_reason']
    hit = ev('window_ratio', {'target_ratio': 0.8, 'min_sample': 30}, {'window': [True] * 27 + [False] * 3})
    assert hit['unlocked'] is True and hit['current_value'] == 0.9
    miss = ev('window_ratio', {'target_ratio': 0.9, 'min_sample': 30}, {'window': [True] * 24 + [False] * 6})
    assert miss['unlocked'] is False and miss['status'] == 'in_progress'

def test_window_spread_sd_and_cv():
    tight = ev('window_spread', {'max_sd': 0.5, 'min_sample': 5}, {'values': [16.0] * 6})
    assert tight['unlocked'] is True and tight['current_value'] == 0.0
    wide = ev('window_spread', {'max_sd': 0.5, 'min_sample': 5}, {'values': [15, 16, 17, 14, 18, 13]})
    assert wide['unlocked'] is False
    cv = ev('window_spread', {'max_cv': 0.05, 'min_sample': 5, 'spread_kind': 'cv'}, {'values': [400.0] * 6})
    assert cv['unlocked'] is True

def test_best_measured_respects_uncertainty_band():
    # measured 452 but +/-40 band does NOT fully clear 450 -> not yet
    assert ev('best_measured', {'threshold': 450, 'direction': 'above'},
              {'best_value': 452, 'uncertainty': 40})['unlocked'] is False
    # 460 with tight +/-5 clears it
    assert ev('best_measured', {'threshold': 450, 'direction': 'above'},
              {'best_value': 460, 'uncertainty': 5})['unlocked'] is True
    assert ev('best_measured', {'threshold': 0, 'direction': 'above'},
              {'best_value': None})['status'] == 'not_trackable'

def test_baseline_delta_and_first_tier():
    assert ev('baseline_delta', {'delta': 50}, {'current': 600, 'baseline': 540})['unlocked'] is True
    assert ev('baseline_delta', {'delta': 50}, {'current': 560, 'baseline': 540})['unlocked'] is False
    assert ev('first_tier', {'tier': 'gold'}, {'reached': True, 'tier': 'gold'})['unlocked'] is True

def test_unknown_rule_type_raises():
    with pytest.raises(ValueError):
        ev('made_up', {}, {})


# ---------------------------------------------------------------- streak break/skip rule
def test_streak_increments_and_unlocks():
    st = None
    for _ in range(10):
        st = update_streak(st, {'qualifies': True, 'is_real_attempt': True, 'analyzable': True})
    assert st['live'] == 10 and st['best'] == 10
    assert ev('streak', {'target': 10}, st)['unlocked'] is True

def test_streak_real_miss_breaks_but_best_kept():
    st = None
    for _ in range(5):
        st = update_streak(st, {'qualifies': True, 'is_real_attempt': True, 'analyzable': True})
    st = update_streak(st, {'qualifies': False, 'is_real_attempt': True, 'analyzable': True})
    assert st['live'] == 0 and st['best'] == 5

def test_streak_unanalyzable_shot_is_skipped_not_a_break():
    st = None
    for _ in range(4):
        st = update_streak(st, {'qualifies': True, 'is_real_attempt': True, 'analyzable': True})
    st = update_streak(st, {'qualifies': False, 'is_real_attempt': True, 'analyzable': False})  # unanalyzable
    st = update_streak(st, {'qualifies': True, 'is_real_attempt': True, 'analyzable': True})
    assert st['live'] == 5 and st['skipped'] == 1     # streak survived the unanalyzable shot
