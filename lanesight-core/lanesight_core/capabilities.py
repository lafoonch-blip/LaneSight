"""Capture tiers: which metrics LaneSight can guarantee for a given recording, and which a paired sensor adds.
A metric is 'guaranteed' only when the capture meets its requirements AND the metric has passed validation at
that tier; 'best_effort' when it runs but is not validated (shown with a confidence badge); else 'unavailable'.
Requirements were set from the 30/60 fps x 720/1080p degradation test (02_RESEARCH/CAPTURE_TIERS.md)."""
from __future__ import annotations
from .sensors import sensor_metrics, SENSORS

# per metric: minimum fps, minimum ball diameter (px) near the foul line, needs release visible, needs pins visible,
# tier at which it is guaranteed ('base' = any supported capture, 'hfr' = >=120 fps, None = not yet guaranteed)
REQ = {
    # metric: min_fps, min_ball_px (near foul line), release (foul-line area visible), pins (deck visible),
    #         guaranteed_at (tier where validated), built (implemented at all), note
    'ball_speed':          dict(min_fps=24, guaranteed_at='base', note='release->impact timing; MAE 0.17-0.28 mph vs Ruby at all tested tiers'),
    'trajectory_replay':   dict(min_fps=24, guaranteed_at='base', note='top-down path, key points, heatmap'),
    'laydown_board':       dict(min_fps=24, release=True, guaranteed_at='base', note='<=0.5 board vs 60 fps reference'),
    'arrows_board':        dict(min_fps=24, guaranteed_at='base', note='<=0.15 board vs 60 fps reference'),
    'breakpoint_board':    dict(min_fps=24, guaranteed_at='standard', note='0.2 board at 60fps/720p and 30fps/1080p; 0.8 at 30fps/720p'),
    'pin_result':          dict(min_fps=24, pins=True, guaranteed_at='base', note='strike/leave correct 14/14 runs; rear-hidden pins flagged'),
    'game_stats':          dict(min_fps=24, pins=True, guaranteed_at='base', note='strike/spare/conversion stats from pin reading (+manual correction)'),
    'entry_board':         dict(min_fps=24, pins=True, guaranteed_at='standard', note='0.6-0.7 board at 60fps/720p, 30fps/1080p; 1.7 at 30fps/720p'),
    'entry_angle':         dict(min_fps=24, pins=True, guaranteed_at='standard', note='0.25 deg at 60fps/720p; 0.74 at 30fps/720p'),
    'speed_profile':       dict(min_fps=24, guaranteed_at='standard', note='early/late speed; late speed off 0.7-1.4 mph below 60 fps'),
    'breakpoint_distance': dict(min_fps=24, guaranteed_at=None, note='geometric; +/-1.3-2.6 ft variation, shown as a range'),
    'launch_angle':        dict(min_fps=24, release=True, guaranteed_at=None, note='low confidence at all tiers so far'),
    'loft':                dict(min_fps=55, release=True, guaranteed_at='standard', note='touchdown needs >=60 fps (1 frame = 0.9 ft at 30 fps); MAE 0.37 ft'),
    'rev_rate':            dict(min_fps=24, min_ball_px=32, guaranteed_at=None, note='surface periodicity; within ~5-8 rpm of Ruby incl. 30 fps, but the factor was fitted on the same shots'),
    'axis_tilt':           dict(min_fps=110, guaranteed_at=None, built=False, note='planned: 120-240 fps spin-axis fit'),
    'axis_rotation':       dict(min_fps=110, guaranteed_at=None, built=False, note='planned: 120-240 fps spin-axis fit'),
    'pap':                 dict(min_fps=110, guaranteed_at=None, built=False, note='planned: finger-hole tracking at 240 fps, marker, or profile entry'),
}

TIERS = {
    'unsupported': 'below minimum: < 24 fps, ball < 20 px at the foul line, or lane/pins not in frame',
    'base': '>= 30 fps, >= 720p (ball >= 40 px at the foul line), whole lane + pins in frame',
    'standard': '>= 60 fps, >= 1080p',
    'hfr': '>= 120 fps (slo-mo), >= 1080p',
}

def capture_profile(fps: float, short_side_px: int, ball_px_at_foul: float | None, camera_motion_px: float,
                    release_visible: bool, pins_visible: bool) -> dict:
    if fps < 24 or (ball_px_at_foul is not None and ball_px_at_foul < 20) or not pins_visible:
        tier = 'unsupported'
    elif fps >= 110 and short_side_px >= 1000: tier = 'hfr'
    elif fps >= 55 and short_side_px >= 1000: tier = 'standard'
    else: tier = 'base'
    return dict(fps=fps, short_side_px=short_side_px, ball_px_at_foul=ball_px_at_foul, moving_camera=camera_motion_px > 25,
                release_visible=release_visible, pins_visible=pins_visible, tier=tier)

ORDER = {'unsupported': 0, 'base': 1, 'standard': 2, 'hfr': 3}

def metric_status(profile: dict, sensor: str | None = None) -> dict:
    """{metric: {'status': guaranteed|best_effort|unavailable|sensor, 'source': ..., 'why': ...}}"""
    out = {}
    for mname, r in REQ.items():
        why = []
        if profile['fps'] < r['min_fps']: why.append(f"needs >= {r['min_fps']} fps")
        if r.get('min_ball_px') and (profile['ball_px_at_foul'] or 0) < r['min_ball_px']: why.append(f"ball must be >= {r['min_ball_px']} px")
        if r.get('release') and not profile['release_visible']: why.append('release not visible')
        if r.get('pins') and not profile['pins_visible']: why.append('pins not visible')
        if not r.get('built', True): why.append('not yet available from video')
        if profile['tier'] == 'unsupported' or why: st = 'unavailable'
        elif r['guaranteed_at'] and ORDER[profile['tier']] >= ORDER[r['guaranteed_at']] and \
                not (profile['moving_camera'] and profile['fps'] < 55): st = 'guaranteed'   # moving camera: guarantees need >=60 fps
        else: st = 'best_effort'
        out[mname] = dict(status=st, source='lanesight_video', why='; '.join(why) or r.get('note', ''))
    if sensor:
        for mname, (field, comparable, note) in sensor_metrics(sensor).items():
            cur = out.get(mname)
            if cur is None or cur['status'] == 'unavailable':
                out[mname] = dict(status='sensor', source=f'sensor:{sensor}', why=note)
            elif comparable:
                cur['sensor_compare'] = f'sensor:{sensor}'
            else:
                cur['sensor_alt'] = dict(source=f'sensor:{sensor}', note=note)
    return out
