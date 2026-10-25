"""Form fundamentals v1 (DEC-057, FORM_BENCHMARKS §0) — the pure decision/geometry layer.

Everything here is Shayne's owner-rule fundamentals turned into honest, measured output:

  * ``timing_checkpoints`` — T1 pushaway, T2 ball-start step, T3 backswing apex, T4 leverage window, each with
    an early / on-time / late verdict and the measured offset, judged against owner windows
    (ENGINE_CONFIG ``form_timing_windows``). Anything the events/view can't support is ``unavailable`` with a
    reason — never a guessed verdict.
  * ``measured_positions`` — M1..M7 (foul-line distance, spine tilt + consistency, balance arm, shoulder tilt,
    follow-through, finish hold, pendulum proxy), computed from the pose landmarks where the geometry is
    resolvable, else ``unavailable`` with the view/calibration reason.
  * ``gate_positions`` — downgrades a measured position to ``unavailable`` when the actual capture view can't
    support it (e.g. forward spine tilt needs a side view; it is not resolvable from a rear/front clip).
  * ``coaching_cues`` — the §0.3 hand/wrist cues as text only (phone video can't measure them yet).
  * ``swing_timing`` — this delivery's phase splits vs the bowler's Profile baseline (entered or "use my
    average"), per phase; honest ``building`` when no baseline is set.

No fabricated numbers: a value that isn't measurable is value=None, status='unavailable', with the reason
(DEC-026 / DEC-042). Hand/wrist rules are coaching cues only, never a measured result (DEC-057).
"""
from __future__ import annotations
import math
from dataclasses import asdict
import numpy as np

from ..models.shot import Measurement
from . import pose as _p

_SRC = 'lanesight_form'
FUNDAMENTALS_VERSION = 'form-fundamentals-0.1.0'

# Provisional owner windows (FORM_BENCHMARKS §0.1). Used only when the store supplies none; the live values
# come from ENGINE_CONFIG ``form_timing_windows`` (rules_seed / migration 015) so Shayne can tune them.
DEFAULT_TIMING_WINDOWS = {
    'T1': {'unit': 'in', 'low': -1.0, 'high': 1.0},     # ±1 in of the ball-side thigh line
    'T2': {'unit': 'step', 'low': 0.0, 'high': 0.0},    # exact step
    'T3': {'unit': 's', 'low': -0.05, 'high': 0.05},    # ±0.05 s around the slide start
    'T4': {'unit': 's', 'low': 0.0, 'high': 0.10},      # 0 → +0.10 s after the slide foot stops
    'provisional': True,
}


# --------------------------------------------------------------------------- measurement builders
def _pos(mid, metric, value, unit, conf, status, note=None, display=None, view_required=None, extra=None):
    d = asdict(Measurement(metric, None if value is None else round(float(value), 2), unit,
                           round(float(conf), 2), status, source=_SRC,
                           algorithm_version=FUNDAMENTALS_VERSION, note=note))
    d['id'] = mid
    d['display'] = display
    d['view_required'] = view_required
    if extra:
        d.update(extra)
    return d


def _unavail_pos(mid, metric, unit, reason, view_required=None):
    return _pos(mid, metric, None, unit, 0.0, 'unavailable', note=reason, display='—',
                view_required=view_required)


# --------------------------------------------------------------------------- geometry helpers
def _side_indices(handed):
    """Bowling-side vs balance-side landmark indices. RH bowler => right arm bowls, left arm balances,
    left foot slides; LH mirrors."""
    if str(handed or 'R').strip().upper().startswith('L'):
        return dict(bowl_sh=_p.L_SHOULDER, bowl_wr=_p.L_WRIST, off_sh=_p.R_SHOULDER, off_wr=_p.R_WRIST)
    return dict(bowl_sh=_p.R_SHOULDER, bowl_wr=_p.R_WRIST, off_sh=_p.L_SHOULDER, off_wr=_p.L_WRIST)


def _idx_at(t, ev):
    if ev is None or t is None or len(t) == 0:
        return None
    return int(np.argmin(np.abs(np.asarray(t) - float(ev))))


