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


def _row_profile(gray, lane, y, win=18):
    """Mean lane-intensity profile across the width at image row y, resampled to N_COLS, or None if off-frame.
    Averages a VERTICAL window (±`win` rows) so the 7-arrow chevron (centre arrow ~3 ft deeper than the outer
    ones) is captured by one profile instead of smeared across rows the single-row comb would miss."""
    xl, xr = lane_x(lane, float(y))
    if not np.isfinite(xl) or not np.isfinite(xr) or xr - xl < 20:
        return None
    xs = np.linspace(xl + 1, xr - 1, N_COLS)
    yy = int(round(y))
    if yy - win < 0 or yy + win >= gray.shape[0] or xs.min() < 0 or xs.max() >= gray.shape[1]:
        return None
    cols = np.clip(np.round(xs).astype(int), 0, gray.shape[1] - 1)
    band = gray[yy - win:yy + win + 1, :].mean(0)
    return band[cols]


def _comb_score(profile):
    """Dark-arrow comb contrast at the fixed board positions, with a separation ratio. Positive = arrows darker
    than the gaps. A small phase search was tried (the detected edges don't map exactly to boards 1/39) but with
    a free phase a comb fits near-foul laydown dots and noise just as well, producing false near-row picks — so
    the fixed comb is used and the detector DECLINES when the arrows don't stand out, rather than guess a row
    (2026-10-30 frame inspection: these down-lane POVs image the 15 ft arrows too faintly to discriminate)."""
    p = profile - profile.mean()
    idx = np.clip((ARROW_FRACS * (N_COLS - 1)).round().astype(int), 0, N_COLS - 1)
    mids = np.clip(((ARROW_FRACS[:-1] + ARROW_FRACS[1:]) / 2 * (N_COLS - 1)).round().astype(int), 0, N_COLS - 1)
    contrast = p[mids].mean() - p[idx].mean()
    spread = profile.std() + 1e-6
    return contrast, contrast / spread


def detect_arrow_row(bg, lane, vp, z_ft=15.0):
    """Return (anchor_px, z_ft, diag) for the arrow row on the stabilized background `bg`, or (None, z_ft, diag)
    when no confident row is found. `anchor_px` is a point (lane centre) ON the arrow row, ready for
    metrics.lane_homography_at(lane, vp, anchor_px, z_ft)."""
    g0 = cv2.cvtColor(bg, cv2.COLOR_BGR2GRAY) if bg.ndim == 3 else bg
    # The arrows are low-contrast on oiled/washed-out maple from a down-lane POV (2026-10-30 frame inspection).
    # CLAHE on the luma lifts the dovetails out of the wood before scoring — without it the true arrow row scores
    # below the decline threshold and the search locks onto a far-lane false comb instead.
    gray = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8)).apply(g0.astype(np.uint8)).astype(np.float32)
    H = gray.shape[0]
    # Search the NEAR lane only: from just past the foul up toward (but short of) the mid lane. The arrows sit at
    # 15 ft; range-finder dots and the pin-deck clutter are farther, so capping the band near the foul keeps those
    # out. Band expressed as a fraction of the foul→vanishing-point span (perspective-robust).
    from .lanes import foul_corners
    F = foul_corners(lane)
    y_bottom = float(max(F[0][1], F[1][1]))        # foul row (largest y = nearest)
    span = y_bottom - vp[1]
    y_far = y_bottom - 0.55 * span                 # ~mid lane (excludes the far-lane false combs)
    y_cut = y_bottom - 0.12 * span                 # skip the first few ft (laydown dots right at the foul)
    ys = np.linspace(y_far, y_cut, 120)

    rows = []
    for y in ys:
        prof = _row_profile(gray, lane, y)
        if prof is None:
            continue
        contrast, ratio = _comb_score(prof)
        rows.append((float(y), float(contrast), float(ratio)))
    diag = {'rows_scored': len(rows)}
    if len(rows) < 10:
        return None, z_ft, {**diag, 'reason': 'too few rows profiled'}

    ys_a = np.array([r[0] for r in rows]); ratios = np.array([r[2] for r in rows])
    best = int(np.argmax(ratios))
    peak = ratios[best]
    others = np.delete(ratios, best)
    margin = peak - (others.mean() + 2.0 * others.std())
    # profile for offline inspection: (y, ratio) sampled sparsely
    prof_s = [(round(ys_a[i], 0), round(float(ratios[i]), 2)) for i in range(0, len(rows), max(1, len(rows) // 20))]
    diag.update(peak_ratio=round(float(peak), 3), median_ratio=round(float(np.median(ratios)), 3),
                margin=round(float(margin), 3), y=round(float(ys_a[best]), 1), profile=prof_s)
    # Decline unless the arrow comb is BOTH strong and clearly separated from every other near-lane row. The
    # thresholds are deliberately strict (margin ≥ 0.15, not > 0): on the down-lane POVs inspected 2026-10-30 a
    # near-zero-margin "peak" was a 16.9 ft false pick 2 mph off, not the real 15 ft arrows. Better to decline and
    # fall back to the impact anchor than anchor on a guessed row (CLAHE + chevron window already applied).
    if peak < 0.6 or margin < 0.15:
        return None, z_ft, {**diag, 'reason': 'no clearly-separated arrow comb'}
    y_arrow = float(ys_a[best])
    xl, xr = lane_x(lane, y_arrow)
    anchor_px = np.array([(xl + xr) / 2.0, y_arrow])
    return anchor_px, z_ft, {**diag, 'reason': 'ok'}
