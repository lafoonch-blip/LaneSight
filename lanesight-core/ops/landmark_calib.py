#!/usr/bin/env python3
"""DEC-130 — landmark-calibrated BOARDS (lateral, no depth). The detected arrows (known boards 5,10,..,35) and
foul-line dots (known boards 3,5,8,11,14 from each edge) give image-x <-> true-board anchors at their rows, so the
ball's board at a row is read by LOCAL LINEAR FIT between the known-board markers — self-calibrating out lane-edge
error. laydown = at the foul row (foul-dots); arrows board = at the arrow row (arrows). board_at_7ft (between them)
comes from the gutter edges. 7 ft dots are NOT assumed (optional per USBC; absent at Shayne's centre)."""
from __future__ import annotations
import numpy as np
from lanesight_core.cv.track import lane_x

BOARDS = 39
ARROW_BOARDS = (5, 10, 15, 20, 25, 30, 35)                 # from an edge (symmetric about 20)
FOUL_DOT_BOARDS = (3, 5, 8, 11, 14)                        # from EACH edge


def _ball_cx_at_row(track, row_y, tol=60):
    """Ball centre-x at image row ~row_y, interpolated from the two track points bracketing it (by contact row)."""
    pts = sorted([c for c in track if 'ct' in c and 'cx' in c], key=lambda c: c['ct'])
    if not pts:
        return None
    for a, b in zip(pts[:-1], pts[1:]):
        if a['ct'] <= row_y <= b['ct'] or b['ct'] <= row_y <= a['ct']:
            if abs(a['ct'] - b['ct']) < 1e-6:
                return a['cx']
            f = (row_y - a['ct']) / (b['ct'] - a['ct'])
            return a['cx'] + f * (b['cx'] - a['cx'])
    near = min(pts, key=lambda c: abs(c['ct'] - row_y))
    return near['cx'] if abs(near['ct'] - row_y) <= tol else None


def _assign_boards(xs_sorted, boards_abs):
    """Given marker image-x sorted left->right and the true absolute boards they correspond to (also ordered
    left->right), return [(x, board_abs)]. board_abs: 1 = right gutter (DEC-088), so left->right is DECREASING."""
    if len(xs_sorted) != len(boards_abs):
        return None
    return list(zip(xs_sorted, boards_abs))


def _board_from_markers(markers, cx):
    xs = np.array([m[0] for m in markers]); bs = np.array([m[1] for m in markers])
    if len(xs) < 2 or np.ptp(xs) < 5:
        return None
    A = np.polyfit(xs, bs, 1)
    return float(np.polyval(A, cx))


def boards_from_landmarks(mc, S, lane, vp, track, foul_y):
    """Return (laydown_board, arrows_board) using the trained arrows/foul-dots, or (None,None). board 1 = right
    gutter looking at the pins."""
    bg = S['bg']
    lay = arr = None
    # ARROWS board
    try:
        ar = mc.detect(bg, 'arrows', thr=0.25, maxn=12)
    except Exception:
        ar = []
    # keep arrows within the lane at their row, sorted by x; need ~7 for boards 5..35
    arow = float(np.median([a[1] for a in ar])) if ar else None
    if ar and arow is not None:
        xa, xb = lane_x(lane, arow)
        inlane = sorted([a[0] for a in ar if xa - 0.15 * (xb - xa) <= a[0] <= xb + 0.15 * (xb - xa)])
        if len(inlane) == 7:
            # left->right x maps to boards; board_abs = 40 - board_from_left_edge; arrows from the LEFT edge are
            # 5,10,..,35, so left->right absolute boards are 35,30,..,5 (1=right gutter).
            markers = _assign_boards(inlane, [BOARDS + 1 - b for b in ARROW_BOARDS])
            bcx = _ball_cx_at_row(track, arow)
            if markers and bcx is not None:
                arr = _board_from_markers(markers, bcx)
    # LAYDOWN (foul row) from foul dots
    try:
        fd = mc.detect(bg, 'foul_dots', thr=0.25, maxn=16)
    except Exception:
        fd = []
    if fd:
        xa, xb = lane_x(lane, foul_y)
        inlane = sorted([d[0] for d in fd if xa - 0.1 * (xb - xa) <= d[0] <= xb + 0.1 * (xb - xa)])
        boards_from_left = sorted(set(list(FOUL_DOT_BOARDS) + [BOARDS + 1 - b for b in FOUL_DOT_BOARDS]))
        if len(inlane) == len(boards_from_left):
            markers = _assign_boards(inlane, [BOARDS + 1 - b for b in boards_from_left])
            bcx = _ball_cx_at_row(track, foul_y)
            if markers and bcx is not None:
                lay = _board_from_markers(markers, bcx)
    return lay, arr