def _pt(lms, k, idx):
    """(x, y) of one landmark at frame k, or None if missing / not visible."""
    if k is None:
        return None
    x, y, vis = lms[k, idx, 0], lms[k, idx, 1], lms[k, idx, 3]
    if np.isnan(x) or np.isnan(y) or vis < _p.MIN_VIS:
        return None
    return float(x), float(y)


def _mid(a, b):
    if a is None or b is None:
        return None
    return ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)


def _angle_from_vertical(top, bottom):
    """Degrees the (bottom->top) segment leans away from straight-up. 0 = upright."""
    if top is None or bottom is None:
        return None
    dx = top[0] - bottom[0]
    dy = bottom[1] - top[1]            # image y grows downward; up = positive dy
    if dx == 0 and dy == 0:
        return None
    return abs(math.degrees(math.atan2(dx, dy)))


def _angle_from_horizontal(left, right):
    if left is None or right is None:
        return None
    dx = right[0] - left[0]
    dy = right[1] - left[1]
    if dx == 0 and dy == 0:
        return None
    return math.degrees(math.atan2(dy, dx))


def _angle_between(center, a, b):
    """Angle a-center-b in degrees."""
    if center is None or a is None or b is None:
        return None
    v1 = (a[0] - center[0], a[1] - center[1])
    v2 = (b[0] - center[0], b[1] - center[1])
    n1 = math.hypot(*v1)
    n2 = math.hypot(*v2)
    if n1 < 1e-6 or n2 < 1e-6:
        return None
    cos = max(-1.0, min(1.0, (v1[0] * v2[0] + v1[1] * v2[1]) / (n1 * n2)))
    return math.degrees(math.acos(cos))


# --------------------------------------------------------------------------- measured positions (M1–M7)
# Which capture views each position can be measured from. 'unknown' is handled specially in gate_positions.
POSITION_VIEWS = {
    'spine_tilt': {'down_lane'},                        # forward (sagittal) lean needs a side profile
    'balance_arm': {'rear', 'bowler_facing'},           # frontal-plane abduction
    'shoulder_tilt': {'rear', 'bowler_facing'},         # frontal-plane shoulder line
    'follow_through': {'down_lane', 'rear', 'bowler_facing', 'unknown'},
    'finish_hold': {'down_lane', 'rear', 'bowler_facing', 'unknown'},
    'pendulum': {'down_lane', 'rear', 'bowler_facing', 'unknown'},
    'foul_line_distance': set(),                        # never — no floor-plane calibration on this framing
}
_FOUL_LINE_REASON = ('needs foul-line detection with floor-plane scale — not calibrated on this framing '
                     '(same unresolved homography as drift/slide length; TRAINING_VIDEOS_CALIBRATED_METRICS)')
_SPINE_FWD_NOTE = ('absolute forward tilt needs a side view; from a rear/front clip this is a provisional '
                   'frontal-plane tilt only')


