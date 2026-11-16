#!/usr/bin/env python3
"""DEC-131 — VISUAL pin-contact timing (replaces the removed audio t_pins). The pins START MOVING at contact; a
temporal model over the target-lane pin-deck crop times that onset to <=4 frames. This module (a) extracts the
per-frame deck motion signal + a stabilised crop stack around the candidate window (the training/inference feature),
and (b) wraps a trained onset model (`PinContactDetector`) exposing `.contact_time(...)` for `analyze_learned`.

Design notes:
- TARGET LANE ONLY: the deck ROW is the detected head-pin row; the deck WIDTH is the lane geometry at that row, so a
  neighbour lane's pins never enter the crop (the failure mode that broke the naive frame-diff).
- BODIES above the bases: the ball and its lane reflection travel across the pin BASES, so we watch the upper part of
  the deck where only the pins scattering registers.
- Per-frame phase-correlation re-alignment removes residual stabilisation jitter so the motion signal is the pins, not
  camera shake.
"""
from __future__ import annotations
import numpy as np

from lanesight_core.cv.track import lane_x

CROP_W, CROP_H = 48, 48          # the deck crop is resampled to this for the temporal model
# The window is anchored on the FOUL cross + the plausible travel time (12-22 mph => 1.84-3.38 s downlane), NOT on
# the ball's projected deck-arrival: in far/portrait shots the ball moves so slowly in pixels near the pins that its
# projected arrival fires ~1.7 s before the actual contact, so a t_reach-anchored window ends before the pins scatter.
FOUL_LO, FOUL_HI = 1.2, 3.6      # seconds after the foul cross: window spans ~11-25 mph with margin
WIN_PRE, WIN_POST = 0.9, 1.3     # fallback window around t_reach when no foul time is available


def _deck_roi(S, pins, lane):
    """Target-lane deck ROI (y0,y1,x0,x1) + the body mask (upper 60%). Mirrors pin_motion_time's geometry."""
    boxes = pins['boxes']; head = pins['head_pin_row']
    h, w = S['bg'].shape[:2]
    y0 = max(int(min(b[1] for b in boxes)), 0)
    y1 = min(int(max(b[1] + b[3] for b in boxes)), h)
    if lane is not None:
        xl, xr = lane_x(lane, head); pad = 0.2 * (xr - xl)
        x0 = max(int(xl - pad), 0); x1 = min(int(xr + pad), w)
    else:
        x0 = max(int(min(b[0] for b in boxes)), 0); x1 = min(int(max(b[0] + b[2] for b in boxes)), w)
    if y1 - y0 < 6 or x1 - x0 < 6:
        return None
    deck_h = y1 - y0
    body_bot = y0 + int(0.60 * deck_h)
    mask = np.zeros((y1 - y0, x1 - x0), bool)
    mask[0:max(body_bot - y0, 1), :] = True
    return (y0, y1, x0, x1, mask) if mask.sum() >= 20 else None


