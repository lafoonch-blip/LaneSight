"""End-to-end analysis: video -> ShotRecord (+ insights, spare plan, sensor variance).
CLI: python -m lanesight_core.cv.pipeline VIDEO OUTPREFIX [--handed R|L] [--sensor sensor.json]"""
from __future__ import annotations
import os, json, pickle, argparse, time, numpy as np
from contextlib import contextmanager
from .stabilize import stabilize
from .lanes import find_lanes, classify_capture_view, foul_corners, lane_x
from .track import extract_blobs, candidates, link, detect_impact, extend_back, extend_forward, touchdown
from .metrics import compute, lane_homography
from .refine import refine
from .pins import read_pins
from .revrate import ball_crops, rev_rate
from ..models.shot import ShotRecord, m, ALGO_VERSION
from ..failures import AnalysisFailure
from ..insights.adjust import strike_adjustment, no_reliable_data_insight
from ..insights.uncertainty import quality_map
from ..insights.spares import spare_plan

# Every shot metric, as (name, unit) — used to emit an all-`unavailable` record when the capture view can't
# support lane metrics (side/approach view), so we never fabricate geometry (DEC-061 / side-view-misroute).
_METRIC_CATALOG = [
    ('ball_speed', 'mph'), ('speed_release', 'mph'), ('speed_early', 'mph'), ('speed_late', 'mph'),
    ('loft', 'ft'), ('laydown_board', 'board'), ('board_at_7ft', 'board'), ('arrows_board', 'board'),
    ('launch_angle', 'deg'), ('breakpoint_board', 'board'), ('breakpoint_distance', 'ft'),
    ('entry_board', 'board'), ('entry_angle', 'deg'), ('entry_angle_52_55', 'deg'),
    ('rev_rate_lane', 'rpm'), ('rev_rate', 'rpm'), ('axis_rotation', 'deg'), ('axis_tilt', 'deg'), ('pap', 'in'),
]


def _unsupported_view_record(video, S, view_info, context, out_prefix, handed):
    """Graceful 'no reliable data' ShotRecord for a view that can't yield lane metrics (side/approach/unknown):
    every metric `unavailable` with the camera reason, a `no_reliable_data` insight with the camera tip and no
    move, and capture_quality naming the view. Never fabricates a lane fit or a number."""
    tip = view_info['reason']
    try:
        fps = round(1 / float(np.median(np.diff(S['ts']))), 2)
    except Exception:
        fps = None
    rec = ShotRecord(
        shot_id=(context or {}).get('shot_id', os.path.basename(out_prefix)),
        handed=handed or 'R',
        video=dict(file=os.path.basename(video), fps=fps,
                   camera_motion_px=round(float(S['shift'].max()), 1) if 'shift' in S else None,
                   reference_frame=int(S['ref']) if 'ref' in S else None),
        events=dict(t_release=None, t_touchdown=None, t_impact=None, release_source=None),
        measurements=[m(name, None, unit, 0, tip) for name, unit in _METRIC_CATALOG],
        trajectory=dict(lane=[], smoothed=[], pixel=[]), key_points={}, pins=None, context=context or {},
        capture_quality={'view': view_info['view'], 'supported': False, 'far_lane': 'limited',
                         'reason': tip, 'lane_center_frac': view_info.get('lane_center_frac')})
    rec.insights = no_reliable_data_insight(tip)
    return rec

REV_SENSOR_FACTOR = 1.12        # video lane-rpm -> Ruby-equivalent (4-shot calibration; pending blind validation)

# Far-lane metrics whose value depends on the downlane depth scale. When the plausibility gate flags the far
# lane, these are the measurements that can't be trusted (handoff B / DEC-061).
_FAR_LANE_METRICS = {'speed_late', 'breakpoint_board', 'breakpoint_distance',
                     'entry_board', 'entry_angle', 'entry_angle_52_55'}
# DEC-065: the far lane is UNVALIDATED from an ordinary phone video — no held-out fiducial past ~16 ft confirms
# entry board/angle, breakpoint or back-half speed — so these stay `unavailable` (NOT an estimate), independent
# of the per-clip plausibility gate, until BOTH the pose geometry AND a real ball measurement pass the Phase-2
# camera reference (CV_PHASE2_CAMERA_VALIDATION_PROTOCOL). Flip to True ONLY when that reference passes; no
# far-lane number ships before then. (A plausibility failure is a SEPARATE, additional camera-spot reason.)
FAR_LANE_VALIDATED = False
# Every metric read off the lane geometry (depth scale + homography). When the depth scale is proven wrong
# (plausibility gate: implausible breakpoint distance), NONE of these can be trusted — they're withheld, not
# shown as measured. DEC-065: far-lane geometry is unvalidated; a broken scale makes it unavailable, not 'ok'.
_GEOMETRY_METRICS = {'entry_board', 'entry_angle', 'entry_angle_52_55', 'breakpoint_board', 'breakpoint_distance',
                     'laydown_board', 'board_at_7ft', 'arrows_board', 'launch_angle'}