def measured_positions(t, lms, events, torso, handed, metrics):
    """M1–M7 from the pose landmarks at the located events. View-agnostic geometry here; gate_positions()
    applies the capture-view rules. Every entry is a Measurement-dict with id/display/view_required.
    `metrics` is the pose FORM_P1 dict (used to surface the already-measured finish_hold as M6)."""
    si = _side_indices(handed)
    E7 = events.get('E7')
    k7 = _idx_at(t, E7)
    out = {}

    # M1 foul-line distance (E8): no floor scale -> honest unavailable
    out['foul_line_distance'] = _unavail_pos('M1', 'foul_line_distance', 'inch', _FOUL_LINE_REASON,
                                             view_required='rear/side + floor scale')

    # M2 spine tilt at release + consistency across the approach
    sh = _mid(_pt(lms, k7, _p.L_SHOULDER), _pt(lms, k7, _p.R_SHOULDER))
    hp = _mid(_pt(lms, k7, _p.L_HIP), _pt(lms, k7, _p.R_HIP))
    tilt7 = _angle_from_vertical(sh, hp)
    if tilt7 is None:
        out['spine_tilt'] = _unavail_pos('M2', 'spine_tilt', 'deg',
                                         'torso landmarks not visible at release', view_required='side')
    else:
        # sample the tilt from ball-start to release to judge "steady vs rising into release"
        E2 = events.get('E2')
        series = []
        if E2 is not None and t is not None:
            m = (np.asarray(t) >= float(E2)) & (np.asarray(t) <= float(E7))
            for k in np.where(m)[0]:
                a = _angle_from_vertical(
                    _mid(_pt(lms, int(k), _p.L_SHOULDER), _pt(lms, int(k), _p.R_SHOULDER)),
                    _mid(_pt(lms, int(k), _p.L_HIP), _pt(lms, int(k), _p.R_HIP)))
                if a is not None:
                    series.append(a)
        sd = float(np.std(series)) if len(series) >= 3 else None
        rise = (tilt7 - float(np.mean(series))) if series else None
        steady = None if rise is None else bool(rise <= 5.0)        # >5° lift into release is the flag (§0.2)
        disp = f'{tilt7:.0f}°' + ('' if steady is None else (' · steady' if steady else ' · rising'))
        out['spine_tilt'] = _pos('M2', 'spine_tilt', tilt7, 'deg', 0.5, 'best_effort',
                                 note='torso angle from vertical at release (target 15–30°, steady). '
                                      + _SPINE_FWD_NOTE,
                                 display=disp, view_required='side',
                                 extra={'consistency_sd': None if sd is None else round(sd, 2),
                                        'rise_deg': None if rise is None else round(rise, 1),
                                        'steady': steady})

    # M3 balance (off) arm abduction at release
    off_sh = _pt(lms, k7, si['off_sh'])
    off_wr = _pt(lms, k7, si['off_wr'])
    down = None if off_sh is None else (off_sh[0], off_sh[1] + 0.2)      # a straight-down reference from the shoulder
    abd = _angle_between(off_sh, off_wr, down)
    if abd is None:
        out['balance_arm'] = _unavail_pos('M3', 'balance_arm', 'deg',
                                          'non-bowling arm not visible at release', view_required='front/rear')
    else:
        out['balance_arm'] = _pos('M3', 'balance_arm', abd, 'deg', 0.5, 'best_effort',
                                  note='off-arm abduction from the body at release (target ~90° out to the side)',
                                  display=f'{abd:.0f}° out', view_required='front/rear')

    # M4 shoulder-line tilt at release
    lsh = _pt(lms, k7, _p.L_SHOULDER)
    rsh = _pt(lms, k7, _p.R_SHOULDER)
    stilt = _angle_from_horizontal(lsh, rsh)
    if stilt is None:
        out['shoulder_tilt'] = _unavail_pos('M4', 'shoulder_tilt', 'deg',
                                            'shoulders not visible at release', view_required='front/rear')
    else:
        bowl_lower = None
        if lsh is not None and rsh is not None:
            bowling_is_right = not str(handed or 'R').strip().upper().startswith('L')
            bowl_sh_y = rsh[1] if bowling_is_right else lsh[1]
            off_sh_y = lsh[1] if bowling_is_right else rsh[1]
            bowl_lower = bool(bowl_sh_y > off_sh_y)      # larger image-y = physically lower
        disp = f'{abs(stilt):.0f}°' + ('' if bowl_lower is None
                                       else (' · bowling lower' if bowl_lower else ' · bowling higher'))
        out['shoulder_tilt'] = _pos('M4', 'shoulder_tilt', abs(stilt), 'deg', 0.5, 'best_effort',
                                    note='shoulder-line tilt at release (bowling shoulder slightly lower; '
                                         'chest rotation needs rear/overhead — not measured)',
                                    display=disp, view_required='front/rear',
                                    extra={'bowling_shoulder_lower': bowl_lower})

    # M5 follow-through: bowling-wrist height vs head after release
    hold_end = events.get('hold_end')
    disp = None
    val = None
    if E7 is not None and t is not None:
        tt = np.asarray(t)
        hi = float(hold_end) if hold_end is not None else float(E7) + 0.6
        m = (tt >= float(E7)) & (tt <= hi)
        best = None          # highest wrist (smallest y)
        headref = None
        for k in np.where(m)[0]:
            wr = _pt(lms, int(k), si['bowl_wr'])
            nose = _pt(lms, int(k), _p.NOSE)
            if wr is None:
                continue
            if best is None or wr[1] < best[1]:
                best = wr
                headref = nose
        if best is not None and headref is not None and torso and torso > 1e-6:
            val = (headref[1] - best[1]) / torso        # torso lengths the wrist finishes above the head (+up)
            if val >= 0.0:
                disp = 'Up to ear'
            elif val >= -0.5:
                disp = 'To shoulder'
            else:
                disp = 'Low'
    if disp is None:
        out['follow_through'] = _unavail_pos('M5', 'follow_through', 'ratio',
                                             'bowling wrist / head not visible through the follow-through',
                                             view_required='side/front')
    else:
        out['follow_through'] = _pos('M5', 'follow_through', val, 'ratio', 0.5, 'best_effort',
                                     note='bowling-wrist peak height vs head after release ("answer the phone"), '
                                          'torso lengths (+ above head)',
                                     display=disp, view_required='side/front')

    # M6 finish hold — already measured in the P1 set; surface it as a position
    fh = (metrics or {}).get('finish_hold') or {}
    if fh.get('value') is not None and fh.get('status') in ('ok', 'best_effort'):
        out['finish_hold'] = _pos('M6', 'finish_hold', fh['value'], 's', fh.get('confidence', 0.6),
                                  fh.get('status', 'best_effort'),
                                  note='hold at the line after release (E8→E9); target is an owner setting '
                                       '(start ≥ 2.5 s ≈ ball travel time)',
                                  display=f'{fh["value"]:.1f} s', view_required='any')
    else:
        out['finish_hold'] = _unavail_pos('M6', 'finish_hold', 's',
                                          fh.get('note') or 'finish hold not measured', view_required='any')

    # M7 pendulum swing — proxy only (downswing time); baseline / T4 context are added by the engine
    dsw = (metrics or {}).get('downswing_time') or {}
    if dsw.get('value') is not None and dsw.get('status') in ('ok', 'best_effort'):
        out['pendulum'] = _pos('M7', 'pendulum', dsw['value'], 's', 0.4, 'best_effort',
                               note='proxy only: downswing time vs your baseline and the T4 leverage window. '
                                    'No direct "muscling" metric from phone video.',
                               display=f'downswing {dsw["value"]:.2f} s', view_required='side')
    else:
        out['pendulum'] = _unavail_pos('M7', 'pendulum', 's',
                                       'downswing time not measured (needed for the pendulum proxy)',
                                       view_required='side')
    return out


