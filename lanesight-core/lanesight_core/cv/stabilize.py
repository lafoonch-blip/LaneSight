"""Stage 1: register every frame to a reference frame (static tripod, handheld, or head-mounted)
and build a clean background plate in reference coordinates. Streaming: frames are never all held."""
import cv2, numpy as np, subprocess, threading, os
from concurrent.futures import ThreadPoolExecutor
from ._parallel import workers
from ..failures import AnalysisFailure

def pts(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'frame=pts_time',
                          '-of', 'csv=p=0', path], capture_output=True, text=True).stdout
    return np.array([float(x.strip(',')) for x in out.split() if x.strip(',')])

# DEC-092 P0: count how often the clip is decoded and how long decode takes, to confirm (with the benchmark)
# that repeated full decodes — not the metric math — are the bottleneck before committing to decode-once (P1).
# Module-level counters; the pipeline is serial so one frames() generator is active at a time.
import time as _time
_DECODE = {'passes': 0, 'frames': 0, 'seconds': 0.0, 'cached_passes': 0, 'cached_frames': 0}

# DEC-092 P1 decode-once: a memory-bounded frame cache. The pipeline decodes the clip ~9× (streaming, to keep
# memory low). For a clip that fits the byte budget — the common case, since real shots are trimmed to a short
# window — the FIRST full pass populates this cache and the remaining ~8 passes are served from it with no
# decode. The frames served are byte-identical to a fresh decode (we store/serve independent copies), so metrics
# are UNCHANGED — the only new resource is RAM, hard-capped by LANESIGHT_FRAME_CACHE_MB. A clip that would exceed
# the budget (e.g. a long/no-trim clip) transparently falls back to today's re-decode, and any partial cache is
# freed immediately, so peak RSS never exceeds (working set + budget). Set the budget to 0 to disable entirely.
STATIC_CAM_PX = 1.0   # max probed camera shift (full-res px) below which pass-B registration is skipped (tripod).
                      # Conservative: validated within DEC-092 tolerance at 0.2-0.3 px (8751/8752/8754, Δ ≤ 0.13
                      # mph); clips with any real camera motion take the full registration path unchanged.
_FRAME_CACHE_MB = int(os.environ.get('LANESIGHT_FRAME_CACHE_MB', '1000'))   # hard RSS bound (well under 4 GiB:
# peak ≈ working set ~2 GB + this ≈ 3 GB). Fits short / lower-fps / lower-res windows; a long 1080p60 window
# (~9 s ≈ 3.3 GB) exceeds it and transparently falls back to re-decode. Set 0 to disable. See
# 03_ENGINEERING/DECODE_ONCE_FINDINGS.md.
_FCACHE = {'path': None, 'frames': {}, 'bytes': 0, 'complete': False, 'too_big': False}


def reset_frame_cache():
    _FCACHE.update(path=None, frames={}, bytes=0, complete=False, too_big=False)


def reset_decode_stats():
    _DECODE.update(passes=0, frames=0, seconds=0.0, cached_passes=0, cached_frames=0)
    reset_frame_cache()                               # free any held frames between analyses (memory hygiene)


def decode_stats():
    return {'passes': _DECODE['passes'], 'frames': _DECODE['frames'],
            'seconds': round(_DECODE['seconds'], 3),
            'cached_passes': _DECODE['cached_passes'], 'cached_frames': _DECODE['cached_frames'],
            'cache_complete': _FCACHE['complete'], 'cache_mb': round(_FCACHE['bytes'] / 1048576, 1)}


def open_capture(path):
    """Open a clip and honor its rotation flag (DEC-092 orientation fix). OpenCV ignores the container's
    rotation metadata by default, so a phone held in PORTRAIT (rotation ±90) would otherwise be decoded with
    the lane lying sideways — which the lane/foul detector can't read. ORIENTATION_AUTO applies the rotation
    so every clip reaches the CV upright, regardless of how the phone was held. Landscape (rotation 0) is
    unchanged."""
    cap = cv2.VideoCapture(path)
    if hasattr(cv2, 'CAP_PROP_ORIENTATION_AUTO'):
        cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1)
    return cap


