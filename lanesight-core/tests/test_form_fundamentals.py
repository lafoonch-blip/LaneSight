"""Form fundamentals v1 (DEC-057, FORM_BENCHMARKS §0): timing checkpoints T1–T4, measured positions M1–M7,
coaching cues, swing-timing baseline, and the after_form_analyzed wiring + MemoryStore/PgStore parity.

Honesty: a verdict/value that the events or view can't support is 'unavailable' with a reason, never guessed.
"""
import numpy as np

from lanesight_core.form import (timing_checkpoints, measured_positions, gate_positions,
                                 coaching_cues, swing_timing, FUNDAMENTALS_VERSION)
from lanesight_api import engines
from lanesight_api.store import MemoryStore, PgStore
from lanesight_api.rules_seed import ENGINE_CONFIG


# ------------------------------------------------------------------ timing checkpoints (pure)
def _record(events, metrics):
    def mm(k, v, u='s', st='ok'):
        return {'metric': k, 'value': v, 'unit': u, 'status': st, 'confidence': 0.6}
    return {'events': events,
            'metrics': {k: mm(k, *(val if isinstance(val, tuple) else (val,))) for k, val in metrics.items()}}


def test_timing_checkpoints_verdicts_match_the_design():
    rec = _record(events={'E4': 1.08, 'E5': 1.00, 'E7': 1.44, 'E8': 1.50},
                  metrics={'ball_start_step': (2, 'step'), 'step_count': (5, 'count')})
    cp = timing_checkpoints(rec, windows=ENGINE_CONFIG['form_timing_windows'], approach_steps=5)
    # T1 is not resolvable without a side view + scale
    assert cp['T1']['status'] == 'unavailable' and cp['T1']['verdict'] is None and cp['T1']['note']
    # T2 ball-start step: step 2 of a 5-step approach = exactly on time
    assert cp['T2']['verdict'] == 'on_time' and cp['T2']['offset'] == 0
    # T3 top of swing: E4−E5 = +0.08 s (> +0.05) -> late
    assert cp['T3']['verdict'] == 'late' and abs(cp['T3']['offset'] - 0.08) < 1e-6
    # T4 leverage: E7−E8 = −0.06 s (< 0) -> early
    assert cp['T4']['verdict'] == 'early' and abs(cp['T4']['offset'] + 0.06) < 1e-6
    assert 0.0 <= cp['T3']['bar_pos'] <= 1.0 and cp['T3']['provisional'] is True


def test_timing_checkpoint_ball_start_step_early_and_late():
    base = {'events': {}, }
    early = timing_checkpoints(_record({}, {'ball_start_step': (1, 'step'), 'step_count': (5, 'count')}),
                               approach_steps=5)
    assert early['T2']['verdict'] == 'early' and early['T2']['offset'] == -1
    late = timing_checkpoints(_record({}, {'ball_start_step': (2, 'step'), 'step_count': (4, 'count')}),
                              approach_steps=4)
    assert late['T2']['verdict'] == 'late' and late['T2']['offset'] == 1


def test_timing_checkpoints_unavailable_when_events_missing():
    cp = timing_checkpoints(_record(events={}, metrics={}))
    for k in ('T1', 'T2', 'T3', 'T4'):
        assert cp[k]['status'] == 'unavailable' and cp[k]['verdict'] is None and cp[k]['note']


def test_timing_checkpoint_t2_needs_4_or_5_step():
    cp = timing_checkpoints(_record({}, {'ball_start_step': (1, 'step'), 'step_count': (3, 'count')}),
                            approach_steps=3)
    assert cp['T2']['status'] == 'unavailable' and '4- or 5-step' in cp['T2']['note']


# ------------------------------------------------------------------ measured positions (geometry + gating)
def _synthetic_lms(n=10):
    """A minimal pose track: shoulders/hips/wrists/nose set so the geometry is finite and sensible."""
    t = np.round(np.arange(n) * 0.1, 3)
    lms = np.full((n, 33, 5), np.nan, np.float32)
    for k in range(n):
        def put(idx, x, y):
            lms[k, idx] = (x, y, 0.0, 0.9, 0.9)
        put(0, 0.50, 0.10)       # NOSE
        put(11, 0.44, 0.30)      # L_SHOULDER
        put(12, 0.56, 0.32)      # R_SHOULDER (bowling side for RH; slightly lower)
        put(23, 0.46, 0.55)      # L_HIP
        put(24, 0.54, 0.55)      # R_HIP
        put(15, 0.20, 0.35)      # L_WRIST (balance arm out to the side)
        put(16, 0.60, 0.15)      # R_WRIST (bowling wrist up near the head late)
    return t, lms


