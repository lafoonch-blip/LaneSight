"""Form P1 contract, capture-view classifier, advisory spot check (DEC-047/045), owner reset (DEC-051)."""
from lanesight_core.form import FORM_P1, analyze_form_clip, classify_view, spot_check
from lanesight_core.owner import reset_plan, RESET_CLEAR_ORDER


# ---------------------------------------------------------------- Form P1 contract (honest unavailable)
def test_form_metrics_unavailable_without_pose_backend():
    r = analyze_form_clip('clip.mov', view='bowler_facing')
    assert r['status'] == 'unavailable' and r['view'] == 'bowler_facing'
    assert {k for k, _ in FORM_P1} == set(r['metrics'])
    for mm in r['measurements']:
        assert mm['value'] is None and mm['status'] == 'unavailable' and mm['note']   # reason given, no guess

def test_form_uses_pose_backend_when_supplied():
    def backend(video, out_prefix, handed):
        return {'swing_time': {'metric': 'swing_time', 'value': 0.46, 'unit': 's',
                               'status': 'best_effort', 'confidence': 0.6}}
    r = analyze_form_clip('clip.mov', pose_backend=backend)
    assert r['status'] == 'ok'
    assert r['metrics']['swing_time']['value'] == 0.46
    assert r['metrics']['step_count']['status'] == 'unavailable'   # not returned by backend -> unavailable


def test_classify_view():
    assert classify_view({'lane_detected': True, 'ball_track_len': 30})['view'] == 'down_lane'
    v = classify_view({'lane_detected': False, 'foreground_motion_px': 400, 'face_toward_camera': True})
    assert v['view'] == 'bowler_facing'
    assert classify_view({'lane_detected': False, 'foreground_motion_px': 10})['view'] == 'unknown'


# ---------------------------------------------------------------- Spot check (never blocks)
def test_spot_check_never_blocks_and_tips():
    assert spot_check({'lane_visible_fraction': 0.6, 'foul_line_visible': True, 'foul_line_y_frac': 0.5}) \
        == {'blocks': False, 'tips': [], 'status': 'looks_good', 'version': 'spotcheck-0.1.0'}
    far = spot_check({'lane_visible_fraction': 0.2, 'foul_line_visible': True, 'foul_line_y_frac': 0.5})
    assert far['blocks'] is False and any('Move back' in t for t in far['tips'])
    low = spot_check({'lane_visible_fraction': 0.6, 'foul_line_visible': False})
    assert low['blocks'] is False and any('foul line' in t for t in low['tips'])
    edge = spot_check({'lane_visible_fraction': 0.6, 'foul_line_visible': True, 'foul_line_y_frac': 0.95})
    assert any('Raise the phone' in t for t in edge['tips'])


# ---------------------------------------------------------------- Owner reset (DEC-051)
def test_reset_plan_archives_then_clears_fk_safe():
    p = reset_plan(['u1', 'u2'])
    assert p['archive'] == p['clear_order'] == RESET_CLEAR_ORDER
    # tier_event (child) cleared before score_snapshot (parent via snapshot_id FK)
    assert p['clear_order'].index('tier_event') < p['clear_order'].index('score_snapshot')
    assert 'achievement_definition' in p['keep'] and 'score_formula_version' in p['keep']
    assert reset_plan([])['clear_order'] == []
