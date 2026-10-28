"""Shot-window detection and trimming (Milestone 4 speed-up).

iPhone clips are ~30-35 s but the actual shot — ball release, travel down the lane, pin impact and settle — is
only ~6-9 s, usually near the end. Analysis cost is dominated by two full-clip passes (stabilize, then blob
extraction), so trimming to the shot window cuts the slow part ~3-4x, and for HDR clips it also shrinks the
SDR conversion by the same factor.

How the window is found: a cheap pre-pass decodes the clip at low resolution with frame-skipping and measures
lane-region motion energy (camera motion removed by phase correlation). The ball rolling down the lane is a
sustained burst well above the quiet set-up baseline; the EARLIEST such burst is the shot (the ball-return and
rake/sweep that follow it also move, but come after). Audio is not used: in a bowling centre the pin crash is
often quieter than ambient noise and other lanes.

Window margins (tuned on IMG_8754/IMG_8751, re-validate on the seed dataset):
- LEAD 4.0 s before the burst: steady, lane-clean frames for the stabiliser reference and background plate.
- TAIL 2.6 s after the burst: the pins settle ~0.8-1.6 s after the ball reaches them, and on a pale/low-contrast
  lane the low-res burst detector loses the ball early so impact can land ~0.8 s PAST the burst end — 1.8 s was
  then too short and the deck left frame before the pins settled (a blocked/early cut-off read, see pins.py).
  2.6 s covers the settle window in both cases while still ending before the rake sweeps (~3 s+ after impact);
  going much longer lets rake motion pollute the background median and far-end ball track, pushing entry board/
  angle off by several boards. Re-validated: reference metrics unchanged at 2.6 s.

The original clip is never modified; trimming writes a separate working file by stream copy (no re-encode).
If no clear burst is found, or the window would cover most of the clip, the caller analyses the whole clip.
"""
from __future__ import annotations
import json, subprocess
import numpy as np

LEAD_S = 4.0
TAIL_S = 2.6               # footage kept after the burst so the pins settle in view (read_pins)
METRIC_TAIL_S = 1.8       # only this much after the burst feeds the reference frame + background median; the rest
                          # is settle-only, so extending TAIL_S for pin reading can't perturb the shot metrics
MIN_BURST_S = 1.0          # a shot's ball-roll lasts ~2-3 s; ignore briefer blips
SKIP_IF_COVERS = 0.85      # if the window is >=85% of the clip, don't bother trimming


def _video_info(path):
    s = (json.loads(subprocess.run(
        ['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-count_packets',
         '-show_entries', 'stream=r_frame_rate,nb_read_packets', '-of', 'json', path],
        capture_output=True, text=True).stdout).get('streams') or [{}])[0]
    a, b = (s.get('r_frame_rate') or '0/1').split('/')
    fps = float(a) / float(b) if float(b) else 0.0
    return fps, int(s.get('nb_read_packets') or 0)


# A burst where a large fraction of the lane strip is moving is a PERSON (the bowler walking into frame or
# working at the ball return), not a ball. The ball is a small object, so its bursts have a LOW moving-area
# fraction. We keep the original motion-energy burst detection (so windows on good clips are unchanged) and
# only SKIP bursts whose moving area says "body" — that's what lets the trimmer ignore the bowler and pick the
# real throw on a POV/behind-the-return clip (IMG_8929), without perturbing any already-correct clip.
BODY_MAX_FRAC = 0.11      # mean moving-area fraction (of the down-lane strip) above this ⇒ a body, not a ball
MOTION_THRESH = 22        # per-pixel abs-diff (after camera-motion removal) that counts as moving


