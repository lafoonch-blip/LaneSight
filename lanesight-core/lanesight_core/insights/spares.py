"""Spare targeting. Two outputs:
1) geometry: a straight cross-lane line through the key pin (laydown board -> arrows board -> pin), the most
   reliable way to shoot single pins (recommend a plastic/straight ball for corner pins);
2) the 3-6-9 system relative to the bowler's strike stance (feet move only, same target) for hook-ball spares."""
from __future__ import annotations
from ..scoring.pins import PIN_BOARD, PIN_ROW, mirror
from .rules import RULES_VERSION

ROW_FT = 10.392 / 12
ARROWS_FT = 15.0
# 3-6-9 (right-hander): feet move in boards, + = move left. Right-side pins move left, left-side pins move right.
SYS_369_RH = {7: -9, 4: -6, 2: -3, 8: -3, 1: 0, 5: 0, 3: 4, 9: 4, 6: 8, 10: 12}

def key_pin(standing):
    """front-most pin; ties broken toward the centre. For multi-pin leaves the shot must hit this pin first."""
    s = sorted(standing, key=lambda p: (PIN_ROW[p], abs(PIN_BOARD[p] - 20)))
    return s[0]

def aim_board(standing):
    """board the ball centre should cross at the pins to take out the whole leave (simple: midpoint of the leave's
    lateral extent, pulled toward the key pin)"""
    b = [PIN_BOARD[p] for p in standing]; k = PIN_BOARD[key_pin(standing)]
    return round(0.5 * k + 0.25 * (min(b) + max(b)), 1)

def spare_plan(standing, handed='R', strike_stance=None, strike_target=None):
    if not standing: return None
    s_rh = set(standing) if handed == 'R' else mirror(standing)
    kp = key_pin(s_rh); target_pin_board = aim_board(s_rh)
    z = 60 + (PIN_ROW[kp] - 1) * ROW_FT
    # cross-lane straight line: lay down on the opposite side, mirrored about the centre, kept off the gutters
    laydown = min(34.0, max(6.0, 40.0 - target_pin_board))
    if abs(laydown - target_pin_board) < 6: laydown = target_pin_board + (8 if target_pin_board < 20 else -8)
    arrows = laydown + (target_pin_board - laydown) * ARROWS_FT / z
    corner = kp in (7, 10) and len(s_rh) == 1
    out = dict(leave='-'.join(map(str, sorted(standing))), key_pin=kp if handed == 'R' else mirror({kp}).pop(),
               straight_line=dict(laydown_board=round(laydown if handed == 'R' else 40 - laydown, 1),
                                  arrows_board=round(arrows if handed == 'R' else 40 - arrows, 1),
                                  pin_board=round(target_pin_board if handed == 'R' else 40 - target_pin_board, 1)),
               ball='spare ball (straight)' if corner or kp in (6, 4) and len(s_rh) <= 2 else 'strike ball or spare ball',
               rules_version=RULES_VERSION)
    if strike_stance is not None:
        mv = SYS_369_RH[kp]
        if handed != 'R': mv = -mv
        out['system_369'] = dict(feet_board=strike_stance + mv, target_board=strike_target,
                                 note=f"3-6-9: move feet {abs(mv)} boards {'left' if mv > 0 else 'right'} from your strike stance, same target." if mv else
                                 "Same stance and target as your strike shot.")
    return out
