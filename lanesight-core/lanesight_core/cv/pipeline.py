"""End-to-end analysis: video -> ShotRecord (+ insights, spare plan, sensor variance).
CLI: python -m lanesight_core.cv.pipeline VIDEO OUTPREFIX [--handed R|L] [--sensor sensor.json]"""
from __future__ import annotations
import os, json, pickle, argparse, time, numpy as np
from contextlib import contextmanager
from .stabilize import stabilize
from .lanes import find_lanes
from .track import extract_blobs, candidates, link, detect_impact, extend_back, extend_forward, touchdown
from .metrics import compute, lane_homography
from .refine import refine
from .pins import read_pins
from .revrate import ball_crops, rev_rate
from ..models.shot import ShotRecord, m, ALGO_VERSION
from ..insights.adjust import strike_adjustment
from ..insights.spares import spare_plan

REV_SENSOR_FACTOR = 1.12        # video lane-rpm -> Ruby-equivalent (4-shot calibration; pending blind validation)

# Far-lane metrics whose value depends on the downlane depth scale. When the plausibility gate flags the far
# lane, these are the measurements that can't be trusted (handoff B / DEC-061).
_FAR_LANE_METRICS = {'speed_late', 'breakpoint_board', 'breakpoint_distance',
                     'entry_board', 'entry_angle', 'entry_angle_52_55'}


def far_lane_quality(M, zboard):
    """Plausibility gate on the downlane depth scale (handoff B / DEC-061). A real ball LOSES speed down the
    lane and curves smoothly; a late-speed that reads faster than early, or a lateral jump of more than 3 boards
    between neighbouring samples, means the depth scale is corrupt (the close/off-axis camera the SHOT_REVIEW
    clip exposed). Returns (limited, reason). reason is a short, user-facing camera-spot nudge."""
    spot = " Set the camera behind the lane, square to it, with the whole lane from the foul line to the pins in frame."
    e, l = M.get('speed_early_mph'), M.get('speed_late_mph')
    if e and l and l > e + max(0.5, 0.03 * abs(e)):
        return True, (f"Late speed ({l:.1f} mph) reads faster than early speed ({e:.1f} mph); a ball can't speed "
                      f"up down the lane, so the far-lane read (entry board/angle, breakpoint, late speed) is "
                      f"unreliable.{spot}")
    jump = 0.0
    for (za, ba), (zb, bb) in zip(zboard, zboard[1:]):
        if ba is not None and bb is not None:
            jump = max(jump, abs(bb - ba))
    if jump > 3.0:
        return True, (f"The tracked path jumps {jump:.1f} boards between neighbouring points downlane, so the "
                      f"far-lane read is unreliable.{spot}")
    return False, None

