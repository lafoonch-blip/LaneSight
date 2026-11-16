from lanesight_core.arsenal.configured import (configured_reaction, parse_layout, layout_values, surface_state,
                                               as_rankable)
from lanesight_core.arsenal.recommend import Condition, rank_for_condition

BALL = dict(manufacturer='Storm', name='Phaze II', cover_type='solid', core_type='symmetric', rg_15=2.48,
            diff_15=0.051, int_diff_15=None, factory_finish='1500 Grit Polished', ls_hook=7.0, ls_length=5.0,
            ls_backend=5.0, reaction_shape='continuous', reaction_confidence='medium')
ASYM = dict(BALL, name='Asym', core_type='asymmetric', int_diff_15=0.018)


def test_parse_layouts():
    assert parse_layout('Dual Angle', '50 x 4.5 x 40') == {'drill_angle_deg': 50, 'pin_to_pap_in': 4.5, 'val_angle_deg': 40}
    assert parse_layout('VLS', '4 x 3 3/8 x 2') == {'pin_to_pap_in': 4, 'psa_to_pap_in': 3.375, 'pin_buffer_in': 2}
    assert parse_layout('VLS', '5×4×2"') == {'pin_to_pap_in': 5, 'psa_to_pap_in': 4, 'pin_buffer_in': 2}
    assert parse_layout('Dual Angle', '45 x 3⅜ x 30')['pin_to_pap_in'] == 3.375
    assert parse_layout('Dual Angle', 'strong') == {} and parse_layout(None, '50 x 4 x 40') == {}
    # structured columns win over the string
    lv = layout_values({'layout_system': 'Dual Angle', 'layout': '50 x 4.5 x 40', 'val_angle_deg': 60})
    assert lv['val_angle_deg'] == 60 and lv['drill_angle_deg'] == 50


def test_no_config_no_surface_is_box_reaction():
    cr = configured_reaction(BALL)
    assert (cr.ls_hook, cr.ls_length, cr.ls_backend) == (7.0, 5.0, 5.0)
    assert cr.adjustments == [] and set(cr.basis.values()) == {'catalog'}
    assert any('no drilling' in n for n in cr.notes) and cr.surface_source == 'box_finish'


def test_bowler_grip_pap_flows_through_without_fabricating_reaction():
    """DEC-074/087: the bowler's grip + PAP flow into configured_reaction and surface on bowler_used, but
    change NO reaction axis (no sourced pitch/span model; PAP is already baked into the layout)."""
    cfg = {'layout_system': 'Dual Angle', 'layout': '50 x 4.5 x 40'}
    bowler = {'grip_middle_pitch_in': 0.25, 'grip_span_in': 4.5, 'pap_over_in': 5.0, 'pap_up_in': 0.5}
    base = configured_reaction(BALL, cfg)
    with_b = configured_reaction(BALL, cfg, bowler=bowler)
    # identical reaction numbers — grip/PAP do not fabricate an effect
    assert (with_b.ls_hook, with_b.ls_length, with_b.ls_backend) == (base.ls_hook, base.ls_length, base.ls_backend)
    # but the inputs are recorded + explained
    assert with_b.bowler_used == bowler
    assert any('PAP on file' in n for n in with_b.notes)
    assert any('grip (pitch/span) recorded' in n for n in with_b.notes)
    # no bowler on file → nothing added
    assert base.bowler_used is None


def test_reference_layout_changes_nothing():
    cr = configured_reaction(BALL, {'layout_system': 'Dual Angle', 'layout': '45 x 4 x 45'})
    assert (cr.ls_hook, cr.ls_length, cr.ls_backend) == (7.0, 5.0, 5.0)


def test_dual_angle_directions():
    early_smooth = configured_reaction(BALL, {'layout_system': 'Dual Angle', 'layout': '30 x 4 x 70'})
    long_snappy = configured_reaction(BALL, {'layout_system': 'Dual Angle', 'layout': '75 x 4 x 25'})
    assert early_smooth.ls_length < 5.0 < long_snappy.ls_length
    assert early_smooth.ls_backend < 5.0 < long_snappy.ls_backend
    assert early_smooth.basis['ls_length'] == 'catalog+layout'


