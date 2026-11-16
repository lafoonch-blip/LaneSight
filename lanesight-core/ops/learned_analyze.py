#!/usr/bin/env python3
"""DEC-130 (reformulated per Shayne 2026-11-14) — EVENT-TIMING metrics for the learned detector.

The headline speed (foul->pins average) is TIME-BASED, exactly how the truth was labeled:
    speed = 59.44 ft / (t_pins - t_foul),  t in seconds, with sub-frame interpolation.
  t_foul = the moment the detected ball's ground-contact row crosses the FOUL-LINE row (foul line from the
           learned/classical lane; a few px of row error is negligible — this is timing, not depth).
  t_pins = the moment the pins start moving (detect_impact: frame-diff in the pin-deck ROI) OR the ball reaches
           the pin-deck row.
This needs NO metric-grade depth geometry. Early-lane / far-lane speed stay unavailable (they need depth).

Boards are LATERAL only (no depth): board = interpolate the ball center between the left/right lane edges ON THE
SAME IMAGE ROW. Edges are straight gutter/lane lines fit over many frames (static camera). laydown = at the foul
row; arrows = at the arrow row (arrow detection — TODO add arrow class; for now reported only if an arrow row is
known). Lateral board = 1..39 across the 41.5 in lane (board 1 = right edge looking at the pins, DEC-088).

Entry point: `analyze_learned(clip, detector)` -> a metrics dict compatible with cv_eval's _run_engine
expectations (metrics {k: value}), with status/plausibility per DEC-128.
"""
from __future__ import annotations
import os, tempfile
import numpy as np

from lanesight_core.cv.stabilize import stabilize
from lanesight_core.cv import track as T
from lanesight_core.cv.track import lane_x, contact_row, exp_diam
from lanesight_core.failures import AnalysisFailure

BOARDS = 39
LANE_IN = 41.5
Z_FOUL_PINS = 59.44          # ft, foul line -> head pin (DEC-064)
SPEED_MIN, SPEED_MAX = 8.0, 30.0   # mph plausibility (DEC-128)


def _foul_row_at(lane, x):
    """Image row y of the foul line at lateral position x (lane['foul'] = [c,d], y = c*x + d)."""
    c, d = lane['foul']
    return c * x + d


def t_foul_cross(track, lane):
    """Sub-frame time the ball's ground-contact row crosses the foul-line row. The ball travels foul->pins, so
    its contact row ct DEcreases through the foul row. Returns t (s) or None."""
    pts = sorted([c for c in track if 'ct' in c and 'cx' in c], key=lambda c: c['t'])
    if len(pts) < 2:
        return None
    for a, b in zip(pts[:-1], pts[1:]):
        fa = _foul_row_at(lane, a['cx']); fb = _foul_row_at(lane, b['cx'])
        da = a['ct'] - fa; db = b['ct'] - fb          # >0 behind foul (toward camera), <0 past it
        if da >= 0 and db < 0 and da != db:
            frac = da / (da - db)
            return a['t'] + frac * (b['t'] - a['t'])
    # ball already past the foul at the first point: extrapolate from the first two points
    a, b = pts[0], pts[1]
    fa = _foul_row_at(lane, a['cx']); fb = _foul_row_at(lane, b['cx'])
    da = a['ct'] - fa; db = b['ct'] - fb
    if da != db:
        frac = da / (da - db)
        t = a['t'] + frac * (b['t'] - a['t'])
        if abs(t - a['t']) < 0.4:                     # only trust a short extrapolation
            return t
    return None


def lateral_board(track, lane, row_y, tol_rows=40):
    """Ball board (1..39) at image row `row_y`: find the track point nearest that row, interpolate the ball
    center x between the lane edges AT THAT ROW. Lateral only — no depth. board 1 = right edge (DEC-088)."""
    cand = [c for c in track if 'cx' in c and 'ct' in c and abs(c['ct'] - row_y) <= tol_rows]
    if not cand:
        return None
    c = min(cand, key=lambda c: abs(c['ct'] - row_y))
    xa, xb = lane_x(lane, c['ct'])                    # left, right edge x at the ball's row
    if xb - xa <= 1:
        return None
    frac = (c['cx'] - xa) / (xb - xa)                 # 0 at left edge, 1 at right edge
    frac = min(max(frac, 0.0), 1.0)
    board_from_left = 1 + frac * (BOARDS - 1)
    return BOARDS + 1 - board_from_left               # board 1 = right edge looking at the pins


