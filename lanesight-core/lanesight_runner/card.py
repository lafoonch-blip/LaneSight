"""Shot card + session view. Pure functions over stored rows, so user inputs (intent, hit-mark, pin
corrections, Ruby values) re-run the cheap insight rules without re-analyzing video.

Display rule: a value is shown only when the measurement exists AND the capture tier supports the metric.
Status is one of guaranteed / best_effort / unavailable (DEC-023); unavailable always carries a reason."""
from __future__ import annotations
from lanesight_core.capabilities import capture_profile, metric_status
from lanesight_core.insights.adjust import strike_adjustment
from lanesight_core.insights.spares import spare_plan
from lanesight_core.insights.reading import read_hit
from lanesight_core.insights.session import summary, consistency
from lanesight_core.cv.pipeline import COMPARABLE, NOT_COMPARABLE
from lanesight_core.power import power

# shot-record metric -> (label, unit, decimals, capability key)
DISPLAY = [
    ('ball_speed', 'Speed', 'mph', 1, 'ball_speed'),
    ('speed_late', 'Pocket speed', 'mph', 1, 'speed_profile'),
    ('rev_rate', 'Rev rate', 'rpm', 0, 'rev_rate'),
    ('loft', 'Loft', 'ft', 1, 'loft'),
    ('laydown_board', 'Laydown', 'bd', 1, 'laydown_board'),
    ('arrows_board', 'Arrows', 'bd', 1, 'arrows_board'),
    ('launch_angle', 'Launch angle', '°', 1, 'launch_angle'),
    ('breakpoint_board', 'Breakpoint', 'bd', 1, 'breakpoint_board'),
    ('breakpoint_distance', 'Breakpoint dist', 'ft', 0, 'breakpoint_distance'),
    ('entry_board', 'Entry board', 'bd', 1, 'entry_board'),
    ('entry_angle', 'Entry angle', '°', 1, 'entry_angle'),
]
SENSOR_FIELDS = ['speed_mph', 'rev_rate_rpm', 'loft_ft', 'axis_tilt_deg', 'axis_rotation_deg', 'breakpoint_ft']

def capture(rec, probe):
    fps = (probe or {}).get('measured_fps') or rec['video'].get('fps') or 0
    short = (probe or {}).get('short_side_px') or 0
    # The record has no ball pixel size. The pipeline only measures rev rate after seeing the ball at >= 32 px in
    # >= 24 frames (the same requirement capabilities.REQ['rev_rate'] checks), so a measured rev rate proves it.
    measured_rev = (rec['metrics'].get('rev_rate_lane') or {}).get('value') is not None
    prof = capture_profile(fps=fps, short_side_px=short, ball_px_at_foul=32.0 if measured_rev else None,
                           camera_motion_px=rec['video'].get('camera_motion_px') or 0,
                           release_visible=rec['events'].get('t_release') is not None, pins_visible=rec.get('pins') is not None)
    return prof, metric_status(prof)

def compact_path(trajectory, n=44):
    """Downsample the smoothed top-down path to ~n [z_ft, board] points for the lane-usage panel (the full path
    would bloat every /api/state). Returns [] when there's no path."""
    sm = (trajectory or {}).get('smoothed') or []
    pts = [[round(p['z_ft'], 1), round(p['board'], 2)] for p in sm if p.get('board') is not None]
    if len(pts) <= n: return pts
    step = len(pts) / n
    out = [pts[int(i * step)] for i in range(n)]
    if out[-1] != pts[-1]: out.append(pts[-1])
    return out

def effective_pins(shot, rec):
    p = rec.get('pins')
    if shot.get('pins_override') is not None:
        st = sorted(shot['pins_override'])
        return dict(standing=st, uncertain=[], strike=not st, source='corrected',
                    video_read=None if not p else dict(standing=p['standing'], uncertain=p['uncertain']))
    if not p: return None
    return dict(standing=p['standing'], uncertain=p['uncertain'], strike=p['strike'], source='video', confidence=p.get('confidence'),
                readable=p.get('readable', True), unread_reason=p.get('unread_reason'))

