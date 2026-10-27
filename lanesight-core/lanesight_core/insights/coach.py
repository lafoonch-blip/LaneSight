"""DEC-088/090 Shot-card coach (M4-02).

A shot's outcome has two independent parts and they must be judged separately, or the advice is wrong:
  - the THROW (execution): speed, rev rate and the line the bowler actually rolled, vs their own normal;
  - the LANE & PINS (reaction): where the ball entered (board + angle) vs the pocket.

Both are classified, then ONE coach action comes from the pair:

  | Throw | Lane  | Coach                                                                        |
  | good  | good  | Keep the line.                                                               |
  | good  | miss  | Lane move (feet/eyes, 2-and-1).                                              |
  | off   | miss  | No move — "that was the throw, not the lane. Repeat your normal [speed]."    |
  | off   | good  | Don't build on it — keep the line, repeat your normal throw.                 |

Under BASELINE_MIN_N qualifying shots there is no personal "normal" yet: the throw rings read
"Building your normal (n/10)" and the coach gives lane-only advice (never "repeat your normal").
Far lane not read → lane is "not_read", the coach says "No move yet".

Pure functions; boards count 1 (right gutter) … 39 (left). Nothing here is fabricated — a missing input
makes its ring/verdict unavailable rather than guessed.
"""
from __future__ import annotations
import statistics

BASELINE_MIN_N = 10
POCKET_BOARD = 17.5          # entry board for the pocket (right-hander; the record is already handed)
POCKET_BAND = 2.0            # within ± this of the pocket = a good lane result
SPEED_BAND_MPH = 0.7         # within ± this of your median = "= your avg"
SPEED_OFF_MPH = 1.0          # beyond ± this = an off throw (faster/slower than usual)
ARROWS_BAND = 1.0            # boards at the arrows vs the target line
ANGLE_TARGET_LO, ANGLE_TARGET_HI = 4.0, 6.0   # entry-angle window that carries (DEC-064)


def baseline(shots: list[dict]) -> dict:
    """Median speed / rev / arrows over the bowler's prior qualifying shots (+ n). None where no data."""
    def med(key):
        vals = [s[key] for s in shots if s.get(key) is not None]
        return round(statistics.median(vals), 2) if vals else None
    return {'n': len([s for s in shots if s.get('ball_speed') is not None]),
            'speed': med('ball_speed'), 'rev': med('rev_rate'), 'arrows': med('arrows_board')}


def _vs_avg(value, avg, band):
    """A short 'vs your avg' string + whether it's within band."""
    if value is None or avg is None:
        return None, None
    d = value - avg
    within = abs(d) <= band
    s = '= your avg' if within else f"{'↑' if d > 0 else '↓'}{abs(round(d, 1))} vs avg"
    return s, within


def classify_throw(metrics: dict, base: dict, target: dict | None = None) -> dict:
    """Throw status from speed/rev vs the bowler's normal + the line rolled vs the target. Below the baseline
    minimum there is no 'normal', so the status is 'building' and the coach uses lane-only advice."""
    speed, rev, arrows = metrics.get('ball_speed'), metrics.get('rev_rate'), metrics.get('arrows_board')
    tgt_arrows = (target or {}).get('arrows_board')
    building = base.get('n', 0) < BASELINE_MIN_N

    speed_s, speed_ok = _vs_avg(speed, base.get('speed'), SPEED_BAND_MPH)
    rev_s, _ = _vs_avg(rev, base.get('rev'), 25.0)
    # Accuracy ring compares the rolled line to the TARGET line when set, else to the bowler's normal line.
    arrows_ref = tgt_arrows if tgt_arrows is not None else base.get('arrows')
    arrows_s, arrows_ok = _vs_avg(arrows, arrows_ref, ARROWS_BAND)
    rings = {'speed': {'value': speed, 'vs': speed_s}, 'rev': {'value': rev, 'vs': rev_s},
             'accuracy': {'value': arrows, 'vs': arrows_s}}

    if building:
        return {'status': 'building', 'verdict': f"Building your normal ({base.get('n', 0)}/{BASELINE_MIN_N})",
                'rings': rings}

    # Off if speed is materially off the bowler's normal (the usual cause of a reaction they shouldn't chase).
    off_speed = speed is not None and base.get('speed') is not None and abs(speed - base['speed']) > SPEED_OFF_MPH
    if off_speed:
        faster = speed > base['speed']
        return {'status': 'off', 'verdict': f"Off · {'faster' if faster else 'slower'} than usual",
                'rings': rings, 'off_reason': 'speed', 'faster': faster}
    if arrows_ok is False:
        return {'status': 'off', 'verdict': 'Off · missed your line', 'rings': rings, 'off_reason': 'line'}
    return {'status': 'good', 'verdict': 'Good · your normal throw', 'rings': rings}


