"""End-to-end analysis: video -> ShotRecord (+ insights, spare plan, sensor variance).
CLI: python -m lanesight_core.cv.pipeline VIDEO OUTPREFIX [--handed R|L] [--sensor sensor.json]"""
from __future__ import annotations
import os, json, pickle, argparse, numpy as np
from .stabilize import stabilize
from .lanes import find_lanes
from .track import extract_blobs, candidates, link, detect_impact, extend_back, touchdown
from .metrics import compute, lane_homography
from .refine import refine
from .pins import read_pins
from .revrate import ball_crops, rev_rate
from ..models.shot import ShotRecord, m, ALGO_VERSION
from ..insights.adjust import strike_adjustment
from ..insights.spares import spare_plan

REV_SENSOR_FACTOR = 1.12        # video lane-rpm -> Ruby-equivalent (4-shot calibration; pending blind validation)

def analyze(video, out_prefix, handed=None, intent=None, pattern=None, sensor=None, history=None, context=None, log=print,
            timing_video=None):
    cache = out_prefix + '_stab.pkl'
    if os.path.exists(cache): S = pickle.load(open(cache, 'rb'))
    else: S = stabilize(video, log=log, timing_path=timing_video); pickle.dump(S, open(cache, 'wb'))
    S['vp_y'] = None
    G = find_lanes(S['bg'], log=log); vp = G['vp']; S['vp_y'] = vp[1]
    bcache = out_prefix + '_blobs.pkl'
    best = None
    for lane in G['lanes']:
        if os.path.exists(bcache) and len(G['lanes']) == 1: B = pickle.load(open(bcache, 'rb'))['B']
        else: B = extract_blobs(video, S, lane, vp, log=log)
        T = link(candidates(B, lane, vp), vp)
        span = T[-1]['u'] - T[0]['u'] if T else 0
        if best is None or span > best[0]: best = (span, lane, T, B)
    if best is None: raise RuntimeError('lane not detected: lane edges/foul line not found in the stabilized background')
    _, lane, T, B = best
    pickle.dump(dict(G=G, lane=lane, B=B), open(bcache, 'wb'))
    if len(T) < 10: raise RuntimeError('ball track not found')
    T = extend_back(B, T, lane, log=log)
    t_imp, _ = detect_impact(video, S, lane, T, log=log)
    if t_imp is None: raise RuntimeError('pin impact not detected')
    ground = [c for c in T if not c.get('airborne_candidate')]
    TR = refine(video, S, lane, ground, t_imp, log=log)
    byf = {c['i']: c for c in T if c['t'] <= t_imp + 0.02}
    for c in TR: byf[c['i']] = c
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
    PR = read_pins(video, S, H, t_imp, log=log)
    # rev rate
    big = [c for c in ground if c['D'] > 32 and c['t'] <= t_imp]
    rpm, rconf = None, 0.0
    if len(big) >= 24:
        rpm, info = rev_rate(ball_crops(video, S, big, max_n=90))
        sc = np.sort(info['score']); rconf = float(np.clip((sc[-1] - np.median(sc)) / 0.25, 0, 1))
    # confidences
    lat_c = float(np.clip(1 - M['lateral_res_boards'] / 1.5, 0, 1))
    speed_c = 0.9 if M['release_source'] == 'first_free_ball_detection' else 0.6
    meas = [
        m('ball_speed', M['ball_speed_mph'], 'mph', speed_c, 'release→impact, 60 ft (Ruby-comparable)'),
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
        m('rev_rate_lane', rpm, 'rpm', rconf, 'surface-pattern periodicity'),
        m('rev_rate', rpm * REV_SENSOR_FACTOR if rpm else None, 'rpm', rconf * 0.7, f'sensor-equivalent ×{REV_SENSOR_FACTOR}',
          status='calibrated_estimate' if rpm else None),
        m('axis_rotation', None, 'deg', 0, 'not yet measured from video'), m('axis_tilt', None, 'deg', 0, 'not yet measured from video'),
        m('pap', None, 'in', 0, 'needs grip reference (holes/marker/profile)'),
    ]
    traj = dict(lane=[dict(t=round(a, 4), z_ft=round(z, 2), board=round(b, 2)) for a, z, b in zip(ser['t'], ser['Z'], ser['board'])],
                smoothed=[dict(z_ft=round(z, 2), board=round(b, 2)) for z, b in zip(ser['curve']['Z'], ser['curve']['board'])],
                pixel=[dict(t=round(a, 4), x=round(p[0], 1), y=round(p[1], 1)) for a, p in zip(ser['t'], ser['px'])])
    kp = dict(laydown=dict(z_ft=0, board=M.get('board_at_0ft')), arrows=dict(z_ft=15, board=M.get('board_at_15ft')),
              breakpoint=dict(z_ft=M['breakpoint_extreme_ft'], board=M['breakpoint_board']),
              entry=dict(z_ft=59.44, board=M['entry_board'], angle_deg=M['entry_angle_deg']))
    pins = None
    if PR:
        pins = {k: PR[k] for k in ('standing', 'uncertain', 'strike', 'pins_down_min', 'pins_down_max', 'confidence')}
        pins['before'] = list(range(1, 11))
    rec = ShotRecord(shot_id=(context or {}).get('shot_id', os.path.basename(out_prefix)), handed=hand,
                     video=dict(file=os.path.basename(video), fps=round(1 / np.median(np.diff(S['ts'])), 2),
                                camera_motion_px=round(float(S['shift'].max()), 1), reference_frame=int(S['ref'])),
                     events=dict(t_release=M['t_release'], t_touchdown=M.get('t_touchdown'), t_impact=t_imp,
                                 release_source=M['release_source']),
                     measurements=meas, trajectory=traj, key_points=kp, pins=pins, context=context or {})
    shot_view = {x.metric: x.value for x in meas}
    shot_view.update(board_at_15ft=M.get('board_at_15ft'), board_at_0ft=M.get('board_at_0ft'), entry_angle_deg=M['entry_angle_deg'],
                     pins_standing=set(pins['standing']) if pins else None, pins_uncertain=set(pins['uncertain']) if pins else None)
    rec.insights = strike_adjustment(shot_view, hand, intent=intent, history=history, pattern=pattern)
    if pins and not pins['strike']:
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
    for k in ('axis_tilt_deg', 'axis_rotation_deg', 'pap', 'breakpoint_ft', 'skid_ft', 'hook_ft', 'roll_ft'):
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
