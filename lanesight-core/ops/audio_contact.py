#!/usr/bin/env python3
"""DEC-130 — frame-accurate t_pins from AUDIO.

The pin impact is a sharp broadband transient. Detecting its onset in the audio track is physically frame-accurate
(unlike position-based pin_geo, which is perspective-limited near the deck where the ball barely moves in pixels).

Pipeline: extract mono audio (ffmpeg) -> STFT spectral-flux onset envelope -> strongest onset inside a search window
-> subtract the sound-travel delay (pins are ~60 ft downlane + the camera's distance behind the foul line, at the
speed of sound 1125 ft/s) -> apply the measured constant capture A/V offset. The window (visual t_pins +/- 25 frames)
keeps neighbour-lane crashes out. The caller cross-checks audio vs visual t_pins; disagreement > 6 frames -> ambiguous.

Server reference (ffmpeg + numpy). On device the same onset math runs on the AVCaptureSession audio buffers.
"""
from __future__ import annotations
import os, subprocess, tempfile
import numpy as np

SOUND_FT_PER_S = 1125.0          # speed of sound, dry air ~68F
LANE_PIN_FT = 60.0               # foul line -> head pin (59.44) + a hair for the deck
HOP = 128                        # STFT hop @ 48 kHz = 2.67 ms (~0.16 frame at 60 fps) — sub-frame onset resolution
NWIN = 512


def extract_audio(clip, sr=48000, log=lambda *a, **k: None):
    """Decode the clip's audio to a mono float32 array at `sr`. Returns (samples, sr) or (None, sr) if no audio."""
    tmp = tempfile.mktemp(suffix='.f32', dir=os.environ.get('TMPDIR', '/tmp'))
    # raw float32 PCM, mono, resampled — robust (no wav header parsing), piped through a temp file
    cmd = ['ffmpeg', '-v', 'error', '-y', '-i', clip, '-map', '0:a:0', '-ac', '1', '-ar', str(sr),
           '-f', 'f32le', tmp]
    try:
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        x = np.fromfile(tmp, dtype=np.float32)
    except subprocess.CalledProcessError as e:
        log(f"[audio] ffmpeg failed: {e.stderr.decode()[:200]}"); return None, sr
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    if x.size == 0:
        return None, sr
    return x, sr


def onset_envelope(x, sr):
    """Spectral-flux onset strength. Returns (env, times_s). High-frequency-weighted: the pin crack is a sharp
    broadband transient, strongest in the highs, so weighting the upper spectrum sharpens the peak vs lane rumble."""
    n = NWIN
    win = np.hanning(n).astype(np.float32)
    nfr = 1 + (len(x) - n) // HOP
    if nfr < 2:
        return np.zeros(0), np.zeros(0)
    # frame the signal
    idx = np.arange(n)[None, :] + HOP * np.arange(nfr)[:, None]
    frames = x[idx] * win
    mag = np.abs(np.fft.rfft(frames, axis=1))            # [nfr, n/2+1]
    nb = mag.shape[1]
    fw = np.linspace(0.3, 1.0, nb)                        # emphasise highs
    mag = mag * fw[None, :]
    flux = np.maximum(0.0, mag[1:] - mag[:-1]).sum(axis=1)   # positive spectral flux
    flux = np.concatenate([[0.0], flux])
    t = (np.arange(nfr) * HOP + n / 2) / sr
    return flux, t


def onset_peaks(clip, win_lo_s, win_hi_s, camera_behind_ft=12.0, av_offset_s=0.0,
                sr=48000, min_rel=0.35, x=None, log=lambda *a, **k: None):
    """All local-maximum onsets inside the window, as delay+offset-corrected CONTACT times (original-clip seconds),
    each with its onset strength. Sorted by time ascending. Lets the caller apply a physical guard (the contact
    cannot precede the ball's arrival at the deck) before choosing, instead of blindly taking the loudest peak."""
    if x is None:
        x, sr = extract_audio(clip, sr, log)
    if x is None:
        return []
    env, t = onset_envelope(x, sr)
    if env.size == 0:
        return []
    delay = (LANE_PIN_FT + camera_behind_ft) / SOUND_FT_PER_S
    m = (t >= win_lo_s) & (t <= win_hi_s)
    if not m.any():
        return []
    ei = np.where(m)[0]
    thr = min_rel * float(env[ei].max())
    peaks = []
    for j in ei:
        if 0 < j < len(env) - 1 and env[j] >= env[j - 1] and env[j] >= env[j + 1] and env[j] >= thr:
            t_onset = t[j]
            peaks.append({'t_contact_s': float(t_onset - delay - av_offset_s), 't_onset_s': float(t_onset),
                          'strength': float(env[j])})
    return sorted(peaks, key=lambda p: p['t_contact_s'])


def pin_onset_time(clip, win_lo_s, win_hi_s, camera_behind_ft=12.0, av_offset_s=0.0,
                   sr=48000, log=lambda *a, **k: None, x=None):
    """Strongest audio onset inside [win_lo_s, win_hi_s] (original-clip seconds), corrected to the physical contact
    time: subtract sound travel (LANE_PIN_FT + camera_behind_ft) and apply the measured capture A/V offset.
    Returns dict {t_contact_s, t_onset_s, delay_s, strength, prominence} in ORIGINAL-clip seconds, or None.
    Pass `x` to reuse already-extracted samples. prominence = peak / median(env in window) — a confidence proxy."""
    if x is None:
        x, sr = extract_audio(clip, sr, log)
    if x is None:
        return None
    env, t = onset_envelope(x, sr)
    if env.size == 0:
        return None
    m = (t >= win_lo_s) & (t <= win_hi_s)
    if not m.any():
        return None
    ei = np.where(m)[0]
    seg = env[ei]
    k = ei[int(np.argmax(seg))]
    # sub-sample parabolic refine around the peak
    if 0 < k < len(env) - 1:
        a, b, c = env[k - 1], env[k], env[k + 1]
        denom = (a - 2 * b + c)
        shift = 0.5 * (a - c) / denom if abs(denom) > 1e-9 else 0.0
        shift = float(np.clip(shift, -1, 1))
    else:
        shift = 0.0
    t_onset = (k + shift) * HOP / sr + (NWIN / 2) / sr
    delay = (LANE_PIN_FT + camera_behind_ft) / SOUND_FT_PER_S
    med = float(np.median(seg)) or 1e-9
    return {'t_onset_s': float(t_onset), 'delay_s': float(delay), 't_contact_s': float(t_onset - delay - av_offset_s),
            'strength': float(env[k]), 'prominence': float(env[k] / med)}