def locate_pin_deck(S, lane, vp):
    """Find the pin-deck box in the STABILISED background by brightness — pins are the bright cluster at the far
    end of the lane (above mid-lane, within the lane x-range). Returns (y0,y1,x0,x1) or None. The ball only
    ENTERS this tight box at impact, so motion here is unambiguous (unlike a broad far-lane band)."""
    import cv2
    bg = S['bg']; gray = cv2.cvtColor(bg, cv2.COLOR_BGR2GRAY)
    h, w = gray.shape
    yFar = max(int(vp[1]), 0); yNear = int(lane.get('yNear') or h)
    span = max(yNear - yFar, 10)
    r0 = max(int(yFar + 0.02 * span), 0); r1 = min(int(yFar + 0.42 * span), h)   # far region (pins live here)
    xm = (r0 + r1) // 2
    xa, xb = lane_x(lane, xm); padx = 0.9 * (xb - xa)
    xa = max(int(min(xa, xb) - padx), 0); xb = min(int(max(xa, xb) + padx), w)
    if r1 - r0 < 10 or xb - xa < 10:
        return None
    region = gray[r0:r1, xa:xb]
    thr = max(float(np.percentile(region, 90)), 140.0)
    ys, xs = np.where(region > thr)
    if len(ys) < 15:
        return None
    py0, py1 = np.percentile(ys, [3, 97]); px0, px1 = np.percentile(xs, [3, 97])
    return (int(r0 + py0), int(r0 + py1) + 1, int(xa + px0), int(xa + px1) + 1)


def robust_pin_impact(path, S, lane, vp, track, log=lambda *a, **k: None):
    """t_pins (s) = first frame the PINS move, watched in the brightness-located pin-deck box (the ball enters it
    only at impact). Frame-diff vs a pre-arrival reference, ball masked. Returns t or None."""
    import cv2
    from lanesight_core.cv.stabilize import frames
    box = locate_pin_deck(S, lane, vp)
    if box is None:
        return None
    y0, y1, x0, x1 = box
    h, w = S['bg'].shape[:2]
    tt = np.array([c['t'] for c in track]); ct_t = np.array([c['ct'] for c in track])
    cx_t = np.array([c['cx'] for c in track]); D_t = np.array([c['D'] for c in track])
    # watch from when the ball nears the pin box (ct within ~2 box-heights below y1) to a bit after
    bh = y1 - y0
    reach = [c['t'] for c in sorted(track, key=lambda c: c['t']) if c['ct'] <= y1 + 2.5 * bh]
    t_reach = reach[0] if reach else (tt.max() if len(tt) else None)
    if t_reach is None:
        return None
    refs = []; series = []
    for i, f in frames(path):
        if i >= len(S['Hs']):
            break
        t = S['ts'][i]
        if t < t_reach - 0.8:
            continue
        if t > t_reach + 1.3:
            break
        G = cv2.cvtColor(cv2.warpPerspective(f, S['Hs'][i], (w, h))[y0:y1, x0:x1],
                         cv2.COLOR_BGR2GRAY).astype(np.float32)
        if t < t_reach - 0.10:
            refs.append(G); continue
        if isinstance(refs, list):
            if len(refs) < 2:
                return None
            refs = np.median(np.stack(refs), 0).astype(np.float32)
        (dx, dy), _ = cv2.phaseCorrelate(refs, G)
        G = cv2.warpAffine(G, np.float32([[1, 0, -dx], [0, 1, -dy]]), (G.shape[1], G.shape[0]))
        dif = np.abs(G - refs)
        if len(tt):                        # mask the ball if it is inside the box
            k = int(np.clip(np.searchsorted(tt, t), 1, len(tt) - 1))
            a = (t - tt[k - 1]) / max(tt[k] - tt[k - 1], 1e-6); a = float(np.clip(a, 0, 1))
            bx = cx_t[k - 1] + a * (cx_t[k] - cx_t[k - 1]); by = ct_t[k - 1] + a * (ct_t[k] - ct_t[k - 1])
            bd = D_t[min(k, len(D_t) - 1)]
            ry0 = int(by - 1.5 * bd) - y0; ry1 = int(by + 1.5 * bd) - y0
            cx0 = int(bx - 1.5 * bd) - x0; cx1 = int(bx + 1.5 * bd) - x0
            dif[max(ry0, 0):max(ry1, 0), max(cx0, 0):max(cx1, 0)] = 0.0
        series.append((t, float((dif > 35).mean())))
    if len(series) < 5:
        return None
    E = np.array(series)
    pre = E[E[:, 0] < t_reach]
    base = np.median(pre[:, 1]) if len(pre) else 0.0
    sd = (1.4826 * np.median(np.abs(pre[:, 1] - base)) + 0.004) if len(pre) else 0.02
    thr = max(base + 6 * sd, 0.06)         # pins falling change a big fraction of the (tight) box
    for k in range(len(E) - 3):
        if E[k, 1] > thr and (E[k:k + 4, 1] > thr).sum() >= 3:
            return float(E[k, 0])
    return None


