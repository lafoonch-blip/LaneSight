"""Benchmarks engine (BENCHMARKS spec §3-5, DEC-046)."""
from lanesight_core.benchmarks import (
    personal_baseline, resolve_benchmark, classify_level, classify_consistency, prioritize,
)


def test_personal_baseline_building_then_established():
    b5 = personal_baseline([16.0] * 5, min_n=10)
    assert b5['established'] is False and b5['status'] == 'building' and b5['n'] == 5
    b10 = personal_baseline([16.0] * 10, min_n=10)
    assert b10['established'] is True and b10['median'] == 16.0 and b10['mad'] == 0.0

def test_personal_baseline_band():
    b = personal_baseline([10, 11, 12, 13, 14, 15, 16, 17, 18, 19], min_n=10)
    assert b['median'] == 14.5 and b['band_low'] < b['median'] < b['band_high']


def test_resolve_order_and_unestablished_personal_skipped():
    coach = {'target': 5}; style = {'low': 4, 'high': 6}; ref = {'low': 3, 'high': 7}
    assert resolve_benchmark(coach=coach, style=style, reference=ref)[0] == 'coach'
    # personal only counts when established
    unest = {'low': 1, 'high': 2, 'established': False}
    assert resolve_benchmark(personal=unest, style=style)[0] == 'style'
    est = {'low': 1, 'high': 2, 'established': True}
    assert resolve_benchmark(personal=est, style=style)[0] == 'personal'
    assert resolve_benchmark() == (None, None)


def test_classify_level_within_watch_outside():
    bench = {'low': 4, 'high': 6}
    assert classify_level(5, bench)['status'] == 'within'
    once = classify_level(8, bench, streak_outside=0, repetition=3)
    assert once['status'] == 'watch' and once['side'] == 'high' and once['streak_outside'] == 1
    rep = classify_level(8, bench, streak_outside=2, repetition=3)
    assert rep['status'] == 'outside'

def test_classify_level_uncertainty_slack():
    # value just outside the band but inside the measurement error -> Within
    bench = {'low': 4, 'high': 6}
    assert classify_level(6.4, bench, uncertainty=1.0)['status'] == 'within'


def test_classify_consistency():
    assert classify_consistency(1.0, 1.0)['status'] == 'within'
    assert classify_consistency(1.2, 1.0)['status'] == 'watch'
    assert classify_consistency(2.0, 1.0)['status'] == 'outside'


def test_prioritize_picks_top_and_suppresses_downstream():
    findings = [
        {'metric': 'timing', 'distance_bands': 2.0, 'confidence': 1.0},
        {'metric': 'finish', 'distance_bands': 1.5, 'downstream_of': ['timing']},
        {'metric': 'drift', 'distance_bands': 1.2},
    ]
    out = prioritize(findings, max_secondary=2)
    assert out['primary']['metric'] == 'timing'
    assert all(f['metric'] != 'finish' for f in out['secondary'])     # finish suppressed under timing
    assert any(f['metric'] == 'finish' for f in out['suppressed'])
    assert out['secondary'][0]['metric'] == 'drift'

def test_prioritize_coach_focus_wins():
    findings = [
        {'metric': 'timing', 'distance_bands': 3.0},
        {'metric': 'drift', 'distance_bands': 0.5, 'focus': True},
    ]
    assert prioritize(findings)['primary']['metric'] == 'drift'
