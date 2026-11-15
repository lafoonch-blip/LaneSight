#!/usr/bin/env python3
"""DEC-130 follow-up — detect the PINS / pin-deck on the STABILISED background (pins are static per shot, so one
detection serves every frame). Used to compute t_pins two independent ways (motion-in-pin-boxes + ball-reaches-
head-pin-row) and cross-check them. OWLv2 (Apache) 'bowling pins' on the clean bg plate, filtered to the far-lane
region + plausible pin size, with a brightness fallback. This is the server reference; the on-device model gets a
trained pins class once the timing logic clears the gate.
"""
from __future__ import annotations
import numpy as np

from lanesight_core.cv.track import lane_x


def _owl_pins(bg_bgr, region, thr=0.08):
    """OWLv2 pin detections within `region`=(y0,y1,x0,x1). Returns boxes [x,y,w,h] in full-frame coords."""
    from ops.zeroshot_label import owl_detect
    y0, y1, x0, x1 = region
    crop = bg_bgr[y0:y1, x0:x1]
    dets = owl_detect(crop, ["a bowling pin", "white bowling pins"], thr=thr, topk=15)
    out = []
    for (x, y, w, h, s, lab) in dets:
        # pins are taller than wide, compact
        if h <= 0 or w <= 0:
            continue
        if 0.2 < w / h < 1.6 and h < 0.5 * (y1 - y0):
            out.append([x0 + x, y0 + y, w, h, s])
    return out


def detect_pins(S, lane, vp, log=lambda *a, **k: None):
    """Return dict: {boxes:[[x,y,w,h],...], head_pin_row: y, deck:(y0,y1,x0,x1)} in STABILISED coords, or None.
    The pins sit in the far region of the lane (below the VP). head_pin_row = the row of the pin CLOSEST to the
    bowler = the max-y (lowest-in-frame) pin bottom — the ball contacts the head pin first."""
    import cv2
    bg = S['bg']; h, w = bg.shape[:2]
    yFar = max(int(vp[1]), 0); yNear = int(lane.get('yNear') or h)
    span = max(yNear - yFar, 10)
    r0 = max(int(yFar - 0.05 * span), 0); r1 = min(int(yFar + 0.5 * span), h)   # far region (pins + a margin)
    xm = (r0 + r1) // 2
    xa, xb = lane_x(lane, xm); padx = 1.1 * (xb - xa)
    xa = max(int(min(xa, xb) - padx), 0); xb = min(int(max(xa, xb) + padx), w)
    if r1 - r0 < 10 or xb - xa < 10:
        return None
    region = (r0, r1, xa, xb)
    boxes = _owl_pins(bg, region)
    if len(boxes) < 2:
        # brightness fallback: pins are bright compact blobs in the far region
        gray = cv2.cvtColor(bg, cv2.COLOR_BGR2GRAY)[r0:r1, xa:xb]
        thr = max(float(np.percentile(gray, 93)), 150.0)
        m = (gray > thr).astype(np.uint8)
        m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        n, lab, stats, _ = cv2.connectedComponentsWithStats(m, 8)
        boxes = []
        for i in range(1, n):
            x, y, bw, bh, area = stats[i]
            if area < 12 or bh < 4 or bw > 0.4 * (xb - xa):
                continue
            if 0.2 < bw / max(bh, 1) < 1.8:
                boxes.append([xa + x, r0 + y, bw, bh, 1.0])
        if len(boxes) < 2:
            return None
    # Keep only TARGET-LANE pins: a pin's center x must lie within the lane edges at the pin's row (+ a small pad,
    # since the lane is narrow at the deck). This drops neighbour-lane pins that would dilute the motion signal and
    # corrupt the head-pin row.
    kept = []
    for b in boxes:
        cx = b[0] + b[2] / 2.0; cy = b[1] + b[3] / 2.0
        xl, xr = lane_x(lane, cy); half = 0.5 * (xr - xl); mid = 0.5 * (xl + xr)
        if abs(cx - mid) <= half + 0.35 * (xr - xl):
            kept.append(b)
    if len(kept) < 2:
        kept = boxes                                           # fall back rather than lose the deck entirely
    # The pins form a tight cluster at the far end; a single spurious low detection (a lane reflection of the pins,
    # or a bright floor spot) must NOT be taken as the head pin. Keep only boxes within the DENSE cluster in y
    # (around the median center-row), then the head pin = the lowest (nearest) box of that cluster.
    cy = np.array([b[1] + b[3] / 2.0 for b in kept])
    my = float(np.median(cy)); band = max(0.10 * span, 0.6 * float(np.median([b[3] for b in kept])) * 4)
    cluster = [b for b, y in zip(kept, cy) if abs(y - my) <= band]
    if len(cluster) < 2:
        cluster = kept
    head = sorted(cluster, key=lambda b: -(b[1] + b[3]))[0]
    head_pin_row = head[1] + head[3]
    return {'boxes': [[b[0], b[1], b[2], b[3]] for b in cluster],
            'head_pin_row': float(head_pin_row), 'deck': region}