def detect_window(path, scale=0.2, step=2, lead=LEAD_S, tail=TAIL_S, log=print):
    """Return (t0, t1, info) for the shot window in seconds, or (None, None, info) if no clear shot was found
    (caller then analyses the whole clip). Motion-energy burst detection is unchanged; bursts dominated by
    large-area (body) motion are skipped so the bowler at the ball return isn't mistaken for the throw."""
    fps, nframes = _video_info(path)
    if not fps or nframes < 60:
        return None, None, dict(reason='too short or no fps', fps=fps, nframes=nframes)
    dur = nframes / fps
    import cv2
    cap = cv2.VideoCapture(path)
    if hasattr(cv2, "CAP_PROP_ORIENTATION_AUTO"): cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1)  # DEC-092 orientation
    prev = None; energy = []; body = []; idxs = []; i = 0
    while True:
        if not cap.grab(): break
        if i % step == 0:
            ok, f = cap.retrieve()
            if not ok: break
            sm = cv2.cvtColor(cv2.resize(f, None, fx=scale, fy=scale), cv2.COLOR_BGR2GRAY).astype(np.float32)
            if prev is not None:
                (dx, dy), _ = cv2.phaseCorrelate(prev, sm)                   # cancel camera motion
                warp = cv2.warpAffine(sm, np.float32([[1, 0, -dx], [0, 1, -dy]]), (sm.shape[1], sm.shape[0]))
                d = np.abs(warp - prev); h, w = d.shape
                roi = d[int(h * 0.35):int(h * 0.95), int(w * 0.2):int(w * 0.8)]  # lane region; skip ceiling/edges
                energy.append(float(roi.mean())); idxs.append(i)
                body.append(float((roi > MOTION_THRESH).mean()))            # moving-area fraction (body vs ball)
            prev = sm
        i += 1
    cap.release()
    if len(energy) < 10:
        return None, None, dict(reason='no motion signal', fps=fps, nframes=nframes, dur=round(dur, 2))
    E = np.convolve(np.array(energy), np.ones(5) / 5, 'same'); idxs = np.array(idxs)
    body = np.array(body)
    base = float(np.median(E)); thr = base * 3.0
    above = E > thr
    runs = []; s = None
    for k, v in enumerate(above):
        if v and s is None: s = k
        if not v and s is not None: runs.append((s, k - 1)); s = None
    if s is not None: runs.append((s, len(above) - 1))
    runs = [(a, b) for a, b in runs if (idxs[b] - idxs[a]) / fps >= MIN_BURST_S]
    info = dict(fps=round(fps, 3), nframes=nframes, dur=round(dur, 2), base=round(base, 3),
                thr=round(thr, 3), nbursts=len(runs))
    if not runs:
        info['reason'] = 'no sustained burst'
        return None, None, info
    # Skip bursts that are a PERSON (large-area motion); the earliest NON-body burst is the shot. If every
    # burst looks like a body, fall through to the earliest (old behaviour) rather than give up.
    ball_runs = [(a, b) for a, b in runs if float(body[a:b + 1].mean()) < BODY_MAX_FRAC]
    info['nbursts_nonbody'] = len(ball_runs)
    a, b = (ball_runs or runs)[0]
    t_s = idxs[a] / fps; t_e = idxs[b] / fps
    t0 = max(0.0, t_s - lead); t1 = min(dur, t_e + tail)
    info['burst'] = (round(t_s, 2), round(t_e, 2)); info['window'] = (round(t0, 2), round(t1, 2))
    if (t1 - t0) >= SKIP_IF_COVERS * dur:
        info['reason'] = 'window covers most of the clip'
        return None, None, info
    return round(t0, 2), round(t1, 2), info


def trim_clip(src, dst, t0, t1):
    """Stream-copy (no re-encode) the window [t0, t1] to dst. Fast and lossless; cuts at the nearest keyframe
    at or before t0, so a little extra lead is normal. Frame timestamps restart near 0; metrics use time
    differences, which are preserved."""
    r = subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', str(t0), '-to', str(t1), '-i', src,
                        '-map', '0', '-c', 'copy', '-movflags', '+faststart', dst], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f'trim failed: {r.stderr.strip()[-200:]}')
    return dst