def frames(path):
    budget = _FRAME_CACHE_MB * 1048576
    # Serve a fully-populated cache without touching the decoder (DEC-092 P1 decode-once). Each pass gets an
    # independent copy, exactly as a fresh decode would — so results are byte-identical.
    if budget > 0 and _FCACHE['path'] == path and _FCACHE['complete']:
        _DECODE['cached_passes'] += 1
        fr = _FCACHE['frames']
        for i in range(len(fr)):
            _DECODE['cached_frames'] += 1
            yield i, fr[i].copy()
        return
    # Decode pass. Also populate the cache up to the budget (unless this path is already known too big).
    _DECODE['passes'] += 1
    caching = budget > 0 and not _FCACHE['too_big']
    if caching and _FCACHE['path'] != path:
        reset_frame_cache(); _FCACHE['path'] = path       # (re)start population for this clip
    elif caching:
        _FCACHE.update(frames={}, bytes=0, complete=False)  # re-populate from scratch this pass
    cap = open_capture(path); i = 0
    nframes_hint = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)   # cheap upfront size check (0 if codec won't say)
    try:
        while True:
            t = _time.perf_counter()
            ok, f = cap.read()
            _DECODE['seconds'] += _time.perf_counter() - t
            if not ok:
                if caching:
                    _FCACHE['complete'] = True              # reached EOF within budget → cache is whole
                return
            _DECODE['frames'] += 1
            if caching and i == 0 and nframes_hint > 0 and nframes_hint * f.nbytes > budget:
                _FCACHE.update(frames={}, bytes=0, too_big=True)   # known too big up front → never populate (no waste)
                caching = False
            if caching:
                if _FCACHE['bytes'] + f.nbytes > budget:    # would exceed the cap → give up caching this clip,
                    _FCACHE.update(frames={}, bytes=0, too_big=True)   # free the partial cache, fall back to decode
                    caching = False
                else:
                    _FCACHE['frames'][i] = f.copy()         # copy: cv2 reuses its read buffer across read() calls
                    _FCACHE['bytes'] += f.nbytes
            yield i, f; i += 1
    finally:
        cap.release()

def wood_mask(bgr):
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    H, S, V = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    m = ((H >= 5) & (H <= 25) & (S > 60) & (V > 90)).astype(np.uint8)
    return cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))

class Registrar:
    def __init__(self, scale=0.5):
        self.s = scale; self.orb = cv2.ORB_create(4000, fastThreshold=10); self.bf = cv2.BFMatcher(cv2.NORM_HAMMING)
    def feats(self, f):
        small = cv2.resize(f, None, fx=self.s, fy=self.s)
        g = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
        # only use features on/near the lane surface (wood + gutters + deck); ignore scoreboards/ceiling/people
        m = cv2.dilate(wood_mask(small), np.ones((41, 41), np.uint8))
        return self.orb.detectAndCompute(g, m)
    def H(self, kf, df, kr, dr):
        if df is None or dr is None or len(kf) < 20: return None, 0
        good = [p[0] for p in self.bf.knnMatch(df, dr, k=2) if len(p) == 2 and p[0].distance < 0.75 * p[1].distance]
        if len(good) < 20: return None, 0
        src = np.float32([kf[m.queryIdx].pt for m in good]); dst = np.float32([kr[m.trainIdx].pt for m in good])
        H, inl = cv2.findHomography(src, dst, cv2.RANSAC, 2.0)
        if H is None: return None, 0
        S = np.diag([self.s, self.s, 1.0])
        return np.linalg.inv(S) @ H @ S, int(inl.sum())

