#!/usr/bin/env python3
"""DEC-130 — integrate the learned detector into the EXISTING measurement pipeline.

The detector (ops/train_detector CenterNet: ball heatmap + lane-geometry params) runs on the engine's STABILISED
frames and replaces ONLY find_lanes + blob extraction. We build:
  - a `lane` dict (left/right edge lines to the VP + the foul line) from the detector's 6 lane params, and
  - per-frame `candidates()`-format points from the ball detections,
then hand them to the UNCHANGED link -> extend -> detect_impact -> refine -> compute (+ DEC-128 plausibility/
honesty gates stay in pipeline.analyze). So a clip the classical front-end fails can still yield honest metrics.

This is the server/Python reference; the iOS port mirrors it in Swift (OnDeviceTracker) with the Core ML model.
"""
from __future__ import annotations
import numpy as np

from lanesight_core.cv.track import contact_row, exp_diam, lane_x, BALL_IN, LANE_IN  # noqa
from lanesight_core.cv import track as T


def lane_from_params(p, img_w, img_h):
    """6 normalized params [foul_lx,foul_ly,foul_rx,foul_ry,vp_x,vp_y] -> a lane dict compatible with the engine:
    left/right edges as x=a*y+b (each line foul_pt -> VP), foul line as y=c*x+d. Returns (lane, vp)."""
    flx, fly, frx, fry, vx, vy = (p * np.array([img_w, img_h, img_w, img_h, img_w, img_h])).tolist()
    def line_xy(x0, y0, x1, y1):            # x = a*y + b through (x0,y0),(x1,y1)
        if abs(y1 - y0) < 1e-6:
            y1 += 1e-3
        a = (x1 - x0) / (y1 - y0); b = x0 - a * y0
        return [a, b]
    left = line_xy(flx, fly, vx, vy); right = line_xy(frx, fry, vx, vy)
    # foul line y = c*x + d through the two foul endpoints
    if abs(frx - flx) < 1e-6:
        frx += 1e-3
    c = (fry - fly) / (frx - flx); d = fly - c * flx
    lane = {'left': left, 'right': right, 'foul': [c, d], 'yNear': max(fly, fry), 'yFar': vy}
    vp = np.array([vx, vy], np.float64)
    return lane, vp


def candidates_from_detections(dets, lane, fps):
    """dets: list of (i, ball_box[x,y,w,h]) in stabilised px. Build the per-frame candidates() structure the engine
    links. Returns C = list-per-frame (here one candidate per detected frame)."""
    by_frame = {}
    for (i, box) in dets:
        x, y, w, h = box
        cx = x + w / 2.0; top = y
        ct = contact_row(lane, top)
        xa, xb = lane_x(lane, ct)
        if xb - xa <= 1:
            continue
        D = exp_diam(lane, ct)
        frac = (cx - xa) / (xb - xa)
        by_frame.setdefault(i, []).append(dict(t=i / fps, i=i, cx=cx, top=top, ct=ct, D=D, w=w,
                                               frac=frac, merged=False))
    # C must be a list indexed by frame order; the engine iterates C as list-of-lists
    maxi = max(by_frame) if by_frame else -1
    C = [by_frame.get(i, []) for i in range(maxi + 1)]
    return C


def ball_track_from_detector(dets, lane_params_per_frame, img_w, img_h, fps):
    """Aggregate per-frame lane params (median -> a stable lane), build candidates, and LINK with the engine's
    linker. Returns (track, lane, vp, C). Caller runs extend/impact/refine/compute as usual."""
    lp = np.median(np.array(lane_params_per_frame), axis=0)   # robust lane across frames
    lane, vp = lane_from_params(lp, img_w, img_h)
    C = candidates_from_detections(dets, lane, fps)
    track = T.link(C, vp)
    return track, lane, vp, C