def test_measured_positions_geometry_and_statuses():
    t, lms = _synthetic_lms()
    events = {'E2': 0.0, 'E7': 0.5, 'hold_end': 0.9}
    metrics = {'finish_hold': {'metric': 'finish_hold', 'value': 2.6, 'unit': 's',
                               'status': 'best_effort', 'confidence': 0.6},
               'downswing_time': {'metric': 'downswing_time', 'value': 0.37, 'unit': 's',
                                  'status': 'best_effort', 'confidence': 0.6}}
    pos = measured_positions(t, lms, events, torso=0.25, handed='R', metrics=metrics)
    assert set(pos) == {'foul_line_distance', 'spine_tilt', 'balance_arm', 'shoulder_tilt',
                        'follow_through', 'finish_hold', 'pendulum'}
    assert pos['foul_line_distance']['status'] == 'unavailable'            # M1: no floor scale
    assert pos['spine_tilt']['status'] == 'best_effort' and pos['spine_tilt']['value'] is not None
    assert pos['spine_tilt']['steady'] is True                            # constant tilt -> steady
    assert pos['balance_arm']['status'] == 'best_effort'                  # M3 off-arm abduction finite
    assert pos['shoulder_tilt']['status'] == 'best_effort'
    assert pos['shoulder_tilt']['bowling_shoulder_lower'] is True         # R shoulder put lower
    assert pos['follow_through']['status'] == 'best_effort'
    assert pos['finish_hold']['status'] == 'best_effort' and pos['finish_hold']['value'] == 2.6
    assert pos['pendulum']['value'] == 0.37
    for p in pos.values():                                                # every entry carries its id
        assert p['id'] in {'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7'}


def test_gate_positions_by_view():
    t, lms = _synthetic_lms()
    events = {'E2': 0.0, 'E7': 0.5, 'hold_end': 0.9}
    metrics = {}
    # rear view: frontal-plane positions stay, forward spine tilt is refused
    rear = gate_positions(measured_positions(t, lms, events, 0.25, 'R', metrics), 'rear')
    assert rear['spine_tilt']['status'] == 'unavailable' and 'side view' in rear['spine_tilt']['note']
    assert rear['balance_arm']['status'] == 'best_effort'
    assert rear['shoulder_tilt']['status'] == 'best_effort'
    # down_lane (side-ish): spine tilt allowed, frontal positions refused
    side = gate_positions(measured_positions(t, lms, events, 0.25, 'R', metrics), 'down_lane')
    assert side['spine_tilt']['status'] == 'best_effort'
    assert side['balance_arm']['status'] == 'unavailable'
    # unknown: spine tilt still refused, frontal kept with a caveat
    unk = gate_positions(measured_positions(t, lms, events, 0.25, 'R', metrics), 'unknown')
    assert unk['spine_tilt']['status'] == 'unavailable'
    assert unk['balance_arm']['status'] == 'best_effort' and 'not confirmed' in unk['balance_arm']['note']


# ------------------------------------------------------------------ coaching cues (text only)
def test_coaching_cues_are_text_only():
    cc = coaching_cues()
    assert "can't be measured" in cc['note'] and len(cc['cues']) >= 5
    assert any('thumb out first' in c for c in cc['cues'])


# ------------------------------------------------------------------ swing-timing baseline (§0.4)
def _swing_record():
    def mm(k, v):
        return {'metric': k, 'value': v, 'unit': 's', 'status': 'best_effort', 'confidence': 0.6}
    return {'metrics': {'pushaway_time': mm('pushaway_time', 0.40), 'backswing_time': mm('backswing_time', 0.70),
                        'downswing_time': mm('downswing_time', 0.37), 'release_time': mm('release_time', 0.03),
                        'swing_time': mm('swing_time', 1.50)}}


def test_swing_timing_entered_baseline():
    fb = {'mode': 'entered', 'pushaway_time': 0.38, 'backswing_time': 0.64,
          'downswing_time': 0.39, 'release_time': 0.03, 'total': 1.44}
    out = swing_timing(_swing_record(), form_baseline=fb)
    assert out['building'] is False and out['source'] == 'profile_entered'
    assert out['baseline']['total'] == 1.44
    assert abs(out['diff']['pushaway_time'] - 0.02) < 1e-6
    assert abs(out['diff']['backswing_time'] - 0.06) < 1e-6