def view(rec, pins):
    mt = rec['metrics']; v = {k: x['value'] for k, x in mt.items()}
    read = pins and pins.get('standing') is not None
    v.update(board_at_15ft=v.get('arrows_board'), board_at_0ft=v.get('laydown_board'), entry_angle_deg=v.get('entry_angle'),
             pins_standing=set(pins['standing']) if read else None, pins_uncertain=set(pins['uncertain']) if read else None)
    return v

def metrics(rec, status):
    out = []
    for key, label, unit, dec, cap in DISPLAY:
        m = rec['metrics'].get(key) or {}
        st = status.get(cap, {}); val = m.get('value')
        if val is None or m.get('status') == 'unavailable':
            out.append(dict(key=key, label=label, unit=unit, value=None, status='unavailable', why=m.get('note') or 'not measured on this shot')); continue
        if st.get('status') == 'unavailable':
            out.append(dict(key=key, label=label, unit=unit, value=None, status='unavailable', why=st.get('why'))); continue
        s = st.get('status', 'best_effort'); why = st.get('why', '')
        if m.get('status') == 'low_confidence':
            s, why = 'best_effort', f"low confidence on this shot ({m.get('confidence')})"
        if m.get('status') == 'calibrated_estimate' and s == 'guaranteed':
            s = 'best_effort'
        out.append(dict(key=key, label=label, unit=unit, dec=dec, value=round(val, dec) if dec else round(val), status=s,
                        confidence=m.get('confidence'), why=why or (m.get('note') or '')))
    return out

def sensor_variance(rec, sensor):
    out = dict(compared={}, sensor_only={}, not_comparable=NOT_COMPARABLE)
    for mk, sk in COMPARABLE.items():
        v, s = rec['metrics'].get(mk, {}).get('value'), sensor.get(sk)
        if v is not None and s not in (None, ''):
            s = float(s); out['compared'][mk] = dict(lanesight=round(v, 2), sensor=s, diff=round(v - s, 2), pct=round(100 * (v - s) / s, 1) if s else None)
    for k in ('axis_tilt_deg', 'axis_rotation_deg', 'breakpoint_ft'):
        if sensor.get(k) not in (None, ''): out['sensor_only'][k] = sensor[k]
    return out

def speech(card):
    """<= ~12 words: result, then the primary move."""
    if card['status'] == 'failed': return 'Shot could not be analyzed.'
    if card['status'] != 'done': return None
    pins = card.get('pins')
    head = ('' if pins is None else 'Pins not read. ' if pins.get('standing') is None
            else 'Strike. ' if pins['strike'] else f"Left {' '.join(map(str, pins['standing']))}. ")
    if card['kind'] == 'spare':
        return 'Spare made.' if pins and pins['strike'] else (head.strip() or 'Spare result unknown.')
    recs = (card.get('insights') or {}).get('recommendations') or []
    r = recs[0] if recs else None
    if r is None or card['insights']['classification'] == 'LOW_CONFIDENCE': return head + 'No adjustment yet.'
    t = r['type']
    if t == 'move': say = f"Move {r['direction']}. Feet {r['move_feet']}, eyes {r['move_target']}."
    elif t == 'execution': say = 'Missed your mark. Repeat the line.'
    elif t == 'speed': say = 'Good line. A touch more speed.'
    elif t == 'release': say = 'Keep the line. A touch slower.'
    elif t == 'transition': say = f"Lane is changing. Move {r['direction']}."
    else: say = 'Repeat the shot.'
    return head + say

def assign_kinds(shots, recs):
    """first / spare from frame order: a non-strike first ball is followed by a spare attempt. Overrides win."""
    kinds, prev = {}, None
    for s in shots:
        if s.get('kind_override'): k = s['kind_override']
        elif prev and prev['kind'] == 'first' and prev['strike'] is False: k = 'spare'
        else: k = 'first'
        kinds[s['id']] = k
        rec = recs.get(s['id']); p = effective_pins(s, rec) if rec else None
        prev = dict(kind=k, strike=p['strike']) if p else None   # unknown result: next shot defaults to a first ball
    return kinds