def gate_positions(positions, view):
    """Downgrade a measured position to unavailable when the actual capture view can't support it. 'unknown'
    keeps frontal/vertical positions as best_effort with a caveat, but still refuses the sagittal spine tilt
    (you cannot claim a forward-lean angle without a side view)."""
    view = view if view in _p_views() else 'unknown'
    for key, p in (positions or {}).items():
        if p.get('status') == 'unavailable':
            continue
        req = POSITION_VIEWS.get(key)
        if req is None:
            continue
        if view == 'unknown':
            if key == 'spine_tilt':
                positions[key] = _unavail_pos(p.get('id'), key, p.get('unit', ''),
                                              'forward spine tilt needs a confirmed side view', 'side')
            else:
                note = (p.get('note') or '')
                p['note'] = (note + ' | capture view not confirmed — treat as provisional.').strip(' |')
            continue
        if view not in req:
            label = p.get('view_required') or ('/'.join(sorted(req)) if req else 'a different')
            positions[key] = _unavail_pos(p.get('id'), key, p.get('unit', ''),
                                          f'needs a {label} view (this clip is {view})',
                                          p.get('view_required'))
    return positions


def _p_views():
    from .analyze import VIEWS
    return VIEWS


# --------------------------------------------------------------------------- timing checkpoints (T1–T4)
def _verdict(off, low, high):
    if off is None:
        return None
    if off < low:
        return 'early'
    if off > high:
        return 'late'
    return 'on_time'