def analyze(video, out_prefix, handed=None, intent=None, pattern=None, sensor=None, history=None, context=None, log=print,
            timing_video=None, core_end_s=None, timings=None):
    # timings: optional dict; sub-stage wall times (seconds) are recorded for profiling. No effect on results.
    _T = timings if timings is not None else {}
    @contextmanager
    def _stage(name):
        t = time.perf_counter()
        try: yield
        finally: _T[name] = round(_T.get(name, 0.0) + time.perf_counter() - t, 3)
    cache = out_prefix + '_stab.pkl'
    with _stage('stabilize_s'):
        if os.path.exists(cache): S = pickle.load(open(cache, 'rb'))
        else: S = stabilize(video, log=log, timing_path=timing_video, core_end_s=core_end_s); pickle.dump(S, open(cache, 'wb'))
    S['vp_y'] = None
    with _stage('find_lanes_s'):
        G = find_lanes(S['bg'], log=log); vp = G['vp']; S['vp_y'] = vp[1]
    bcache = out_prefix + '_blobs.pkl'
    best = None
    for lane in G['lanes']:
        with _stage('extract_blobs_s'):
            if os.path.exists(bcache) and len(G['lanes']) == 1: B = pickle.load(open(bcache, 'rb'))['B']
            else: B = extract_blobs(video, S, lane, vp, log=log)
        with _stage('link_s'):
            T = link(candidates(B, lane, vp), vp)
        span = T[-1]['u'] - T[0]['u'] if T else 0
        if best is None or span > best[0]: best = (span, lane, T, B)
    if best is None: raise RuntimeError('lane not detected: lane edges/foul line not found in the stabilized background')
    _, lane, T, B = best
    pickle.dump(dict(G=G, lane=lane, B=B), open(bcache, 'wb'))
    if len(T) < 10: raise RuntimeError('ball track not found')
    with _stage('extend_s'):
        T = extend_back(B, T, lane, log=log)
        T = extend_forward(candidates(B, lane, vp), T, lane, vp, log=log)
    with _stage('detect_impact_s'):
        t_imp, _ = detect_impact(video, S, lane, T, log=log)
    if t_imp is None: raise RuntimeError('pin impact not detected')
    ground = [c for c in T if not c.get('airborne_candidate')]
    with _stage('refine_s'):
        TR = refine(video, S, lane, ground, t_imp, log=log)
    byf = {c['i']: c for c in T if c['t'] <= t_imp + 0.02}
    for c in TR: byf[c['i']] = c
    with _stage('compute_s'):
        M = compute(sorted(byf.values(), key=lambda c: c['t']), lane, vp, t_imp, t_touch=touchdown(B, T), anchor_track=ground)
    ser = M.pop('_series')
    # Distance scale sanity: the impact anchor (the 60 ft reference) is the ball's position extrapolated to the
    # impact. If the ball was lost before the pins (occlusion or low contrast in the back half, or pin-deck
    # clutter defeating the linker), that anchor sits mid-lane and every distance is stretched. A thrown ball
    # tops out near ~22 mph, so a release speed past 30 means the scale is wrong - fail with a clear reason
    # rather than emit confidently-wrong speed/entry/angle numbers (accuracy beats coverage).
    v = M.get('ball_speed_mph')
    if v is not None and v > 30:
        raise RuntimeError(f"ball not tracked to the pins (measured {v:.0f} mph is not physically possible): the "
                           f"ball was lost in the back half of the lane, so the distance scale is unreliable. The "
                           f"lane and early line read fine, but speed/entry can't be trusted. Reshoot with the ball "
                           f"visible all the way to the pins (less glare / nothing crossing the back of the lane).")
    hand = handed or ('R' if M['right_handed'] else 'L')
    # pins
    Tp = [c for c in ground if c['t'] <= t_imp]
    from .metrics import impact_anchor
    pi = impact_anchor(Tp, t_imp, vp_y=vp[1])
    H = lane_homography(lane, vp, np.array(pi))
    with _stage('read_pins_s'):
        PR = read_pins(video, S, H, t_imp, log=log)
    # rev rate
    big = [c for c in ground if c['D'] > 32 and c['t'] <= t_imp]
    rpm, rconf, rev_note = None, 0.0, 'surface-pattern periodicity'
    rev_sigma, rev_fps = None, None                 # honest resolution band (lane rpm) + capture fps
    if len(big) >= 24:
        with _stage('rev_rate_s'):
            rpm, info = rev_rate(ball_crops(video, S, big, max_n=90))
        sc = np.sort(info['score']); rconf = float(np.clip((sc[-1] - np.median(sc)) / 0.25, 0, 1))
        if info['at_rail']:          # no clear spin period found; 60/P is the search-band edge, not a reading
            rpm, rconf, rev_note = None, 0.0, "couldn't read the ball's spin pattern (no clear repeat)"
        else:
            rev_sigma, rev_fps = info['sigma'], info['fps']
            rel = rev_sigma / rpm                   # false precision is dishonest: temper confidence by the band width
            rconf = float(rconf * np.clip(1 - rel / 0.15, 0.25, 1.0))
            rev_note = f'surface-pattern periodicity; ±{rev_sigma:.0f} rpm, frame-lag limited at {rev_fps:.0f} fps (120 fps ~halves it)'
    else:
        rev_note = f'too few ball frames to read spin ({len(big)}<24)'
    # confidences
    lat_c = float(np.clip(1 - M['lateral_res_boards'] / 1.5, 0, 1))
    speed_c = 0.9 if M['release_source'] == 'first_free_ball_detection' else 0.6
    meas = [
        m('ball_speed', M['ball_speed_mph'], 'mph', speed_c, '60 ft foul→pins average (Ruby-comparable); ball tracked to the pins via far-lane recovery'),
        m('speed_release', M.get('speed_release_mph'), 'mph', 0.6, 'release/skid front-half; robust when the back half is lost, reads ~9% low from a near-field scale residual (Specto)', status='best_effort' if M.get('speed_release_mph') is not None else None),
        m('speed_early', M['speed_early_mph'], 'mph', 0.8), m('speed_late', M['speed_late_mph'], 'mph', 0.7),
        m('loft', M['loft_ft'], 'ft', 0.6, 'touchdown unseen' if M['loft_ft'] is None else '±0.45 ft at 60 fps'),
        m('laydown_board', M.get('board_at_0ft'), 'board', lat_c if M['track_first_ft'] < 3 else 0.3),
        m('board_at_7ft', M.get('board_at_7ft'), 'board', lat_c if M['track_first_ft'] < 6 else 0.3),
        m('arrows_board', M.get('board_at_15ft'), 'board', lat_c if M['track_first_ft'] < 13 else 0.3),
        m('launch_angle', M.get('launch_angle_deg'), 'deg', 0.5 * lat_c),
        m('breakpoint_board', M['breakpoint_board'], 'board', lat_c),
        m('breakpoint_distance', M['breakpoint_extreme_ft'], 'ft', 0.5 * lat_c, 'geometric breakpoint (DEC-022)'),
        m('entry_board', M['entry_board'], 'board', lat_c), m('entry_angle', M['entry_angle_deg'], 'deg', 0.7 * lat_c),
        m('entry_angle_52_55', M.get('entry_angle_52_55_deg'), 'deg', 0.7 * lat_c, 'Specto-compatible: direction between 52 and 55 ft'),
        m('rev_rate_lane', rpm, 'rpm', rconf, rev_note, uncertainty=rev_sigma),
        m('rev_rate', rpm * REV_SENSOR_FACTOR if rpm else None, 'rpm', rconf * 0.7,
          f'sensor-equivalent ×{REV_SENSOR_FACTOR}; ±{rev_sigma * REV_SENSOR_FACTOR:.0f} rpm at {rev_fps:.0f} fps' if rpm else rev_note,
          status='calibrated_estimate' if rpm else None,
          uncertainty=rev_sigma * REV_SENSOR_FACTOR if rev_sigma is not None else None),
        m('axis_rotation', None, 'deg', 0, 'not yet measured from video'), m('axis_tilt', None, 'deg', 0, 'not yet measured from video'),
        m('pap', None, 'in', 0, 'needs grip reference (holes/marker/profile)'),
    ]
    # Plausibility gate (DEC-061): if the downlane depth scale is corrupt, keep the far-lane measurements but
    # mark them low_confidence with the reason, and flag capture_quality.far_lane = "limited" for the camera-spot
    # banner. Accuracy over coverage: a mis-calibrated entry board drives a wrong move, so it must not read 'ok'.
    cq_limited, cq_reason = far_lane_quality(M, list(zip(ser['Z'], ser['board'])))
    if cq_limited:
        for x in meas:
            if x.metric in _FAR_LANE_METRICS and x.value is not None and x.status not in ('unavailable',):
                x.status = 'low_confidence'
                x.note = (x.note + ' ' if x.note else '') + 'Far-lane read limited by camera position.'
    traj = dict(lane=[dict(t=round(a, 4), z_ft=round(z, 2), board=round(b, 2)) for a, z, b in zip(ser['t'], ser['Z'], ser['board'])],
                smoothed=[dict(z_ft=round(z, 2), board=round(b, 2)) for z, b in zip(ser['curve']['Z'], ser['curve']['board'])],
                pixel=[dict(t=round(a, 4), x=round(p[0], 1), y=round(p[1], 1)) for a, p in zip(ser['t'], ser['px'])])
    kp = dict(laydown=dict(z_ft=0, board=M.get('board_at_0ft')), arrows=dict(z_ft=15, board=M.get('board_at_15ft')),
              breakpoint=dict(z_ft=M['breakpoint_extreme_ft'], board=M['breakpoint_board']),
              entry=dict(z_ft=59.44, board=M['entry_board'], angle_deg=M['entry_angle_deg']))
    pins = None
    if PR:
        pins = {k: PR[k] for k in ('standing', 'uncertain', 'strike', 'pins_down_min', 'pins_down_max', 'confidence',
                                   'readable', 'unread_reason')}
        pins['before'] = list(range(1, 11))
    rec = ShotRecord(shot_id=(context or {}).get('shot_id', os.path.basename(out_prefix)), handed=hand,
                     video=dict(file=os.path.basename(video), fps=round(1 / np.median(np.diff(S['ts'])), 2),
                                camera_motion_px=round(float(S['shift'].max()), 1), reference_frame=int(S['ref'])),
                     events=dict(t_release=M['t_release'], t_touchdown=M.get('t_touchdown'), t_impact=t_imp,
                                 release_source=M['release_source']),
                     measurements=meas, trajectory=traj, key_points=kp, pins=pins, context=context or {},
                     capture_quality={'far_lane': 'limited' if cq_limited else 'ok',
                                      **({'reason': cq_reason} if cq_reason else {})})
    shot_view = {x.metric: x.value for x in meas}
    shot_view['trajectory'] = traj          # lets the insights gate also see lateral-jump evidence
    pins_read = pins and pins.get('readable', True)   # None standing (unread) -> leave classification stays 'unknown'
    shot_view.update(board_at_15ft=M.get('board_at_15ft'), board_at_0ft=M.get('board_at_0ft'), entry_angle_deg=M['entry_angle_deg'],
                     pins_standing=set(pins['standing']) if pins_read else None,
                     pins_uncertain=set(pins['uncertain']) if pins_read else None)
    rec.insights = strike_adjustment(shot_view, hand, intent=intent, history=history, pattern=pattern)
    if pins_read and not pins['strike']:
        rec.spare_plan = spare_plan(set(pins['standing']) | set(pins['uncertain']), hand)
    if sensor: rec.sensor = sensor_variance(rec, sensor)
    return rec

