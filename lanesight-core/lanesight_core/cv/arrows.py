"""Arrow-row detection — an impact-INDEPENDENT depth anchor (DEC-110 metric-independence, 2026-10-30).

The production homography anchors the lane depth scale on the ball's position at pin impact (metrics.py
`lane_homography`). When the impact isn't detected there is no depth scale, so speed / boards / the throw line
are all withheld (DEC-109). The seven aiming arrows are a fixed landmark ~12-16 ft past the foul line, so
locating them gives a near-lane depth anchor that needs neither the ball nor the pins.

KNOWN-PATTERN FIT (2026-10-30, replacing the earlier single-row intensity comb). Frame inspection showed the
arrows ARE imaged on the down-lane POV but are low-contrast and form a shallow V (centre arrow deepest), which
a one-row comb can't match. Instead we fit the real layout:
  * Lateral X: arrows at boards 5,10,15,20,25,30,35 (USBC), fixed from the DETECTED lane edges — no free phase.
  * Longitudinal Z: a NOMINAL symmetric V inside the USBC 12-16 ft range. The exact per-arrow stagger is NOT
    specified — lane_geometry.USBC_RANGES_FT['arrow'] = (12.0, 16.0) and lane_geometry marks the stagger TBD
    (USBC Equipment Specifications Manual 2026-03-26; Shayne 2026-10-25: USBC permits a range, not a universal
    point). So the ABSOLUTE anchor depth carries house-dependent uncertainty; the V SHAPE is what's matched.
The only unknown is the near depth scale. For each candidate we anchor the centre arrow (board 20) at a trial
image row, project all 7 arrows through the resulting near homography, and score each projected point by how
much darker it is than its local surroundings on the CLAHE'd stabilized background. Accept only if the best
candidate clearly beats the next non-overlapping one AND >=5/7 arrows score positive; else decline (the caller
falls back to the impact anchor — never a guessed row).
"""
from __future__ import annotations
import numpy as np, cv2
from .lanes import lane_x, foul_corners
from .metrics import lane_homography_at, LANE_IN

ARROW_BOARDS = (5, 10, 15, 20, 25, 30, 35)          # USBC target arrows, boards from the edge (symmetric about 20)
Z_CENTER_FT = 15.0                                  # nominal centre-arrow (board 20) distance, within USBC 12-16 ft
# PROVISIONAL nominal V stagger (ft per arrow-pair outward, centre deepest). NOT a validated constant: a sweep on
# IMG_8751/53/54 (same house, 2 sessions) showed 0.75 was too steep (8753 off by -0.97 mph) and ~0.5 reconciles
# all three to within ~0.27 mph. The AUTHORITATIVE value is Shayne's tape measurement of the arrow layout
# (pending); until then this stays shadow-gated and is never shipped into baselines/coaching. (2026-10-30)
Z_STEP_FT = 0.5


def _arrow_model(z_center=Z_CENTER_FT, z_step=Z_STEP_FT):
    """Arrow layout: (X inches from left edge, Z ft from foul) for the 7 arrows. X exact (board centres); Z a
    symmetric V, `z_center` at board 20 stepping back `z_step` ft per arrow-pair outward. z_center/z_step are
    NOMINAL within the USBC 12-16 ft range — the real values are Shayne's tape measurements (pending), so these
    are parameters, not constants (see module docstring)."""
    pts = []
    for b in ARROW_BOARDS:
        x_in = (b - 0.5) * LANE_IN / 39.0           # board centre, inches from the LEFT edge (lane_geometry convention)
        z = z_center - z_step * abs(b - 20) / 5.0
        pts.append((b, x_in, z))
    return pts


def _clahe_gray(bg):
    g = cv2.cvtColor(bg, cv2.COLOR_BGR2GRAY) if bg.ndim == 3 else bg
    return cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8)).apply(g.astype(np.uint8)).astype(np.float32)