def _bar_pos(off, low, high):
    """Normalized 0..1 marker position for the early/on-time/late bar: the on-time band maps to [0.4, 0.6]."""
    if off is None:
        return None
    width = (high - low) or 1.0
    center = (low + high) / 2.0
    pos = 0.5 + ((off - center) / width) * 0.2
    return round(max(0.05, min(0.95, pos)), 3)


def _measured_val(metrics, key):
    m = (metrics or {}).get(key) or {}
    if m.get('value') is None or m.get('status') not in ('ok', 'best_effort', 'low_confidence'):
        return None
    return m['value']


def timing_checkpoints(record, windows=None, approach_steps=None):
    """T1–T4 with early/on-time/late verdicts + measured offsets, judged against the owner windows.
    Pure: reads record['events'] + record['metrics']; anything missing is unavailable with a reason."""
    w = dict(DEFAULT_TIMING_WINDOWS)
    if windows:
        w.update({k: v for k, v in windows.items() if k in ('T1', 'T2', 'T3', 'T4', 'provisional')})
    events = record.get('events') or {}
    metrics = record.get('metrics') or {}
    provisional = bool(w.get('provisional', True))
    out = {}

    def entry(cid, label, phase, unit, offset, win, detail, note=None, status='ok'):
        low, high = win.get('low'), win.get('high')
        v = _verdict(offset, low, high) if offset is not None else None
        return {'id': cid, 'label': label, 'phase': phase, 'unit': unit,
                'offset': None if offset is None else round(float(offset), 3),
                'verdict': v, 'status': status if offset is not None else 'unavailable',
                'bar_pos': _bar_pos(offset, low, high) if offset is not None else None,
                'window': {'low': low, 'high': high}, 'provisional': provisional,
                'detail': detail, 'note': note}

    # T1 pushaway — fore-aft ball-vs-thigh: not resolvable without a side view + horizontal scale
    out['T1'] = {'id': 'T1', 'label': 'Pushaway', 'phase': 'P2', 'unit': w['T1'].get('unit', 'in'),
                 'offset': None, 'verdict': None, 'status': 'unavailable', 'bar_pos': None,
                 'window': {'low': w['T1'].get('low'), 'high': w['T1'].get('high')},
                 'provisional': provisional, 'detail': '—',
                 'note': ('ball-vs-thigh fore-aft position needs a side view with horizontal scale — not '
                          'resolvable on this framing')}

    # T2 ball-start step — exact step vs the 4-step(→1) / 5-step(→2) reference
    bss = _measured_val(metrics, 'ball_start_step')
    steps = approach_steps or _measured_val(metrics, 'step_count')
    steps = int(steps) if steps is not None else None
    if bss is None or steps is None:
        out['T2'] = entry('T2', 'Ball start step', 'P1', 'step', None, w['T2'], '—',
                          note='ball-start step or step count not measured')
    elif steps not in (4, 5):
        out['T2'] = entry('T2', 'Ball start step', 'P1', 'step', None, w['T2'], '—',
                          note=f'reference defined for 4- or 5-step approaches (measured {steps} steps)')
    else:
        expected = steps - 3                          # 4-step → step 1, 5-step → step 2
        off = int(round(bss)) - expected
        detail = f'step {int(round(bss))} (expected step {expected} for a {steps}-step approach)'
        out['T2'] = entry('T2', 'Ball start step', 'P1', 'step', off, w['T2'], detail)

    # T3 backswing apex vs slide start — E4 − E5
    E4, E5 = events.get('E4'), events.get('E5')
    if E4 is None or E5 is None:
        out['T3'] = entry('T3', 'Top of swing', 'P2', 's', None, w['T3'], '—',
                          note='top of backswing (E4) or slide start (E5) not located')
    else:
        off = float(E4) - float(E5)
        detail = (f'{abs(off):.2f} s ' + ('after slide start' if off > 0 else 'before slide start')
                  if abs(off) >= 0.005 else 'at slide start')
        out['T3'] = entry('T3', 'Top of swing', 'P2', 's', off, w['T3'], detail)

    # T4 leverage window — release after slide stop, E7 − E8
    E7, E8 = events.get('E7'), events.get('E8')
    if E7 is None or E8 is None:
        out['T4'] = entry('T4', 'Release', 'P2', 's', None, w['T4'], '—',
                          note='release (E7) or slide stop (E8) not located')
    else:
        off = float(E7) - float(E8)
        detail = (f'{abs(off):.2f} s ' + ('after it stopped' if off > 0 else 'before it stopped')
                  if abs(off) >= 0.005 else 'as it stopped')
        out['T4'] = entry('T4', 'Release', 'P2', 's', off, w['T4'], detail)
    return out