def classify_lane(metrics: dict, key_points: dict | None, far_lane: str | None = None) -> dict:
    """Lane result from the entry board/angle vs the pocket. 'not_read' when the far lane wasn't measured."""
    entry = (key_points or {}).get('entry') or {}
    entry_board = entry.get('board') if entry.get('board') is not None else metrics.get('entry_board')
    entry_angle = entry.get('angle_deg') if entry.get('angle_deg') is not None else metrics.get('entry_angle')
    if entry_board is None or far_lane == 'not_read':
        return {'status': 'not_read', 'explanation': 'Not read from this camera spot',
                'entry_board': None, 'entry_angle': entry_angle}
    d = entry_board - POCKET_BOARD
    rings = {'entry_board': entry_board, 'entry_angle': entry_angle}
    if abs(d) <= POCKET_BAND:
        return {'status': 'good', 'explanation': 'Lane carried it to the pocket', **rings}
    # Below the pocket board = entered to the right (light); above = entered left (high/came up).
    side = 'light' if d < 0 else 'high'
    return {'status': 'miss', 'side': side, 'delta_boards': round(d, 1),
            'explanation': f"Entered board {round(entry_board, 1)} vs pocket {POCKET_BOARD} · {side}", **rings}


def coach(throw: dict, lane: dict, recommendation: dict | None = None) -> dict:
    """One action for the pair (the matrix above). `recommendation` is the existing adjust.py move (direction +
    move_feet) reused for the feet/eyes of a lane move, so the coach never invents a geometry."""
    t, l = throw.get('status'), lane.get('status')
    if l == 'not_read':
        return {'action': 'no_move_yet', 'text': 'Keep the same line. Move the tripod so your next shot gets '
                'a full read.'}
    if t == 'building':
        if l == 'good':
            return {'action': 'keep', 'text': 'Good line — keep repeating it while we learn your normal throw.'}
        return {'action': 'lane_move', 'text': _lane_move_text(lane, recommendation),
                'move': _move(recommendation)}
    if t == 'good' and l == 'good':
        return {'action': 'keep', 'text': 'Good throw, good read — keep the same line.'}
    if t == 'good' and l == 'miss':
        return {'action': 'lane_move', 'text': _lane_move_text(lane, recommendation), 'move': _move(recommendation)}
    if t == 'off' and l == 'miss':
        speed = ' speed' if throw.get('off_reason') == 'speed' else ''
        return {'action': 'no_move', 'text': f"That was the throw, not the lane. Stay where you are and repeat "
                f"your normal{speed}."}
    # off throw + good result: a reaction not to build on
    return {'action': 'no_move', 'text': "Good result, but off your normal throw — don't move on it. "
            "Repeat your normal throw and see where it reads."}


def _move(rec: dict | None) -> dict | None:
    if not rec:
        return None
    feet = rec.get('move_feet')
    if feet is None and rec.get('direction') is None:
        return None
    # 2-and-1: eyes move half the feet move (rounded), same direction.
    return {'feet': feet, 'eyes': (round(feet / 2) if isinstance(feet, (int, float)) else None),
            'direction': rec.get('direction')}


def _lane_move_text(lane: dict, rec: dict | None) -> str:
    base = f"Lane read {lane.get('side', 'off')}."
    if rec and rec.get('direction') and rec.get('move_feet') is not None:
        return f"{base} Move your feet {abs(rec['move_feet'])} board(s) {rec['direction']} (eyes half that)."
    return f"{base} Adjust your feet and eyes toward the pocket (2-and-1)."


def build(metrics: dict, key_points: dict | None, prior_shots: list[dict],
          target: dict | None = None, recommendation: dict | None = None, far_lane: str | None = None) -> dict:
    """Full coach block for the shot card: {throw, lane, coach, baseline}."""
    base = baseline(prior_shots)
    throw = classify_throw(metrics or {}, base, target)
    lane = classify_lane(metrics or {}, key_points, far_lane)
    return {'throw': throw, 'lane': lane, 'coach': coach(throw, lane, recommendation), 'baseline': base}
