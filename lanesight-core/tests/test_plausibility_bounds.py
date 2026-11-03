"""DEC-128: plausibility bounds on BOTH engines. A value physically off the lane / out of range is reported
`unavailable` + reason_code IMPLAUSIBLE_VALUE, never surfaced as a measurement. These tests cover the shared
helper, the server video pipeline's gate, and the on-device-submission backstop in _apply_status_policy."""
from lanesight_core.failures import implausible_reason, IMPLAUSIBLE_VALUE
from lanesight_core.models.shot import Measurement
from lanesight_api.app import _apply_status_policy


def test_helper_board_bounds():
    assert implausible_reason('board_at_7ft', 50.6)          # off the 39-board lane
    assert implausible_reason('laydown_board', 0.5)          # board < 1
    assert implausible_reason('arrows_board', 40.0)          # board > 39
    assert implausible_reason('arrows_board', 37.1) is None  # 1..39 is fine
    assert implausible_reason('arrows_board', 1.0) is None
    assert implausible_reason('arrows_board', 39.0) is None


def test_helper_speed_and_rev_bounds():
    assert implausible_reason('ball_speed', 55.0)
    assert implausible_reason('ball_speed', 3.0)
    assert implausible_reason('ball_speed', 17.6) is None
    assert implausible_reason('rev_rate', 50)
    assert implausible_reason('rev_rate', 900)
    assert implausible_reason('rev_rate', 370) is None
    assert implausible_reason('ball_speed', float('nan'))
    assert implausible_reason('ball_speed', float('inf'))
    assert implausible_reason('laydown_board', None) is None


def test_helper_ignores_unbounded_metrics():
    # angles / loft / launch aren't board/speed/rev — never flagged by this helper
    assert implausible_reason('launch_angle', 90.0) is None
    assert implausible_reason('entry_angle', 12.0) is None
    assert implausible_reason('loft', 3.0) is None


def test_pipeline_pass_marks_unavailable():
    # Simulate the pipeline's end-of-analyze plausibility pass over Measurement objects.
    from lanesight_core.failures import implausible_reason as ir
    meas = [Measurement('board_at_7ft', 50.6, 'board', 0.9, 'ok'),
            Measurement('arrows_board', 14.5, 'board', 0.9, 'ok'),
            Measurement('ball_speed', 17.6, 'mph', 0.8, 'best_effort')]
    for x in meas:
        reason = ir(x.metric, x.value)
        if reason and x.status != 'unavailable':
            x.value, x.status, x.confidence, x.reason_code = None, 'unavailable', 0.0, IMPLAUSIBLE_VALUE
    by = {x.metric: x for x in meas}
    assert by['board_at_7ft'].status == 'unavailable' and by['board_at_7ft'].reason_code == IMPLAUSIBLE_VALUE
    assert by['board_at_7ft'].value is None
    assert by['arrows_board'].status == 'ok' and by['arrows_board'].value == 14.5   # in-band untouched
    assert by['ball_speed'].status == 'best_effort'


def test_apply_status_policy_backstop_rejects_implausible():
    # An on-device submission with an impossible board must come back unavailable + IMPLAUSIBLE_VALUE.
    metrics = {
        'board_at_7ft': {'value': 50.6, 'status': 'ok', 'unit': 'board'},
        'arrows_board': {'value': 14.5, 'status': 'ok', 'unit': 'board'},
        'ball_speed': {'value': 95.0, 'status': 'best_effort', 'unit': 'mph'},
        'rev_rate': {'value': 370.0, 'status': 'calibrated_estimate', 'unit': 'rpm'},
    }
    _apply_status_policy(metrics)
    assert metrics['board_at_7ft']['status'] == 'unavailable'
    assert metrics['board_at_7ft']['reason_code'] == IMPLAUSIBLE_VALUE
    assert metrics['board_at_7ft']['value'] is None
    assert metrics['ball_speed']['status'] == 'unavailable'          # 95 mph impossible
    assert metrics['ball_speed']['reason_code'] == IMPLAUSIBLE_VALUE
    assert metrics['arrows_board']['status'] == 'ok'                 # 14.5 in-band, keeps measured status
    assert metrics['rev_rate']['value'] == 370.0                    # in-band rev kept
