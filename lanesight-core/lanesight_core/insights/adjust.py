"""Next-shot recommendations: strike-ball moves (feet/target, speed, ball) and lane transition.
Moves follow the widely taught 'move toward your miss' rule with a 2-and-1 ratio (feet:target) for
angle changes and parallel moves for pure line shifts. Magnitudes are capped and rounded to whole boards."""
from __future__ import annotations
from statistics import mean
from .rules import RULES_VERSION, POCKET_RH
from .reading import read_hit, read_leave, execution_check, classify_shot
from .uncertainty import gate as uncertainty_gate

def _rec(kind, reason, evidence, confidence, **kw):
    return dict(type=kind, reason=reason, evidence=evidence, confidence=confidence, rules_version=RULES_VERSION, **kw)

def _clamp_board(b):
    """Keep a board on the lane: 1 (right gutter) .. 39 (left gutter). None stays None.
    Guards against off-lane projections like the breakpoint-board 0/-1 seen in SHOT_REVIEW 2026-10-25."""
    return None if b is None else float(min(39.0, max(1.0, b)))

def no_reliable_data_insight(note: str) -> dict:
    """Canonical `no_reliable_data` insights payload (no move, low confidence) for callers that must refuse a
    shot before any metric is measured — e.g. an unsupported capture view (side-view-misroute handoff,
    DEC-061). Same shape `strike_adjustment` emits on its no_reliable_data path."""
    rec = _rec('none', note, {'reason': 'no_reliable_data'}, 'low', low_confidence=True, move_feet=0, move_target=0)
    return dict(hit=None, leave=None, execution=None, classification='LOW_CONFIDENCE',
                state='no_reliable_data', confidence='low', note=note, recommendations=[rec])


def far_lane_unreliable(shot: dict) -> tuple[bool, str | None]:
    """Plausibility gate on far-lane metrics (SHOT_REVIEW 2026-10-25, fix #2). A real ball LOSES speed down
    the lane, so a late speed that reads faster than the early speed (beyond measurement noise) means the
    downlane depth scale is corrupt — entry board, entry angle, breakpoint and the speed split can't be
    trusted. Noise band = max(0.5 mph, 3% of the early speed). Secondary signal (only checked when a
    trajectory is attached to the shot dict): a lateral jump of more than 3 boards between neighbouring
    samples. Returns (unreliable, reason)."""
    if shot.get('far_lane_limited'):      # the CV plausibility gate already judged the far lane unreliable
        return True, (shot.get('far_lane_reason')
                      or 'The far-lane measurements are unreliable for this camera position.')
    early, late = shot.get('speed_early'), shot.get('speed_late')
    if early is not None and late is not None:
        noise = max(0.5, 0.03 * abs(early))
        if late > early + noise:
            return True, (f"Late speed ({late:.1f} mph) reads faster than early speed ({early:.1f} mph); "
                          "a ball can't speed up down the lane, so the far-lane measurements are unreliable.")
    traj = shot.get('trajectory')
    samples = traj.get('lane') or traj.get('smoothed') if isinstance(traj, dict) else (traj if isinstance(traj, (list, tuple)) else None)
    if samples:
        boards = [p.get('board') for p in samples if isinstance(p, dict) and p.get('board') is not None]
        for a, b in zip(boards, boards[1:]):
            if abs(b - a) > 3.0:
                return True, (f"The tracked path jumps {abs(b - a):.1f} boards between neighbouring samples; "
                              "the far-lane track is unreliable.")
    return False, None

def _move_size(d, confirmed=False):
    """Move cap (SHOT_REVIEW fix #3, handoff C.5): a single shot never moves more than 2-and-1 (feet, target).
    A larger 3-and-2 is only allowed when the session already shows the ball missing the SAME side on 2+ earlier
    shots (confirmed=True) — one shot is never enough to justify a big move. Returns (move_feet, move_target, label)."""
    if confirmed and abs(d) >= 4.0:
        return 3, 2, '3-and-2'
    return 2, 1, '2-and-1'


def _confirmed_direction(history, hit, handed) -> bool:
    """True when 2+ earlier comparable shots this session missed the same side as this one (handoff C.5). Used to
    allow a larger 3-and-2 move; a single shot stays capped at 2-and-1."""
    side = (hit or {}).get('hit')
    if side not in ('high', 'light', 'brooklyn') or not history:
        return False
    n = 0
    for h in history:
        hb = h.get('entry_board')
        if hb is None:
            continue
        hs = read_hit(hb, None, handed).get('hit')
        if hs == side or (side == 'brooklyn' and hs == 'high') or (side == 'high' and hs == 'brooklyn'):
            n += 1
    return n >= 2


# Explicit card states the app renders from (handoff C.7). One primary state per shot.
STATES = ('move', 'low_confidence_move', 'strike_repeat', 'execution_miss', 'pins_unknown', 'no_reliable_data')


