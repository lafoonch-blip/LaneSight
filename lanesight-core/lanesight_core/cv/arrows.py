"""Arrow-row detection — an impact-INDEPENDENT depth anchor (DEC-110 metric-independence, 2026-10-30).

The production homography anchors the lane depth scale on the ball's position at pin impact (metrics.py
`lane_homography`). When the impact isn't detected there is no depth scale, so speed / boards / the throw line
are all withheld (DEC-109). But the seven aiming arrows sit at a FIXED, always-present landmark 15 ft past the
foul line — detect their row and we have a near-lane depth anchor that needs neither the ball nor the pins.

This finds the arrow row on the STABILIZED BACKGROUND (ball absent, lane static) by scoring each near-lane row
against the expected 7-arrow comb across the lane width (arrows at boards 5,10,…,35 → fractional positions
below). It is deliberately CONSERVATIVE: if no row carries a clear, well-separated comb it returns None, and the
caller keeps the honest "unavailable" rather than anchoring on a guess (CLAUDE.md: accuracy beats coverage).
"""
from __future__ import annotations
import numpy as np, cv2
from .lanes import lane_x

# Fractional positions across the lane width of the 7 arrows (boards 5,10,…,35 of 39, centre = board 20).
ARROW_FRACS = np.array([(b - 0.5) / 39.0 for b in (5, 10, 15, 20, 25, 30, 35)])
N_COLS = 91                       # cross-lane profile resolution (~2.3 cols/board)


def _row_profile(gray, lane, y):
    """Mean lane-intensity profile across the width at image row y, resampled to N_COLS, or None if off-frame."""
    xl, xr = lane_x(lane, float(y))
    if not np.isfinite(xl) or not np.isfinite(xr) or xr - xl < 20:
        return None
    xs = np.linspace(xl + 1, xr - 1, N_COLS)
    yy = int(round(y))
    if yy < 1 or yy >= gray.shape[0] - 1 or xs.min() < 0 or xs.max() >= gray.shape[1]:
        return None
    # average 3 rows for a little vertical support against noise
    cols = np.clip(np.round(xs).astype(int), 0, gray.shape[1] - 1)
    band = gray[yy - 1:yy + 2, :].mean(0)
    return band[cols]


def _comb_score(profile):
    """How strongly the profile dips at the 7 arrow positions vs. between them. Positive = arrows darker than the
    surrounding boards (the usual case); we return the signed contrast and a separation ratio."""
    p = profile - profile.mean()
    idx = np.clip((ARROW_FRACS * (N_COLS - 1)).round().astype(int), 0, N_COLS - 1)
    # "between" samples: midpoints between consecutive arrows + the two margins
    mids = np.clip(((ARROW_FRACS[:-1] + ARROW_FRACS[1:]) / 2 * (N_COLS - 1)).round().astype(int), 0, N_COLS - 1)
    at = p[idx].mean(); between = p[mids].mean()
    contrast = between - at                       # >0 when arrows are darker than the gaps
    spread = profile.std() + 1e-6
    return contrast, contrast / spread


def detect_arrow_row(bg, lane, vp, z_ft=15.0):
    """Return (anchor_px, z_ft, diag) for the arrow row on the stabilized background `bg`, or (None, z_ft, diag)
    when no confident row is found. `anchor_px` is a point (lane centre) ON the arrow row, ready for
    metrics.lane_homography_at(lane, vp, anchor_px, z_ft)."""
    gray = cv2.cvtColor(bg, cv2.COLOR_BGR2GRAY).astype(np.float32) if bg.ndim == 3 else bg.astype(np.float32)
    H = gray.shape[0]
    # Foul line is the near edge; the arrows sit ~1/4 of the way to the horizon. Search the near-lane band only:
    # between the foul row and ~40% toward the vanishing point (past 15 ft, short of the mid lane).
    from .lanes import foul_corners
    F = foul_corners(lane)
    y_foul = float(min(F[0][1], F[1][1]))         # nearest (largest y) is bottom; foul corners carry the row
    y_near = float(max(F[0][1], F[1][1]))
    y_bottom = max(y_foul, y_near)
    y_top = vp[1] + 0.40 * (y_bottom - vp[1])      # 40% of the way from vp down to the foul = past the mid lane
    ys = np.linspace(min(y_top, y_bottom - 5), y_bottom - 2, 80)

    rows = []
    for y in ys:
        prof = _row_profile(gray, lane, y)
        if prof is None:
            continue
        contrast, ratio = _comb_score(prof)
        rows.append((y, contrast, ratio))
    diag = {'rows_scored': len(rows)}
    if len(rows) < 10:
        return None, z_ft, {**diag, 'reason': 'too few rows profiled'}

    ys_a = np.array([r[0] for r in rows]); ratios = np.array([r[2] for r in rows])
    best = int(np.argmax(ratios))
    peak = ratios[best]
    # Confidence: the arrow row's comb must stand clearly above the rest of the near lane.
    others = np.delete(ratios, best)
    margin = peak - (others.mean() + 2.0 * others.std())
    diag.update(peak_ratio=round(float(peak), 3), median_ratio=round(float(np.median(ratios)), 3),
                margin=round(float(margin), 3), y=round(float(ys_a[best]), 1))
    if peak < 0.5 or margin < 0:                   # weak or ambiguous → decline (no guessed anchor)
        return None, z_ft, {**diag, 'reason': 'no clearly-separated arrow comb'}
    y_arrow = float(ys_a[best])
    xl, xr = lane_x(lane, y_arrow)
    anchor_px = np.array([(xl + xr) / 2.0, y_arrow])
    return anchor_px, z_ft, {**diag, 'reason': 'ok'}
