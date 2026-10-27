"""DEC-088/090 shot-card coach — the four matrix rows + the building and far-lane-not-read states."""
from lanesight_core.insights import coach


def _base(n=20, speed=12.0, rev=400.0, arrows=10.0):
    # n prior shots at a steady normal throw
    return [{'ball_speed': speed, 'rev_rate': rev, 'arrows_board': arrows} for _ in range(n)]


POCKET = {'entry': {'board': 17.8, 'angle_deg': 5.0}}          # a pocket read
MISS = {'entry': {'board': 12.0, 'angle_deg': 3.0}}            # entered light


def test_good_throw_good_lane_keep():
    out = coach.build({'ball_speed': 12.1, 'rev_rate': 405, 'arrows_board': 10.2}, POCKET, _base())
    assert out['throw']['status'] == 'good' and out['lane']['status'] == 'good'
    assert out['coach']['action'] == 'keep'


def test_good_throw_miss_lane_move():
    out = coach.build({'ball_speed': 12.1, 'rev_rate': 405, 'arrows_board': 10.1}, MISS, _base(),
                      recommendation={'direction': 'left', 'move_feet': 2})
    assert out['throw']['status'] == 'good' and out['lane']['status'] == 'miss'
    assert out['coach']['action'] == 'lane_move'
    assert out['coach']['move'] == {'feet': 2, 'eyes': 1, 'direction': 'left'}


def test_off_throw_miss_lane_no_move():
    # 2 mph faster than the bowler's normal → off; lane missed (light). Never move on the throw.
    out = coach.build({'ball_speed': 14.0, 'rev_rate': 405, 'arrows_board': 10.1}, MISS, _base())
    assert out['throw']['status'] == 'off' and out['throw']['off_reason'] == 'speed'
    assert out['lane']['status'] == 'miss'
    assert out['coach']['action'] == 'no_move' and 'repeat your normal' in out['coach']['text'].lower()


def test_off_throw_good_lane_dont_build():
    out = coach.build({'ball_speed': 14.0, 'rev_rate': 405, 'arrows_board': 10.1}, POCKET, _base())
    assert out['throw']['status'] == 'off' and out['lane']['status'] == 'good'
    assert out['coach']['action'] == 'no_move' and "don't move on it" in out['coach']['text'].lower()


def test_building_baseline_lane_only():
    out = coach.build({'ball_speed': 14.0, 'rev_rate': 405, 'arrows_board': 10.1}, MISS, _base(n=4),
                      recommendation={'direction': 'left', 'move_feet': 2})
    assert out['throw']['status'] == 'building' and '4/10' in out['throw']['verdict']
    # still gives lane-only advice, never "repeat your normal"
    assert out['coach']['action'] == 'lane_move'
    assert 'normal' not in out['coach']['text'].lower()


def test_far_lane_not_read():
    out = coach.build({'ball_speed': 12.1, 'rev_rate': 405, 'arrows_board': 10.1}, {}, _base(), far_lane='not_read')
    assert out['lane']['status'] == 'not_read'
    assert out['coach']['action'] == 'no_move_yet'


def test_baseline_medians_and_count():
    b = coach.baseline(_base(n=5, speed=12.0) + [{'ball_speed': 20.0, 'rev_rate': None, 'arrows_board': None}])
    assert b['n'] == 6 and b['speed'] == 12.0        # median robust to the one outlier
    assert b['rev'] == 400.0 and b['arrows'] == 10.0