def build_cards(session, shots):
    """All cards for a session, in shot order (history for lane transition needs earlier shots)."""
    recs = {s['id']: s['record'] for s in shots if s.get('record')}
    kinds = assign_kinds(shots, recs)
    cards, history = [], {}
    pattern = dict(length_ft=session['pattern_length_ft']) if session.get('pattern_length_ft') else None
    for s in shots:
        c = dict(id=s['id'], n=s['n'], status=s['status'], error=s.get('error'), kind=kinds[s['id']], ball=s.get('ball_name'),
                 ball_weight_lb=s.get('ball_weight_lb'), created_at=s['created_at'], original_name=s.get('original_name'),
                 timings=s.get('timings'), probe=s.get('probe'), intent=s.get('intent'), hit_mark=s.get('hit_mark'),
                 sensor=s.get('sensor'), rec_vote=s.get('rec_vote'), rec_note=s.get('rec_note'), rec_followed=s.get('rec_followed'),
                 pins_override=s.get('pins_override'))
        rec = recs.get(s['id'])
        if rec:
            prof, status = capture(rec, s.get('probe'))
            pins = effective_pins(s, rec)
            v = view(rec, pins)
            c.update(capture=prof, metrics=metrics(rec, status), pins=pins, handed=rec['handed'],
                     key_points=rec.get('key_points'), path=compact_path(rec.get('trajectory')))
            tilt = (s.get('sensor') or {}).get('axis_tilt_deg')              # axis tilt is Ruby-only (60 fps can't measure it)
            c['metrics'].append(dict(key='axis_tilt', label='Axis tilt', unit='°', dec=0,
                                     value=float(tilt) if tilt not in (None, '') else None,
                                     status='ruby' if tilt not in (None, '') else 'unavailable',
                                     why='From Ruby (entered). Not measurable from 60 fps video yet.' if tilt not in (None, '')
                                     else 'Needs 120+ fps; enter the Ruby value to show it.'))
            sens = s.get('sensor') or {}
            rev = sens.get('rev_rate_rpm') or v.get('rev_rate')
            pw = power(s.get('ball_weight_lb'), v.get('speed_late') if status.get('speed_profile', {}).get('status') != 'unavailable' else None,
                       float(rev) if rev not in (None, '') else None, s.get('ball_rg_in'))
            if sens.get('rev_rate_rpm'): pw['why'] += '; rev rate from Ruby'
            c['power'] = pw
            if c['kind'] == 'first':
                hist = history.setdefault(s.get('ball_name'), [])
                user_said = {'yes': 'yes', 'no': 'no'}.get(s.get('hit_mark'))
                ins = strike_adjustment(v, rec['handed'], intent=s.get('intent'), user_said=user_said, history=list(hist), pattern=pattern)
                c['insights'] = ins
                hist.append(dict(v, classification=ins['classification']))
                if pins and pins.get('standing') is not None and not pins['strike']:
                    c['spare_plan'] = spare_plan(set(pins['standing']) | set(pins['uncertain']), rec['handed'])
                c['hit'] = read_hit(v.get('entry_board'), v.get('entry_angle_deg'), rec['handed'])
            if sens and any(sens.get(k) not in (None, '') for k in SENSOR_FIELDS):
                c['sensor_variance'] = sensor_variance(rec, sens)
        c['speech'] = speech(c)
        cards.append(c)
    return cards

def _display_frame(f):
    """Roll marks for one frame: X strike, / spare, - miss, digits. Handles the 10th frame's rack resets."""
    p = [r.pins for r in f.rolls]; out = []
    g = lambda v: '-' if v == 0 else str(v)
    if f.number < 10:
        if len(p) >= 1: out.append('X' if p[0] == 10 else g(p[0]))
        if len(p) >= 2: out.append('/' if (p[0] < 10 and p[0] + p[1] == 10) else g(p[1]))
    else:
        rem = 10
        for v in p:
            if v == 10 and rem == 10: out.append('X'); rem = 10
            elif rem < 10 and v == rem: out.append('/'); rem = 10
            else: out.append(g(v)); rem = (rem - v) or 10
    return out

