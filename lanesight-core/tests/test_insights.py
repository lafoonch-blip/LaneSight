from lanesight_core.insights.reading import read_hit, read_leave, classify_shot, execution_check
from lanesight_core.insights.adjust import strike_adjustment
from lanesight_core.insights.spares import spare_plan, key_pin

def test_read_hit_rh_lh():
    assert read_hit(17.5)['hit'] == 'pocket'
    assert read_hit(20.0)['hit'] == 'high'
    assert read_hit(14.0)['hit'] == 'light'
    assert read_hit(22.0)['hit'] == 'brooklyn'
    assert read_hit(40 - 14.0, handed='L')['hit'] == 'light'

def test_leave_reads_mirror():
    assert read_leave({10})['read'] == 'weak_or_light'
    assert read_leave({7}, handed='L')['read'] == 'weak_or_light'
    assert read_leave(set())['leave'] == 'X'

def test_shot1_like_light_hit_moves_right():
    # shot 1 from the validation set: entry board 18.7, 3-6-10 leave... entry 18.7 is pocket-ish; use a light one
    r = strike_adjustment(dict(entry_board=14.5, entry_angle_deg=4.5, pins_standing={3, 6, 10}))
    m = r['recommendations'][0]
    assert r['hit']['hit'] == 'light' and m['direction'] == 'right' and m['move_feet'] == 2 * m['move_target']

def test_strike_in_pocket_no_move():
    r = strike_adjustment(dict(entry_board=17.6, entry_angle_deg=5.5, pins_standing=set()))
    assert r['recommendations'][0]['type'] == 'none'

def test_execution_miss_does_not_move():
    r = strike_adjustment(dict(entry_board=21, board_at_15ft=13.0, entry_angle_deg=5), intent=dict(arrows_board=10))
    assert r['classification'] == 'EXECUTION_MISS' and r['recommendations'][0]['move_feet'] == 0

def test_transition_needs_evidence():
    h = [dict(entry_board=17.0, classification='EXECUTED')] * 2
    r = strike_adjustment(dict(entry_board=17.5, pins_standing=set()), history=h)
    assert not any(x['type'] == 'transition' for x in r['recommendations'])
    h = [dict(entry_board=16.5, classification='EXECUTED')] * 3 + [dict(entry_board=19.5, classification='REACTION_CHANGE')] * 3
    r = strike_adjustment(dict(entry_board=20.0, pins_standing={4}), history=h)
    assert any(x['type'] == 'transition' and x['direction'] == 'left' for x in r['recommendations'])

def test_spares():
    assert key_pin({3, 6, 10}) == 3 and key_pin({7, 10}) in (7, 10) and key_pin({2, 4, 5, 8}) == 2
    p = spare_plan({10}, strike_stance=25, strike_target=10)
    assert p['straight_line']['laydown_board'] > 20 and p['system_369']['feet_board'] == 37
    assert p['ball'].startswith('spare ball')
    pl = spare_plan({7}, handed='L')
    assert pl['straight_line']['laydown_board'] < 20     # absolute boards: a lefty shoots the 7 pin from the right side

def test_strike_never_moves_unless_brooklyn():
    r = strike_adjustment(dict(entry_board=20.5, entry_angle_deg=5.5, pins_standing=set()))
    assert r['recommendations'][0]['type'] == 'none' and r['recommendations'][0]['watch'] == 'high'
    r = strike_adjustment(dict(entry_board=22.6, entry_angle_deg=5.5, pins_standing=set()))
    assert r['recommendations'][0]['type'] == 'move'

def test_pocket_light_leave_adds_angle():
    r = strike_adjustment(dict(entry_board=18.7, entry_angle_deg=4.8, pins_standing={3, 6, 10}, pins_uncertain={9}))
    rec = r['recommendations'][0]
    assert r['leave']['read'] == 'light' and r['leave']['hidden'] == [9] and rec['type'] == 'move' and rec['direction'] == 'right'
    r = strike_adjustment(dict(entry_board=17.4, entry_angle_deg=3.2, pins_standing={10}))
    assert r['recommendations'][0]['type'] == 'release'


def test_apply_move_and_suggested_target():
    from lanesight_core.insights.adjust import apply_move, suggested_target
    # high hit -> move left (toward higher boards): feet 2n, target n
    r = strike_adjustment(dict(entry_board=20.0, entry_angle_deg=5.0, pins_standing={4}))
    m = r['recommendations'][0]
    assert r['hit']['hit'] == 'high' and m['direction'] == 'left' and m['move_feet'] == 2 * m['move_target']
    st = suggested_target(r, dict(feet_board=20.0, arrows_board=15.0, breakpoint_board=8.0))
    assert st['feet_board'] == round(20.0 + m['move_feet'], 1)
    assert st['arrows_board'] == round(15.0 + m['move_target'], 1)
    assert st['breakpoint_board'] == round(8.0 + m['move_target'], 1)   # breakpoint pivots with the target
    # light hit -> move right (subtract boards); intent fields not set stay None
    rr = strike_adjustment(dict(entry_board=14.5, entry_angle_deg=4.5, pins_standing={3, 6, 10}))
    mr = rr['recommendations'][0]
    st2 = suggested_target(rr, dict(arrows_board=15.0))
    assert mr['direction'] == 'right' and st2['arrows_board'] == round(15.0 - mr['move_target'], 1)
    assert st2['feet_board'] is None and st2['breakpoint_board'] is None
    # no intent, or no actionable move -> None
    assert suggested_target(r, None) is None
    assert apply_move(dict(arrows_board=15.0), {'type': 'none'}) is None
