"""Target-vs-actual + execution routing (DEC-049, DEC-005/006)."""
from lanesight_core.insights.routing import target_vs_actual, route_recommendation


def test_target_vs_actual_misses_and_no_mark_prompt():
    intent = {'feet_board': 20.0, 'arrows_board': 15.0, 'breakpoint_board': 8.0}
    actual = {'laydown_board': 20.0, 'arrows_board': 16.0, 'breakpoint_board': 10.0,
              'entry_board': 17.0, 'entry_angle': 5.0}
    out = target_vs_actual(intent, actual, 'R')
    assert out['misses'] == {'arrows_board': 1.0, 'breakpoint_board': 2.0}
    assert out['has_target'] is True and out['intended']['feet_board'] == 20.0
    assert out['hit']['hit'] == 'pocket'
    # classification derived without any 'did you hit your mark' input
    assert out['classification'] in ('EXECUTED', 'EXECUTION_MISS', 'REACTION_CHANGE', 'MIXED', 'NO_INTENT', 'LOW_CONFIDENCE')

def test_target_vs_actual_no_intent():
    actual = {'entry_board': 17.0, 'entry_angle': 5.0}
    out = target_vs_actual(None, actual, 'R')
    assert out['has_target'] is False and out['intended'] is None and out['misses'] == {}


def test_execution_miss_with_form_finding_routes_to_form_cue():
    lane = [{'engine': 'lane', 'type': 'move', 'reason': 'move 2 left', 'confidence': 'high'}]
    finding = {'explains_miss': True, 'cue': 'Post the shot', 'drill_ref': 'DRILL-finish',
               'reason': 'Early timing pulled it in', 'rule_id': 'RULE-early', 'rule_version': 1}
    out = route_recommendation('EXECUTION_MISS', lane, finding)
    assert out['routed_to'] == 'form' and out['primary']['engine'] == 'form'
    assert out['primary']['cue'] == 'Post the shot' and out['secondary'] is None   # no lane move

def test_execution_miss_without_form_finding_uses_lane():
    lane = [{'engine': 'lane', 'type': 'move', 'reason': 'move 2 left', 'confidence': 'high'},
            {'engine': 'lane', 'type': 'speed', 'reason': 'add speed', 'confidence': 'medium'}]
    out = route_recommendation('EXECUTION_MISS', lane, form_finding=None)
    assert out['routed_to'] == 'lane' and out['primary']['type'] == 'move'
    assert out['secondary']['type'] == 'speed'      # secondary option offered

def test_reaction_change_uses_lane_even_with_form_finding():
    lane = [{'engine': 'lane', 'type': 'move', 'reason': 'ball read early', 'confidence': 'high'}]
    finding = {'explains_miss': True, 'cue': 'x'}
    # not an execution miss -> form routing does not apply
    assert route_recommendation('REACTION_CHANGE', lane, finding)['routed_to'] == 'lane'