def game_frames(cards):
    """Ten frames built from the session's first-ball/spare order with pins down from the effective pins.
    A shot with an unknown result ends the scoreable run (the rest of the game stays blank, never guessed);
    an inconsistent sequence returns None. Each frame: {n, rolls:[marks], score:int|None, shot_ids:[...]}."""
    from lanesight_core.scoring.game import Roll, build_frames, GameError
    rolls, prev_down = [], None
    for c in cards:
        if c['status'] != 'done': break
        p = c.get('pins')
        if p is None or p.get('standing') is None: break      # unknown / unreadable result -> stop; rest stays blank
        standing = frozenset(p['standing'])
        if c['kind'] == 'first':
            down = 10 - len(standing); prev_down = down
        else:                                                 # spare: pins down = (pins left after the first ball) - (now)
            down = max(0, (10 - (prev_down or 0)) - len(standing)); prev_down = None
        rolls.append(Roll(down, standing_after=standing, shot_id=str(c['id'])))
    try:
        frames = build_frames(rolls)
    except GameError:
        return None
    return [dict(n=f.number, rolls=_display_frame(f), score=f.score,
                 shot_ids=[int(r.shot_id) for r in f.rolls if r.shot_id]) for f in frames]

def session_stats(cards, shots):
    done = [c for c in cards if c['status'] == 'done' and c.get('pins') is not None]
    first = [c for c in done if c['kind'] == 'first']; spare = [c for c in done if c['kind'] == 'spare']
    rd = lambda cs: [c for c in cs if c['pins'].get('standing') is not None]   # pins the video actually read
    first_r, spare_r = rd(first), rd(spare)                   # strike/carry rates only over read results, never guessed
    strikes = [c for c in first_r if c['pins']['strike']]
    pocket = [c for c in first if (c.get('hit') or {}).get('hit') == 'pocket']
    pocket_r = rd(pocket)
    pocket_strikes = [c for c in pocket_r if c['pins']['strike']]
    made = [c for c in spare_r if c['pins']['strike']]
    pct = lambda a, b: round(100 * len(a) / len(b)) if b else None
    recs = [s['record'] for s in shots if s.get('record')]
    pw = [c['power']['value'] for c in first if (c.get('power') or {}).get('value') is not None]
    marks = [c.get('hit_mark') for c in first]
    st = dict(shots=len(cards), analyzed=len([c for c in cards if c['status'] == 'done']), failed=len([c for c in cards if c['status'] == 'failed']),
              first_balls=len(first), strikes=len(strikes), strike_pct=pct(strikes, first_r),
              pins_unread=len(first) - len(first_r),
              pocket_hits=len(pocket), pocket_pct=pct(pocket, first), carry_pct=pct(pocket_strikes, pocket_r),
              spare_attempts=len(spare), spares_made=len(made), spare_pct=pct(made, spare_r),
              avg_power=round(sum(pw) / len(pw)) if pw else None, power_range=[min(pw), max(pw)] if pw else None,
              hit_marks=dict(yes=marks.count('yes'), no=marks.count('no'), unsure=marks.count('unsure'),
                             marked=len([m for m in marks if m])),
              averages=summary(recs) if recs else {}, consistency=consistency(recs) if len(recs) >= 3 else {})
    var = [c['sensor_variance']['compared'] for c in cards if c.get('sensor_variance')]
    agg = {}
    for k in COMPARABLE:
        d = [v[k]['diff'] for v in var if k in v]
        if d: agg[k] = dict(n=len(d), mean_diff=round(sum(d) / len(d), 2), mae=round(sum(abs(x) for x in d) / len(d), 2))
    st['sensor_variance'] = agg
    st['game'] = game_frames(cards)
    return st
