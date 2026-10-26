from lanesight_core.insights.reading import read_hit, read_leave, classify_shot, execution_check
from lanesight_core.insights.adjust import strike_adjustment, far_lane_unreliable, project_breakpoint
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


def _no_move(rec):
    """A recommendation that is not an actionable line move: no feet/target shift and no off-lane breakpoint."""
    bp = rec.get('breakpoint_board')
    return (not rec.get('move_feet')) and (not rec.get('move_target')) and (bp is None or 1.0 <= bp <= 39.0)


def test_far_lane_unreliable_speed_and_lateral():
    # Primary signal: late speed faster than early speed beyond the noise band (shot 14b234c8).
    bad, why = far_lane_unreliable(dict(speed_early=15.8, speed_late=19.4))
    assert bad and why and 'speed' in why.lower()
    # Within the noise band (max(0.5 mph, 3%)) is tolerated.
    assert not far_lane_unreliable(dict(speed_early=16.0, speed_late=16.4))[0]
    # A real ball slows down -> plausible.
    assert not far_lane_unreliable(dict(speed_early=17.0, speed_late=15.5))[0]
    # Missing speeds -> no primary signal.
    assert not far_lane_unreliable(dict(entry_board=17.0))[0]
    # Secondary signal: a lateral jump >3 boards between neighbouring trajectory samples.
    traj = {'lane': [{'board': 10.0, 'z_ft': 40.0}, {'board': 14.8, 'z_ft': 42.5}, {'board': 2.0, 'z_ft': 57.0}]}
    assert far_lane_unreliable(dict(speed_early=15.0, speed_late=14.0, trajectory=traj))[0]


def test_corrupt_far_lane_shot_14b234c8_suppresses_move():
    # Regression for SHOT_REVIEW 2026-10-25 (upload 14b234c8): far-lane metrics are corrupt
    # (late speed 19.4 > early 15.8) and the deck is unreadable (pins_standing None). The engine must NOT
    # convert that into a confident move; it returns a single low-confidence "no move" rec with no off-lane
    # breakpoint. (Corrected entry/speed numbers are the separate calibration fix, not asserted here.)
    shot = dict(entry_board=10.5, entry_angle_deg=3.5, board_at_15ft=8.3, breakpoint_board=2.0,
                speed_early=15.8, speed_late=19.4, pins_standing=None)
    r = strike_adjustment(shot, handed='R')
    recs = r['recommendations']
    assert len(recs) == 1
    rec = recs[0]
    assert rec['type'] == 'none' and rec['confidence'] == 'low'
    assert all(_no_move(x) for x in recs)
    assert r['classification'] == 'LOW_CONFIDENCE'


def test_unreadable_pins_no_move_even_with_plausible_speed():
    # Pins unreadable but speeds plausible: still no line move (can't tell a strike from a miss).
    r = strike_adjustment(dict(entry_board=10.5, entry_angle_deg=3.5, speed_early=16.0, speed_late=15.0,
                               pins_standing=None), handed='R')
    rec = r['recommendations'][0]
    assert rec['type'] == 'none' and rec['confidence'] == 'low' and _no_move(rec)


def test_move_size_capped_at_3_and_2():
    # A big miss is capped at 3-and-2 for one shot; it must never emit the old feet-8/target-4 move.
    r = strike_adjustment(dict(entry_board=28.0, entry_angle_deg=5.0, pins_standing={4, 7}))
    m = r['recommendations'][0]
    assert m['type'] == 'move' and m['move_feet'] <= 3 and m['move_target'] <= 2
    assert 'boards' in m['reason'] and 'ft' not in m['reason'].split('(')[0]


def test_project_breakpoint_clamped_to_lane():
    # A straight-line projection that would land off the lane is clamped to 1..39, never 0/-1.
    bp = project_breakpoint(30.0, 5.0, 43.0, {'approach_offset_ft': 15.0, 'arrows_ft': 15.0})
    assert bp is not None and 1.0 <= bp <= 39.0


def test_normal_plausible_shot_still_moves():
    # Control: a plausible shot (late speed <= early, readable pins) still gets its normal move.
    r = strike_adjustment(dict(entry_board=14.5, entry_angle_deg=4.5, speed_early=17.0, speed_late=15.8,
                               pins_standing={3, 6, 10}))
    m = r['recommendations'][0]
    assert r['hit']['hit'] == 'light' and m['type'] == 'move' and m['direction'] == 'right'
    assert m['move_feet'] and m['move_target']


GEOM = {'approach_offset_ft': 15.0, 'arrows_ft': 15.0}


