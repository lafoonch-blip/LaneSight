"""DEC-092 P0 — ~2 s framing precheck (three-way verdict).

Before the full (minutes-long) pipeline, decode only a handful of frames across the clip, build a rough
background plate from their median, and run the existing lane / foul-line finder on it. If framing is clearly
unusable we fail in ~2 s instead of ~140 s.

SHIPPING MODE (DEC-092): run in **shadow** — record the verdict on the attempt, do NOT block — until the
benchmark (`ops/precheck_vs_pipeline.py`) shows it rejects ZERO clips the full pipeline passes. Only then is it
safe to enforce.

The verdict is three-way — reject only on a confident failure, never on doubt (the ~9-frame median plate is
much rougher than the pipeline's stabilised background, so most failures are inconclusive):
- `ok=True`  : the lane/foul finder succeeded — framing is usable → run the full pipeline.
- `ok=False` : a CONFIDENT framing failure (the camera isn't pointed at a lane: no lane-coloured wood at any
               saturation floor, on a non-HDR plate) → fast-reject.
- `ok=None`  : inconclusive (HDR residual, pale lane, a low/off-axis camera, a NO_EDGES or FOUL_LINE miss on
               the rough plate, a decode hiccup) → fall through to the full pipeline. NEVER reject on doubt.

HDR handling: an iPhone HDR (HLG) clip decodes washed-out/desaturated, so the lane wood reads as "no wood" and
the finder would wrongly reject (IMG_8751/8754). We tone-map the ~9 sampled frames to SDR first (cheap), so the
precheck sees what the pipeline sees. PQ HDR has no numpy tone-map path → inconclusive. An HDR clip is never
confidently rejected regardless.
"""
from __future__ import annotations
import json
import subprocess
import time
import numpy as np

_MAX_FRAMES = 9
_HLG = 'arib-std-b67'          # iPhone HDR Video (ARIB STD-B67 / HLG)
_PQ = 'smpte2084'              # PQ HDR — no numpy inverse curve here
_HDR = {_HLG, _PQ}
_CONFIDENT_NO_WOOD_PCT = 1.0   # <this % of lane-coloured pixels at the strict floor ⇒ not pointed at a lane


def _color_transfer(path: str):
    """The clip's color_transfer tag (for HDR detection), or None on any error."""
    try:
        r = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
                            '-show_entries', 'stream=color_transfer', '-of', 'json', path],
                           capture_output=True, text=True, timeout=10)
        return ((json.loads(r.stdout).get('streams') or [{}])[0] or {}).get('color_transfer')
    except Exception:
        return None


def _confident_reject(err, transfer) -> tuple[bool, str]:
    """(confident, reason). Reject only when we're sure the FULL pipeline would also fail. On this rough plate
    that's just one case: a non-HDR clip with no lane-coloured wood anywhere (the camera isn't at a lane).
    Everything else — HDR, NO_EDGES, FOUL_LINE (low-camera miss), geometry — is inconclusive."""
    if transfer in _HDR:
        return False, 'hdr'                       # never confidently reject HDR from a rough plate
    if err.code == 'LANE_NOT_DETECTED_NO_WOOD':
        pct = (err.diagnostics or {}).get('pct_pixels_matched')
        if pct is not None and pct < _CONFIDENT_NO_WOOD_PCT:
            return True, ''                        # essentially no lane wood at any floor → not a lane
        return False, 'low_wood_uncertain'
    return False, err.code.lower()                # NO_EDGES / FOUL_LINE_NOT_IN_VIEW / etc. → inconclusive


def precheck(path: str) -> dict:
    """Returns {ok, seconds, frames_used, code?, stage?, message?, inconclusive?, sdr?}. `ok` is True / False /
    None (inconclusive). Never raises — any probe/decode problem yields ok=None so the caller runs the full
    pipeline."""
    t0 = time.perf_counter()
    import cv2
    from .lanes import find_lanes
    from .stabilize import open_capture
    from ..failures import AnalysisFailure

    def done(d):
        return {'seconds': round(time.perf_counter() - t0, 3), **d}

    transfer = _color_transfer(path)
    try:
        cap = open_capture(path)      # honor rotation so the precheck sees the same upright frames (DEC-092)
        n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        idxs = sorted({int(round(i)) for i in np.linspace(0, max(n - 1, 0), _MAX_FRAMES)}) if n else [0]
        frames = []
        for idx in idxs:
            cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
            ok, f = cap.read()
            if ok:
                frames.append(f)
        cap.release()
    except Exception as e:
        return done({'ok': None, 'probe_error': str(e)[:150]})

    if not frames:
        return done({'ok': None, 'frames_used': 0})

    # DEC-092: tone-map HLG → SDR on the sampled frames so the finder sees what the pipeline sees. PQ has no
    # numpy path → inconclusive (don't judge framing from a washed-out HDR plate).
    sdr = None
    if transfer == _HLG:
        from lanesight_runner.probe import _hlg_to_709
        frames = [cv2.cvtColor(_hlg_to_709(cv2.cvtColor(f, cv2.COLOR_BGR2RGB)), cv2.COLOR_RGB2BGR) for f in frames]
        sdr = 'hlg_to_709'
    elif transfer == _PQ:
        return done({'ok': None, 'frames_used': len(frames), 'inconclusive': 'pq_hdr_not_tonemapped'})

    bg = np.median(np.stack(frames), axis=0).astype(np.uint8)
    base = {'frames_used': len(frames), **({'sdr': sdr} if sdr else {})}
    try:
        find_lanes(bg, log=lambda *a, **k: None)
        return done({'ok': True, **base})
    except AnalysisFailure as e:
        confident, reason = _confident_reject(e, transfer)
        if confident:
            return done({'ok': False, 'code': e.code, 'stage': e.stage, 'message': str(e)[:150], **base})
        # inconclusive — the full pipeline decides. Record what the rough precheck saw, for the shadow table.
        return done({'ok': None, 'inconclusive': reason, 'precheck_code': e.code, **base})
    except Exception as e:
        return done({'ok': None, 'error': str(e)[:150], **base})
