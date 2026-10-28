"""DEC-094 §5/§6 — the uncertainty contract between measurement and coaching.

A coaching adjustment is suppressed (with a reason the shot card shows) when a metric it depends on is
unavailable, low-confidence, or an unapproved estimate; it's shown when the metrics are measured; and a shot
carrying no quality map behaves exactly as before (back-compat)."""
from lanesight_core.insights.adjust import strike_adjustment
from lanesight_core.insights import coach as _coach
from lanesight_core.insights.uncertainty import gate, metric_ok, quality_map

# A high hit with a real leave → strike_adjustment produces a 'move' (verified in the gate tests below).
_BASE = dict(entry_board=22.0, entry_angle_deg=4.0, board_at_15ft=15.0, board_at_0ft=12.0,
             breakpoint_board=10.0, speed_early=17.0, speed_late=16.0, pins_standing={2, 4, 5})


def _q(**over):
    d = {'entry_board': {'status': 'ok'}, 'arrows_board': {'status': 'ok'}, 'entry_angle': {'status': 'ok'}}
    d.update(over)
    return d


def _primary(ins):
    return ins['recommendations'][0]


# ---- strike_adjustment integration ----

def test_measured_metrics_keep_the_move():
    ins = strike_adjustment({**_BASE, '_quality': _q()}, 'R')
    assert _primary(ins)['type'] == 'move'


def test_uncertain_arrows_board_suppresses_the_move():
    ins = strike_adjustment({**_BASE, '_quality': _q(arrows_board={'status': 'low_confidence'})}, 'R')
    p = _primary(ins)
    assert p['type'] == 'none' and p.get('move_feet') == 0
    assert 'arrows' in p['suppressed_reason'] and ins['state'] in ('no_reliable_data', 'low_confidence_move')


def test_unavailable_entry_board_suppresses_entry_based_advice():
    ins = strike_adjustment({**_BASE, '_quality': _q(entry_board={'status': 'unavailable'})}, 'R')
    p = _primary(ins)
    assert p['type'] == 'none' and "wasn't measured" in p['suppressed_reason']


def test_unapproved_estimate_is_not_used_for_a_move():
    ins = strike_adjustment({**_BASE, '_quality': _q(entry_board={'status': 'calibrated_estimate'})}, 'R')
    assert _primary(ins)['type'] == 'none'


def test_no_quality_map_is_backward_compatible():
    # Older callers / stored records without a quality map must behave exactly as before — no suppression.
    assert _primary(strike_adjustment(_BASE, 'R'))['type'] == 'move'


# ---- gate / metric_ok units ----

def test_metric_ok_degrades_gracefully_without_quality():
    ok, why = metric_ok({}, 'entry_board')
    assert ok and why is None


def test_gate_passes_when_requirements_met():
    ok, why = gate({'type': 'move'}, {'_quality': _q()})
    assert ok and why is None


def test_gate_fails_on_unavailable_requirement():
    ok, why = gate({'type': 'move'}, {'_quality': _q(entry_board={'status': 'unavailable'})})
    assert not ok and 'entry board' in why


def test_numeric_uncertainty_threshold_enforced_when_present():
    ok, why = metric_ok({'_quality': {'rev_rate': {'status': 'ok', 'uncertainty': 40.0}}},
                        'rev_rate', max_uncertainty=25.0)
    assert not ok and '±40' in why


def test_types_without_requirements_never_suppressed():
    for t in ('none', 'execution', 'pattern_note'):
        ok, _ = gate({'type': t}, {'_quality': _q(entry_board={'status': 'unavailable'})})
        assert ok


# ---- coach lane verdict gating ----

def test_coach_lane_not_read_when_entry_board_low_confidence():
    metrics = {'entry_board': 22.0, 'entry_angle': 4.0, 'ball_speed': 17.0}
    kp = {'entry': {'board': 22.0, 'angle_deg': 4.0}}
    good = _coach.classify_lane(metrics, kp, far_lane=None, quality={'entry_board': {'status': 'ok'}})
    assert good['status'] in ('good', 'miss')
    gated = _coach.classify_lane(metrics, kp, far_lane=None, quality={'entry_board': {'status': 'low_confidence'}})
    assert gated['status'] == 'not_read'


def test_coach_lane_unchanged_without_quality():
    metrics = {'entry_board': 22.0, 'entry_angle': 4.0}
    kp = {'entry': {'board': 22.0, 'angle_deg': 4.0}}
    assert _coach.classify_lane(metrics, kp).get('status') in ('good', 'miss')


# ---- quality_map helper ----

def test_quality_map_from_measurements():
    from lanesight_core.models.shot import m
    meas = [m('entry_board', 17.0, 'board', 0.8), m('arrows_board', None, 'board', 0.0)]
    qm = quality_map(meas)
    assert qm['entry_board']['status'] == 'ok' and qm['arrows_board']['status'] == 'unavailable'
