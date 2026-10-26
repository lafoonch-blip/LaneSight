"""Form P1 pose backend — rear/bowler-side view (DEC-047, FORM_ANALYSIS_SPEC §3/§4/§9).

Implements `pose_backend(video, out_prefix, handed) -> {metric_key: Measurement-dict}` for the timing/relative
P1 metrics that are robust WITHOUT floor-plane calibration. Absolute/board metrics (drift in boards, slide
length in inches, laydown distance, ball speed, entry board/angle) stay `unavailable` with a reason — the
floor homography needed for them is still unresolved on this low rear-view framing (see
02_RESEARCH/TRAINING_VIDEOS_CALIBRATED_METRICS.md addenda 2-4).

Method (matches the 2026-10-17 and 2026-10-20 pilots):
  * MediaPipe Pose (heavy) on every frame, timestamped from the real container PTS (not nominal fps).
  * Foot plants from the per-foot height "staircase" + stationary runs -> step count / intervals / cadence.
  * The swing is tracked by a *ball-colour* blob seeded on the bowling wrist (the pilot proved ball-colour vs
    background gives clean apex / bottom-of-arc). Release = ball/hand separation. Backswing apex / bottom of
    arc come from the ball arc, with the bowling-wrist arc as a fallback when the ball blob is lost.
  * Delivery is isolated by the finish hold (both feet stationary >= FINISH_HOLD_MIN_S after the slide).
  * Slo-mo export (IMG_8845: 120 fps captured, saved at 30 fps playback) is DETECTED from an implausibly slow
    cadence and corrected by an integer factor; if it can't be resolved the raw values are returned flagged
    'slo-mo, uncorrected' — never silently wrong (per the task contract / DEC-028).

No fabricated values: a metric that can't be measured is value=None, status='unavailable', with the reason
(DEC-026 / DEC-042).
"""
from __future__ import annotations
import hashlib, os, subprocess
from dataclasses import asdict
import numpy as np
from ..models.shot import Measurement

POSE_BACKEND_VERSION = 'form-pose-0.1.0'
_SRC = 'lanesight_form'

# --- model location + integrity (never hardcode the only path; default under ~/LaneSightData, env-overridable) ---
POSE_MODEL_ENV = 'LANESIGHT_POSE_MODEL'
POSE_MODEL_PATH = os.environ.get(
    POSE_MODEL_ENV, os.path.expanduser('~/LaneSightData/models/pose_landmarker_heavy.task'))
POSE_MODEL_SHA256 = '64437af838a65d18e5ba7a0d39b465540069bc8aae8308de3e318aad31fcbc7b'

# --- MediaPipe pose landmark indices (BlazePose 33-point topology) ---
NOSE = 0
L_SHOULDER, R_SHOULDER = 11, 12
L_HIP, R_HIP = 23, 24
L_WRIST, R_WRIST = 15, 16
L_ANKLE, R_ANKLE = 27, 28
L_HEEL, R_HEEL = 29, 30
L_FOOT, R_FOOT = 31, 32
# A foot = ankle+heel+foot_index fused (visibility-weighted); left/right handedness drives the bowling side.
R_FOOT_PTS = (R_ANKLE, R_FOOT, R_HEEL)
L_FOOT_PTS = (L_ANKLE, L_FOOT, L_HEEL)

# --- tuning constants (scale-free where possible; times in seconds) ---
MIN_VIS = 0.3                 # landmark visibility floor to trust a point
FINISH_HOLD_MIN_S = 0.45      # both feet stationary this long = the posted finish (E8->E9 region)
# foot speed is in normalized frame-heights per second (gradient of the 0..1 landmark coord vs real time).
FOOT_STATIONARY = 0.28        # below this a foot is planted (a swinging foot runs ~0.5-1.5)
FOOT_STILL_FINISH = 0.16      # stricter: both feet below this = the posted finish hold
NOMINAL_APPROACH_S = 1.45     # physiological first-step->release for a 4-step approach (used only to size slo-mo)
PLAUSIBLE_STEP_MAX_S = 0.85   # a single real bowling step never exceeds this; above => slo-mo suspected
SLOWMO_FACTORS = (2, 3, 4, 5, 6, 8)   # iPhone slo-mo export factors (120/240 fps over 30 fps playback)


class PoseBackendError(RuntimeError):
    pass


# --------------------------------------------------------------------------- model / IO
def verify_model(path: str = POSE_MODEL_PATH) -> str:
    """Return the model path after checking it exists and its sha256 matches. Raise a clear error otherwise."""
    if not os.path.exists(path):
        raise PoseBackendError(
            f'pose model not found at {path!r}. Set {POSE_MODEL_ENV} or place pose_landmarker_heavy.task '
            'under ~/LaneSightData/models/ (do not commit the model into the repo).')
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            h.update(chunk)
    got = h.hexdigest()
    if got != POSE_MODEL_SHA256:
        raise PoseBackendError(
            f'pose model checksum mismatch at {path!r}: got {got}, expected {POSE_MODEL_SHA256}. '
            'The model file is wrong or corrupt; refusing to run on an unverified model.')
    return path


def frame_times(path: str) -> np.ndarray:
    """Presentation timestamps of every video frame, from the container (ffprobe) — authoritative over fps."""
    r = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                        'frame=pts_time', '-of', 'csv=p=0', path], capture_output=True, text=True)
    ts = np.array([float(x.strip(',')) for x in r.stdout.split() if x.strip(',')])
    return ts


def extract_landmarks(path: str, model_path: str = POSE_MODEL_PATH, log=print) -> tuple[np.ndarray, np.ndarray]:
    """Run MediaPipe Pose (heavy, VIDEO mode) on every frame. Returns (t[N], lms[N,33,5]) where the last axis
    is (x, y, z, visibility, presence), x/y normalized 0..1. Frames with no detection are NaN."""
    try:
        import cv2
        import mediapipe as mp
        from mediapipe.tasks.python import vision, BaseOptions
    except ImportError as e:   # pragma: no cover - env-dependent
        raise PoseBackendError(f'MediaPipe/OpenCV not available: {e}. Install the "form" extra (mediapipe).')
    verify_model(model_path)
    pts = frame_times(path)
    opts = vision.PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=model_path),
        running_mode=vision.RunningMode.VIDEO, num_poses=1,
        min_pose_detection_confidence=0.3, min_tracking_confidence=0.3)
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        raise PoseBackendError(f"OpenCV can't decode {path!r} (re-export as H.264 / Most Compatible).")
    ts: list[float] = []
    rows: list[np.ndarray] = []
    with vision.PoseLandmarker.create_from_options(opts) as lm:
        i = 0
        while True:
            ok, img = cap.read()
            if not ok:
                break
            t = float(pts[i]) if i < len(pts) else (ts[-1] + 1 / 30.0 if ts else 0.0)
            rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            res = lm.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb),
                                      int(round(t * 1000)))
            if res.pose_landmarks:
                L = res.pose_landmarks[0]
                rows.append(np.array([[p.x, p.y, p.z, p.visibility, p.presence] for p in L], np.float32))
            else:
                rows.append(np.full((33, 5), np.nan, np.float32))
            ts.append(t)
            i += 1
    cap.release()
    if not rows:
        raise PoseBackendError(f'no frames decoded from {path!r}')
    log(f'pose: {len(rows)} frames, mean bowling-side wrist visibility '
        f'{np.nanmean([r[R_WRIST, 3] for r in rows]):.2f}')
    return np.array(ts), np.array(rows)


