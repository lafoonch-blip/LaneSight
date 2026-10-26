from lanesight_core.cv.pipeline import far_lane_quality


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