def test_swing_timing_use_my_average():
    bases = {'pushaway_time': {'established': True, 'median': 0.38},
             'backswing_time': {'established': True, 'median': 0.64},
             'downswing_time': {'established': True, 'median': 0.39},
             'release_time': {'established': True, 'median': 0.03}}
    out = swing_timing(_swing_record(), form_baseline={'mode': 'average'}, bases=bases)
    assert out['source'] == 'profile_average' and out['building'] is False
    assert out['baseline']['pushaway_time'] == 0.38


def test_swing_timing_building_when_no_baseline():
    out = swing_timing(_swing_record(), form_baseline=None)
    assert out['building'] is True and out['baseline'] is None
    assert out['this_delivery']['total'] == 1.50 and out['prompt']


# ------------------------------------------------------------------ store parity (form baseline + config)
def test_form_baseline_roundtrip_memory():
    store = MemoryStore()
    assert store.get_form_baseline('u1') is None                 # none set -> building
    fb = {'mode': 'entered', 'pushaway_time': 0.38, 'total': 1.44}
    store.set_form_baseline('u1', fb)
    assert store.get_form_baseline('u1') == fb


def test_engine_config_has_timing_windows_both_stores():
    assert MemoryStore().engine_config()['form_timing_windows']['T3']['high'] == 0.05
    # PgStore inherits get_form_baseline/set_form_baseline from MemoryStore (profile-backed) -> parity
    assert PgStore.get_form_baseline is MemoryStore.get_form_baseline
    assert PgStore.set_form_baseline is MemoryStore.set_form_baseline


# ------------------------------------------------------------------ after_form_analyzed wiring
def _full_form_record():
    def mm(k, v, u='s', st='best_effort'):
        return {'metric': k, 'value': v, 'unit': u, 'status': st, 'confidence': 0.6}
    metrics = {'pushaway_time': mm('pushaway_time', 0.40), 'backswing_time': mm('backswing_time', 0.70),
               'downswing_time': mm('downswing_time', 0.37), 'release_time': mm('release_time', 0.03),
               'swing_time': mm('swing_time', 1.50), 'finish_hold': mm('finish_hold', 1.2),
               'step_count': mm('step_count', 5, 'count'), 'ball_start_step': mm('ball_start_step', 2, 'step')}
    return {'form_version': 'form-0.0.0', 'metrics': metrics, 'measurements': list(metrics.values()),
            'events': {'E4': 1.08, 'E5': 1.00, 'E7': 1.44, 'E8': 1.50},
            'key_frames': ['ball_start', 'end_pushaway', 'top_of_swing', 'release'],
            'measured_positions': {
                'pendulum': {'id': 'M7', 'metric': 'pendulum', 'value': 0.37, 'unit': 's',
                             'status': 'best_effort', 'confidence': 0.4, 'note': 'proxy'},
                'finish_hold': {'id': 'M6', 'metric': 'finish_hold', 'value': 1.2, 'unit': 's',
                                'status': 'best_effort', 'confidence': 0.6}}}


def test_after_form_analyzed_attaches_fundamentals():
    store = MemoryStore()
    user, session = 'uF', 'sF'
    store.set_form_baseline(user, {'mode': 'average'})
    for _ in range(12):                                          # establish downswing baseline for M7 + average
        sh = store.create_shot(user, session, {'source': 'form'})
        store.save_shot_result(sh['id'], _full_form_record(), {'ok': True, 'mode': 'form'})
    cur = _full_form_record()
    footer = engines.after_form_analyzed(store, user, session, cur, analyze_seconds=48.0)
    cp = cur['timing_checkpoints']
    assert cp['T3']['verdict'] == 'late' and cp['T4']['verdict'] == 'early' and cp['T2']['verdict'] == 'on_time'
    assert cur['swing_timing']['source'] == 'profile_average' and cur['swing_timing']['building'] is False
    assert cur['measured_positions']['pendulum'].get('vs_baseline') is not None   # enriched vs baseline
    assert cur['measured_positions']['pendulum'].get('leverage_verdict') == 'early'
    assert cur['coaching_cues']['cues'] and footer['coaching_cues']['cues']
    assert cur['footer']['fundamentals_version'] == FUNDAMENTALS_VERSION
    assert footer['timing_checkpoints']['T3']['verdict'] == 'late'