def _apply_uncertainty_contract(recs, shot):
    """DEC-094 §5/§6: suppress any adjustment whose required metrics don't meet the quality bar (shot['_quality']),
    so a move is never shown off an unavailable / low-confidence metric. The primary (recs[0]) is replaced by a
    'none' recommendation whose `suppressed_reason` the shot card shows; a suppressed secondary is dropped. No-op
    when the shot carries no quality map (older callers / unit tests)."""
    if not recs:
        return recs
    out = []
    for i, r in enumerate(recs):
        ok, why = uncertainty_gate(r, shot)
        if ok:
            out.append(r)
        elif i == 0:
            out.append(_rec('none', "Not enough reliable lane data to suggest a move this shot.",
                            dict(reason=why, suppressed=r.get('type')), 'low',
                            low_confidence=True, move_feet=0, move_target=0, suppressed_reason=why))
        # a suppressed secondary recommendation is simply dropped
    return out


def _derive_state(cls, recs, leave) -> str:
    """Collapse the classification + primary recommendation into one card state (handoff C.7). Priority:
    no reliable data > pins unreadable > execution miss > strike/repeat > line move."""
    lv = (leave or {}).get('leave')
    p = recs[0] if recs else None
    if p is None:
        return 'no_reliable_data'
    if cls == 'LOW_CONFIDENCE':
        return 'no_reliable_data'               # gate failed / key metric unavailable (entry board, etc.)
    if cls == 'EXECUTION_MISS':
        return 'execution_miss'                 # missed the line — advice holds even if the deck wasn't read
    if lv == 'unknown':
        return 'pins_unknown'                   # deck unreadable: the user can report the leave to recompute
    t = p.get('type')
    if t in ('move', 'release', 'speed'):
        return 'low_confidence_move' if (p.get('low_confidence') or p.get('confidence') == 'low') else 'move'
    # t == 'none': a strike, or a pocket hit with no line change — both render as "repeat, no move".
    if p.get('low_confidence') or p.get('confidence') == 'low':
        return 'no_reliable_data'
    return 'strike_repeat'

def project_breakpoint(feet_board, arrows_board, breakpoint_ft, geometry) -> float | None:
    """Board where the straight feet->arrows sight line reaches the breakpoint distance. The line runs from
    the stance (approach_offset_ft BEHIND the foul line) through the arrows (arrows_ft past the foul line);
    extend it to breakpoint_ft and round to the nearest whole board. Geometry constants come from
    engine_config (owner-editable). Clamped to the lane (1..39). None when any input is missing."""
    off = (geometry or {}).get('approach_offset_ft')
    af = (geometry or {}).get('arrows_ft')
    if None in (feet_board, arrows_board, breakpoint_ft, off, af) or (af + off) == 0:
        return None
    slope = (arrows_board - feet_board) / (af + off)        # boards per ft along the sight line
    return _clamp_board(round(arrows_board + slope * (breakpoint_ft - af)))


def apply_move(intent: dict | None, rec: dict | None, geometry=None, breakpoint_ft=None) -> dict | None:
    """The target line that results from applying a feet/target move to the intent you threw. Feet and the
    target (arrows) carry SEPARATE whole-board deltas from the rec (move_feet, move_target — e.g. 2-and-1,
    3-and-2). Boards count from the right gutter (1) to the left (39), so 'left' adds boards and 'right'
    subtracts — for either hand. The breakpoint is DERIVED, not shifted by the target: project the new
    feet->arrows line to the breakpoint distance (project_breakpoint). Returns None when there's no intent to
    move from or the rec isn't an actionable board move; fields the intent didn't set stay None."""
    if not intent or not rec:
        return None
    feet, tgt, d = rec.get('move_feet'), rec.get('move_target'), rec.get('direction')
    if d not in ('left', 'right') or not (feet or tgt):
        return None
    sign = 1 if d == 'left' else -1

    def mv(cur, delta):
        return _clamp_board(round(cur + sign * delta, 1)) if (cur is not None and delta) else cur
    new_feet = mv(intent.get('feet_board'), feet)
    new_arrows = mv(intent.get('arrows_board'), tgt)
    return dict(feet_board=new_feet, arrows_board=new_arrows,
                breakpoint_board=project_breakpoint(new_feet, new_arrows, breakpoint_ft, geometry),
                direction=d, move_feet=feet, move_target=tgt, rules_version=RULES_VERSION)