def test_pin_to_pap_flare_peak_and_length():
    near_peak = configured_reaction(BALL, {'pin_to_pap_in': 3.5})
    short = configured_reaction(BALL, {'pin_to_pap_in': 1.5})
    long_ = configured_reaction(BALL, {'pin_to_pap_in': 6})
    assert near_peak.ls_hook >= 7.0 and short.ls_hook < 7.0 and long_.ls_hook < 7.0
    assert short.ls_length < 5.0 < long_.ls_length


def test_vls_psa_only_for_asymmetric_and_pin_buffer():
    sym = configured_reaction(BALL, {'layout_system': 'VLS', 'layout': '4 x 6 x 2'})
    asym = configured_reaction(ASYM, {'layout_system': 'VLS', 'layout': '4 x 6 x 2'})
    assert sym.ls_backend == 5.0 and any('symmetric' in n for n in sym.notes)
    assert asym.ls_backend > 5.0 and asym.ls_length > 5.0
    quick = configured_reaction(BALL, {'layout_system': 'VLS', 'layout': '4 x 4 x 1'})
    slow = configured_reaction(BALL, {'layout_system': 'VLS', 'layout': '4 x 4 x 4'})
    assert quick.ls_backend > 5.0 > slow.ls_backend


def test_pin_up_down_only_when_no_angle_given():
    up = configured_reaction(BALL, {'pin_position': 'above_fingers'})
    down = configured_reaction(BALL, {'pin_position': 'below_fingers'})
    assert up.ls_backend > 5.0 > down.ls_backend and up.ls_length == down.ls_length == 5.0
    both = configured_reaction(BALL, {'pin_position': 'above_fingers', 'val_angle_deg': 45})
    assert not any(a.variable == 'pin_position' for a in both.adjustments)


def test_surface_changes_reaction_relative_to_box():
    sanded = configured_reaction(BALL, surface_event={'grit': '500 Abralon'})
    shined = configured_reaction(BALL, surface_event={'grit_value': 4000, 'polished': True})
    same = configured_reaction(BALL, surface_event={'grit': '1500', 'polish': 'Royal Compound'})
    assert sanded.ls_length < 5.0 and sanded.ls_hook > 7.0 and sanded.ls_backend < 5.0
    assert shined.ls_length > 5.0 and shined.ls_backend > 5.0
    assert (same.ls_hook, same.ls_length) == (7.0, 5.0)
    assert sanded.surface_grit == 500 and sanded.surface_polished is False and sanded.basis['ls_length'] == 'catalog+surface'
    assert surface_state({'grit': 'Polished'}) == (None, True)


def test_low_diff_ball_responds_less_and_caps_hold():
    weak = dict(BALL, diff_15=0.012)
    strong_layout = {'layout_system': 'Dual Angle', 'layout': '90 x 6.5 x 10'}
    assert abs(configured_reaction(weak, strong_layout).ls_length - 5.0) < abs(configured_reaction(BALL, strong_layout).ls_length - 5.0)
    extreme = configured_reaction(dict(BALL, diff_15=0.060), strong_layout, {'grit_value': 30000, 'polished': True})
    assert extreme.ls_length <= 5.0 + 5.0 and 1 <= extreme.ls_backend <= 10


def test_unknown_axes_stay_none():
    cr = configured_reaction(dict(BALL, ls_hook=None), {'pin_to_pap_in': 3.5})
    assert cr.ls_hook is None and cr.ls_length is not None


def test_configured_ball_ranks_differently():
    box = dict(BALL, ls_oil='medium')
    sanded = as_rankable(box, configured_reaction(box, surface_event={'grit_value': 500}), name='Phaze II (500)')
    out = rank_for_condition([box, sanded], Condition(oil_level='heavy', pattern_length_ft=45))
    assert out['results'][0]['name'] == 'Phaze II (500)'
