"""Stage 1: register every frame to a reference frame (static tripod, handheld, or head-mounted)
and build a clean background plate in reference coordinates. Streaming: frames are never all held."""
import cv2, numpy as np, subprocess, threading
from concurrent.futures import ThreadPoolExecutor
from ._parallel import workers

def pts(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'frame=pts_time',
                          '-of', 'csv=p=0', path], capture_output=True, text=True).stdout
    return np.array([float(x.strip(',')) for x in out.split() if x.strip(',')])

def frames(path):
    cap = cv2.VideoCapture(path); i = 0
    while True:
        ok, f = cap.read()
        if not ok: return
        yield i, f; i += 1

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
        if n != len(ts): raise RuntimeError(f'timing source has {len(ts)} frames but the video has {n}')
    core = (lambda i: True) if core_end_s is None else (lambda i: i >= len(ts) or ts[i] <= core_end_s)
    # pass A: reference = middle of the longest steady stretch with the lane visible (within the core, not the tail)
    prevg = None; mot = []; woodf = []
    for i, f in frames(path):
        sm = cv2.resize(f, None, fx=0.125, fy=0.125)
        g = cv2.cvtColor(sm, cv2.COLOR_BGR2GRAY).astype(np.float32)
        mot.append(0.0 if prevg is None else np.hypot(*cv2.phaseCorrelate(prevg, g)[0]) * 8)
        woodf.append(wood_mask(sm).mean()); prevg = g
    mot = np.convolve(np.array(mot), np.ones(15) / 15, 'same'); woodf = np.array(woodf)
    cm = np.array([core(i) for i in range(len(mot))])          # thresholds over core frames only, so the settle
    thr = max(3.0, np.percentile(mot[cm], 40)); wmax = woodf[cm].max()   # tail never shifts the reference choice
    steady = (mot < thr) & (woodf > 0.5 * wmax) & cm
    best = (0, 0, 0); run = 0
    for i, v in enumerate(steady):
        run = run + 1 if v else 0
        if run > best[0]: best = (run, i - run + 1, i)
    ref = (best[1] + best[2]) // 2
    R = Registrar()
    # pass B: homographies (direct to reference; chain through previous frame when direct match is weak)
    Hs = []; inl = []; kr = dr = None; prev = None
    for i, f in frames(path):
        if i == ref: kr, dr = R.feats(f); ref_img = f.copy(); break
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