def far_lane_quality(M, zboard):
    """Plausibility gate on the downlane depth scale (handoff B / DEC-061). A real ball LOSES speed down the
    lane and curves smoothly; a late-speed that reads faster than early, or a lateral jump of more than 3 boards
    between neighbouring samples, means the depth scale is corrupt (the close/off-axis camera the SHOT_REVIEW
    clip exposed). Returns (limited, reason). reason is a short, user-facing camera-spot nudge."""
    spot = " Set the camera behind the lane, square to it, with the whole lane from the foul line to the pins in frame."
    # Off-lane geometry: a board is 1 (right gutter) .. 39 (left gutter). An entry or breakpoint well off the
    # lane means the lane homography is broken (wrong VP / edges from an awkward framing) — the whole far-lane
    # read is then meaningless, so flag it rather than surface an impossible board as a move.
    for nm, v in (('entry board', M.get('entry_board')), ('breakpoint', M.get('breakpoint_board'))):
        if v is not None and not (0.0 <= v <= 40.0):
            return True, (f"The measured {nm} ({v:.0f}) is off the lane, so the lane geometry read is unreliable.{spot}")
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

def ball_speed_plausible(v, lo=8.0, hi=30.0):
    """(ok, reason) for the headline 60 ft foul→pins ball speed. A thrown ball's average lives in ~8-30 mph:
    above ~30 the ball was lost in the back half (distance scale stretched); below ~8 — or negative / non-finite —
    the release/impact time anchor is corrupt. Outside the band the number is not physical, so the caller fails
    the shot with the reason rather than surfacing a confidently-wrong speed/entry as `ok` (honesty, DEC-026/027/061)."""
    if v is not None and np.isfinite(v) and lo <= v <= hi:
        return True, None
    if v is not None and np.isfinite(v) and v > hi:
        return False, (f"ball not tracked to the pins (measured {v:.0f} mph is not physically possible): the ball "
                       f"was lost in the back half of the lane, so the distance scale is unreliable.")
    shown = f"{v:.1f} mph" if (v is not None and np.isfinite(v)) else "an invalid value"
    return False, (f"the shot timing came out implausible (measured {shown} over 60 ft): the ball's release or "
                   f"pin impact wasn't pinned down, so speed and entry can't be trusted.")