def _front_end(clip, out_prefix, log=lambda *a, **k: None, return_t0=False):
    """Production front-end: trim to the shot window + HDR->SDR, EXACTLY like lanesight_runner.core.analyze_once,
    so the detector sees the same focused frames the production engine does (the untrimmed whole clip fragments
    the link and the per-frame argmax picks up non-ball peaks across a long span). When return_t0, also return the
    trim start time t0 (s in the ORIGINAL clip) so detected event times (in the trimmed/stabilised clock) can be
    mapped back to original-clip frames for per-event comparison against the labels."""
    from lanesight_runner.probe import probe as _probe, convert_sdr
    from lanesight_runner.trim import detect_window, trim_clip
    p = _probe(clip)
    src = clip; t0 = 0.0
    try:
        t0w, t1w, win = detect_window(clip, log=log)
        if t0w is not None:
            trimmed = out_prefix + '_trim.mov'; trim_clip(clip, trimmed, t0w, t1w); src = trimmed; t0 = float(t0w)
    except Exception as e:
        log(f'trim skipped: {e}')
    if p.get('hdr'):
        sdr = os.path.splitext(src)[0] + '_sdr.mov'
        convert_sdr(src, sdr); src = sdr
    return (src, t0) if return_t0 else src


def pin_motion_time(video, S, pins, track, fps, lane=None, log=lambda *a, **k: None):
    """Follow-up #1: t_pins = first frame of real motion in the target-lane DECK (ignoring the lane in front, where
    the ball's reflection travels). The deck ROW comes from the detected pins (head_pin_row + pin heights); the
    deck WIDTH comes from the LANE geometry at that row — so a single correctly-located pin still defines the full
    target-lane deck, robust to low pin recall."""
    import cv2
    from lanesight_core.cv.stabilize import frames
    boxes = pins['boxes']; head = pins['head_pin_row']
    h, w = S['bg'].shape[:2]
    y0 = max(int(min(b[1] for b in boxes)), 0)
    y1 = min(int(max(b[1] + b[3] for b in boxes)), h)
    if lane is not None:
        xl, xr = lane_x(lane, head); pad = 0.2 * (xr - xl)   # target-lane width at the deck + small pad
        x0 = max(int(xl - pad), 0); x1 = min(int(xr + pad), w)
    else:
        x0 = max(int(min(b[0] for b in boxes)), 0); x1 = min(int(max(b[0] + b[2] for b in boxes)), w)
    if y1 - y0 < 6 or x1 - x0 < 6:
        return None
    # Watch the whole target-lane DECK region, BODIES above the bases. The ball — and its mirror reflection —
    # travel at LANE level across the pin BASES, so excluding the bottom ~40% (bases + lane in front) means only
    # the pins SCATTERING registers, not the ball arriving. Using the deck bounding box (not the sparse individual
    # boxes) makes it robust to low pin recall — a few correctly-located pins still define the deck extent.
    deck_h = y1 - y0
    body_bot = y0 + int(0.60 * deck_h)                 # bodies = upper 60% of the deck span
    mask = np.zeros((y1 - y0, x1 - x0), bool)
    mask[0:max(body_bot - y0, 1), :] = True
    if mask.sum() < 20:
        return None
    head = pins['head_pin_row']
    reach = [c['t'] for c in sorted(track, key=lambda c: c['t']) if c['ct'] <= head + 4.0 * c.get('D', 10)]
    t_reach = reach[0] if reach else (track[-1]['t'] if track else None)
    if t_reach is None:
        return None
    refs = []; series = []
    for i, f in frames(video):
        if i >= len(S['Hs']):
            break
        t = S['ts'][i]
        if t < t_reach - 0.9:
            continue
        if t > t_reach + 1.3:
            break
        G = cv2.cvtColor(cv2.warpPerspective(f, S['Hs'][i], (w, h))[y0:y1, x0:x1], cv2.COLOR_BGR2GRAY).astype(np.float32)
        if t < t_reach - 0.12:
            refs.append(G); continue
        if isinstance(refs, list):
            if len(refs) < 2:
                return None
            refs = np.median(np.stack(refs), 0).astype(np.float32)
        (dx, dy), _ = cv2.phaseCorrelate(refs, G)
        G = cv2.warpAffine(G, np.float32([[1, 0, -dx], [0, 1, -dy]]), (G.shape[1], G.shape[0]))
        dif = np.abs(G - refs)
        series.append((t, float((dif[mask] > 35).mean())))
    if len(series) < 5:
        return None
    E = np.array(series)
    pre = E[E[:, 0] < t_reach]
    base = np.median(pre[:, 1]) if len(pre) else 0.0
    sd = (1.4826 * np.median(np.abs(pre[:, 1] - base)) + 0.004) if len(pre) else 0.02
    thr = max(base + 6 * sd, 0.05)
    for k in range(len(E) - 3):
        if E[k, 1] > thr and (E[k:k + 4, 1] > thr).sum() >= 3:
            return float(E[k, 0])
    return None


