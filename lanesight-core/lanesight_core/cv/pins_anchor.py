"""Pin-spot depth anchor — an impact-INDEPENDENT, SPEC-FIXED near-lane depth reference (Shayne, 2026-10-30).

Why not the arrows: USBC permits target arrows anywhere in 12-16 ft (center-variable), so they can't be a
universal distance anchor (arrows.py is kept only as a 12-16 ft plausibility cross-check). The foul line (Z=0)
and the standing pin spots ARE spec-fixed (12-in centers; head pin at Z=60 ft, universal), and the pins stand
in the pre-shot stabilized background — so this anchors the depth scale with no ball and no pin-impact, at ANY
center.

Structure mirrors the arrow V-fit (no free pose search): the pins' LATERAL positions are known from the
detected lane edges; the only unknown is DEPTH. Sweep the head-pin image row across the far lane band, project
the 7 VISIBLE PERIMETER pin BASES (pins 1,2,3,4,6,7,10 — the centre-column back pins 5/8/9 are occluded by the
front pins from a down-lane POV) through the planar lane homography (Y=0 base → no pin-height/pose needed), and
score the bright pin BODY just above each base. A glossy lane MIRRORS each pin downward, so a candidate with a
brighter match far above it is a reflection, not a pin → penalised (take the TOP of each pin/mirror pair).
Accept iff >=5/7 pins score positive AND the best depth clearly beats the next non-overlapping one; else decline
(the caller keeps the impact anchor / unavailable — never a guessed depth).

Validated on IMG_8751-54 (both orientations, same house) in SHADOW: 7/7 pins on all four (incl. the two
portrait clips the arrow fit declined), head depth 58-63 ft (vs 60), fitted base within ~2-6 px of the
hand/oracle pin bases, near-lane speed within ~0.75 mph of the impact anchor. NOT promoted — shadow only until
the residual (~0.5 mph, from base-vs-body offset + far-lane planar conditioning) is tightened and the live
pose-solver path (cv/calib/pose.py) is wired. Never feeds baselines/coaching.
"""
from __future__ import annotations
import numpy as np, cv2
from .lanes import lane_x, foul_corners
from .metrics import lane_homography_at
from .calib.lane_geometry import CANONICAL

VISIBLE_PINS = ('pin_1', 'pin_2', 'pin_3', 'pin_4', 'pin_6', 'pin_7', 'pin_10')   # perimeter; 5/8/9 occluded
_PINS = [(CANONICAL.landmarks[n].x_in, CANONICAL.landmarks[n].z_ft) for n in VISIBLE_PINS]
Z_HEAD_FT = 60.0            # head-pin spot distance (spec)


def _bright(bg):
    hsv = cv2.cvtColor(bg, cv2.COLOR_BGR2HSV) if bg.ndim == 3 else cv2.cvtColor(cv2.cvtColor(bg, cv2.COLOR_GRAY2BGR), cv2.COLOR_BGR2HSV)
    return (((hsv[..., 1] < 70) & (hsv[..., 2] > 150)) * 255).astype(np.float32)   # low-sat + bright = white pin


def detect_pin_anchor(bg, lane, vp):
    """Return (anchor_px, Z_HEAD_FT, diag): anchor_px = the fitted HEAD-PIN BASE (board 20, Z=60 ft), ready for
    metrics.lane_homography_at(lane, vp, anchor_px, 60.0). (None, Z_HEAD_FT, diag) when no confident fit."""
    wm = _bright(bg)
    H_img, W = wm.shape
    F = foul_corners(lane); y_foul = float(max(F[0][1], F[1][1])); span = y_foul - vp[1]
    results = []
    # Pins at Z=60 ft sit in the FAR band of the image (oracle: head pin ~0.22-0.26 of the foul→vp span). Search
    # that band so the nearer pin reflections / bright lane spots can't win.
    for yh in np.linspace(vp[1] + 0.08 * span, vp[1] + 0.40 * span, 180):
        xl, xr = lane_x(lane, float(yh))
        if not (np.isfinite(xl) and np.isfinite(xr)) or xr - xl < 12:
            continue
        cx = (xl + xr) / 2.0
        try:
            Hm = lane_homography_at(lane, vp, np.array([cx, yh]), Z_HEAD_FT); Hinv = np.linalg.inv(Hm)
        except Exception:
            continue
        lane_px = xr - xl
        bh = max(8, int(0.16 * lane_px))         # pin-body strip height (px), ~a pin tall at this scale
        hw = max(2, int(0.5 * lane_px / 39.0))   # half-width of the sample column (~1 board)
        per = []
        for (x_in, z) in _PINS:
            p = Hinv @ np.array([x_in, z, 1.0])
            if abs(p[2]) < 1e-9:
                per.append(None); continue
            u, vb = int(p[0] / p[2]), int(p[1] / p[2])
            if u - hw < 0 or u + hw >= W or vb - 4 * bh < 0 or vb + bh >= H_img:
                per.append(None); continue
            body = wm[vb - bh:vb, u - hw:u + hw + 1].mean()                 # pin body, just above the base
            gap = wm[vb - 2 * bh:vb - bh, u - hw:u + hw + 1].mean()         # above the pin top = should be dark
            far_above = wm[vb - 4 * bh:vb - 2 * bh, u - hw:u + hw + 1].mean()   # bright here = a pin above → mirror
            per.append(float((body - gap - far_above) / 255.0))
        vals = [s for s in per if s is not None]
        if len(vals) < 5:
            continue
        results.append((float(yh), float(np.sum(vals)), int(np.sum(np.array(vals) > 0.15)),
                        [round(s, 2) if s is not None else None for s in per], float(cx)))
    diag = {'candidates': len(results)}
    if len(results) < 5:
        return None, Z_HEAD_FT, {**diag, 'reason': 'pins not imaged (too few candidate rows)'}
    results.sort(key=lambda r: r[1], reverse=True)
    best = results[0]
    sep = 0.05 * span
    runner = next((r for r in results[1:] if abs(r[0] - best[0]) > sep), None)
    margin = best[1] - (runner[1] if runner else 0.0)
    diag.update(head_y=round(best[0], 1), total=round(best[1], 2), n_positive=best[2],
                per_pin=best[3], runner_total=round(runner[1], 2) if runner else None, margin=round(margin, 2))
    if best[2] < 5:
        return None, Z_HEAD_FT, {**diag, 'reason': f'only {best[2]}/7 pins scored positive'}
    if runner is None or margin < 0.4 * max(best[1], 1e-6):
        return None, Z_HEAD_FT, {**diag, 'reason': 'best pin depth not clearly separated from the next'}
    return np.array([best[4], best[0]]), Z_HEAD_FT, {**diag, 'reason': 'ok'}
