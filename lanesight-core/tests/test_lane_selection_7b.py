"""DEC-122 step 7b unit tests: lane-selection-from-the-ball scoring + the foul-observation honesty gate."""
from lanesight_core.cv.pipeline import _lane_ball_score, _foul_observed, FOUL_OBS_MAX_FT


def _track(fracs, u0=0.1, du=0.02):
    # minimal track points: link() output carries 'frac' (lateral position in the lane) and 'u' (1/depth).
    return [{'frac': f, 'u': u0 + i * du} for i, f in enumerate(fracs)]


def test_lane_ball_score_rewards_an_on_lane_track():
    on_lane = _track([0.4, 0.45, 0.5, 0.52, 0.55, 0.5, 0.48])     # ball stays within the lane edges
    assert _lane_ball_score(on_lane) > 0


def test_lane_ball_score_rejects_a_track_off_the_lane():
    off_lane = _track([1.8, 1.9, 2.0, 2.1, 2.2, 2.3])             # ball sits outside this lane's edges (wrong lane)
    assert _lane_ball_score(off_lane) == 0.0


def test_lane_ball_score_prefers_the_lane_the_ball_is_on():
    ball_lane = _track([0.45, 0.5, 0.52, 0.5, 0.48, 0.5, 0.5, 0.5])
    neighbour = _track([1.6, 1.7, 1.8, 1.9])                       # shorter AND off-lane
    assert _lane_ball_score(ball_lane) > _lane_ball_score(neighbour)


def test_lane_ball_score_zero_for_short_or_empty():
    assert _lane_ball_score([]) == 0.0
    assert _lane_ball_score(_track([0.5, 0.5])) == 0.0            # < 5 points


def test_foul_observed_gate():
    assert _foul_observed({'track_first_ft': -2.3}) is True        # ball tracked at the foul (accurate clips)
    assert _foul_observed({'track_first_ft': 0.7}) is True
    assert _foul_observed({'track_first_ft': FOUL_OBS_MAX_FT}) is True
    assert _foul_observed({'track_first_ft': 32.2}) is False       # IMG_8970: foul extrapolated -> withhold
    assert _foul_observed({'track_first_ft': None}) is False
    assert _foul_observed({}) is False
    assert _foul_observed(None) is False