def stabilize(path, log=print, min_inliers=60, timing_path=None, core_end_s=None):
    """timing_path: read frame times from this file instead (e.g. the original HDR clip when frames come from an
    SDR copy). It must contain the same frames in the same order; checked here by count.
    core_end_s: frames after this time are the pin-settle tail — they still get homographies (so read_pins can
    use them) but are excluded from the reference frame and the background median, so extra settle footage never
    perturbs the lane geometry / shot metrics."""
    ts = pts(timing_path or path)
    if timing_path:
        n = len(pts(path))
        if n != len(ts):
            raise AnalysisFailure('TIMING_FRAME_MISMATCH',
                                  f'timing source has {len(ts)} frames but the video has {n}',
                                  stage='stabilize', diagnostics={'timing_frames': len(ts), 'video_frames': n})
    core = (lambda i: True) if core_end_s is None else (lambda i: i >= len(ts) or ts[i] <= core_end_s)
    # pass A: reference = middle of the longest steady stretch with the lane visible (within the core, not the tail)
    prevg = None; mot = []; woodf = []
    for i, f in frames(path):
        sm = cv2.resize(f, None, fx=0.125, fy=0.125)
        g = cv2.cvtColor(sm, cv2.COLOR_BGR2GRAY).astype(np.float32)
        mot.append(0.0 if prevg is None else np.hypot(*cv2.phaseCorrelate(prevg, g)[0]) * 8)
        woodf.append(wood_mask(sm).mean()); prevg = g
    mot_raw = np.array(mot)                                     # per-frame camera translation (full-res px), unsmoothed
    mot = np.convolve(mot_raw, np.ones(15) / 15, 'same'); woodf = np.array(woodf)
    cm = np.array([core(i) for i in range(len(mot))])          # thresholds over core frames only, so the settle
    thr = max(3.0, np.percentile(mot[cm], 40)); wmax = woodf[cm].max()   # tail never shifts the reference choice
    steady = (mot < thr) & (woodf > 0.5 * wmax) & cm
    best = (0, 0, 0); run = 0
    for i, v in enumerate(steady):
        run = run + 1 if v else 0
        if run > best[0]: best = (run, i - run + 1, i)
    ref = (best[1] + best[2]) // 2
    R = Registrar()
    # reference features (needed by both the static probe and the full pass B)
    kr = dr = ref_img = None
    for i, f in frames(path):
        if i == ref: kr, dr = R.feats(f); ref_img = f.copy(); break
    n = len(ts); c = np.array([540., 960., 1.])
    # DEC-092 P2 static-camera shortcut: a tripod clip has ~0–1 px camera motion, so every per-frame homography is
    # ~identity and the ORB registration (pass B) — ~65% of the whole analysis — is pure cost. We can't read the
    # true camera motion from the cheap phase-correlation pass (the moving ball/bowler contaminate it), so PROBE:
    # register ~30 frames spread across the clip against the reference using the SAME registrar as the full pass
    # (so it's as reliable as the real camera-motion read, ~0.5 s). If the max shift is below STATIC_CAM_PX, skip
    # pass B and use identity homographies — the downstream warps become sub-pixel no-ops, so the lane/ball/pin
    # reads are unchanged (gated on the benchmark). Handheld clips (shift ≥ threshold) take the full path.
    probe_idx = set(range(0, n, max(1, n // 30)))
    probe_sh = []
    for i, f in frames(path):
        if i in probe_idx and i != ref:
            kf, df = R.feats(f); H, cnt = R.H(kf, df, kr, dr)
            if H is not None and cnt >= min_inliers:
                probe_sh.append(float(np.linalg.norm((H @ c / (H @ c)[2])[:2] - c[:2])))
    cam_px = max(probe_sh) if len(probe_sh) >= 8 else 999.0     # too few confident probes → don't risk the shortcut
    if cam_px < STATIC_CAM_PX:
        Hs = np.array([np.eye(3) for _ in range(n)]); inl = [min_inliers] * n
        h, w = ref_img.shape[:2]
        core_idx = [i for i in range(n) if core(i)]; step = max(1, len(core_idx) // 80)
        sample = set(core_idx[::step]); stack = []
        for i, f in frames(path):
            if i in sample: stack.append(f)                    # identity warp = the raw frame
        bg = np.median(np.stack(stack), axis=0).astype(np.uint8)
        log(f'ref frame {ref} (t={ts[ref]:.2f}s); static camera ({cam_px:.1f}px ≤ {STATIC_CAM_PX}px, {len(probe_sh)} probes) '
            f'— skipped registration')
        return dict(ts=ts[:n], Hs=Hs, ref=ref, bg=bg, inliers=np.array(inl), shift=np.zeros(n))
    # pass B: homographies (direct to reference; chain through previous frame when direct match is weak)
    Hs = []; inl = []; prev = None
    # Two phases per chunk so BOTH halves use the cores. ORB feature extraction is per-frame independent (the heavy
    # part here) and scales only when each cv2 call is single-threaded, so it is fanned across worker threads with
    # cv2 threads forced to 1 (each worker gets its own deterministic Registrar -> bit-identical features). The
    # homography solve (R.H: BFMatcher.knnMatch + findHomography) is instead ~10x faster at full cv2 thread count
    # AND is sequential (chains through the previous frame + Hs[-1]), so it runs on this thread in frame order with
    # the default thread count restored -> identical Hs and unchanged RANSAC RNG sequence. Chunking bounds memory
    # and the per-chunk setNumThreads toggle is negligible. Net: pure speed-up, results identical to the serial loop.
    _tl = threading.local()
    def _feats(f):
        R2 = getattr(_tl, 'R', None)
        if R2 is None: R2 = _tl.R = Registrar()
        return R2.feats(f)
    nw = workers(); default_threads = cv2.getNumThreads(); chunk = max(nw * 4, 48); gen = frames(path)
    try:
        with ThreadPoolExecutor(max_workers=nw) as ex:
            while True:
                batch = []
                for _ in range(chunk):
                    nf = next(gen, None)
                    if nf is None: break
                    batch.append(nf)                                   # (i, frame)
                if not batch: break
                cv2.setNumThreads(1)                                   # phase 1: parallel ORB (per-frame independent)
                feats = list(ex.map(lambda nf: _feats(nf[1]), batch)) # ex.map preserves input order
                cv2.setNumThreads(default_threads)                    # phase 2: sequential solve at full threads
                for (i, f), (kf, df) in zip(batch, feats):
                    H, n = R.H(kf, df, kr, dr)
                    if (H is None or n < min_inliers) and prev is not None:
                        Hp, n2 = R.H(kf, df, prev[1], prev[2])         # frame -> previous frame
                        H, n = (Hs[-1] @ Hp, -n2) if Hp is not None else (Hs[-1], -1)
                    if H is None: H, n = np.eye(3), -1
                    Hs.append(H); inl.append(n); prev = (i, kf, df)
    finally:
        cv2.setNumThreads(default_threads)
    Hs = np.array(Hs)
    c = np.array([540., 960., 1.]); sh = [np.linalg.norm((h @ c / (h @ c)[2])[:2] - c[:2]) for h in Hs]
    log(f'ref frame {ref} (t={ts[ref]:.2f}s); median inliers {np.median([v for v in inl if v > 0]):.0f}; '
        f'chained {sum(v < 0 for v in inl)}/{len(inl)}; camera motion up to {max(sh):.0f}px')
    # pass C: background = temporal median of warped frames (moving bowler/ball removed), core frames only so the
    # pin-settle tail (rake sweep, reset, bowler walking back) never pollutes the lane geometry
    h, w = ref_img.shape[:2]
    core_idx = [i for i in range(len(Hs)) if core(i)]; step = max(1, len(core_idx) // 80)
    sample = set(core_idx[::step]); stack = []
    for i, f in frames(path):
        if i in sample: stack.append(cv2.warpPerspective(f, Hs[i], (w, h)))
    bg = np.median(np.stack(stack), axis=0).astype(np.uint8)
    return dict(ts=ts[:len(Hs)], Hs=Hs, ref=ref, bg=bg, inliers=np.array(inl), shift=np.array(sh))
