#!/usr/bin/env python3
"""DEC-130 landmarks — detect the STATIC lane markings in the stabilised background, geometry-constrained:
  * arrows   — 7 dark targets ~15 ft downlane at boards 5,10,15,20,25,30,35 (reuse cv/arrows.detect_arrow_row).
  * foul dots — the locator dots just behind the foul line at boards 3,5,8,11,14 from EACH edge (known-board ref
    for laydown).
  * approach dots — the set at the start of the approach (further toward the bowler); optional, reported if found.
Used to CALIBRATE boards laterally: at a marker row we know image-x <-> true board for several boards, so the
ball's board at that row is read by interpolation between known-board markers (no depth). These are also the pin/
landmark label sources for the multi-class retrain (static per clip -> all frames), after a contact-sheet audit.
"""
from __future__ import annotations
import numpy as np

from lanesight_core.cv.arrows import detect_arrow_row, _arrow_model, _clahe_gray, _point_darkness, ARROW_BOARDS
from lanesight_core.cv.track import lane_x
from lanesight_core.cv.lanes import foul_corners

LANE_IN, BOARDS = 41.5, 39
FOUL_DOT_BOARDS = (3, 5, 8, 11, 14)        # locator dots from EACH edge, just behind the foul line (USBC)


def _board_x(lane, y, board_from_left):
    """Image x of a board (1..39 from the LEFT edge) at row y."""
    xa, xb = lane_x(lane, y)
    return xa + (board_from_left - 0.5) / BOARDS * (xb - xa)


def detect_arrows(bg, lane, vp):
    """Return {'row': y, 'points': [(x,y,board_abs), ...]} for the 7 arrows, or None. board_abs: 1=right gutter."""
    anchor, z_ft, diag = detect_arrow_row(bg, lane, vp)
    if anchor is None:
        return None
    # project the 7 arrows through the fitted near-homography at z_ft (arrows.py already did the heavy lifting;
    # we re-read the fitted points from diag if present, else reconstruct the row from the centre anchor).
    pts = diag.get('points') if isinstance(diag, dict) else None
    if pts:
        out = [(float(px), float(py), BOARDS + 1 - b) for (px, py, b) in pts]
        return {'row': float(np.median([p[1] for p in out])), 'points': out, 'z_ft': z_ft}
    # fallback: the centre anchor row, project boards 5..35 laterally on that row
    ay = float(anchor[1])
    out = []
    for b in ARROW_BOARDS:
        x = _board_x(lane, ay, b)
        out.append((float(x), ay, BOARDS + 1 - b))
    return {'row': ay, 'points': out, 'z_ft': z_ft}


def detect_foul_dots(bg, lane, vp):
    """Detect the locator dots just behind the foul line at boards 3,5,8,11,14 from each edge. Scan a small band
    of rows above (toward the camera from) the foul line for the row where those board positions are darkest.
    Returns {'row': y, 'points': [(x,y,board_abs)]} or None."""
    gray = _clahe_gray(bg)
    F = foul_corners(lane); yf = float(F[:, 1].max())
    boards_from_left = sorted(set(list(FOUL_DOT_BOARDS) + [BOARDS + 1 - b for b in FOUL_DOT_BOARDS]))
    best = None
    for dy in range(2, 60, 2):                     # dots sit a little behind (below, larger y) the foul line
        y = yf + dy
        xa, xb = lane_x(lane, y)
        if xb - xa < 30:
            continue
        half = max(2, int(0.02 * (xb - xa)))
        scores = []
        for bl in boards_from_left:
            x = _board_x(lane, y, bl)
            d = _point_darkness(gray, x, y, half)
            scores.append(d if d is not None else -9)
        pos = sum(1 for s in scores if s > 0.4)
        med = np.median([s for s in scores if s > -9]) if any(s > -9 for s in scores) else -9
        if pos >= max(4, len(boards_from_left) // 2):
            if best is None or med > best[0]:
                best = (med, y, [(float(_board_x(lane, y, bl)), float(y), BOARDS + 1 - bl)
                                 for bl, s in zip(boards_from_left, scores) if s > 0.4])
    if best is None:
        return None
    return {'row': float(best[1]), 'points': best[2]}


def board_of_point(lane, cx, row_y, markers=None):
    """Ball board (1=right gutter) at image (cx,row_y). If `markers`=[(x, board_abs)] at this row are given, use a
    local linear fit image_x -> board (known-board calibration); else fall back to the lane-edge interpolation."""
    if markers and len(markers) >= 2:
        xs = np.array([m[0] for m in markers]); bs = np.array([m[1] for m in markers])
        A = np.polyfit(xs, bs, 1)
        return float(np.polyval(A, cx))
    xa, xb = lane_x(lane, row_y)
    if xb - xa <= 1:
        return None
    frac = (cx - xa) / (xb - xa)
    return float(BOARDS + 1 - (1 + frac * (BOARDS - 1)))
