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
_FRAME_CACHE_MB = int(os.environ.get('LANESIGHT_FRAME_CACHE_MB', '1000'))   # hard RSS bound (well under 4 GiB:
# peak ≈ working set ~2 GB + this ≈ 3 GB). Fits short / lower-fps / lower-res windows; a long 1080p60 window
# (~9 s ≈ 3.3 GB) exceeds it and transparently falls back to re-decode. Set 0 to disable. See
# 03_ENGINEERING/DECODE_ONCE_FINDINGS.md.
_FCACHE = {'path': None, 'frames': {}, 'bytes': 0, 'complete': False, 'too_big': False, 'prime_tried': False}


def reset_frame_cache():
    _FCACHE.update(path=None, frames={}, bytes=0, complete=False, too_big=False, prime_tried=False)


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


# DEC-107 (Shayne 2026-10-31): the opencv wheel's bundled video decoder produces DIFFERENT pixels on Linux
# (Cloud Run) vs macOS, which shifts the lane geometry and drops server speed ~14% (IMG_8753: 16.0 vs 18.7 on
# the Mac). ffmpeg CLI decodes deterministically on both, so LANESIGHT_FFMPEG_DECODE=1 reads frames through
# ffmpeg instead of cv2.VideoCapture — same pixels everywhere. Validate per-clip (ops Cloud Run Job) that
# IMG_8751-54 match the Mac within 0.1 mph before shipping it as the default.
def _ff_display_dims(path):
    """Display (post-autorotate) width,height. ffprobe gives coded w/h + a rotation side-data; ffmpeg's default
    -autorotate outputs the rotated frame, so a ±90 rotation swaps w/h (matches cv2 ORIENTATION_AUTO)."""
    import json as _json
    out = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                          'stream=width,height:stream_side_data=rotation', '-of', 'json', path],
                         capture_output=True, text=True).stdout
    st = _json.loads(out)['streams'][0]
    w, h = int(st['width']), int(st['height'])
    rot = 0
    for sd in st.get('side_data_list', []) or []:
        if 'rotation' in sd:
            rot = int(sd['rotation'])
    if abs(rot) % 180 == 90:
        w, h = h, w
    return w, h


def _ff_frames(path):
    """Stream BGR frames via ffmpeg CLI (bgr24 rawvideo pipe). Deterministic across platforms (DEC-107). Capped
    to the ffprobe frame count = len(pts(path)), so the frame stream and the timestamp array stay the SAME length
    (ffmpeg rawvideo can emit one extra/fewer frame than ffprobe counts → index mismatch otherwise). Broken-pipe
    stderr (when the consumer stops early) is discarded."""
    import os as _os
    w, h = _ff_display_dims(path)
    fsz = w * h * 3
    nexp = len(pts(path))                      # same accounting the timestamps use
    proc = subprocess.Popen(['ffmpeg', '-v', 'error', '-i', path, '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-'],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=fsz)
    count = 0
    try:
        while count < nexp:
            buf = proc.stdout.read(fsz)
            if buf is None or len(buf) < fsz:
                break
            count += 1
            yield np.frombuffer(buf, np.uint8).reshape(h, w, 3).copy()
    finally:
        try:
            proc.stdout.close()
        except Exception:
            pass
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()


def _prime_canonical(path, budget):
    """DEC-107/113 decode-once: the canonical SDR decode is ~11 s/pass in pure numpy, and a full analysis makes
    ~4 passes over overlapping-but-PARTIAL frame ranges (reference search, core homographies, ball window, pin
    tail) — so no single pass reaches EOF and the lazy per-pass cache below never flips `complete`, re-converting
    every pass (4× → the Cloud Run smoke timeout). For a canonical clip, decode the WHOLE clip ONCE here and fill
    the cache; every pass (incl. the first) is then served from RAM. Needs the clip to fit the budget (8 GiB
    instance + a large LANESIGHT_FRAME_CACHE_MB); if it won't fit we abort, mark too_big, and fall back to the
    per-pass decode. cv2 (non-canonical) decode is fast, so it is left on the lazy path. Returns True if primed."""
    from . import decode as _dec
    meta = _dec.probe_meta(path)
    if not _dec.can_canonical(meta):
        return False
    reset_frame_cache(); _FCACHE.update(path=path, prime_tried=True)
    _DECODE['passes'] += 1
    try:
        for i, f in enumerate(_dec.canonical_frames(path, meta, len(pts(path)))):
            t = _time.perf_counter()
            if _FCACHE['bytes'] + f.nbytes > budget:          # won't fit → abort prime, fall back to per-pass decode
                reset_frame_cache(); _FCACHE.update(path=path, too_big=True, prime_tried=True)
                _DECODE['seconds'] += _time.perf_counter() - t
                return False
            _FCACHE['frames'][i] = f; _FCACHE['bytes'] += f.nbytes
            _DECODE['frames'] += 1
            _DECODE['seconds'] += _time.perf_counter() - t
    except Exception:
        reset_frame_cache(); _FCACHE.update(path=path, too_big=True, prime_tried=True)
        return False
    _FCACHE['complete'] = True
    return True