# --------------------------------------------------------------------------- coaching cues (§0.3, text only)
_COACHING_CUES = [
    'Behind and under: firm or slightly cupped wrist, hand under the ball.',
    'Inside-out path: hand slightly inside the ball before release, rolling outside on the follow-through.',
    'Finger exit: thumb out first, then middle and ring fingers.',
    'Avoid "suitcasing": hand not on top or fully on the side early.',
    'Avoid a broken wrist: wrist not collapsing backward.',
    'Non-bowling arm palm facing down or back.',
]


def coaching_cues():
    """The §0.3 hand/wrist cues — text only, never a measured result (phone video can't see them yet)."""
    return {'note': "Hand and wrist position can't be measured from phone video yet — these are cues only.",
            'cues': list(_COACHING_CUES)}


# --------------------------------------------------------------------------- swing-timing baseline (§0.4)
_PHASES = ('pushaway_time', 'backswing_time', 'downswing_time', 'release_time')
_PHASE_LABELS = {'pushaway_time': 'Pushaway', 'backswing_time': 'Backswing',
                 'downswing_time': 'Downswing', 'release_time': 'Release'}
_ADD_PROMPT = 'Add one in Profile › Form baseline to compare.'


def swing_timing(record, form_baseline=None, bases=None):
    """This delivery's phase splits vs the bowler's baseline, phase by phase (FORM_BENCHMARKS §0.4).

    Baseline source:
      * form_baseline={'mode':'entered', 'pushaway_time':…, …}  → the values the bowler typed in Profile.
      * form_baseline={'mode':'average'}                         → "use my average": medians from `bases`
                                                                   (the engine's view='form' personal baselines).
      * no baseline set / not enough data                       → honest 'building', only this delivery shown.
    """
    metrics = record.get('metrics') or {}
    this = {ph: _measured_val(metrics, ph) for ph in _PHASES}
    total_this = _measured_val(metrics, 'swing_time')

    base = None
    source = None
    mode = (form_baseline or {}).get('mode')
    if mode == 'entered':
        vals = {ph: form_baseline.get(ph) for ph in _PHASES}
        if any(v is not None for v in vals.values()):
            base = {ph: (None if vals[ph] is None else float(vals[ph])) for ph in _PHASES}
            source = 'profile_entered'
    elif mode == 'average':
        vals = {}
        for ph in _PHASES:
            b = (bases or {}).get(ph)
            if b and b.get('established') and b.get('median') is not None:
                vals[ph] = float(b['median'])
        if vals:
            base = {ph: vals.get(ph) for ph in _PHASES}
            source = 'profile_average'

    building = base is None
    total_base = None
    diff = None
    if not building:
        bvals = [base[ph] for ph in _PHASES if base.get(ph) is not None]
        total_base = round(sum(bvals), 3) if bvals else None
        if mode == 'entered' and form_baseline.get('total') is not None:
            total_base = float(form_baseline['total'])
        diff = {ph: (round(this[ph] - base[ph], 3)
                     if (this.get(ph) is not None and base.get(ph) is not None) else None)
                for ph in _PHASES}

    return {
        'phases': list(_PHASES),
        'phase_labels': _PHASE_LABELS,
        'this_delivery': {**{ph: this[ph] for ph in _PHASES}, 'total': total_this},
        'baseline': (None if building else {**base, 'total': total_base}),
        'diff': diff,
        'source': source,
        'building': building,
        'prompt': _ADD_PROMPT if building else None,
    }