# --------------------------------------------------------------------------- signal helpers
def _smooth(a: np.ndarray, w: int) -> np.ndarray:
    """NaN-aware centered moving average (width w)."""
    n = len(a)
    out = np.full(n, np.nan)
    for i in range(n):
        lo, hi = max(0, i - w // 2), min(n, i + w // 2 + 1)
        seg = a[lo:hi]
        seg = seg[~np.isnan(seg)]
        if len(seg):
            out[i] = seg.mean()
    return out


def _point(lms: np.ndarray, idxs, axis: int) -> np.ndarray:
    """Visibility-weighted series of one coordinate (axis 0=x,1=y) fused over several landmark indices."""
    vals, wts = [], []
    for k in idxs:
        v = lms[:, k, 3].copy()
        c = lms[:, k, axis]
        ok = (v > MIN_VIS) & ~np.isnan(c)
        vals.append(np.where(ok, c, np.nan))
        wts.append(np.where(ok, v, 0.0))
    vals = np.array(vals)
    wts = np.array(wts)
    w = wts.sum(0)
    out = np.nansum(vals * wts, 0) / np.maximum(w, 1e-6)
    out[w < MIN_VIS] = np.nan
    return out


def _torso(lms: np.ndarray) -> float:
    """Robust body scale = median shoulder-to-hip vertical distance (one 'torso length'), for scale-free ratios."""
    sho = _point(lms, (L_SHOULDER, R_SHOULDER), 1)
    hip = _point(lms, (L_HIP, R_HIP), 1)
    d = np.abs(hip - sho)
    d = d[~np.isnan(d)]
    return float(np.median(d)) if len(d) else 0.2


def _speed(x: np.ndarray, y: np.ndarray, t: np.ndarray) -> np.ndarray:
    xf = np.nan_to_num(x, nan=np.nanmean(x) if np.any(~np.isnan(x)) else 0.0)
    yf = np.nan_to_num(y, nan=np.nanmean(y) if np.any(~np.isnan(y)) else 0.0)
    return _smooth(np.hypot(np.gradient(xf, t), np.gradient(yf, t)), 5)


# --------------------------------------------------------------------------- delivery segmentation
BURST_MOTION = 0.35       # combined foot speed (frame-heights/s) above this = the feet are moving
BURST_MIN_S = 0.6         # a real approach burst lasts at least this
BURST_MAX_S = 5.0         # ... and (even stretched by slo-mo) no more than this
FOOTVIS_MIN = 0.45        # the approach has the feet clearly in frame; bystander walk-backs do not


def _find_delivery(t, lms, Rs, Ls, burst_motion=BURST_MOTION, burst_max_s=BURST_MAX_S, still_thr=FOOT_STILL_FINISH):
    """Isolate the one delivery. The approach is a burst of alternating foot motion with the feet clearly in
    frame; empty-frame periods and bystander walk-backs are rejected by low foot visibility. The posted finish
    is the first both-feet-still run after that burst. Returns (approach_win, (hold_start, hold_end)) or None.
    `burst_motion`/`burst_max_s`/`still_thr` are lowered/raised when a slo-mo export is suspected (every speed
    is divided by the slow factor, so the same gait reads slower)."""
    footvis = np.nan_to_num(lms[:, [L_ANKLE, R_ANKLE, L_FOOT, R_FOOT], 3], nan=0.0).mean(1)
    Ms = _smooth(np.fmax(np.nan_to_num(Rs, nan=9.0), np.nan_to_num(Ls, nan=9.0)), 9)
    hot = np.nan_to_num(Ms, nan=0.0) > burst_motion
    n = len(t)
    bursts = []
    i = 0
    while i < n:
        if hot[i]:
            j = i
            while j < n and hot[j]:
                j += 1
            t0, t1 = t[i], t[min(j - 1, n - 1)]
            if BURST_MIN_S <= (t1 - t0) <= burst_max_s:
                vis = float(footvis[(t >= t0) & (t <= t1)].mean())
                bursts.append((t0, t1, vis))
            i = j
        else:
            i += 1
    good = [b for b in bursts if b[2] >= FOOTVIS_MIN]
    pick = (max(good, key=lambda b: b[2] * min(b[1] - b[0], 2.5)) if good
            else (max(bursts, key=lambda b: b[2]) if bursts else None))
    if pick is None:
        return None
    b0, b1, _ = pick
    approach_win = (max(t[0], b0 - 0.4), b1 + 0.6)
    still = (np.nan_to_num(Rs, nan=9.0) < still_thr) & (np.nan_to_num(Ls, nan=9.0) < still_thr)
    hold = None
    i = int(np.searchsorted(t, b1 - 0.4))
    while i < n:
        if still[i]:
            j = i
            while j < n and still[j]:
                j += 1
            if (t[min(j - 1, n - 1)] - t[i]) >= FINISH_HOLD_MIN_S:
                hold = (float(t[i]), float(t[min(j - 1, n - 1)]))
                break
            i = j
        else:
            i += 1
    if hold is None:                       # no clean hold (clip truncated at the finish): use the burst end
        hold = (float(b1), float(min(b1 + FINISH_HOLD_MIN_S, t[-1])))
    return approach_win, hold


def _looks_slowmo(t, lms, Rs, Ls):
    """Clip-level slo-mo cue, independent of the delivery: an iPhone slo-mo exported at 30 fps is far longer
    than a normal form clip AND its action plays back slowly, so the frame-to-frame motion almost never reaches
    the normal gait speed even while the bowler is clearly present and moving. Returns True if BOTH: the clip is
    anomalously long, and, over the frames where the bowler's feet are visible, the peak foot speed stays well
    below a normal walking gait."""
    dur = float(t[-1] - t[0])
    if dur < 40.0:                         # a normal single-delivery form clip is ~10-25 s
        return False
    footvis = np.nan_to_num(lms[:, [L_ANKLE, R_ANKLE, L_FOOT, R_FOOT], 3], nan=0.0).mean(1)
    present = footvis > 0.5
    if present.sum() < 20:
        return False
    M = np.fmax(np.nan_to_num(Rs, nan=0.0), np.nan_to_num(Ls, nan=0.0))
    # fraction of bowler-present frames that are below a normal gait speed: a slo-mo export spends almost all
    # its (stretched) frames below gait speed even while the bowler is clearly moving (0.84 vs 0.52-0.71 on the
    # training clips); any brief normal-speed walk-off tail doesn't move this fraction much.
    return float((M[present] < BURST_MOTION).mean()) > 0.78


def _local_minima(sig, t, sep_s, max_frac=0.65):
    """Indices of local minima of `sig` separated by >= sep_s, below max_frac of the signal's range. Used for
    foot plants (a plant = both feet briefly slow => a dip in the combined foot motion)."""
    s = np.nan_to_num(sig, nan=np.nanmax(sig[~np.isnan(sig)]) if np.any(~np.isnan(sig)) else 1.0)
    dt = np.median(np.diff(t))
    w = max(1, int(sep_s / dt))
    lo, hi = float(np.min(s)), float(np.max(s))
    thr = lo + max_frac * (hi - lo)
    out = []
    for i in range(len(s)):
        a, b = max(0, i - w), min(len(s), i + w + 1)
        if s[i] == s[a:b].min() and s[i] < thr:
            if not out or (i - out[-1]) >= w:
                out.append(i)
            elif s[i] < s[out[-1]]:
                out[-1] = i
    return out


def _foot_strikes(t, lms, win, Rs, Ls):
    """Foot plants inside the delivery window. A plant is a dip in the combined foot motion max(Rs, Ls): when
    one foot plants the other is mid-swing, so the combined motion troughs at each strike. This is more robust
    than per-foot stationarity (quick plants / the occluded slide foot never fully stop below a fixed threshold).
    Returns a chronological list of (t_strike, 'R'|'L') where the label is whichever foot is slower at that time.
    """
    m = (t >= win[0]) & (t <= win[1])
    tt = t[m]
    Rm = np.nan_to_num(Rs[m], nan=9.0)
    Lm = np.nan_to_num(Ls[m], nan=9.0)
    comb = _smooth(np.fmax(Rm, Lm), 5)
    idx = _local_minima(comb, tt, 0.20, 0.65)
    out = []
    for i in idx:
        lab = 'R' if Rm[i] <= Lm[i] else 'L'
        out.append((float(tt[i]), lab))
    return out


# --------------------------------------------------------------------------- ball-colour swing track
def _ball_track(path, t, lms, t0, t1, log=print):
    """Track the ball as a dark, moderately-saturated, round blob seeded near the bowling wrist across the
    delivery. Returns dict t->(cx,cy,area) in normalized coords. The seed disambiguates the ball from the ball
    return / body; once seeded it links by nearest-neighbour with a motion gate.
    Falls back to {} (caller then uses the wrist arc) if the ball can't be followed."""
    try:
        import cv2
    except ImportError:
        return {}
    pts = frame_times(path)
    cap = cv2.VideoCapture(path)
    H = W = None
    frames = {}
    idx0 = int(np.searchsorted(pts, t0))
    i = 0
    buf = []
    while True:
        ok, img = cap.read()
        if not ok:
            break
        tt = float(pts[i]) if i < len(pts) else i / 30.0
        if t0 <= tt <= t1:
            if H is None:
                H, W = img.shape[:2]
            buf.append((i, tt, img))
        if tt > t1:
            break
        i += 1
    cap.release()
    if len(buf) < 5:
        return {}
    bg = np.median(np.stack([f for _, _, f in buf[::max(1, len(buf) // 40)]]), 0).astype(np.int16)
    # wrist position per frame index for seeding
    wr_x = np.interp([tt for _, tt, _ in buf], t, np.nan_to_num(lms[:, R_WRIST, 0], nan=np.nanmean(lms[:, R_WRIST, 0])))
    wr_y = np.interp([tt for _, tt, _ in buf], t, np.nan_to_num(lms[:, R_WRIST, 1], nan=np.nanmean(lms[:, R_WRIST, 1])))
    out = {}
    prev = None
    for k, (fi, tt, img) in enumerate(buf):
        diff = np.abs(img.astype(np.int16) - bg).max(2).astype(np.uint8)
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        V, S = hsv[..., 2], hsv[..., 1]
        mask = ((diff > 30) & (V < 130) & (S > 35)).astype(np.uint8)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
        n, lab, st, cen = cv2.connectedComponentsWithStats(mask)
        seed = np.array([wr_x[k] * W, wr_y[k] * H]) if prev is None else prev
        best = None
        for j in range(1, n):
            a = st[j, cv2.CC_STAT_AREA]
            w, h = st[j, cv2.CC_STAT_WIDTH], st[j, cv2.CC_STAT_HEIGHT]
            if a < 70 or a > 7000:
                continue
            ar = w / max(h, 1)
            if ar < 0.5 or ar > 2.0:
                continue
            if a / (w * h + 1e-6) < 0.5:
                continue
            c = cen[j]
            d = np.hypot(*(c - seed))
            gate = 0.18 * W if prev is None else 0.12 * W
            if d > gate:
                continue
            if best is None or d < best[0]:
                best = (d, c, a)
        if best is not None:
            out[round(tt, 4)] = (best[1][0] / W, best[1][1] / H, int(best[2]))
            prev = best[1]
        else:
            prev = None
    return out


# --------------------------------------------------------------------------- swing events
def _local_extrema(y, t, sep_s):
    """Indices of local maxima and minima of y, each separated by >= sep_s."""
    dt = np.median(np.diff(t))
    w = max(1, int(sep_s / dt))
    mx, mn = [], []
    for i in range(len(y)):
        a, b = max(0, i - w), min(len(y), i + w + 1)
        if y[i] == y[a:b].max() and (not mx or i - mx[-1] >= w):
            mx.append(i)
        if y[i] == y[a:b].min() and (not mn or i - mn[-1] >= w):
            mn.append(i)
    return mx, mn


def _swing_events(t, lms, ball, win, torso):
    """Locate the swing landmarks from the bowling-wrist arc (the method the 2026-10-20 reference used; in this
    rear view the ball-colour blob is occluded behind the body through the backswing, so the wrist arc is more
    reliable and the ball track is used only to confirm release).

    The rear-view wrist-height (image y) trace runs: setup -> pushaway DOWN (a local max y) -> backswing UP
    (apex = a local MIN y) -> downswing DOWN (bottom of arc = the local MAX y just before follow-through) ->
    follow-through UP (a deep MIN y). So:
      E6 bottom of arc  = the last local max before the follow-through minimum.
      E4 top of backswing = the last local min before E6.
      E2 ball start     = first sustained wrist motion out of the setup hold.
      E3 ball at hip    = last descending ball-height (wrist + ~torso/2) crossing of the hip line before E4;
                          in rear view the hand often stays above the hip landmark, so E3 falls back to E2.
      E7 release        = E6 + ~1 frame (ball leaves at the bottom), confirmed by the on-lane ball if tracked.
    Returns a dict of event times (any may be None) and the arc source/quality.
    """
    m = (t >= win[0]) & (t <= win[1])
    tt = t[m]
    if len(tt) < 6:
        return dict(E2=None, E3=None, E4=None, E6=None, E7=None, src='wrist', quality='low')
    wy = _point(lms, (R_WRIST,), 1)[m]
    good = ~np.isnan(wy)
    if good.sum() < 4:
        return dict(E2=None, E3=None, E4=None, E6=None, E7=None, src='wrist', quality='low')
    wy = np.interp(tt, tt[good], wy[good])
    wy = _smooth(wy, 3)
    hipy = _point(lms, (L_HIP, R_HIP), 1)[m]
    g = ~np.isnan(hipy)
    hipy = np.interp(tt, tt[g], hipy[g]) if g.any() else np.full_like(tt, np.nan)
    bally = wy + 0.45 * torso
    dt = float(np.median(np.diff(tt)))
    span = tt[-1] - tt[0]
    mx, mn = _local_extrema(wy, tt, 0.18)
    late = [i for i in mn if tt[i] > tt[0] + 0.55 * span]
    pr = min(late, key=lambda i: wy[i]) if late else int(np.argmin(wy))
    before_max = [i for i in mx if i < pr]
    i6 = before_max[-1] if before_max else int(np.argmax(wy))
    E6 = float(tt[i6])
    before_min = [i for i in mn if i < i6]
    i4 = before_min[-1] if before_min else int(np.argmin(wy[:i6 + 1]))
    E4 = float(tt[i4])
    v = np.gradient(wy, tt)
    # scale-free "ball leaves the setup" threshold: a fraction of the swing's own peak wrist speed (so it still
    # fires on a slo-mo export, where every speed is divided by the slow factor).
    vthr = max(0.05, 0.30 * float(np.nanmax(np.abs(v[tt <= E6])))) if np.any(tt <= E6) else 0.25
    E2 = None
    for k in range(len(tt)):
        if tt[k] >= E4:
            break
        if abs(v[k]) > vthr:
            E2 = float(tt[k])
            break
    E3 = E2
    if g.any():
        for k in range(i4, 0, -1):
            if E2 is not None and tt[k] < E2:        # ball-at-hip cannot precede ball-start
                break
            if bally[k] >= hipy[k] and bally[k - 1] < hipy[k - 1]:
                E3 = float(tt[k])
                break
    E7 = E6 + dt
    # confirm/refine release with the on-lane ball: first clean monotone recede (ball rolling away) after E6
    if ball:
        bt = np.array(sorted(ball))
        by = np.array([ball[k][1] for k in bt])
        after = np.where(bt >= E6 - dt)[0]
        for k in after[:-3]:
            seg = by[k:k + 4]
            if len(seg) == 4 and np.all(np.diff(seg) < 0.0):     # ball receding up-lane (y decreasing)
                E7 = max(E7, float(bt[k]))
                break
    return dict(E2=E2, E3=E3, E4=E4, E6=E6, E7=E7, src='wrist',
                quality='best_effort' if E3 == E2 else 'ok')


# --------------------------------------------------------------------------- slo-mo
def detect_slowmo(step_intervals, first_to_release):
    """Decide whether the clip is an exported slo-mo (frames real, timestamps stretched) and by what factor.
    Single-clip, metadata-free: iPhone exports no reliable capture-fps tag on these files, so we judge by
    physiology — a real bowling step is 0.30-0.65 s and a 4-step approach->release is ~1.2-1.6 s. An
    implausibly slow cadence => slo-mo; the factor is the integer that brings it back into range.
    Returns (is_slowmo, factor, note)."""
    ivals = [x for x in (step_intervals or []) if x is not None]
    med = float(np.median(ivals)) if ivals else None
    slow = (med is not None and med > PLAUSIBLE_STEP_MAX_S) or \
           (first_to_release is not None and first_to_release > 2.6)
    if not slow:
        return False, 1, ''
    # size the factor from whichever anchor we have (first-step->release preferred; else step cadence)
    if first_to_release and first_to_release > 0:
        raw = first_to_release / NOMINAL_APPROACH_S
    else:
        raw = med / 0.45
    factor = min(SLOWMO_FACTORS, key=lambda c: abs(c - raw))
    note = (f'slo-mo export detected: raw cadence ~{raw:.1f}x physiological; corrected by {factor}x '
            f'(captured ~{30 * factor:.0f} fps, saved at 30 fps). Single-clip detection — no capture-fps '
            'metadata present; factor snapped to the nearest iPhone slo-mo ratio.')
    return True, factor, note


# --------------------------------------------------------------------------- metric assembly
def _m(metric, value, unit, conf, status, note=None, uncertainty=None):
    return asdict(Measurement(metric, None if value is None else round(float(value), 3), unit,
                              round(float(conf), 2), status, source=_SRC,
                              algorithm_version=POSE_BACKEND_VERSION, note=note,
                              uncertainty=None if uncertainty is None else round(float(uncertainty), 3)))


def _unavail(metric, unit, reason):
    return asdict(Measurement(metric, None, unit, 0.0, 'unavailable', source=_SRC,
                              algorithm_version=POSE_BACKEND_VERSION, note=reason))


_CALIB_REASON = ('needs floor-plane calibration — unresolved, see '
                 'TRAINING_VIDEOS_CALIBRATED_METRICS addenda')

# Metrics the design surfaces but the current rear-view method does not yet trust: ball-vs-slide timing and
# slide length both need 120 fps release/slide-foot tracking that is still being validated (DEC-026 — report
# 'unavailable' with the reason, never a guessed number). These flow through as honest unavailable tiles.
_VALIDATING_REASON = ('still being validated — ball-vs-slide timing / slide length need 120 fps '
                      'slide-and-release tracking that is not yet verified on this view (FORM_ANALYSIS_SPEC §9)')

# --- qualitative read-out thresholds (auditable; provisional, pending per-metric form-baseline validation) ---
# Rhythm is reported from the swing-tempo ratio rhythm_ratio = downswing_time / backswing_time (already
# computed): a downswing clearly quicker than the backswing (ratio well below 1) reads as the swing "speeding
# up" into release; near-equal is "even"; a slower downswing "slows down". The reference session mean is 0.51,
# so a well-timed swing typically reads "Speeds up". Bands chosen symmetrically around 1.0 with a dead-zone so
# frame-timing jitter near parity does not flip the label.
RHYTHM_SPEEDS_UP_MAX = 0.85      # ratio <= this -> "Speeds up"  (downswing clearly quicker than the backswing)
RHYTHM_SLOWS_DOWN_MIN = 1.15     # ratio >= this -> "Slows down" (downswing slower than the backswing)
# Backswing apex height vs the shoulder line, in torso lengths (+ above shoulder, - below). A +/-0.15-torso
# dead-zone around the shoulder line reads as "Shoulder"; clearly above/below crosses to the outer labels.
BACKSWING_ABOVE_MIN = 0.15       # backswing_height_rel >= this -> "Above shoulder"
BACKSWING_BELOW_MAX = -0.15      # backswing_height_rel <= this -> "Below shoulder"


def _rhythm_display(ratio):
    if ratio is None:
        return None
    if ratio <= RHYTHM_SPEEDS_UP_MAX:
        return 'Speeds up'
    if ratio >= RHYTHM_SLOWS_DOWN_MIN:
        return 'Slows down'
    return 'Even'


def _backswing_display(rel):
    if rel is None:
        return None
    if rel >= BACKSWING_ABOVE_MIN:
        return 'Above shoulder'
    if rel <= BACKSWING_BELOW_MAX:
        return 'Below shoulder'
    return 'Shoulder'


# --- key-position frame export (design "KEY POSITIONS": ball start, end of pushaway, top of swing, release) ---
# Each maps to a located swing event time (DEC-057 / FORM_BENCHMARKS §0.2); only frames the pose actually
# found are exported, cropped to the bowler (so the thumbnail is the bowler, not the whole lane).
KEY_FRAME_EVENTS = (('ball_start', 'E2'), ('end_pushaway', 'E3'), ('top_of_swing', 'E4'), ('release', 'E7'))


def _bowler_crop(lms, idx, pad=0.22):
    """Normalized (x0, y0, x1, y1) bounding box of the visible pose at frame `idx`, padded, clamped 0..1.
    Returns None if the pose wasn't found on that frame (caller then keeps the full frame)."""
    if idx is None or idx >= len(lms):
        return None
    row = lms[idx]
    vis = row[:, 3]
    ok = (vis > MIN_VIS) & ~np.isnan(row[:, 0]) & ~np.isnan(row[:, 1])
    if ok.sum() < 6:
        return None
    xs, ys = row[ok, 0], row[ok, 1]
    x0, x1 = float(np.min(xs)), float(np.max(xs))
    y0, y1 = float(np.min(ys)), float(np.max(ys))
    px, py = pad * max(x1 - x0, 0.04), pad * max(y1 - y0, 0.04)
    return (max(0.0, x0 - px), max(0.0, y0 - py), min(1.0, x1 + px), min(1.0, y1 + py))


def export_key_frames(video, out_prefix, events, crops=None, log=print) -> list:
    """Write a JPEG for each located key position to ``<out_prefix>_form_<key>.jpg`` and return the keys
    actually written (in canonical order). Event times come from the pose ``_extras`` block; a missing event
    is skipped (no frame, no fabrication). `crops` maps a key -> normalized (x0,y0,x1,y1) bowler box; when
    present the frame is cropped to the bowler before writing. Best-effort: any decode/write failure is
    logged and omitted, never raised — the visual stills must not break the numeric analysis."""
    if not out_prefix or not events:
        return []
    try:
        import cv2
    except ImportError:   # pragma: no cover - env-dependent
        log('key-frames: OpenCV not available; skipping frame export')
        return []
    want = {key: float(events[ev]) for key, ev in KEY_FRAME_EVENTS
            if events.get(ev) is not None}
    if not want:
        return []
    crops = crops or {}
    try:
        pts = frame_times(video)
        if not len(pts):
            return []
        targets = {key: int(np.argmin(np.abs(pts - tval))) for key, tval in want.items()}
        need = {}
        for key, idx in targets.items():
            need.setdefault(idx, []).append(key)
        cap = cv2.VideoCapture(video)
        if not cap.isOpened():
            log(f'key-frames: OpenCV cannot decode {video!r}; skipping')
            return []
        written = set()
        i, maxidx = 0, max(need)
        while need and i <= maxidx:
            ok, img = cap.read()
            if not ok:
                break
            if i in need:
                h, w = img.shape[:2]
                for key in need.pop(i):
                    frame = img
                    box = crops.get(key)
                    if box:
                        x0 = max(0, int(box[0] * w)); y0 = max(0, int(box[1] * h))
                        x1 = min(w, int(box[2] * w)); y1 = min(h, int(box[3] * h))
                        if x1 - x0 >= 8 and y1 - y0 >= 8:
                            frame = img[y0:y1, x0:x1]
                    path = f'{out_prefix}_form_{key}.jpg'
                    if cv2.imwrite(path, frame):
                        written.add(key)
            i += 1
        cap.release()
    except Exception as e:   # pragma: no cover - env-dependent (decode/codec issues)
        log(f'key-frames: export failed ({e}); continuing without stills')
        return []
    return [key for key, _ in KEY_FRAME_EVENTS if key in written]


def classify_view_from_pose(t, lms) -> dict:
    """Detect the capture view from the pose track (MVP-03). Returns {view, confidence, reason} with view in
    down_lane (side profile) / rear / unknown. Discriminator: the bowler's TRAVEL DIRECTION in frame — a side
    camera sees the approach move ACROSS the frame (horizontal); a rear camera sees it move UP the frame toward
    the pins (vertical). Validated on IMG_8905 (side, dy/dx≈0.14) vs IMG_8907 (rear, dy/dx≈0.56); threshold 0.30
    separates them. Front (bowler_facing) is NOT separately detected — it's advisory-only for MVP and would read
    as 'rear' (documented limitation; needs a front clip to validate). Confidence stays modest until more
    bowlers are validated (FORM_ANALYSIS_SPEC §6)."""
    vis = lms[:, :, 3]
    ok = ((vis[:, L_SHOULDER] > MIN_VIS) & (vis[:, R_SHOULDER] > MIN_VIS)
          & (vis[:, L_HIP] > MIN_VIS) & (vis[:, R_HIP] > MIN_VIS))
    if ok.sum() < 8:
        return dict(view='unknown', confidence=0.0, reason='Not enough clear pose frames to tell the camera view.')
    f = lms[ok]
    hip_x = (f[:, L_HIP, 0] + f[:, R_HIP, 0]) / 2
    hip_y = (f[:, L_HIP, 1] + f[:, R_HIP, 1]) / 2
    dx = float(np.nanmax(hip_x) - np.nanmin(hip_x))
    dy = float(np.nanmax(hip_y) - np.nanmin(hip_y))
    if max(dx, dy) < 0.08:
        return dict(view='unknown', confidence=0.1,
                    reason='The bowler barely moves in frame — the camera view is unclear (check framing).')
    frac = float(ok.mean())
    if dy / max(dx, 1e-3) < 0.30:
        return dict(view='down_lane', confidence=round(0.5 + 0.2 * frac, 2),
                    reason='The bowler moves across the frame — a side (profile) view.')
    return dict(view='rear', confidence=round(0.4 + 0.2 * frac, 2),
                reason='The bowler moves up the frame toward the pins — a rear view.')


def analyze(video, out_prefix=None, handed=None, model_path=POSE_MODEL_PATH, log=print) -> dict:
    """Full per-clip analysis. Returns a dict {metric_key: Measurement-dict} covering the FORM_P1 keys plus
    diagnostic extras (step_intervals, first_step_to_release, slide_to_release, tempo_ratio, ball_at_hip_to_release,
    events, slowmo). Unmeasurable metrics are 'unavailable' with a reason."""
    t, lms = extract_landmarks(video, model_path, log=log)
    fps = 1.0 / np.median(np.diff(t)) if len(t) > 1 else 30.0
    frame_s = 1.0 / fps
    torso = _torso(lms)

    # foot speeds over the whole clip to find the finish hold, then the delivery window
    Rx, Ry = _point(lms, R_FOOT_PTS, 0), _point(lms, R_FOOT_PTS, 1)
    Lx, Ly = _point(lms, L_FOOT_PTS, 0), _point(lms, L_FOOT_PTS, 1)
    Rs, Ls = _speed(Rx, Ry, t), _speed(Lx, Ly, t)
    slow_suspect = _looks_slowmo(t, lms, Rs, Ls)
    if slow_suspect:
        # the delivery plays back slowly: every foot speed is divided by the slow factor, so lower the motion
        # gates and allow a longer (stretched) burst so the real throw — not a normal-speed walk-off — is found.
        delivery = _find_delivery(t, lms, Rs, Ls, burst_motion=0.11, burst_max_s=9.0, still_thr=0.06)
    else:
        delivery = _find_delivery(t, lms, Rs, Ls)

    out = {}
    extras = {}
    extras['view_info'] = classify_view_from_pose(t, lms)   # MVP-03: detected capture view (both return paths)

    if delivery is None:
        reason = ('could not isolate the delivery (no clear finish hold — pose likely failed on this clip, '
                  'e.g. bowler too small or occluded; see FORM_ANALYSIS_SPEC §9).')
        for k, u in (('pushaway_time', 's'), ('backswing_time', 's'), ('downswing_time', 's'),
                     ('release_time', 's'), ('swing_time', 's'), ('approach_time', 's'),
                     ('rhythm_ratio', 'ratio'), ('finish_hold', 's'), ('backswing_height_rel', 'ratio')):
            out[k] = _unavail(k, u, reason)
        out['step_count'] = _unavail('step_count', 'count', reason)
        out['ball_start_step'] = _unavail('ball_start_step', 'index', reason)
        out['drift_boards'] = _unavail('drift_boards', 'board', _CALIB_REASON)
        out['timing_at_slide'] = _unavail('timing_at_slide', 's', _VALIDATING_REASON)
        out['slide_length'] = _unavail('slide_length', 'inch', _VALIDATING_REASON)
        extras['events'] = {}
        extras['key_frames'] = []
        extras['measured_positions'] = {}
        out['_extras'] = extras
        return out

    approach_win, (hold_start, hold_end) = delivery
    b0 = approach_win[0] + 0.4            # first-motion onset of the approach burst

    # swing events from the bowling-wrist arc (ball track only confirms release). Window runs from before the
    # pushaway (b0 - 0.8) to just past release (hold_start + 0.3); ending at the finish hold would let the
    # follow-through hump masquerade as the bottom of arc.
    swing_win = (max(t[0], b0 - 0.8), min(hold_start + 0.3, t[-1]))
    ball = _ball_track(video, t, lms, swing_win[0], min(hold_start + 0.8, t[-1]), log=log)
    ev = _swing_events(t, lms, ball, swing_win, torso)
    E2, E3, E4, E6, E7 = ev['E2'], ev['E3'], ev['E4'], ev['E6'], ev['E7']

    # foot plants: combined-motion dips from just before the burst to release (the approach ends at release;
    # post-release trail-leg / walk-off motion is not a step).
    rel_bound = (E7 if E7 is not None else hold_start) + 0.12
    strikes = _foot_strikes(t, lms, (b0 - 0.25, rel_bound + 0.1), Rs, Ls)
    plants = [s for s in strikes if (b0 - 0.2) <= s[0] <= rel_bound]
    if not plants:
        reason = 'delivery found but no foot plants detected in the approach window.'
        for k, u in (('pushaway_time', 's'), ('backswing_time', 's'), ('downswing_time', 's'),
                     ('release_time', 's'), ('swing_time', 's'), ('approach_time', 's'),
                     ('rhythm_ratio', 'ratio'), ('finish_hold', 's'), ('backswing_height_rel', 'ratio')):
            out[k] = _unavail(k, u, reason)
        out['step_count'] = _unavail('step_count', 'count', reason)
        out['ball_start_step'] = _unavail('ball_start_step', 'index', reason)
        out['drift_boards'] = _unavail('drift_boards', 'board', _CALIB_REASON)
        out['timing_at_slide'] = _unavail('timing_at_slide', 's', _VALIDATING_REASON)
        out['slide_length'] = _unavail('slide_length', 'inch', _VALIDATING_REASON)
        extras.setdefault('events', {k: (None if v is None else round(v, 3)) for k, v in
                                     dict(E2=E2, E3=E3, E4=E4, E6=E6, E7=E7).items()})
        extras['key_frames'] = []
        extras['measured_positions'] = {}
        out['_extras'] = extras
        return out

    plants.sort()
    seq = plants
    strike_t = [s[0] for s in seq]
    raw_intervals = [strike_t[i + 1] - strike_t[i] for i in range(len(strike_t) - 1)]
    slide_plant = strike_t[-1]
    first_step = strike_t[0]

    raw_first_to_release = (E7 - first_step) if (E7 is not None) else None
    is_slow, factor, slownote = detect_slowmo(raw_intervals, raw_first_to_release)
    slow_uncorrected = False
    if slow_suspect:
        # Clip-level slo-mo is certain (long clip, slowed interior), but the delivery can't be reliably isolated
        # or corrected: in slo-mo the slow backswing (feet planted while the wrist climbs) mimics a finish hold,
        # the explosive release blurs the pose, and the throw straddles the export speed ramp (so the slowdown
        # is NOT a single uniform factor). Report raw file-time values, flagged and uncorrected (task contract).
        is_slow, factor, scale, slow_uncorrected = True, 1, 1.0, True
        slownote = (f'slo-mo export DETECTED (clip {t[-1] - t[0]:.0f}s with a playback-slowed interior). The '
                    'delivery could NOT be reliably isolated or corrected on this clip: the slow backswing '
                    'resembles a finish hold, the release blurs the pose, and the throw straddles the export '
                    'speed ramp (non-uniform slowdown — no single factor applies). Values below are RAW '
                    'file-time, UNCORRECTED.')
    else:
        scale = 1.0 / factor if is_slow else 1.0

    def dur(a, b):
        if a is None or b is None:
            return None
        return (b - a) * scale

    intervals = [v * scale for v in raw_intervals]
    step_count = len(strike_t)
    # bowling side: RH slide = left foot last; report slide foot label from the sequence
    slide_foot = seq[-1][1]

    # --- events / phase splits ---
    pushaway = dur(E2, E3)
    backswing = dur(E3, E4)
    downswing = dur(E4, E6)
    release_time = dur(E6, E7)                   # bottom of arc -> release (the swing-bar 4th segment)
    swing_time = dur(E2, E7)
    approach_time = dur(first_step, E7)          # E1 (true approach start) not reliable here; use first step
    finish_hold = (hold_end - hold_start) * scale
    ball_hip_to_release = dur(E3, E7)
    slide_to_release = dur(slide_plant, E7)
    first_to_release = dur(first_step, E7)
    tempo = (downswing / backswing) if (backswing and downswing and backswing > 1e-6) else None

    # backswing height relative to shoulder (torso lengths; + = above shoulder, - = below). Uses the wrist apex
    # (the ball-colour arc has no reliable shoulder reference frame), scale-free so slo-mo doesn't affect it.
    bh_rel = None
    if E4 is not None and torso > 1e-6:
        k = int(np.argmin(np.abs(t - E4)))
        wy4 = lms[k, R_WRIST, 1]
        sh4 = np.nanmean(lms[k, (L_SHOULDER, R_SHOULDER), 1])
        if not (np.isnan(wy4) or np.isnan(sh4)):
            bh_rel = float((sh4 - wy4) / torso)      # wrist above shoulder => positive

    unc = frame_s * scale        # ±1 frame at the clip's (corrected) fps
    ok = 'ok'
    be = 'best_effort'
    slow_tag = (' [slo-mo: RAW/uncorrected]' if slow_uncorrected
                else (' [slo-mo corrected %dx]' % factor) if is_slow else '')
    sw_src = ev['src']

    out['step_count'] = _m('step_count', step_count, 'count',
                           0.8 if 3 <= step_count <= 5 else 0.4, ok if 3 <= step_count <= 5 else be,
                           note=f'{step_count} foot plants (slide foot: {slide_foot}){slow_tag}')
    out['approach_time'] = _m('approach_time', approach_time, 's', 0.6, be,
                              note=f'first foot plant -> release (E1 true start not reliable in rear view){slow_tag}',
                              uncertainty=2 * unc)
    out['swing_time'] = _m('swing_time', swing_time, 's', 0.55 if E2 and E7 else 0.0,
                           be if (E2 and E7) else 'unavailable',
                           note=f'E2 ball-start -> E7 release, swing arc via {sw_src}{slow_tag}', uncertainty=2 * unc)
    out['pushaway_time'] = _m('pushaway_time', pushaway, 's', 0.4 if pushaway else 0.0,
                              'low_confidence' if pushaway else 'unavailable',
                              note=f'E2->E3, hard to time in rear view ({sw_src} arc){slow_tag}', uncertainty=2 * unc)
    out['backswing_time'] = _m('backswing_time', backswing, 's', 0.6 if backswing else 0.0,
                               be if backswing else 'unavailable',
                               note=f'E3 ball-at-hip -> E4 apex ({sw_src} arc){slow_tag}', uncertainty=2 * unc)
    out['downswing_time'] = _m('downswing_time', downswing, 's', 0.65 if downswing else 0.0,
                               be if downswing else 'unavailable',
                               note=f'E4 apex -> E6 bottom of arc ({sw_src} arc){slow_tag}', uncertainty=unc)
    out['release_time'] = _m('release_time', release_time, 's', 0.4 if release_time else 0.0,
                             be if release_time else 'unavailable',
                             note=f'E6 bottom of arc -> E7 release; the ball leaves at the bottom so this is '
                                  f'~1 frame unless the on-lane ball refines it ({sw_src} arc){slow_tag}',
                             uncertainty=unc)
    out['rhythm_ratio'] = _m('rhythm_ratio', tempo, 'ratio', 0.5 if tempo else 0.0,
                             be if tempo else 'unavailable',
                             note='swing tempo = downswing / backswing (ref session mean 0.51)')
    out['rhythm_ratio']['display'] = _rhythm_display(tempo)   # "Speeds up" / "Even" / "Slows down"
    out['finish_hold'] = _m('finish_hold', finish_hold, 's', 0.6, be,
                            note=f'both feet stationary after the slide (E8->E9){slow_tag}', uncertainty=unc)
    out['backswing_height_rel'] = _m('backswing_height_rel', bh_rel, 'ratio', 0.5 if bh_rel is not None else 0.0,
                                     be if bh_rel is not None else 'unavailable',
                                     note='bowling-wrist apex vs shoulder line, torso lengths (+above/-below; '
                                          'ref "about shoulder height")')
    out['backswing_height_rel']['display'] = _backswing_display(bh_rel)   # "Above shoulder"/"Shoulder"/"Below shoulder"
    # ball-start step index (which step contains E2)
    bss = None
    if E2 is not None:
        for i in range(len(strike_t)):
            lo = strike_t[i]
            hi = strike_t[i + 1] if i + 1 < len(strike_t) else E7 or (lo + 1)
            if lo <= E2 < hi:
                bss = i + 1
                break
        if bss is None and E2 < strike_t[0]:
            bss = 0
    out['ball_start_step'] = _m('ball_start_step', bss, 'index', 0.4 if bss is not None else 0.0,
                                'low_confidence' if bss is not None else 'unavailable',
                                note='step index containing E2 ball-start (0 = before the first tracked plant)')
    out['drift_boards'] = _unavail('drift_boards', 'board', _CALIB_REASON)
    out['timing_at_slide'] = _unavail('timing_at_slide', 's', _VALIDATING_REASON)
    out['slide_length'] = _unavail('slide_length', 'inch', _VALIDATING_REASON)

    # diagnostic extras (surfaced to the validation harness; analyze_form_clip only uses the FORM_P1 keys)
    extras['step_intervals'] = _m('step_intervals', None, 's', 0.6, be,
                                  note='per-step landing intervals (s): ' +
                                       ', '.join(f'{v:.2f}' for v in intervals))
    extras['step_intervals_values'] = [round(v, 3) for v in intervals]
    extras['first_step_to_release'] = _m('first_step_to_release', first_to_release, 's', 0.6, be,
                                         note='first foot plant -> release' + slow_tag, uncertainty=2 * unc)
    extras['slide_to_release'] = _m('slide_to_release', slide_to_release, 's',
                                    0.45 if slide_to_release is not None else 0.0,
                                    'low_confidence' if slide_to_release is not None else 'unavailable',
                                    note='slide-foot plant -> release (release synchronization)' + slow_tag,
                                    uncertainty=unc)
    extras['ball_at_hip_to_release'] = _m('ball_at_hip_to_release', ball_hip_to_release, 's',
                                          0.5 if ball_hip_to_release else 0.0,
                                          be if ball_hip_to_release else 'unavailable',
                                          note='E3 ball-at-hip -> E7 release (ref session mean 1.21 s)' + slow_tag,
                                          uncertainty=2 * unc)
    extras['tempo_ratio'] = _m('tempo_ratio', tempo, 'ratio', 0.5 if tempo else 0.0,
                               be if tempo else 'unavailable', note='downswing / backswing (ref 0.51)')
    # E5 slide start = slide-foot plant; E8 slide stop = start of the posted finish hold (FORM_ANALYSIS_SPEC §3).
    # These feed the T3 (E4−E5) and T4 (E7−E8) timing checkpoints (DEC-057).
    extras['events'] = {k: (None if v is None else round(v, 3)) for k, v in
                        dict(E2=E2, E3=E3, E4=E4, E5=slide_plant, E6=E6, E7=E7, E8=hold_start,
                             first_step=first_step, slide_plant=slide_plant,
                             hold_start=hold_start, hold_end=hold_end).items()}
    # export the design's four KEY POSITIONS stills at the located event times, cropped to the bowler
    # (only those the pose found)
    crops = {key: _bowler_crop(lms, int(np.argmin(np.abs(t - float(extras['events'][ev])))))
             for key, ev in KEY_FRAME_EVENTS if extras['events'].get(ev) is not None}
    extras['key_frames'] = export_key_frames(video, out_prefix, extras['events'], crops=crops, log=log)
    # Form fundamentals v1 measured positions M1–M7 (DEC-057). View-agnostic geometry here; analyze_form_clip
    # applies the capture-view gating. Imported lazily to keep pose import-light and avoid an import cycle.
    from . import fundamentals as _fund
    pos_events = dict(E2=E2, E3=E3, E4=E4, E5=slide_plant, E6=E6, E7=E7, E8=hold_start,
                      first_step=first_step, slide_plant=slide_plant,
                      hold_start=hold_start, hold_end=hold_end)
    extras['measured_positions'] = _fund.measured_positions(t, lms, pos_events, torso, handed, out)
    extras['strikes'] = [(round(x, 3), lab) for x, lab in seq]
    extras['slowmo'] = dict(is_slowmo=is_slow, factor=factor, note=slownote,
                            raw_step_intervals=[round(v, 3) for v in raw_intervals],
                            raw_first_to_release=None if raw_first_to_release is None else round(raw_first_to_release, 3))
    extras['swing_source'] = sw_src
    extras['fps'] = round(fps, 2)

    # When slo-mo is detected but uncorrected, every delivery timing is raw file-time and the event isolation is
    # unreliable: downgrade each measured metric to low_confidence and prepend the reason (never silently wrong).
    if slow_uncorrected:
        warn = 'SLO-MO (uncorrected): ' + slownote + ' | '
        for k, mm in list(out.items()) + list(extras.items()):
            if not isinstance(mm, dict) or 'status' not in mm:
                continue
            if mm.get('value') is not None and mm.get('status') not in ('unavailable',):
                mm['status'] = 'low_confidence'
                mm['confidence'] = min(mm.get('confidence', 0.0), 0.2)
                mm['note'] = warn + (mm.get('note') or '')
    out['_extras'] = extras
    return out


def build_backend(model_path: str = POSE_MODEL_PATH, log=print):
    """Return a `pose_backend(video, out_prefix, handed)` callable for analyze_form_clip. The callable returns
    {metric_key: Measurement-dict} for the FORM_P1 keys (plus a '_extras' diagnostic block)."""
    def pose_backend(video, out_prefix=None, handed=None):
        return analyze(video, out_prefix=out_prefix, handed=handed, model_path=model_path, log=log)
    return pose_backend


# default backend instance (model path from env/default; validated lazily on first call)
pose_backend = build_backend()
