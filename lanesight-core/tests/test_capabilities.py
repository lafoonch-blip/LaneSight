from lanesight_core.capabilities import capture_profile, metric_status

def P(fps, side, ball=110, motion=0, rel=True, pins=True):
    return capture_profile(fps, side, ball, motion, rel, pins)

def test_tiers():
    assert P(30, 720)['tier'] == 'base' and P(60, 1080)['tier'] == 'standard' and P(240, 1080)['tier'] == 'hfr'
    assert P(15, 1080)['tier'] == 'unsupported' and P(60, 1080, pins=False)['tier'] == 'unsupported'

def test_base_vs_standard():
    b = metric_status(P(30, 720)); s = metric_status(P(60, 1080))
    assert b['ball_speed']['status'] == 'guaranteed' and b['pin_result']['status'] == 'guaranteed'
    assert b['entry_board']['status'] == 'best_effort' and s['entry_board']['status'] == 'guaranteed'
    assert b['loft']['status'] == 'unavailable' and s['loft']['status'] == 'guaranteed'
    assert s['axis_tilt']['status'] == 'unavailable' and s['rev_rate']['status'] == 'best_effort'

def test_moving_camera_needs_60fps_for_guarantees():
    assert metric_status(P(30, 1080, motion=200))['ball_speed']['status'] == 'best_effort'
    assert metric_status(P(60, 1080, motion=200))['ball_speed']['status'] == 'guaranteed'

def test_sensor_fills_gaps():
    m = metric_status(P(60, 1080), sensor='ruby')
    assert m['axis_tilt']['status'] == 'sensor' and m['axis_tilt']['source'] == 'sensor:ruby'
    assert m['ball_speed']['sensor_compare'] == 'sensor:ruby'
    assert 'sensor_alt' in m['breakpoint_distance'] or m.get('breakpoint_sensor', {}).get('status') == 'sensor'
    f = metric_status(P(60, 1080), sensor='f5')
    assert f['track_flare']['status'] == 'sensor' and 'pap' not in [k for k, v in f.items() if v['source'].startswith('sensor')]