def geometric_contact_time(track, head_pin_row, fps):
    """Follow-up #2: t_pins = time the ball's contact row reaches the HEAD-PIN row. Interpolate between the two
    track points that bracket it; if the track ends before the head-pin row, extrapolate from the last few points
    (<=3 frames of extrapolation allowed). Returns t or None."""
    pts = sorted([c for c in track if 'ct' in c], key=lambda c: c['t'])
    if len(pts) < 3:
        return None
    for a, b in zip(pts[:-1], pts[1:]):
        if (a['ct'] - head_pin_row) >= 0 and (b['ct'] - head_pin_row) < 0 and a['ct'] != b['ct']:
            frac = (a['ct'] - head_pin_row) / (a['ct'] - b['ct'])
            return a['t'] + frac * (b['t'] - a['t'])
    # track ends above the head-pin row? already past — not applicable. Else extrapolate forward (<=3 frames).
    last = pts[-3:]
    tt = np.array([c['t'] for c in last]); cc = np.array([c['ct'] for c in last])
    if cc[-1] <= head_pin_row:                       # already reached/passed within the track
        return None
    sl = np.polyfit(tt, cc, 1)                        # ct = sl[0]*t + sl[1]
    if sl[0] >= -1e-6:
        return None
    t_hit = (head_pin_row - sl[1]) / sl[0]
    if 0 < (t_hit - tt[-1]) <= 3.0 / max(fps, 1):
        return float(t_hit)
    return None


