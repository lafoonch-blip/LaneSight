"""DEC-092 P0 — ~2 s framing precheck.

Before the full (minutes-long) pipeline, decode only a handful of frames across the clip, build a rough
background plate from their median, and run the existing lane / foul-line finder on it. If framing is
unusable the finder raises the same DEC-086 codes the full pipeline would (LANE_NOT_DETECTED_NO_WOOD /
NO_EDGES / FOUL_LINE_NOT_IN_VIEW) — so we can fail in ~2 s instead of ~140 s.

SHIPPING MODE (DEC-092): run in **shadow** — record the verdict on the attempt, do NOT block — until the
benchmark shows it rejects zero clips the full pipeline passes. Only then is it safe to enforce.
"""
from __future__ import annotations
import time
import numpy as np

_MAX_FRAMES = 9


def precheck(path: str) -> dict:
    """Returns {ok, seconds, frames_used, code?, stage?, message?}. Never raises — a probe/decode problem
    just yields ok=None (unknown) so the caller falls through to the full pipeline."""
    t0 = time.perf_counter()
    import cv2
    from .lanes import find_lanes
    from ..failures import AnalysisFailure
    try:
        cap = cv2.VideoCapture(path)
        n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        # Sample evenly across the clip (CAP_PROP_POS_FRAMES seeks to the enclosing keyframe → cheap).
        idxs = sorted({int(round(i)) for i in np.linspace(0, max(n - 1, 0), _MAX_FRAMES)}) if n else [0]
        frames = []
        for idx in idxs:
            cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
            ok, f = cap.read()
            if ok:
                frames.append(f)
        cap.release()
    except Exception as e:
        return {'ok': None, 'seconds': round(time.perf_counter() - t0, 3), 'probe_error': str(e)[:150]}

    if not frames:
        return {'ok': None, 'seconds': round(time.perf_counter() - t0, 3), 'frames_used': 0}

    # Median across the sampled frames approximates a static background (lane wood + foul line are fixed;
    # the moving ball/bowler average out). The lane/foul finder runs on it exactly as in the full pipeline.
    bg = np.median(np.stack(frames), axis=0).astype(np.uint8)
    try:
        find_lanes(bg, log=lambda *a, **k: None)
        return {'ok': True, 'seconds': round(time.perf_counter() - t0, 3), 'frames_used': len(frames)}
    except AnalysisFailure as e:
        return {'ok': False, 'seconds': round(time.perf_counter() - t0, 3), 'frames_used': len(frames),
                'code': e.code, 'stage': e.stage, 'message': str(e)[:150]}
    except Exception as e:
        # An unexpected error in the cheap finder is NOT a reason to reject — fall through to the full run.
        return {'ok': None, 'seconds': round(time.perf_counter() - t0, 3), 'frames_used': len(frames),
                'error': str(e)[:150]}
