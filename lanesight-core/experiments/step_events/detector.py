"""Event-based approach step detector (OFFLINE EXPERIMENT — not a production code path).

Finds individual leg-advancement (plant) events, not periodic peaks. For each frame it uses the existing pose
output (landmarks only) to measure, along a per-clip forward axis:
  * each leg's ANKLE (or KNEE, when ankles aren't visible) advancement relative to the hip midpoint,
  * hip forward translation,
and takes candidate events = ALTERNATING leg-advance maxima, each confirmed by hip forward translation since the
previous event (this rejects in-place weight shifts, the backswing, and slide adjustments, which advance a foot
or knee but do NOT move the hip down-lane). Events are restricted to the setup→slide window.

The detector does NOT know the expected step count. It returns the events it finds plus a per-clip visibility
mode (feet / knees_only / insufficient); insufficient → step_count unavailable with a reason.

Thresholds here are physiological (gait timing / fraction-of-approach), chosen once and NOT tuned per clip; the
earlier periodic-cue work is reference only and its thresholds are not reused.
"""
from __future__ import annotations
import numpy as np

# BlazePose indices not re-exported by the production module
L_KNEE, R_KNEE = 25, 26
# imported lazily from the production pose module (read-only) inside helpers that need landmark indices

# --- physiological constants (not clip-tuned) ---
MIN_STEP_INTERVAL_S = 0.22     # a real approach step is never closer than this to the next
PEAK_WIN_S = 0.20              # local-maximum neighbourhood for a leg-advance event
MIN_ADV_PROM_FRAC = 0.15       # a leg advance must stand out this much of the clip's advance range (reject jitter)
MIN_HIP_ADVANCE_FRAC = 0.06    # hip must move >= this fraction of its total approach travel between two steps
ANKLE_VIS_FEET = 0.55          # mean ankle visibility >= this -> trust ankles ("feet" mode)
KNEE_VIS_OK = 0.55             # else mean knee visibility >= this -> "knees_only"
# below both -> "insufficient"


def _interp_nan(a: np.ndarray, tt: np.ndarray) -> np.ndarray:
    g = ~np.isnan(a)
    if not g.any():
        return np.zeros_like(tt)
    return np.interp(tt, tt[g], a[g])