def extend_track_to_pins(video, S, lane, vp, track, head_pin_row, detector, log=lambda *a, **k: None):
    """Follow-up #3: extend the ball track toward the pins using a CONSTANT-ACCELERATION motion model to predict
    the next position + a NATIVE-RES crop detection to confirm it (the far-lane ball is ~8px and is lost in the
    downsized full-frame pass). Bridges <=3 missed frames from the model. Stops at the head-pin row. This lets
    t_geom reach the head-pin row from REAL detections instead of a perspective-biased extrapolation."""
    import cv2
    pts = sorted([c for c in track if 'i' in c], key=lambda c: c['t'])
    if len(pts) < 5:
        return track
    tt = np.array([c['t'] for c in pts]); cxa = np.array([c['cx'] for c in pts]); cta = np.array([c['ct'] for c in pts])
    n = min(15, len(pts))
    px = np.polyfit(tt[-n:], cxa[-n:], 2); pc = np.polyfit(tt[-n:], cta[-n:], 2)   # constant-accel (quadratic)
    H, W = S['bg'].shape[:2]; Hs = S['Hs']
    cap = cv2.VideoCapture(video)
    misses = 0; new = []; i = int(pts[-1]['i']) + 1
    MAX_EXT = 60                                       # hard cap: never scan more than ~1 s of frames (perf guard)
    while i < len(Hs) and misses <= 3 and len(new) + (i - int(pts[-1]['i'])) < MAX_EXT:
        t = S['ts'][i]
        pcx = float(np.polyval(px, t)); pct = float(np.polyval(pc, t))
        if pct <= head_pin_row:
            break
        cap.set(cv2.CAP_PROP_POS_FRAMES, i)
        ok, f = cap.read()
        if not ok:
            break
        stab = cv2.warpPerspective(f, Hs[i].astype(np.float64), (W, H))
        det = detector.detect_in_crop(stab, pcx, pct)
        if det is not None and abs(det[0] - pcx) < 45 and abs(det[1] - pct) < 45:
            bcx, bcy, bw, bh, sc = det
            top = bcy - bh / 2.0
            ctr = contact_row(lane, top); xa, xb = lane_x(lane, ctr)
            if xb - xa > 1:
                new.append(dict(t=t, i=i, cx=bcx, top=top, ct=ctr, D=exp_diam(lane, ctr), w=bw,
                                frac=(bcx - xa) / (xb - xa), merged=False))
                misses = 0
                # refit the model including the new point (keeps the prediction honest as the ball decelerates)
                pts2 = pts + new; m = min(15, len(pts2))
                t2 = np.array([c['t'] for c in pts2]); x2 = np.array([c['cx'] for c in pts2]); c2 = np.array([c['ct'] for c in pts2])
                px = np.polyfit(t2[-m:], x2[-m:], 2); pc = np.polyfit(t2[-m:], c2[-m:], 2)
            else:
                misses += 1
        else:
            misses += 1
        i += 1
    cap.release()
    if new:
        log(f'extended track by {len(new)} native-res crop detections toward the pins')
    return track + new