def suggested_target(insights: dict | None, intent: dict | None, geometry=None, breakpoint_ft=None) -> dict | None:
    """Pick the first actionable board move in an insights result and return the target it implies for the
    next shot (for the shot card's 'Apply this move'). The breakpoint is derived from the lane geometry +
    the shot's measured breakpoint distance. None when nothing actionable or no intent set."""
    recs = (insights or {}).get('recommendations') or []
    primary = next((r for r in recs if r.get('direction') in ('left', 'right')
                    and (r.get('move_feet') or r.get('move_target'))), None)
    return apply_move(intent, primary, geometry=geometry, breakpoint_ft=breakpoint_ft)


def strike_adjustment(shot: dict, handed='R', intent=None, user_said=None, history=None, pattern=None):
    """shot: metrics dict (entry_board, entry_angle_deg, arrows/breakpoint boards, speed_mph, pins_standing).
    history: list of earlier shot dicts in this session (same lane/ball) for transition evidence."""
    hit = read_hit(shot.get('entry_board'), shot.get('entry_angle_deg'), handed)
    leave = read_leave(shot.get('pins_standing'), handed, shot.get('pins_uncertain'))
    actual = dict(arrows_board=shot.get('board_at_15ft'), breakpoint_board=shot.get('breakpoint_board'),
                  laydown_board=shot.get('board_at_0ft'))
    ex = execution_check(intent, actual)
    cls = classify_shot(hit, ex, user_said)
    left, right = ('left', 'right') if handed == 'R' else ('right', 'left')
    # Fail-safe plausibility gate (SHOT_REVIEW 2026-10-25, fix #2): if the far-lane metrics are physically
    # implausible, don't convert corrupt numbers into a confident line move. No feet/target move, no
    # breakpoint, no transition/pattern note — just a single low-confidence "no move" recommendation.
    unreliable, why = far_lane_unreliable(shot)
    if unreliable:
        rec = _rec('none', 'Not enough reliable measurement to recommend a move.', dict(reason=why), 'low',
                   low_confidence=True)
        return dict(hit=hit, leave=leave, execution=ex, classification='LOW_CONFIDENCE',
                    state='no_reliable_data', confidence='low', note=why, recommendations=[rec])
    recs = []
    confirmed = _confirmed_direction(history or [], hit, handed)
    if cls == 'LOW_CONFIDENCE':
        recs.append(_rec('none', 'Not enough reliable measurement to recommend a move.', {}, 'low', low_confidence=True))
    elif cls == 'EXECUTION_MISS':
        k, v = max(ex['off'].items(), key=lambda kv: abs(kv[1]))
        where = {'laydown_board': 'laydown', 'arrows_board': 'the arrows', 'breakpoint_board': 'the breakpoint'}[k]
        recs.append(_rec('execution', f"Missed your target by {abs(v):.1f} boards at {where}. Repeat the same line and hit your mark before moving.",
                         dict(intent=intent, actual=actual), 'high', move_feet=0, move_target=0,
                         expected="Hitting your mark tells us whether the lane actually needs a move — most 'bad' shots are execution, not the lane."))
    elif leave.get('leave') == 'unknown':
        # Unreadable deck (SHOT_REVIEW 2026-10-25, fix #3a): can't tell a strike from a miss, so no line move.
        recs.append(_rec('none', "Can't confirm the result — the pins weren't readable, so I can't tell a strike "
                         "from a miss. No line move on this shot.", dict(entry_board=shot.get('entry_board')),
                         'low', low_confidence=True))
    elif leave.get('leave') == 'X' and hit['hit'] != 'brooklyn':
        note = '' if hit['hit'] == 'pocket' else (f" You carried it {abs(hit['boards_from_pocket']):.1f} boards "
               f"{'high' if hit['hit'] == 'high' else 'light'}; if it starts leaving "
               f"{'4/7 pins or splits' if hit['hit'] == 'high' else '10/6-10 pins'}, move {left if hit['hit'] == 'high' else right} 2 boards and 1 (2-and-1).")
        recs.append(_rec('none', f"Strike. No adjustment: repeat the shot.{note}", dict(entry_board=shot.get('entry_board')),
                         'high' if hit['hit'] == 'pocket' else 'medium', watch=hit['hit'] if hit['hit'] != 'pocket' else None))
    else:
        d = hit.get('boards_from_pocket', 0.0)
        exp_pocket = f"Should bring your entry about {abs(d):.0f} board{'s' if round(abs(d)) != 1 else ''} toward the pocket."
        if hit['hit'] in ('high', 'brooklyn'):
            feet, tgt, lab = _move_size(d, confirmed)
            recs.append(_rec('move', f"{hit['reason']} Move {left}: feet {feet} boards, target {tgt} board{'s' if tgt != 1 else ''} ({lab}).",
                             dict(entry_board=shot.get('entry_board'), boards_from_pocket=d, leave=leave.get('leave')),
                             'medium' if cls == 'REACTION_CHANGE' else 'low', direction=left, move_feet=feet, move_target=tgt,
                             expected=exp_pocket,
                             note=None if cls != 'NO_INTENT' else 'Set your target line to separate a missed shot from a lane change.'))
        elif hit['hit'] == 'light':
            feet, tgt, lab = _move_size(d, confirmed)
            recs.append(_rec('move', f"{hit['reason']} Move {right}: feet {feet} boards, target {tgt} board{'s' if tgt != 1 else ''} ({lab}).",
                             dict(entry_board=shot.get('entry_board'), boards_from_pocket=d, leave=leave.get('leave')),
                             'medium' if cls == 'REACTION_CHANGE' else 'low', direction=right, move_feet=feet, move_target=tgt,
                             expected=exp_pocket,
                             note=None if cls != 'NO_INTENT' else 'Set your target line to separate a missed shot from a lane change.'))
        else:   # pocket
            if leave.get('read') == 'light':
                recs.append(_rec('move', f"{hit['reason']} {leave.get('reason', '')} Move toward the miss: {right}, feet 2 boards and target 1 board (2-and-1).",
                                 dict(entry_board=shot.get('entry_board'), leave=leave.get('leave')), 'low',
                                 direction=right, move_feet=2, move_target=1,
                                 expected="Should tighten your entry angle and carry that corner."))
            elif leave.get('read') in ('weak_or_light', 'weak', 'slightly_light') or hit.get('angle') == 'flat':
                recs.append(_rec('release', f"{hit['reason']} {leave.get('reason', '')} Keep the line; get more entry angle and drive: "
                                 "a touch less speed or a stronger release.".strip(),
                                 dict(entry_angle=shot.get('entry_angle_deg'), leave=leave.get('leave')), 'low', speed='slightly slower',
                                 expected="More entry angle should help the ball drive through the pocket and carry."))
            elif leave.get('read') in ('high', 'slightly_high'):
                recs.append(_rec('speed', f"{hit['reason']} {leave.get('reason', '')} Good line; a touch more speed or a firmer release usually carries this.",
                                 dict(leave=leave.get('leave')), 'low', speed='slightly faster',
                                 expected="A touch more speed should hold the pocket and improve carry."))
            else:
                recs.append(_rec('none', f"{hit['reason']} Pocket hit with an unlucky leave ({leave.get('leave')}). Repeat the shot.", {}, 'medium'))
    tr = transition(history or [], shot, handed)
    if tr: recs.append(tr)
    if pattern and pattern.get('length_ft') and shot.get('breakpoint_board') is not None:
        exp = pattern['length_ft'] - 31
        recs.append(_rec('pattern_note', f"On a {pattern['length_ft']} ft pattern the usual exit point is around board {exp:.0f}; "
                         f"your breakpoint was board {shot['breakpoint_board']:.1f}.", dict(rule='length − 31'), 'low'))
    recs = _apply_uncertainty_contract(recs, shot)      # DEC-094 §5/§6: gate moves on per-metric quality
    state = _derive_state(cls, recs, leave)
    primary = recs[0] if recs else None
    return dict(hit=hit, leave=leave, execution=ex, classification=cls, state=state,
                confidence=(primary or {}).get('confidence'), note=(primary or {}).get('note'),
                recommendations=recs)