def frames(path):
    budget = _FRAME_CACHE_MB * 1048576
    # Decode-once prime for canonical clips (see _prime_canonical). A NEW clip clears any prior too_big/cache;
    # the prime then runs at most once (guarded by complete/too_big) and the serve-block below handles every pass.
    if budget > 0 and os.environ.get('LANESIGHT_FFMPEG_DECODE') == '1':
        if _FCACHE['path'] != path:
            reset_frame_cache(); _FCACHE['path'] = path       # new clip → drop any stale cache + flags
        if not _FCACHE['prime_tried']:                        # attempt the prime exactly once per clip (a
            _FCACHE['prime_tried'] = True                     # non-canonical clip just returns False and keeps
            _prime_canonical(path, budget)                    # the normal lazy cv2 cache below — no re-probing)
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
    # DEC-107: ffmpeg CLI decode (deterministic Linux==macOS) when enabled, else cv2.VideoCapture. Both yield
    # upright BGR frames (ffmpeg autorotate ≈ cv2 ORIENTATION_AUTO).
    _use_ff = os.environ.get('LANESIGHT_FFMPEG_DECODE') == '1'
    _canon = False
    if _use_ff:
        from . import decode as _dec
        _meta = _dec.probe_meta(path)
        _canon = _dec.can_canonical(_meta)
    if _use_ff and _canon:
        _gen = _dec.canonical_frames(path, _meta, len(pts(path)))   # yuv decode + numpy BGR (deterministic)
        def _read():
            try:
                return True, next(_gen)
            except StopIteration:
                return False, None
        _release = _gen.close
        nframes_hint = 0
    else:
        cap = open_capture(path)
        nframes_hint = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)   # cheap upfront size check (0 if codec won't say)
        _read, _release = cap.read, cap.release
    i = 0
    try:
        while True:
            t = _time.perf_counter()
            ok, f = _read()
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
        _release()

def wood_mask(bgr):
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    H, S, V = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    m = ((H >= 5) & (H <= 25) & (S > 60) & (V > 90)).astype(np.uint8)
    return cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))