def deck_motion_series(video, S, pins, lane, track, fps, log=lambda *a, **k: None, want_crops=False, t_foul=None):
    """Per-frame deck motion signal across the contact window. Returns dict:
      t[], energy[] (fraction of body pixels changed vs a pre-contact reference), flow[] (mean abs frame-diff),
      t_reach (window anchor), and optionally crops[N,CROP_H,CROP_W] (stabilised uint8 deck).
    None if the deck/track can't be set up. This is the shared feature for both the trained model and the fallback.
    The window is foul-anchored ([t_foul+FOUL_LO, t_foul+FOUL_HI]) when t_foul is given — reliable, and it always spans
    the true contact — else a wide window around the ball's projected deck-arrival."""
    import cv2
    from lanesight_core.cv.stabilize import frames
    roi = _deck_roi(S, pins, lane)
    if roi is None:
        return None
    y0, y1, x0, x1, mask = roi
    h, w = S['bg'].shape[:2]
    head = pins['head_pin_row']
    if t_foul is not None:
        lo_t, hi_t = t_foul + FOUL_LO, t_foul + FOUL_HI
    else:
        reach = [c['t'] for c in sorted(track, key=lambda c: c['t']) if c['ct'] <= head + 4.0 * c.get('D', 10)]
        tr = reach[0] if reach else (track[-1]['t'] if track else None)
        if tr is None:
            return None
        lo_t, hi_t = tr - WIN_PRE, tr + WIN_POST
    t_reach = lo_t                                   # the reference is built from the first frames of the window
    refs = []; t_list = []; energy = []; flow = []; crops = []
    for i, f in frames(video):
        if i >= len(S['Hs']):
            break
        t = S['ts'][i]
        if t < lo_t:
            continue
        if t > hi_t:
            break
        G = cv2.cvtColor(cv2.warpPerspective(f, S['Hs'][i], (w, h))[y0:y1, x0:x1], cv2.COLOR_BGR2GRAY).astype(np.float32)
        if t < lo_t + 0.15:                          # first ~0.15 s of the window = static pre-contact reference
            refs.append(G); continue
        if isinstance(refs, list):
            if len(refs) < 2:
                return None
            refs = np.median(np.stack(refs), 0).astype(np.float32)
        (dx, dy), _ = cv2.phaseCorrelate(refs, G)
        Ga = cv2.warpAffine(G, np.float32([[1, 0, -dx], [0, 1, -dy]]), (G.shape[1], G.shape[0]))
        dif = np.abs(Ga - refs)
        t_list.append(t)
        energy.append(float((dif[mask] > 35).mean()))
        flow.append(float(dif[mask].mean()))
        if want_crops:
            crops.append(cv2.resize(Ga, (CROP_W, CROP_H), interpolation=cv2.INTER_AREA).astype(np.uint8))
    if len(t_list) < 5:
        return None
    out = {'t': np.array(t_list), 'energy': np.array(energy), 'flow': np.array(flow), 't_reach': float(t_reach),
           'roi': (y0, y1, x0, x1)}
    if want_crops:
        out['crops'] = np.stack(crops) if crops else np.zeros((0, CROP_H, CROP_W), np.uint8)
    return out


def detect_contact(series, wa=15, wb=8, noise_thr=0.08, span_min=0.10, refine_frac=0.20, offset_f=3.0):
    """Frame-accurate pin contact from the deck motion series (DEC-131). The pin scatter is the largest STEP from the
    pre-contact level into a sustained high-motion region; a pre-contact ball bump is a smaller, non-sustained rise.
    Steps: (1) guard out NOISY decks (high baseline = handheld camera-motion residual) and WEAK decks (no scatter);
    (2) changepoint = frame maximising mean(E after) - mean(E before); (3) walk back to where the rise began;
    (4) subtract the calibrated systematic offset (the changepoint lands mid-rise). Returns (t_contact_s, reason)."""
    t = series['t']; E = series['energy']
    if len(t) < 10:
        return None, 'SHORT'
    dt = float(np.median(np.diff(t))) or (1.0 / 60)
    n0 = max(int(0.5 / dt), 5)
    base = float(np.median(E[:n0])); peak = float(np.percentile(E, 95))
    if base > noise_thr:
        return None, 'NOISY'                                  # stabilisation residual drowns the pin signal
    if peak - base < span_min:
        return None, 'WEAK'                                   # deck too far/small — pins don't register
    best = None
    for c in range(wb, len(E) - 4):
        step = E[c:c + wa].mean() - E[max(c - wb, 0):c].mean()
        if best is None or step > best[0]:
            best = (step, c)
    c = best[1]
    before = E[max(c - wb, 0):c].mean(); after = E[c:c + wa].mean()
    thr = before + refine_frac * (after - before)
    k = c
    while k > max(c - wb, 0) and E[k - 1] > thr:
        k -= 1
    if k > 0 and E[k] != E[k - 1]:
        fr = min(max((thr - E[k - 1]) / (E[k] - E[k - 1]), 0.0), 1.0)
        t_rise = t[k - 1] + fr * (t[k] - t[k - 1])
    else:
        t_rise = t[k]
    return float(t_rise - offset_f * dt), 'ok'


class PinContactDetector:
    """DEC-131 visual pin-contact timer. `offset_f` is the single calibrated parameter (the changepoint's systematic
    mid-rise lag, ~3 frames on the labeled set). `.contact_time(...)` is what analyze_learned calls; returns t (s) in
    analysis time, or None when the deck signal is too noisy/weak to time (-> speed goes unavailable, never wrong)."""
    def __init__(self, offset_f=3.0):
        self.offset_f = offset_f

    def contact_time(self, video, S, pins, lane, track, fps, t_foul=None, log=lambda *a, **k: None):
        ser = deck_motion_series(video, S, pins, lane, track, fps, log=log, t_foul=t_foul)
        if ser is None:
            return None
        t_c, reason = detect_contact(ser, offset_f=self.offset_f)
        if t_c is None:
            log(f'[pin-contact] unavailable: {reason}')
        return t_c
