"""Auto-prefill candidate landmarks from the EXISTING pipeline (Step 1). Output is always UNVERIFIED
('suggested'); a human verifies it in the label tool before it ever calibrates (Step 3).

What the existing pipeline can honestly produce on a still plate:
- **Foul-line endpoints** (foul_l, foul_r): from `cv.lanes.find_lanes` + `foul_corners` — the gutter/edge
  intersection with the foul line. Reliable where the lane detects; simply absent where it doesn't.
- **Approach dots** (approach_dot_*): best-effort dark-blob detection BELOW the foul line, with identity
  assigned by board via the (extrapolated) lane edges — only when a single round blob lands near a
  5-board position. Low confidence by design; the human confirms/moves/rejects.

NOT auto-suggested (too unreliable to label honestly from the existing pipeline — left for manual add in the
tool, where zoom makes them quick): individual pin spots, mid-lane arrows, guide dots.

Nothing here runs on or modifies the production path.
"""
from __future__ import annotations
import os
import pickle
import numpy as np

from .landmarks import LandmarkSet
from .lane_geometry import CANONICAL, x_in_for_board


def _clip_id(stab_path: str) -> str:
    base = os.path.basename(stab_path)
    return base[:-len("_stab.pkl")] if base.endswith("_stab.pkl") else os.path.splitext(base)[0]


def _pick_lane(lanes):
    """The most complete lane to seed from: widest at the foul line (most central / least clipped)."""
    from ..lanes import foul_corners  # local import; cv.lanes is heavy
    best, best_w = None, -1.0
    for l in lanes:
        try:
            fc = foul_corners(l)
        except Exception:
            continue
        w = abs(fc[1][0] - fc[0][0])
        if w > best_w:
            best, best_w = (l, fc), w
    return best


def _approach_dots(bg, lane, foul_y, ls: LandmarkSet, geometry=CANONICAL, log=print):
    """Suggest approach dots: round dark blobs below the foul line, identity by board via extrapolated edges."""
    import cv2
    from ..lanes import lane_x
    h, w = bg.shape[:2]
    gray = cv2.cvtColor(bg, cv2.COLOR_BGR2GRAY)
    y0 = int(min(h - 1, foul_y + 5))
    if y0 >= h - 5:
        return 0
    region = gray[y0:h, :]
    thr = max(10, int(np.median(region) - 1.2 * region.std()))
    dark = (region < thr).astype(np.uint8)
    dark = cv2.morphologyEx(dark, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, lab, st, cen = cv2.connectedComponentsWithStats(dark)
    by_board = {}                                   # board -> (confidence, cx, cy)
    for k in range(1, n):
        x, y, bw, bh, area = st[k]
        if not (10 <= area <= 900) or bw == 0 or bh == 0:
            continue
        ar = bw / bh
        if not (0.5 < ar < 2.0):                    # roughly round
            continue
        roundness = area / (bw * bh)                # filled-box ratio (circle ~0.785)
        if roundness < 0.55:
            continue
        cx = cen[k][0]; cy = cen[k][1] + y0
        xa, xb = lane_x(lane, cy)
        if not (xa < cx < xb) or xb - xa < 20:
            continue
        frac = (cx - xa) / (xb - xa)
        board_fl = frac * geometry.boards + 0.5
        b = int(round(board_fl / 5.0) * 5)
        if b not in (5, 10, 15, 20, 25, 30, 35) or abs(board_fl - b) > 1.2:
            continue
        conf = float(np.clip(roundness, 0, 1) * (1 - abs(board_fl - b) / 1.2))
        if b not in by_board or conf > by_board[b][0]:
            by_board[b] = (conf, float(cx), float(cy))
    for b, (conf, cx, cy) in by_board.items():
        ls.suggest(f"approach_dot_{b}", cx, cy, round(conf, 3), "auto:approach_dots")
    if by_board:
        log(f"approach dots: {len(by_board)} suggested (boards {sorted(by_board)})")
    return len(by_board)


def autofill(stab_path: str, geometry=CANONICAL, log=print) -> LandmarkSet:
    """Build a LandmarkSet of UNVERIFIED suggestions from a stabilized background plate."""
    from ..lanes import find_lanes
    S = pickle.load(open(stab_path, "rb"))
    bg = S["bg"]
    h, w = bg.shape[:2]
    clip = _clip_id(stab_path)
    ls = LandmarkSet.template(clip, (w, h))
    ls.notes = ("AUTO-PREFILL (UNVERIFIED). Suggestions are 'suggested' only; verify in the label tool "
                "before any calibration. Pins/arrows/guide-dots are not auto-suggested — add them manually.")
    try:
        G = find_lanes(bg, log=lambda *a, **k: None)
    except Exception as e:                          # failing clip: honest empty suggestion file + reason
        ls.notes += f"  find_lanes failed: {e}"
        log(f"{clip}: find_lanes failed ({e}); no foul/approach suggestions")
        return ls
    picked = _pick_lane(G["lanes"])
    if picked is None:
        log(f"{clip}: no usable lane for foul corners")
        return ls
    lane, fc = picked
    foul_res = float(lane.get("foul_res", 0.0))
    conf = float(np.clip(1.0 - foul_res / 5.0, 0.2, 0.95))
    ls.suggest("foul_l", float(fc[0][0]), float(fc[0][1]), round(conf, 3), "auto:find_lanes")
    ls.suggest("foul_r", float(fc[1][0]), float(fc[1][1]), round(conf, 3), "auto:find_lanes")
    foul_y = max(fc[0][1], fc[1][1])
    try:
        _approach_dots(bg, lane, foul_y, ls, geometry, log=log)
    except Exception as e:
        log(f"{clip}: approach-dot detection skipped ({e})")
    log(f"{clip}: {ls.suggested_count()} suggestions (foul conf {conf:.2f})")
    return ls
