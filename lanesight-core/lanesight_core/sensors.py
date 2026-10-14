"""Sensor capability registry (DEC-021). What each supported sensor adds, how its fields map to LaneSight
metrics, and which overlaps are comparable with video (variance shown) vs. different definitions.
Sources: Ruby = observed in the Ruby app (2026-10-13 screenshots); F5 = stormbowling.com/f5-bowling-sensor;
Witsee = bowlinglife.eu (2026-06-25). Vendor data access (SDK/API/export) is unverified for all three."""

# metric -> (sensor field, comparable_with_video, note)
SENSORS = {
    'ruby': dict(
        name='Ruby', placement='in-ball', data_access='unverified (app screenshots / manual entry today)',
        metrics={
            'ball_speed': ('speed_mph', True, 'timing-based; matched video within 0.5% on 3 of 4 shots'),
            'rev_rate': ('rev_rate_rpm', True, 'at release; video lane-rpm reads ~11% lower'),
            'axis_tilt': ('axis_tilt_deg', False, 'release value; video estimate not built yet'),
            'axis_rotation': ('axis_rotation_deg', False, 'release value; video estimate not built yet'),
            'pap': ('pap', False, 'over/up from grip; showed "--" until configured'),
            'loft': ('loft_ft', True, 'video touchdown method ±0.45 ft at 60 fps'),
            'breakpoint_sensor': ('breakpoint_ft', False, 'rotational skid->hook point; NOT the geometric breakpoint'),
            'skid_length': ('skid_ft', False, 'rotational phase'), 'hook_length': ('hook_ft', False, 'rotational phase'),
            'roll_length': ('roll_ft', False, 'rotational phase'),
            'swing_height': ('swing_height_ft', False, 'approach'), 'approach_time': ('approach_s', False, 'approach'),
            'pushaway_time': ('pushaway_s', False, 'approach'), 'backswing_time': ('backswing_s', False, 'approach'),
            'downswing_time': ('downswing_s', False, 'approach'), 'release_time': ('release_s', False, 'approach'),
            'setup_time': ('setup_s', False, 'approach'), 'release_score': ('release_score', False, 'vendor score'),
            'setup_hand_position': ('setup_orientation', False, 'ball orientation at setup'),
        }),
    'f5': dict(
        name='F5 (Storm)', placement='in-ball (drilled sleeve)', data_access='unverified',
        metrics={
            'ball_speed': ('release_speed_mph', False, 'RELEASE speed; video reports release->impact average, compare to speed_early instead'),
            'speed_early': ('release_speed_mph', True, 'compare against video speed at the foul line'),
            'rev_rate': ('rev_rate_rpm', True, 'at release'),
            'axis_tilt': ('axis_tilt_deg', False, ''), 'axis_rotation': ('axis_rotation_deg', False, ''),
            'track_flare': ('track_flare', False, 'sensor only'), 'rev_to_speed_ratio': ('rev_to_speed', False, 'derived'),
        }),
    'witsee': dict(
        name='Witsee', placement='in-ball (removable)', data_access='unverified',
        metrics={
            'ball_speed': ('release_speed_mph', False, 'release speed (compare to speed_early)'),
            'speed_early': ('release_speed_mph', True, ''), 'rev_rate': ('rev_rate_rpm', True, ''),
            'axis_tilt': ('axis_tilt_deg', False, ''), 'axis_rotation': ('axis_rotation_deg', False, ''),
            'swing_height': ('swing_height_ft', False, 'approach'),
        }),
}

def sensor_metrics(vendor: str) -> dict:
    return SENSORS.get(vendor.lower(), {}).get('metrics', {})

def normalize(vendor: str, raw: dict) -> dict:
    """vendor payload -> {lanesight_metric: value}"""
    return {m: raw.get(f) for m, (f, _, _) in sensor_metrics(vendor).items() if raw.get(f) is not None}