def analyze_learned(clip, detector, log=lambda *a, **k: None, mc_detector=None, pin_contact_detector=None):
    """Run the learned detector + event-timing metrics on one clip. Returns a dict with 'metrics', 'status',
    'reason_code', 'camera_class'(caller fills), 'track_pts'."""
    with tempfile.TemporaryDirectory() as td:
        video, t0 = _front_end(clip, os.path.join(td, 'ev'), log=log, return_t0=True)   # trim + HDR->SDR
        S = stabilize(video, log=log)
        detector.prepare(video, S)
        p = detector._prepared
        fps = p['fps']
        G = detector.geometry(video, S); vp = G['vp']
        out = {'metrics': {}, 'status': 'analyzed', 'track_pts': 0, 'reason_code': None,
               'n_dets': len(p['dets']), 't0': t0, 'fps': fps}
        best = None
        for lane in G['lanes']:
            C = detector.candidates(S, lane, vp)
            Tk = T.link(C, vp)
            if not Tk:
                continue
            Tk = T.extend_forward(detector.candidates(S, lane, vp), Tk, lane, vp, log=log)
            score = len(Tk)
            if best is None or score > best[0]:
                best = (score, lane, Tk)
        if best is None:
            out['reason_code'] = 'BALL_TRACK_NOT_FOUND'; return out
        _, lane, Tk = best
        out['track_pts'] = len(Tk)
        if len(Tk) < 6:
            out['reason_code'] = 'BALL_TRACK_NOT_FOUND'; return out
        # --- t_pins via the pins class, two independent ways, cross-checked (DEC-130 follow-ups #1 + #2) ---
        from ops.pin_detect import detect_pins
        mc_boxes = mc_detector.pins_boxes(S['bg']) if mc_detector is not None else None   # trained pins class
        pins = detect_pins(S, lane, vp, log=log, boxes=mc_boxes)
        t_motion = t_geom = None
        if pins is not None:
            out['head_pin_row'] = pins['head_pin_row']; out['n_pins'] = len(pins['boxes'])
            # #3 (crop track extension) is DISABLED by default — its per-frame VideoCapture seeks are very slow and
            # it is not needed: pin_motion watches the deck directly and t_geom uses the existing track (which
            # usually reaches the head-pin row). Set LS_CROP_EXTEND=1 to re-enable.
            if os.environ.get('LS_CROP_EXTEND') == '1':
                Tk = extend_track_to_pins(video, S, lane, vp, Tk, pins['head_pin_row'], detector, log=log)
                out['track_pts'] = len(Tk)
            t_motion = pin_motion_time(video, S, pins, Tk, fps, lane=lane, log=log)
            t_geom = geometric_contact_time(Tk, pins['head_pin_row'], fps)
        frame_s = 1.0 / max(fps, 1)
        tf = t_foul_cross(Tk, lane)
        # --- t_pins: VISUAL pin-contact (DEC-131). Primary = the temporal "pins start moving" classifier on the
        # target-lane pin-deck crop (frame-accurate); fall back to the motion/geom cross-check. No audio (DEC-131). ---
        t_cls = None
        if pins is not None and pin_contact_detector is not None:
            try:
                t_cls = pin_contact_detector.contact_time(video, S, pins, lane, vp, fps, anchor=t_geom, log=log)
            except Exception as e:
                log(f'[pin-cls] contact failed: {e}')
        t_imp = None
        if t_cls is not None:
            t_imp = t_cls; out['t_pins_src'] = 'classifier'          # frame-accurate (pins-start-moving classifier)
        elif t_motion is not None and t_geom is not None:
            if abs(t_motion - t_geom) <= 2.0 * frame_s:
                t_imp = max(t_motion, t_geom); out['t_pins_src'] = 'visual'
            else:
                out['reason_code'] = 'CONTACT_AMBIGUOUS'
        elif t_motion is not None:
            t_imp = t_motion; out['t_pins_src'] = 'visual'
        elif t_geom is not None:
            t_imp = t_geom; out['t_pins_src'] = 'visual'
        if t_imp is None and out['reason_code'] is None and os.environ.get('LS_IMPACT_FALLBACK') == '1':
            # Opt-in last resort only: the engine's ball-following detect_impact is unreliable on these camera
            # angles (it produced plausible-but-wrong speeds), so it no longer feeds the headline by default —
            # without a pin-contact time the honest answer is PIN_IMPACT_NOT_DETECTED (unavailable).
            try:
                t_imp, _ = T.detect_impact(video, S, lane, Tk, log=log)
            except Exception:
                t_imp = None
        out['t_foul'] = tf; out['t_pins_motion'] = t_motion; out['t_pins_geom'] = t_geom   # for per-event diagnosis
        # Foul-confidence guard: if the foul crossing is extrapolated well BEFORE the first observed track point,
        # we never saw the ball behind the foul and the crossing time is unreliable (it biases speed) -> withhold.
        # A short extrapolation (<=5 frames, e.g. the ball first seen just past the line) stays trusted.
        if tf is not None and Tk and tf < Tk[0]['t'] - 5 * frame_s:
            out['reason_code'] = 'FOUL_CROSS_LOW_CONFIDENCE'
        # --- headline speed: time-based foul->pins ---
        if out['reason_code'] in ('CONTACT_AMBIGUOUS', 'FOUL_CROSS_LOW_CONFIDENCE'):
            pass
        elif t_imp is not None and tf is not None and t_imp > tf:
            mph = Z_FOUL_PINS / (t_imp - tf) * 3600 / 5280
            if SPEED_MIN <= mph <= SPEED_MAX:
                out['metrics']['speed_avg_foul_to_pins'] = round(float(mph), 2)
                out['metrics']['ball_speed'] = round(float(mph), 2)   # headline = foul->pins (time-based)
                out['t_pins_motion'] = t_motion; out['t_pins_geom'] = t_geom; out['t_foul'] = tf
            else:
                out['reason_code'] = 'IMPLAUSIBLE_VALUE'
        else:
            out['reason_code'] = 'PIN_IMPACT_NOT_DETECTED' if t_imp is None else 'FOUL_CROSS_NOT_DETECTED'
        # --- boards: LATERAL only, calibrated by the detected landmarks (known boards) where available ---
        foul_y = lane.get('yNear') or max(_foul_row_at(lane, Tk[0]['cx']), 1)
        # landmark-calibrated laydown (foul-dots) + arrows board (arrows), falling back to lane-edge interpolation.
        lay = arr_board = None
        if mc_detector is not None:
            from ops.landmark_calib import boards_from_landmarks
            lay, arr_board = boards_from_landmarks(mc_detector, S, lane, vp, Tk, foul_y)
        if lay is None:
            lay = lateral_board(Tk, lane, foul_y)
        if lay is not None and 1 <= lay <= BOARDS:
            out['metrics']['laydown_board'] = round(float(lay), 1)
        if arr_board is not None and 1 <= arr_board <= BOARDS:
            out['metrics']['arrows_board'] = round(float(arr_board), 1)
        # rev rate is geometry-free (reuse the engine) — optional, best-effort
        return out