def transition(history, shot, handed='R', min_shots=3, drift_boards=1.0):
    """lane transition from comparable well-executed shots: breakpoint/entry drifting over time with the same line"""
    good = [h for h in history if h.get('classification') in ('EXECUTED', 'REACTION_CHANGE', 'NO_INTENT') and h.get('entry_board') is not None]
    if len(good) < min_shots: return None
    first, last = good[:max(1, len(good) // 2)], good[-max(1, len(good) // 2):] + [shot]
    d_entry = mean(s['entry_board'] for s in last if s.get('entry_board') is not None) - mean(s['entry_board'] for s in first)
    if handed != 'R': d_entry = -d_entry
    if abs(d_entry) < drift_boards: return None
    left, right = ('left', 'right') if handed == 'R' else ('right', 'left')
    if d_entry > 0:
        return _rec('transition', f"Over the last {len(good) + 1} comparable shots the ball is finishing {d_entry:.1f} boards higher: "
                    f"the lane is hooking earlier. Move {left} (feet 2 boards, target 1 board) or switch to a weaker ball.",
                    dict(n=len(good) + 1, entry_drift=round(d_entry, 1)), 'medium', direction=left, move_feet=2, move_target=1)
    return _rec('transition', f"Over the last {len(good) + 1} comparable shots the ball is finishing {abs(d_entry):.1f} boards lighter: "
                f"the ball is reading the lane later. Move {right} (feet 2 boards, target 1 board) or use a stronger ball.",
                dict(n=len(good) + 1, entry_drift=round(d_entry, 1)), 'medium', direction=right, move_feet=2, move_target=1)
