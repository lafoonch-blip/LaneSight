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


# --- DEC-031 per-shot Accuracy score (0-100), wired into the throw accuracy ring (DEC-090) ---

def test_accuracy_score_exact_dec031():
    # On line at both: arrow err 0 -> 100, bp err 0 -> 100 -> 0.6*100+0.4*100 = 100.
    assert coach.accuracy_score(12.0, 12.0, 40.0, 40.0)['value'] == 100
    # Arrow 2 boards off (score 100*(1-2/5)=60), breakpoint 4 off (100*(1-4/8)=50): 0.6*60+0.4*50 = 56.
    a = coach.accuracy_score(14.0, 12.0, 44.0, 40.0)
    assert a['value'] == 56 and a['status'] == 'ok'
    assert a['components'] == {'arrow': 60, 'breakpoint': 50}
    # Full miss beyond both scales clamps to 0 (a measured total miss is a real 0 only when both inputs exist).
    assert coach.accuracy_score(20.0, 12.0, 60.0, 40.0)['value'] == 0


def test_accuracy_unavailable_without_target_is_never_zero():
    a = coach.accuracy_score(12.0, None)
    assert a['value'] is None and a['status'] == 'unavailable' and 'target line' in a['note']
    # measured arrows missing -> unavailable, not 0
    assert coach.accuracy_score(None, 12.0)['value'] is None


def test_accuracy_arrows_only_when_breakpoint_missing_is_low_confidence():
    # Breakpoint is a far-lane metric gated under DEC-065: with no bp, score is arrows-only + low_confidence,
    # NOT blended as a 0-board breakpoint hit.
    a = coach.accuracy_score(13.0, 12.0, None, 40.0)      # arrow 1 off -> 80
    assert a['value'] == 80 and a['status'] == 'low_confidence' and 'arrows only' in a['note']
    assert a['vs'] == '13.0 vs 12.0'


def test_accuracy_ring_drops_low_confidence_breakpoint_via_quality():
    base = _base()
    m = {'ball_speed': 12.1, 'rev_rate': 405, 'arrows_board': 12.0, 'breakpoint_board': 44.0}
    tgt = {'arrows_board': 12.0, 'breakpoint_board': 40.0}
    # breakpoint measured but low_confidence -> dropped -> arrows-only score (100 on line), low_confidence.
    q = {'arrows_board': {'status': 'ok'}, 'breakpoint_board': {'status': 'low_confidence'}}
    ring = coach.classify_throw(m, coach.baseline(base), tgt, quality=q)['rings']['accuracy']
    assert ring['value'] == 100 and ring['status'] == 'low_confidence'
    # both ok -> full DEC-031 score
    q2 = {'arrows_board': {'status': 'ok'}, 'breakpoint_board': {'status': 'ok'}}
    ring2 = coach.classify_throw(m, coach.baseline(base), tgt, quality=q2)['rings']['accuracy']
    assert ring2['status'] == 'ok' and ring2['value'] == round(0.6*100 + 0.4*coach._component_score(4.0, 8.0))


def test_lane_move_text_before_after_and_escalation():
    base = _base()
    m = {'ball_speed': 12.1, 'rev_rate': 405, 'arrows_board': 10.0}
    # measured arrows (10) + a 2-and-1 move left -> eyes to the 11 board, from 10; plus the escalation line.
    out = coach.build(m, MISS, base, recommendation={'direction': 'left', 'move_feet': 2, 'move_target': 1},
                      quality={'arrows_board': {'status': 'ok'}})
    txt = out['coach']['text']
    assert 'feet 2 boards left' in txt and 'eyes to the 11 board (from 10)' in txt
    assert 'Ball change only if it keeps missing' in txt
    # right subtracts boards: 10 -> 9
    outr = coach.build(m, MISS, base, recommendation={'direction': 'right', 'move_feet': 2, 'move_target': 1},
                       quality={'arrows_board': {'status': 'ok'}})
    assert 'eyes to the 9 board (from 10)' in outr['coach']['text']
    # arrows WITHHELD (bad geometry) -> no fabricated board, falls back to the delta phrasing + escalation
    outw = coach.build(m, MISS, base, recommendation={'direction': 'left', 'move_feet': 2, 'move_target': 1},
                       quality={'arrows_board': {'status': 'unavailable'}})
    assert 'from' not in outw['coach']['text'] and 'eyes 1 board the same way' in outw['coach']['text']
    assert 'Ball change only' in outw['coach']['text']