def _smooth(a: np.ndarray, w: int = 3) -> np.ndarray:
    if w <= 1 or len(a) < w:
        return a
    k = np.ones(w) / w
    return np.convolve(np.pad(a, w // 2, mode='edge'), k, mode='valid')[:len(a)]


def _forward_axis(ankle_pts: list[np.ndarray]) -> tuple[float, float]:
    """Down-lane direction = net travel of the feet over the window (feet move most and most consistently).
    ankle_pts = [Lx,Ly,Rx,Ry] each already nan-interpolated over the window. Returns a unit (fx, fy)."""
    Lx, Ly, Rx, Ry = ankle_pts
    dx = (Lx[-1] - Lx[0]) + (Rx[-1] - Rx[0])
    dy = (Ly[-1] - Ly[0]) + (Ry[-1] - Ry[0])
    n = float(np.hypot(dx, dy)) or 1.0
    return dx / n, dy / n


def _local_maxima(sig: np.ndarray, tt: np.ndarray, sep_s: float, min_prom: float) -> list[int]:
    dt = float(np.median(np.diff(tt))) if len(tt) > 1 else 1 / 30
    w = max(1, int(sep_s / dt))
    out: list[int] = []
    for i in range(len(sig)):
        a, b = max(0, i - w), min(len(sig), i + w + 1)
        if sig[i] == sig[a:b].max():
            lo = min(sig[a:i + 1].min() if i > a else sig[i], sig[i:b].min() if b > i else sig[i])
            if sig[i] - lo >= min_prom and (not out or i - out[-1] >= w):
                out.append(i)
    return out


def detect_steps(t: np.ndarray, lms: np.ndarray, window: tuple[float, float], *, handed: str = 'right') -> dict:
    """Pure detector on pose arrays. `t` [N] frame times (s), `lms` [N,33,>=4] (x,y,z,visibility). `window` =
    (setup_end, slide_stop). Returns {steps, step_count, visibility_mode, confidence, forward_axis, debug}.
    steps = [{frame, t_s, leg, evidence, confidence}]. Never uses the expected count."""
    from lanesight_core.form import pose as P   # read-only: landmark indices + helpers
    t = np.asarray(t, float)
    m = (t >= window[0]) & (t <= window[1])
    idx = np.where(m)[0]
    fps = 1.0 / float(np.median(np.diff(t))) if len(t) > 1 else 30.0
    reason_unavail = None
    if len(idx) < 5:
        return dict(steps=[], step_count=None, visibility_mode='insufficient',
                    confidence=0.0, forward_axis=(0.0, 0.0),
                    reason='delivery window too short to detect steps', debug={})
    tt = t[idx]

    def P_(i, ax):
        return _interp_nan(lms[idx, i, ax], tt)

    # visibility mode
    ankle_vis = float(np.nan_to_num(lms[idx][:, [P.L_ANKLE, P.R_ANKLE], 3], nan=0.0).mean())
    foot_vis = float(np.nan_to_num(lms[idx][:, [P.L_ANKLE, P.R_ANKLE, P.L_FOOT, P.R_FOOT], 3], nan=0.0).mean())
    knee_vis = float(np.nan_to_num(lms[idx][:, [L_KNEE, R_KNEE], 3], nan=0.0).mean())
    if ankle_vis >= ANKLE_VIS_FEET:
        mode, ljoint, rjoint, ev = 'feet', P.L_ANKLE, P.R_ANKLE, 'ankle'
    elif knee_vis >= KNEE_VIS_OK:
        mode, ljoint, rjoint, ev = 'knees_only', L_KNEE, R_KNEE, 'knee'
    else:
        return dict(steps=[], step_count=None, visibility_mode='insufficient', confidence=0.0,
                    forward_axis=(0.0, 0.0),
                    reason=f'legs not reliably visible in the approach (ankle vis {ankle_vis:.2f}, '
                           f'knee vis {knee_vis:.2f}); step count unavailable', debug={})

    Lx, Ly = _smooth(P_(ljoint, 0)), _smooth(P_(ljoint, 1))
    Rx, Ry = _smooth(P_(rjoint, 0)), _smooth(P_(rjoint, 1))
    hx = _smooth((P_(P.L_HIP, 0) + P_(P.R_HIP, 0)) / 2)
    hy = _smooth((P_(P.L_HIP, 1) + P_(P.R_HIP, 1)) / 2)
    fx, fy = _forward_axis([Lx, Ly, Rx, Ry])

    def fwd(X, Y):
        return X * fx + Y * fy

    hipf = fwd(hx, hy)
    advL = _smooth(fwd(Lx, Ly) - hipf)
    advR = _smooth(fwd(Rx, Ry) - hipf)
    rng = max(1e-6, float(max(advL.max() - advL.min(), advR.max() - advR.min())))
    prom = MIN_ADV_PROM_FRAC * rng
    hip_total = max(1e-6, float(hipf.max() - hipf.min()))
    min_hip = MIN_HIP_ADVANCE_FRAC * hip_total

    # candidate leg-advance events = local maxima of each leg's advancement
    cands = ([(i, 'L', float(advL[i])) for i in _local_maxima(advL, tt, PEAK_WIN_S, prom)]
             + [(i, 'R', float(advR[i])) for i in _local_maxima(advR, tt, PEAK_WIN_S, prom)])
    cands.sort(key=lambda c: c[0])

    # enforce ALTERNATION: between two same-leg maxima keep the stronger (a true gait alternates feet)
    alt: list[tuple[int, str, float]] = []
    for c in cands:
        if alt and alt[-1][1] == c[1]:
            if c[2] > alt[-1][2]:
                alt[-1] = c
        else:
            alt.append(c)

    # HIP-TRANSLATION gate: accept an event only if the hip advanced >= min_hip since the last accepted event
    # (rejects weight shifts / backswing / slide adjustments that move a leg but not the hip down-lane)
    steps = []
    last_hf = None
    min_sep_fr = max(1, int(MIN_STEP_INTERVAL_S * fps))
    for i, leg, val in alt:
        hf = float(hipf[i])
        if steps and (i - steps[-1]['_i']) < min_sep_fr:
            continue
        if last_hf is not None and (hf - last_hf) < min_hip:
            continue
        last_hf = hf
        # per-event confidence: advance prominence (vs range) blended with local joint visibility
        jvis = float(np.nan_to_num(lms[idx[i], (ljoint, rjoint), 3], nan=0.0).mean())
        conf = round(min(1.0, 0.5 * (val - min(advL.min(), advR.min())) / rng + 0.5 * jvis), 2)
        steps.append(dict(frame=int(idx[i]), t_s=round(float(tt[i]), 4), leg=leg, evidence=ev,
                          confidence=conf, _i=i))
    for s in steps:
        s.pop('_i', None)

    # clip-level confidence: visibility + how cleanly events alternated + hip-advance consistency
    alt_clean = 1.0 if len(steps) >= 2 else 0.5
    clip_conf = round(min(1.0, 0.6 * (foot_vis if mode == 'feet' else knee_vis) + 0.4 * alt_clean), 2)
    return dict(steps=steps, step_count=len(steps), visibility_mode=mode, confidence=clip_conf,
                forward_axis=(round(fx, 3), round(fy, 3)), reason=None,
                debug=dict(ankle_vis=round(ankle_vis, 2), knee_vis=round(knee_vis, 2),
                           foot_vis=round(foot_vis, 2), adv_range=round(rng, 4),
                           hip_total=round(hip_total, 4), tt=tt, advL=advL, advR=advR, hipf=hipf))


def analyze_clip(video: str, *, handed: str = 'right', log=lambda *a: None) -> dict:
    """IO wrapper: extract pose (production, read-only), derive the setup→slide window from the production
    delivery helpers, run detect_steps. Returns the detector dict plus fps and the window."""
    from lanesight_core.form import pose as P
    t, lms = P.extract_landmarks(video, log=log)
    fps = 1.0 / float(np.median(np.diff(t))) if len(t) > 1 else 30.0
    Rx, Ry = P._point(lms, P.R_FOOT_PTS, 0), P._point(lms, P.R_FOOT_PTS, 1)
    Lx, Ly = P._point(lms, P.L_FOOT_PTS, 0), P._point(lms, P.L_FOOT_PTS, 1)
    Rs, Ls = P._speed(Rx, Ry, t), P._speed(Lx, Ly, t)
    deliv = P._find_delivery(t, lms, Rs, Ls)
    if deliv is None:
        return dict(steps=[], step_count=None, visibility_mode='insufficient', confidence=0.0,
                    reason='no delivery isolated', fps=round(fps, 2), window=None, t=t, lms=lms)
    # setup→slide window: from the setup-hold end (where step 1 breaks the stance) to the posted-finish start
    # (the slide has stopped by then). A small start margin + the hip-translation gate inside detect_steps make
    # the exact boundaries non-critical — no step occurs during the setup stance or the finish hold (hip still).
    approach_start, (hold_start, _hold_end) = deliv
    b0 = approach_start[0] + 0.4
    setup_end = P._setup_hold_end(t, Rs, Ls, b0)
    start = max(float(t[0]), min(setup_end, approach_start[0]) - 0.3)
    end = min(float(t[-1]), hold_start + 0.10)
    out = detect_steps(t, lms, (start, end), handed=handed)
    out.update(fps=round(fps, 2), window=(round(start, 3), round(end, 3)), t=t, lms=lms)
    return out
