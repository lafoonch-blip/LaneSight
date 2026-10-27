"""Speed-only helper: fan per-frame CPU work (ORB, warp, blob extraction) across cores while decode stays
sequential and results are reassembled in strict frame order. Pure-performance — no effect on any result.

OpenCV's heavy ops release the GIL, so a thread pool gives real parallelism without pickling frames. Each
worker's cv2 call is forced single-threaded (setNumThreads(1)) so N workers don't oversubscribe the cores;
restored on exit. Determinism: fn must be a pure per-frame function (no cross-frame state); callers keep any
sequential reduction (e.g. homography chaining, RANSAC) on the main thread in frame order, so numeric output
is identical to the serial loop."""
from __future__ import annotations
import os, collections, cv2
from contextlib import contextmanager
from concurrent.futures import ThreadPoolExecutor


def workers():
    env = os.environ.get('LANESIGHT_CV_WORKERS')
    if env:
        try: return max(1, int(env))
        except ValueError: pass
    return max(1, min(os.cpu_count() or 1, 12))


@contextmanager
def single_threaded_cv():
    prev = cv2.getNumThreads()
    cv2.setNumThreads(1)
    try: yield
    finally: cv2.setNumThreads(prev)


def pmap_frames(frames_iter, fn, upto=None, nworkers=None, inflight=None):
    """Decode frames sequentially from `frames_iter` (yields (i, frame)); apply fn(i, frame) in a thread pool;
    yield (i, result) in ascending frame-index order. A sliding window of `inflight` in-flight frames bounds
    memory and overlaps decode with compute. Stops once index >= `upto` (exclusive) if given.

    If nworkers == 1 the work runs inline (no pool) — identical results, zero threading overhead."""
    nw = nworkers or workers()
    if nw <= 1:
        for i, f in frames_iter:
            if upto is not None and i >= upto: return
            yield i, fn(i, f)
        return
    cap = inflight or nw * 2
    with single_threaded_cv(), ThreadPoolExecutor(max_workers=nw) as ex:
        futs: collections.deque = collections.deque()
        for i, f in frames_iter:
            if upto is not None and i >= upto: break
            futs.append((i, ex.submit(fn, i, f)))
            if len(futs) >= cap:
                i0, fu = futs.popleft(); yield i0, fu.result()
        while futs:
            i0, fu = futs.popleft(); yield i0, fu.result()