def _point_darkness(gray, u, v, half):
    """How much darker a small patch at (u,v) is than its local surroundings, normalised by local contrast.
    Positive = darker than around it (an arrow mark). None if off-frame."""
    h, w = gray.shape
    u, v, half = int(round(u)), int(round(v)), int(half)
    r_in, r_out = max(2, half), max(5, half * 3)
    if v - r_out < 0 or v + r_out >= h or u - r_out < 0 or u + r_out >= w:
        return None
    inner = gray[v - r_in:v + r_in + 1, u - r_in:u + r_in + 1]
    outer = gray[v - r_out:v + r_out + 1, u - r_out:u + r_out + 1]
    surround = (outer.sum() - inner.sum()) / max(1, outer.size - inner.size)
    spread = outer.std() + 1e-6
    return float((surround - inner.mean()) / spread)


def detect_arrow_row(bg, lane, vp, z_ft=Z_CENTER_FT, z_step=Z_STEP_FT):
    """Return (anchor_px, z_ft, diag). anchor_px = the fitted centre-arrow point (board 20) ON the arrow V, at
    depth z_ft, ready for metrics.lane_homography_at(lane, vp, anchor_px, z_ft). (None, z_ft, diag) when no
    confident fit — the caller then keeps the impact anchor / unavailable (never a guessed row). z_ft/z_step are
    the nominal V (pending Shayne's measured arrow layout)."""
    gray = _clahe_gray(bg)
    model = _arrow_model(z_ft, z_step)
    F = foul_corners(lane)
    y_bottom = float(max(F[0][1], F[1][1]))          # foul row (largest y = nearest)
    span = y_bottom - vp[1]
    # Sweep the centre-arrow image row across the near lane (roughly 8-24 ft worth of band in fraction terms).
    y_lo = y_bottom - 0.55 * span                    # far cap: excludes the mid/far-lane clutter
    y_hi = y_bottom - 0.10 * span                    # near cap: just past the foul
    cand_y = np.linspace(y_lo, y_hi, 140)

    results = []
    for yc in cand_y:
        xl, xr = lane_x(lane, float(yc))
        if not (np.isfinite(xl) and np.isfinite(xr)) or xr - xl < 25:
            continue
        cx = (xl + xr) / 2.0
        try:
            H = lane_homography_at(lane, vp, np.array([cx, yc]), z_ft)
            Hinv = np.linalg.inv(H)
        except Exception:
            continue
        lane_px = xr - xl
        half = max(2.0, 0.6 * lane_px / 39.0)        # ~0.6 board patch radius in px at this row
        per = []
        for (b, x_in, z) in model:
            p = Hinv @ np.array([x_in, z, 1.0])
            if abs(p[2]) < 1e-9:
                per.append(None); continue
            u, v = p[0] / p[2], p[1] / p[2]
            per.append(_point_darkness(gray, u, v, half))
        vals = [s for s in per if s is not None]
        if len(vals) < 5:
            continue
        score = float(np.sum(vals))
        n_pos = int(np.sum(np.array(vals) > 0))
        results.append((float(yc), score, n_pos, [round(s, 2) if s is not None else None for s in per]))

    diag = {'candidates': len(results)}
    if len(results) < 5:
        return None, z_ft, {**diag, 'reason': 'too few candidate rows on the lane'}

    results.sort(key=lambda r: r[1], reverse=True)
    best = results[0]
    # next-best candidate OUTSIDE the winner's basin — the fit is smooth over a few px around the true row, so a
    # near-neighbour isn't a real alternative. Require a genuine separation (~a couple board-depths) so the margin
    # reflects a competing feature, not the same arrows one row over.
    sep = 0.09 * span
    runner = next((r for r in results[1:] if abs(r[0] - best[0]) > sep), None)
    margin = best[1] - (runner[1] if runner else 0.0)
    diag.update(best_y=round(best[0], 1), best_score=round(best[1], 2), n_positive=best[2],
                per_arrow=best[3], runner_score=round(runner[1], 2) if runner else None,
                margin=round(margin, 2))
    # Accept only on a clear win AND a real majority of arrows individually present.
    if best[2] < 5:
        return None, z_ft, {**diag, 'reason': f'only {best[2]}/7 arrows scored positive'}
    if runner is None or margin < 0.5 * max(best[1], 1e-6):
        return None, z_ft, {**diag, 'reason': 'best arrow fit not clearly separated from the next'}
    xl, xr = lane_x(lane, best[0])
    anchor_px = np.array([(xl + xr) / 2.0, best[0]])
    return anchor_px, z_ft, {**diag, 'reason': 'ok'}