COMPARABLE = {'ball_speed': 'speed_mph', 'rev_rate': 'rev_rate_rpm', 'loft': 'loft_ft'}
NOT_COMPARABLE = {'breakpoint_distance': 'sensor breakpoint is rotational (skid→hook); LaneSight is geometric (DEC-022)'}

def sensor_variance(rec, sensor: dict):
    """sensor: normalized SensorShot dict, e.g. {'vendor':'ruby','speed_mph':17.0,'rev_rate_rpm':428,'loft_ft':1.5,
    'axis_tilt_deg':31,'axis_rotation_deg':71,'breakpoint_ft':41}"""
    out = dict(vendor=sensor.get('vendor'), compared={}, sensor_only={}, not_comparable=NOT_COMPARABLE)
    for mk, sk in COMPARABLE.items():
        v, s = rec.value(mk), sensor.get(sk)
        if v is not None and s is not None:
            out['compared'][mk] = dict(lanesight=round(v, 2), sensor=s, diff=round(v - s, 2), pct=round(100 * (v - s) / s, 1))
    # Ruby-only values video can't produce: axis geometry, PAP, and the approach/swing timing breakdown.
    for k in ('axis_tilt_deg', 'axis_rotation_deg', 'pap', 'pap_over_in', 'pap_up_in', 'breakpoint_ft',
              'skid_ft', 'hook_ft', 'roll_ft', 'swing_height_ft',
              'setup_s', 'pushaway_s', 'backswing_s', 'downswing_s', 'release_s'):
        if sensor.get(k) is not None: out['sensor_only'][k] = sensor[k]
    return out

def _json_default(o):
    if isinstance(o, (set, frozenset)): return sorted(o)
    if isinstance(o, (np.floating, np.integer)): return o.item()
    return str(o)

if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('video'); ap.add_argument('out')
    ap.add_argument('--handed'); ap.add_argument('--sensor'); ap.add_argument('--pattern-length', type=float)
    a = ap.parse_args()
    sensor = json.load(open(a.sensor)) if a.sensor else None
    rec = analyze(a.video, a.out, handed=a.handed, sensor=sensor,
                  pattern=dict(length_ft=a.pattern_length) if a.pattern_length else None)
    json.dump(rec.to_dict(), open(a.out + '_shot.json', 'w'), indent=1, default=_json_default)
    print(json.dumps({k: v['value'] for k, v in rec.to_dict()['metrics'].items()}, default=_json_default))
    print('pins', rec.pins and rec.pins['standing'], '| insight:', rec.insights['recommendations'][0]['reason'])