def test_state_machine_covers_every_card_state():
    # handoff C.7: insights carry an explicit `state` the app renders from.
    from lanesight_core.insights.adjust import STATES
    # no_reliable_data: far-lane gate fires (late > early)
    r = strike_adjustment(dict(entry_board=10.5, speed_early=15.8, speed_late=19.4, pins_standing=None))
    assert r['state'] == 'no_reliable_data' and r['confidence'] == 'low' and r['note']
    # pins_unknown: readable metrics but the deck couldn't be read (pins_standing None, speeds plausible)
    r = strike_adjustment(dict(entry_board=17.5, entry_angle_deg=4.5, speed_early=16.5, speed_late=15.2, pins_standing=None))
    assert r['state'] == 'pins_unknown'
    # strike_repeat: pocket strike
    r = strike_adjustment(dict(entry_board=17.6, entry_angle_deg=5.0, speed_early=17.0, speed_late=15.8, pins_standing=set()))
    assert r['state'] == 'strike_repeat'
    # execution_miss: missed the arrows by >1 board vs a set intent
    r = strike_adjustment(dict(entry_board=21, board_at_15ft=13.0, entry_angle_deg=5), intent=dict(arrows_board=10))
    assert r['state'] == 'execution_miss'
    # move: a light pocket miss with a readable leave gets a confident-enough line move
    r = strike_adjustment(dict(entry_board=14.5, entry_angle_deg=4.5, speed_early=17.0, speed_late=15.8, pins_standing={3, 6, 10}))
    assert r['state'] in ('move', 'low_confidence_move') and r['recommendations'][0]['type'] == 'move'
    assert all(s in STATES for s in [r['state']])


def test_far_lane_limited_flag_forces_no_reliable_data():
    # When the CV plausibility gate flags the far lane (e.g. off-lane entry from broken geometry), the insights
    # state must be no_reliable_data — never a move — even if speeds look monotonic.
    r = strike_adjustment(dict(entry_board=45.6, speed_early=22.0, speed_late=22.0,
                               far_lane_limited=True, far_lane_reason='off lane', pins_standing=None))
    assert r['state'] == 'no_reliable_data' and r['recommendations'][0]['type'] == 'none'


def test_big_move_needs_two_agreeing_shots():
    # A single big miss stays capped at 2-and-1 (handoff C.5)...
    r = strike_adjustment(dict(entry_board=28.0, entry_angle_deg=5.0, speed_early=17.0, speed_late=15.5, pins_standing={4, 7}))
    m = r['recommendations'][0]
    assert (m['move_feet'], m['move_target']) == (2, 1)
    # ...but with 2+ earlier shots missing the same (high) side, a 3-and-2 is allowed.
    hist = [dict(entry_board=24.0, classification='NO_INTENT'), dict(entry_board=25.0, classification='NO_INTENT')]
    r = strike_adjustment(dict(entry_board=28.0, entry_angle_deg=5.0, speed_early=17.0, speed_late=15.5, pins_standing={4, 7}),
                          history=hist)
    m = r['recommendations'][0]
    assert (m['move_feet'], m['move_target']) == (3, 2)


def test_apply_move_separate_deltas_and_derived_breakpoint():
    from lanesight_core.insights.adjust import apply_move, suggested_target, project_breakpoint
    # feet and arrows carry SEPARATE whole-board deltas; the breakpoint is PROJECTED, not shifted by target.
    # 2-and-1 left
    st = apply_move(dict(feet_board=20.0, arrows_board=15.0, breakpoint_board=10.0),
                    dict(direction='left', move_feet=2, move_target=1), geometry=GEOM, breakpoint_ft=43.0)
    assert (st['feet_board'], st['arrows_board']) == (22.0, 16.0)        # +2 feet, +1 arrows (separate)
    assert st['breakpoint_board'] == 10.0                                # 16 + (-6/30)*28 = 10.4 -> 10
    # 3-and-2 right
    st = apply_move(dict(feet_board=22.0, arrows_board=16.0, breakpoint_board=11.0),
                    dict(direction='right', move_feet=3, move_target=2), geometry=GEOM, breakpoint_ft=43.0)
    assert (st['feet_board'], st['arrows_board']) == (19.0, 14.0)        # -3 feet, -2 arrows (separate)
    assert st['breakpoint_board'] == 9.0                                 # 14 + (-5/30)*28 = 9.33 -> 9
    # parallel move (equal deltas): the whole sight line translates, so the breakpoint translates the same
    base = dict(feet_board=20.0, arrows_board=15.0, breakpoint_board=10.0)
    st = apply_move(base, dict(direction='left', move_feet=2, move_target=2), geometry=GEOM, breakpoint_ft=43.0)
    assert (st['feet_board'], st['arrows_board']) == (22.0, 17.0)
    assert st['breakpoint_board'] - project_breakpoint(20.0, 15.0, 43.0, GEOM) == 2.0
    # without geometry/breakpoint distance the breakpoint stays None; feet/arrows still move
    st = apply_move(base, dict(direction='left', move_feet=2, move_target=1))
    assert (st['feet_board'], st['arrows_board'], st['breakpoint_board']) == (22.0, 16.0, None)
    # integration: engine emits separate feet/arrows deltas; suggested_target threads the geometry through
    r = strike_adjustment(dict(entry_board=20.0, entry_angle_deg=5.0, pins_standing={4}))
    m = r['recommendations'][0]
    assert m['direction'] == 'left' and m['move_feet'] == 2 * m['move_target']
    sg = suggested_target(r, dict(feet_board=20.0, arrows_board=15.0, breakpoint_board=10.0),
                          geometry=GEOM, breakpoint_ft=43.0)
    assert sg['feet_board'] == 20.0 + m['move_feet'] and sg['arrows_board'] == 15.0 + m['move_target']
    assert sg['breakpoint_board'] is not None
    assert suggested_target(r, None) is None
    assert apply_move(dict(arrows_board=15.0), {'type': 'none'}) is None