def speed_withhold_reasons(speed_release, speed_late, breakpoint_ft,
                           seg_noise=2.0, max_decel=5.0, bp_min=25.0, bp_max=55.0):
    """Internal-consistency reasons to WITHHOLD a ball speed even when it's inside the 8-30 hard band — the
    headline can still be confidently wrong when the track/geometry is internally inconsistent (wrong burst,
    compressed depth scale). A real roll decelerates monotonically, and a real breakpoint sits mid-lane. Returns
    a list of human reasons (empty = internally consistent). Pure + unit-tested; the pipeline acts on it."""
    r = []
    if speed_release is not None and speed_late is not None:
        if speed_late > speed_release + seg_noise:
            r.append(f'back-half speed {speed_late:.1f} exceeds release speed {speed_release:.1f} mph — a ball only decelerates')
        elif speed_release - speed_late > max_decel:
            r.append(f'release vs back-half speed diverge {speed_release - speed_late:.1f} mph — beyond physical deceleration')
    if breakpoint_ft is not None and not (bp_min <= breakpoint_ft <= bp_max):
        r.append(f'breakpoint distance {breakpoint_ft:.0f} ft outside the plausible {bp_min:.0f}-{bp_max:.0f} ft range — depth scale likely wrong')
    return r


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
    # Capture-view gate (side-view-misroute handoff / DEC-061): refuse a view no lane metric can come from —
    # a side/approach clip fits a lane high in the frame and would otherwise fabricate confident-wrong geometry
    # (IMG_8905). Classify from the lane geometry BEFORE any ball extraction; if no candidate lane is a valid
    # rear/down-lane view, return an honest no_reliable_data record + camera tip with zero shot metrics.
    views = [classify_capture_view(l, vp, S['bg'].shape) for l in G['lanes']]
    if views and not any(v['supported'] for v in views):
        vinfo = max(views, key=lambda v: (v.get('lane_center_frac') or 0.0))
        log(f"capture view unsupported ({vinfo['view']}, lane center {vinfo['lane_center_frac']}): refusing")
        return _unsupported_view_record(video, S, vinfo, context, out_prefix, handed)
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
    if best is None:
        raise AnalysisFailure('LANE_NOT_DETECTED',
                              'lane not detected: lane edges/foul line not found in the stabilized background',
                              stage='lane', diagnostics={'candidates_tried': len(G.get('lanes') or [])})
    _, lane, T, B = best
    # Record which lane was selected among those detected (transparency — a mounted down-lane POV between two
    # lanes can lock onto the wrong one): the chosen lane's lateral centre at the foul line + the detected count.
    _F = foul_corners(lane); _yf = float(_F[:, 1].max()); _xa, _xb = lane_x(lane, _yf)
    chosen_lane = {'center_x_px': round((_xa + _xb) / 2, 1), 'lanes_detected': len(G['lanes'])}
    pickle.dump(dict(G=G, lane=lane, B=B), open(bcache, 'wb'))
    if len(T) < 10:
        raise AnalysisFailure('BALL_TRACK_NOT_FOUND', 'ball track not found', stage='track',
                              diagnostics={'track_points': len(T), 'needed': 10})
    with _stage('extend_s'):
        T = extend_back(B, T, lane, log=log)
        T = extend_forward(candidates(B, lane, vp), T, lane, vp, log=log)
    with _stage('detect_impact_s'):
        t_imp, _ = detect_impact(video, S, lane, T, log=log)
    if t_imp is None:
        raise AnalysisFailure('PIN_IMPACT_NOT_DETECTED', 'pin impact not detected', stage='impact',
                              diagnostics={'track_points': len(T),
                                           'track_last_t': round(float(T[-1]['t']), 3) if T else None})
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
    # A reading below ~8 mph (or negative / non-finite) is the mirror image of >30: the release/impact time
    # anchor is corrupt, so the number is not physical either. Both ends fail with a clear reason (ball_speed_plausible).
    SPEED_MIN_MPH, SPEED_MAX_MPH = 8.0, 30.0
    v = M.get('ball_speed_mph')
    ok, why = ball_speed_plausible(v, SPEED_MIN_MPH, SPEED_MAX_MPH)
    if not ok:
        raise AnalysisFailure(
            'IMPOSSIBLE_SPEED_SCALE', why, stage='sanity',
            diagnostics={'measured_mph': (round(float(v), 1) if (v is not None and np.isfinite(v)) else None),
                         'plausible_mph': [SPEED_MIN_MPH, SPEED_MAX_MPH], 'track_last_ft': M.get('track_last_ft')})
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
    # Release-anchor confidence (2026-10-29): 'first_free_ball_detection' is the first ON-LANE ball, a reliable
    # RELEASE proxy ONLY when a near-lane laydown is actually anchored — the ball can be visible well before
    # release (esp. two-handed), so first-appearance ≠ release. Drop the old flat 0.9: require the laydown anchor
    # for a confident speed (the consistency gate below withholds it entirely when the track is inconsistent).
    _ffd = M['release_source'] == 'first_free_ball_detection'
    speed_c = (0.75 if M.get('board_at_0ft') is not None else 0.45) if _ffd else 0.6
    meas = [
        m('ball_speed', M['ball_speed_mph'], 'mph', speed_c, 'early-lane (release) speed, front ~4–24 ft; best effort until the DEC-065 pose solver anchors the near-lane Z-scale (today it still rides the impact-anchored 2-point homography)', status='best_effort' if M.get('ball_speed_mph') is not None else None),
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
    # Honesty gate: a speed can only be positive. A negative / non-finite segment speed (e.g. a back-half fit
    # going the wrong way) must never surface as a number — mark it unavailable with the reason. The headline
    # ball_speed is already hard-gated above, so this covers the per-segment speeds.
    for x in meas:
        if x.metric in ('ball_speed', 'speed_release', 'speed_early', 'speed_late') and x.value is not None \
           and (not np.isfinite(x.value) or x.value <= 0):
            x.value, x.status, x.confidence = None, 'unavailable', 0.0
            x.note = (x.note + ' ' if x.note else '') + 'Segment speed came out non-physical (≤0); not reported.'
    # Speed consistency gate (2026-10-29): the headline passed the 8-30 hard band but can still be confidently
    # wrong when the track/geometry is internally inconsistent. WITHHOLD the speed (unavailable + reason) on a
    # clear physical/geometry impossibility; mark it low_confidence when only the near-lane laydown anchor is
    # missing (release extrapolated). Accuracy over coverage — never surface a confidently-wrong speed.
    _SPEED_METRICS = ('ball_speed', 'speed_release', 'speed_early', 'speed_late')
    withhold = speed_withhold_reasons(M.get('speed_release_mph'), M.get('speed_late_mph'), M.get('breakpoint_extreme_ft'))
    # A breakpoint-distance reason means the DEPTH SCALE itself is wrong — then every geometry-derived metric
    # (entry board/angle, breakpoint, laydown, arrows, launch) shares the corruption and must be withheld too,
    # and the far-lane-not-read state shown (A2/DEC-065). A speed-track-only reason withholds just the speeds.
    geom_bad = any('breakpoint distance' in r for r in withhold)
    if withhold:
        why2 = 'Speed withheld — ' + '; '.join(withhold) + '.'
        for x in meas:
            if x.metric in _SPEED_METRICS:
                x.value, x.status, x.confidence = None, 'unavailable', 0.0
                x.note = why2
        if geom_bad:
            for x in meas:
                if x.metric in _GEOMETRY_METRICS and x.status != 'unavailable':
                    x.value, x.status, x.confidence = None, 'unavailable', 0.0
                    x.note = 'Lane depth scale unreliable (breakpoint distance implausible); geometry not reported.'
        log('speed consistency gate: ' + why2 + (' [geometry withheld]' if geom_bad else ''))
    elif M.get('board_at_0ft') is None:            # no near-lane laydown -> release extrapolated, trust less
        for x in meas:
            if x.metric in _SPEED_METRICS and x.value is not None and x.status not in ('unavailable',):
                x.status = 'low_confidence'
                x.confidence = min(x.confidence, 0.4)
                x.note = (x.note + ' ' if x.note else '') + 'No near-lane laydown detected; release extrapolated.'
    # Plausibility gate (DEC-061): if the downlane depth scale is corrupt, keep the far-lane measurements but
    # mark them low_confidence with the reason, and flag capture_quality.far_lane = "limited" for the camera-spot
    # banner. Accuracy over coverage: a mis-calibrated entry board drives a wrong move, so it must not read 'ok'.
    cq_limited, cq_reason = far_lane_quality(M, list(zip(ser['Z'], ser['board'])))
    if geom_bad:                                   # compromised depth scale ⇒ far-lane-not-read state (A2/A3)
        cq_limited = True
        cq_reason = cq_reason or 'The lane depth scale came out implausible, so the far-lane read (entry, breakpoint) is not reliable.'
    # DEC-065 unconditional gate: until Phase-2 validation, the far-lane metrics are not reported AT ALL
    # (unavailable, not an estimate) — regardless of whether this clip's depth scale looked plausible. A
    # plausibility/camera reason (if one fired) is kept because it's more actionable; otherwise the honest
    # reason is that the read isn't validated yet (NOT a camera-position problem — the lane may be fully framed).
    if not FAR_LANE_VALIDATED:
        cq_limited = True
        cq_reason = cq_reason or ("Back-lane metrics (entry point & angle, breakpoint, back-half speed) aren't "
                                  "validated from phone video yet, so they're not shown. Everything up to the "
                                  "arrows is measured.")
        for x in meas:
            if x.metric in _FAR_LANE_METRICS and x.status != 'unavailable':
                x.value, x.status, x.confidence = None, 'unavailable', 0.0
                x.note = (x.note + ' ' if x.note else '') + 'Far-lane metric gated until Phase-2 validation (DEC-065).'
    if cq_limited:
        for x in meas:
            if x.metric in _FAR_LANE_METRICS and x.value is not None and x.status not in ('unavailable',):
                x.status = 'low_confidence'
                x.note = (x.note + ' ' if x.note else '') + 'Far-lane read limited by camera position.'
    for x in meas:                                 # A4: never surface "-0.0" (a rounding artifact) — normalize it
        if isinstance(x.value, float) and x.value == 0.0:
            x.value = 0.0
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
                     capture_quality={'far_lane': 'limited' if cq_limited else 'ok', 'lane': chosen_lane,
                                      **({'reason': cq_reason} if cq_reason else {})})
    shot_view = {x.metric: x.value for x in meas}
    shot_view['_quality'] = quality_map(meas)   # DEC-094 §5/§6: per-metric status/uncertainty for the coaching gate
    shot_view['trajectory'] = traj          # lets the insights gate also see lateral-jump evidence
    shot_view['far_lane_limited'] = cq_limited      # the gate's verdict drives the insights state (single source)
    if cq_reason:
        shot_view['far_lane_reason'] = cq_reason
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