class Registrar:
    # DEC-092 P2 perf: the detection resolution + ORB feature count are the per-frame registration cost. On a
    # fixed-tripod clip a few hundred good lane-surface matches already pin the homography, so fewer features at a
    # lower detection scale cut stabilize time with no measurable geometry change (re-validate on IMG_8751-54,
    # Standard tier). Measurement is unaffected — it runs at FULL res on the warped frames; only the registration
    # that computes the warp is down-scaled. Defaults preserve the original 0.5 / 4000.
    def __init__(self, scale=None):
        self.s = float(os.environ.get('LANESIGHT_ORB_SCALE', '0.5')) if scale is None else scale
        nfeat = int(os.environ.get('LANESIGHT_ORB_FEATURES', '1500'))   # DEC-115: 1500 (was 4000) cuts the O(n^2)
        fast = int(os.environ.get('LANESIGHT_ORB_FAST', '10'))
        self.orb = cv2.ORB_create(nfeat, fastThreshold=fast); self.bf = cv2.BFMatcher(cv2.NORM_HAMMING)
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
    _dbg = {'passA_s': 0.0, 'featsB_s': 0.0, 'solveB_s': 0.0, 'bgC_s': 0.0}   # DEC-115 sub-stage profiling
    _tA = _time.perf_counter()
    # pass A: reference = middle of the longest steady stretch with the lane visible (within the core, not the tail).
    # DEC-115 perf: this per-frame motion/wood scan (resize + grey + wood_mask at 1/8 res) is the single biggest
    # stabilize stage on the server (~52%). The per-frame work is independent, so it is fanned across worker threads
    # (cv2 threads forced to 1) exactly like pass B; the phaseCorrelate motion is then computed sequentially over the
    # pre-computed greys (cheap FFTs). Same greys, same order -> bit-identical mot/woodf/ref as the serial scan, so
    # the reference choice (which some clips' speed is sensitive to) is UNCHANGED — this is pure parallel speed-up.
    def _mscan(f):
        sm = cv2.resize(f, None, fx=0.125, fy=0.125)
        return cv2.cvtColor(sm, cv2.COLOR_BGR2GRAY).astype(np.float32), float(wood_mask(sm).mean())
    _nwA = workers(); _dtA = cv2.getNumThreads(); greys = []; woodf = []
    cv2.setNumThreads(1)
    try:
        with ThreadPoolExecutor(max_workers=_nwA) as _exA:
            _genA = frames(path)
            while True:
                _bA = []
                for _ in range(max(_nwA * 8, 64)):
                    _nf = next(_genA, None)
                    if _nf is None: break
                    _bA.append(_nf[1])
                if not _bA: break
                for _g, _wm in _exA.map(_mscan, _bA):
                    greys.append(_g); woodf.append(_wm)
    finally:
        cv2.setNumThreads(_dtA)
    mot = [0.0] + [np.hypot(*cv2.phaseCorrelate(greys[k - 1], greys[k])[0]) * 8 for k in range(1, len(greys))]
    mot = np.convolve(np.array(mot), np.ones(15) / 15, 'same'); woodf = np.array(woodf)
    cm = np.array([core(i) for i in range(len(mot))])          # thresholds over core frames only, so the settle
    thr = max(3.0, np.percentile(mot[cm], 40)); wmax = woodf[cm].max()   # tail never shifts the reference choice
    steady = (mot < thr) & (woodf > 0.5 * wmax) & cm
    best = (0, 0, 0); run = 0
    for i, v in enumerate(steady):
        run = run + 1 if v else 0
        if run > best[0]: best = (run, i - run + 1, i)
    ref = (best[1] + best[2]) // 2
    _dbg['passA_s'] = round(_time.perf_counter() - _tA, 2)
    R = Registrar()
    # pass B: homographies (direct to reference; chain through previous frame when direct match is weak)
    Hs = []; inl = []; kr = dr = None; prev = None
    for i, f in frames(path):
        if i == ref: kr, dr = R.feats(f); ref_img = f.copy(); break
    # Subsample-registration fast path (DEC-092 P2 perf): pass B's per-frame ORB registration is ~80% of analysis
    # time on the server, but LaneSight is shot from a fixed tripod — the camera barely moves (logs: "motion up to
    # 1px"). So register only every LANESIGHT_REG_STRIDE-th frame with real ORB (which captures the clip's ACTUAL
    # small camera offset — unlike assuming identity, which biased IMG_8751 by ~0.4 mph) and reuse the nearest
    # registered homography for the frames in between. Consecutive frames differ by <1px on a tripod, so a
    # neighbour's homography is accurate; the cost drops ~STRIDE-fold. STRIDE=1 (default) is the exact original
    # per-frame path. Re-validate on IMG_8751-54 (Standard tier) whenever STRIDE changes.
    STRIDE = int(os.environ.get('LANESIGHT_REG_STRIDE', '1'))
    _stride_done = False
    if STRIDE > 1 and kr is not None:
        reg_ids = sorted(set([ref] + list(range(0, len(ts), STRIDE))))
        regset = set(reg_ids); regmax = max(reg_ids); rf = {}
        for i, f in frames(path):
            if i in regset: rf[i] = f
            if i >= regmax: break
        _tl = threading.local()
        def _feats(f):
            R2 = getattr(_tl, 'R', None)
            if R2 is None: R2 = _tl.R = Registrar()
            return R2.feats(f)
        nw = workers(); default_threads = cv2.getNumThreads()
        cv2.setNumThreads(1)
        with ThreadPoolExecutor(max_workers=nw) as ex:
            feats = list(ex.map(lambda i: _feats(rf[i]), reg_ids))
        cv2.setNumThreads(default_threads)
        regH = {}; prevf = None
        for i, (kf, df) in zip(reg_ids, feats):
            H, n = R.H(kf, df, kr, dr)
            if (H is None or n < min_inliers) and prevf is not None:
                Hp, n2 = R.H(kf, df, prevf[1], prevf[2])
                H, n = (regH[prevf[0]] @ Hp, -n2) if Hp is not None else (regH[prevf[0]], -1)
            if H is None: H, n = np.eye(3), -1
            regH[i] = H; prevf = (i, kf, df)
        reg_arr = np.array(reg_ids)
        for i in range(len(ts)):
            p = int(np.searchsorted(reg_arr, i))
            cand = [c for c in (p - 1, p) if 0 <= c < len(reg_arr)]
            j = reg_ids[min(cand, key=lambda c: abs(reg_arr[c] - i))]
            Hs.append(regH[j]); inl.append(999 if np.array_equal(regH[j], np.eye(3)) else int(min_inliers))
        log(f'subsample registration: ORB on {len(reg_ids)}/{len(ts)} frames (stride {STRIDE}), nearest-H fill')
        _stride_done = True
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
    if not _stride_done:
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
                    _tf = _time.perf_counter()
                    feats = list(ex.map(lambda nf: _feats(nf[1]), batch)) # ex.map preserves input order
                    _dbg['featsB_s'] += _time.perf_counter() - _tf
                    cv2.setNumThreads(default_threads)                    # phase 2: sequential solve at full threads
                    _ts2 = _time.perf_counter()
                    for (i, f), (kf, df) in zip(batch, feats):
                        H, n = R.H(kf, df, kr, dr)
                        if (H is None or n < min_inliers) and prev is not None:
                            Hp, n2 = R.H(kf, df, prev[1], prev[2])         # frame -> previous frame
                            H, n = (Hs[-1] @ Hp, -n2) if Hp is not None else (Hs[-1], -1)
                        if H is None: H, n = np.eye(3), -1
                        Hs.append(H); inl.append(n); prev = (i, kf, df)
                    _dbg['solveB_s'] += _time.perf_counter() - _ts2
        finally:
            cv2.setNumThreads(default_threads)
    Hs = np.array(Hs)
    c = np.array([540., 960., 1.]); sh = [np.linalg.norm((h @ c / (h @ c)[2])[:2] - c[:2]) for h in Hs]
    log(f'ref frame {ref} (t={ts[ref]:.2f}s); median inliers {np.median([v for v in inl if v > 0]):.0f}; '
        f'chained {sum(v < 0 for v in inl)}/{len(inl)}; camera motion up to {max(sh):.0f}px')
    # pass C: background = temporal median of warped frames (moving bowler/ball removed), core frames only so the
    # pin-settle tail (rake sweep, reset, bowler walking back) never pollutes the lane geometry
    _tC = _time.perf_counter()
    h, w = ref_img.shape[:2]
    core_idx = [i for i in range(len(Hs)) if core(i)]; step = max(1, len(core_idx) // 80)
    sample = set(core_idx[::step]); stack = []
    for i, f in frames(path):
        if i in sample: stack.append(cv2.warpPerspective(f, Hs[i], (w, h)))
    bg = np.median(np.stack(stack), axis=0).astype(np.uint8)
    _dbg['bgC_s'] = round(_time.perf_counter() - _tC, 2)
    _dbg['featsB_s'] = round(_dbg['featsB_s'], 2); _dbg['solveB_s'] = round(_dbg['solveB_s'], 2)
    log(f"stabilize sub: passA={_dbg['passA_s']}s featsB={_dbg['featsB_s']}s solveB={_dbg['solveB_s']}s bgC={_dbg['bgC_s']}s")
    return dict(ts=ts[:len(Hs)], Hs=Hs, ref=ref, bg=bg, inliers=np.array(inl), shift=np.array(sh))
