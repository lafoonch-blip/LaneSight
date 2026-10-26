import numpy as np
from lanesight_core.cv.pipeline import far_lane_quality, _unsupported_view_record, _METRIC_CATALOG
from lanesight_core.cv.lanes import classify_capture_view


# ---- capture-view gate (side-view-misroute handoff / DEC-061) ----
# A rear/down-lane view puts the lane band in the lower frame; a side/approach view (IMG_8905) compresses it
# into a thin band high in the frame. Values below are the measured lane y_rng on real clips (frame h=1920).

def test_view_gate_refuses_side_view():
    v = classify_capture_view({'y_rng': (213.0, 381.0)}, (694, 503), (1920, 1080, 3))   # IMG_8905 side
    assert v['view'] == 'side' and v['supported'] is False and 'down-lane' in v['reason'].lower()
    assert v['lane_center_frac'] < 0.4


def test_view_gate_passes_rear_and_elevated_views():
    rear = classify_capture_view({'y_rng': (1491.0, 1753.0)}, (371, 992), (1920, 1080, 3))   # IMG_8753 rear
    assert rear['view'] == 'rear' and rear['supported'] is True
    elevated = classify_capture_view({'y_rng': (864.0, 998.0)}, (140, 250), (1920, 1080, 3))  # cohort 8907 ~0.49
    assert elevated['supported'] is True            # elevated ball-return rear is still supported


def test_view_gate_unknown_when_no_lane():
    v = classify_capture_view({'y_rng': None}, (0, 0), (1920, 1080, 3))
    assert v['view'] == 'unknown' and v['supported'] is False


def test_unsupported_view_record_is_all_unavailable_no_reliable_data():
    S = dict(ts=np.arange(0, 1.0, 1 / 60.0), shift=np.array([0.0, 1.5]), ref=0,
             bg=np.zeros((1920, 1080, 3), np.uint8))
    vinfo = dict(view='side', supported=False, reason='No down-lane view. Set the camera behind the lane.',
                 lane_center_frac=0.16)
    rec = _unsupported_view_record('IMG_8905.MOV', S, vinfo, {'shot_id': 'x'}, '/tmp/x', 'R')
    d = rec.to_dict()
    assert len(d['measurements']) == len(_METRIC_CATALOG)
    assert all(mm['status'] == 'unavailable' and mm['value'] is None for mm in d['measurements'])
    assert d['insights']['state'] == 'no_reliable_data' and d['insights']['recommendations'][0]['move_feet'] == 0
    assert d['capture_quality']['view'] == 'side' and d['capture_quality']['supported'] is False
    assert d['video']['fps'] == 60.0                # fps from the probe, never a constant



def test_speed_speedup_flags_far_lane():
    # A ball can't speed up down the lane -> far lane limited (SHOT_REVIEW 14b234c8: 15.8 -> 19.4).
    limited, reason = far_lane_quality(dict(speed_early_mph=15.8, speed_late_mph=19.4), [])
    assert limited and reason and 'camera' in reason.lower()


def test_plausible_slowdown_is_ok():
    # A real ball loses speed -> not flagged.
    limited, _ = far_lane_quality(dict(speed_early_mph=18.7, speed_late_mph=17.1), [])
    assert not limited


def test_noise_band_tolerated():
    limited, _ = far_lane_quality(dict(speed_early_mph=16.0, speed_late_mph=16.4), [])
    assert not limited


def test_off_lane_entry_flags_geometry():
    # A board is 1..39; an entry board of 45 means the lane homography is broken (awkward framing).
    limited, reason = far_lane_quality(dict(entry_board=45.6, speed_early_mph=22.0, speed_late_mph=22.0), [])
    assert limited and 'off the lane' in reason.lower()
    # on-lane entry with plausible speeds is fine
    assert not far_lane_quality(dict(entry_board=17.5, speed_early_mph=17.0, speed_late_mph=15.8), [])[0]


def test_lateral_jump_flags_far_lane():
    # A >3-board jump between neighbouring samples downlane -> far lane limited.
    zb = [(30.0, 10.0), (42.5, 14.8), (44.0, 2.0)]
    limited, reason = far_lane_quality(dict(speed_early_mph=15.0, speed_late_mph=14.0), zb)
    assert limited and 'jump' in reason.lower()


def test_missing_speeds_and_smooth_path_ok():
    # Dense per-frame samples (as the pipeline passes): a real hook moves <1 board between neighbours.
    zb = [(z / 2.0, 20.0 - 0.1 * z) for z in range(0, 112)]
    limited, _ = far_lane_quality(dict(), zb)
    assert not limited
