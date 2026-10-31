"""Canonical frame decode (DEC-107 fix, Shayne 2026-10-31). The server-vs-Mac speed gap (16.0 vs 18.7) was
localized to the YUV→BGR COLOUR CONVERSION: the raw YUV420P is bit-identical on both platforms, but the
swscale/opencv conversion differs (Mac ffmpeg 9.0.2 vs container ffmpeg 5.1 / cv2 5.0) by ~1% per channel
(red-biased), and the 2-point homography's impact anchor is sensitive enough that this shifts speed ~14%.

Fix: decode the raw YUV420P via ffmpeg (bit-identical everywhere) and convert YUV→BGR in PURE NUMPY, driven by
the clip's colour_space/range metadata — so the exact same bytes come out on the Mac and in the container. SDR
(bt709/bt601) is handled here; HDR (HLG/PQ bt2020 — clips are tone-mapped to SDR by probe.convert_sdr before
this) falls back to the cv2 path until canonicalised. Rotation is applied to match cv2's ORIENTATION_AUTO.
"""
from __future__ import annotations
import subprocess, json
import numpy as np

# YUV(full-range)→RGB per BT.x: (Kr, Kb). Non-constant-luminance matrices.
_KRKB = {'bt709': (0.2126, 0.0722), 'bt601': (0.299, 0.114), 'smpte170m': (0.299, 0.114),
         'bt470bg': (0.299, 0.114), 'fcc': (0.30, 0.11), 'bt2020nc': (0.2627, 0.0593),
         'bt2020_ncl': (0.2627, 0.0593), 'unknown': (0.2126, 0.0722), '': (0.2126, 0.0722)}
# Transfers we can decode as SDR directly (no tone-map needed). HLG/PQ are handled upstream (convert_sdr).
_SDR_TRANSFER = {'bt709', 'bt601', 'smpte170m', 'bt470bg', 'iec61966-2-1', 'srgb', 'unknown', '', None}


def probe_meta(path):
    pr = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                         'stream=width,height,color_space,color_range,color_transfer:stream_side_data=rotation',
                         '-of', 'json', path], capture_output=True, text=True).stdout
    st = (json.loads(pr).get('streams') or [{}])[0]
    rot = 0
    for sd in st.get('side_data_list', []) or []:
        if 'rotation' in sd:
            rot = int(sd['rotation'])
    return {'w': int(st.get('width', 0)), 'h': int(st.get('height', 0)),
            'cs': st.get('color_space') or 'bt709', 'range': st.get('color_range') or 'tv',
            'transfer': st.get('color_transfer') or 'bt709', 'rotation': rot}


def can_canonical(meta):
    """SDR clips with a known matrix decode canonically here; HDR (HLG/PQ) is left to the cv2 path for now."""
    return meta['transfer'] in _SDR_TRANSFER and meta['cs'] in _KRKB


def yuv420p_to_bgr(buf, w, h, cs='bt709', rng='tv'):
    """Planar YUV420P bytes → HxWx3 BGR uint8. Bilinear chroma upsample; limited/full range aware."""
    ysz = w * h
    Y = np.frombuffer(buf[:ysz], np.uint8).reshape(h, w).astype(np.float32)
    cw, ch = w // 2, h // 2
    U = np.frombuffer(buf[ysz:ysz + cw * ch], np.uint8).reshape(ch, cw).astype(np.float32)
    V = np.frombuffer(buf[ysz + cw * ch:ysz + 2 * cw * ch], np.uint8).reshape(ch, cw).astype(np.float32)
    # bilinear upsample the chroma planes to full res (deterministic)
    import cv2 as _cv
    U = _cv.resize(U, (w, h), interpolation=_cv.INTER_LINEAR)
    V = _cv.resize(V, (w, h), interpolation=_cv.INTER_LINEAR)
    Kr, Kb = _KRKB.get(cs, _KRKB['bt709']); Kg = 1.0 - Kr - Kb
    if rng in ('pc', 'jpeg', 'full'):
        Yl, Cb, Cr = Y, U - 128.0, V - 128.0
    else:
        Yl = (Y - 16.0) * (255.0 / 219.0)
        Cb = (U - 128.0) * (255.0 / 224.0)
        Cr = (V - 128.0) * (255.0 / 224.0)
    R = Yl + (2.0 - 2.0 * Kr) * Cr
    B = Yl + (2.0 - 2.0 * Kb) * Cb
    G = Yl - (Kb * (2.0 - 2.0 * Kb) / Kg) * Cb - (Kr * (2.0 - 2.0 * Kr) / Kg) * Cr
    return np.clip(np.stack([B, G, R], -1) + 0.5, 0, 255).astype(np.uint8)


def _apply_rotation(img, rot):
    """Match cv2 ORIENTATION_AUTO: apply the display rotation. ffprobe rotation is the clockwise angle to apply
    for display; the stream side-data convention is negative for a phone held rotated. -90 → rotate 90° CW."""
    import cv2 as _cv
    r = rot % 360
    if r == 90 or r == -270:
        return _cv.rotate(img, _cv.ROTATE_90_COUNTERCLOCKWISE)
    if r == 270 or r == -90:
        return _cv.rotate(img, _cv.ROTATE_90_CLOCKWISE)
    if r == 180:
        return _cv.rotate(img, _cv.ROTATE_180)
    return img


def canonical_frames(path, meta, nexp):
    """Stream canonical BGR frames (SDR). yuv420p decode (bit-identical) + numpy conversion + rotation. Capped to
    `nexp` frames so the stream length matches the timestamp array."""
    w, h = meta['w'], meta['h']
    fsz = w * h * 3 // 2
    proc = subprocess.Popen(['ffmpeg', '-v', 'error', '-noautorotate', '-i', path,
                             '-f', 'rawvideo', '-pix_fmt', 'yuv420p', '-'],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=fsz)
    count = 0
    try:
        while count < nexp:
            buf = proc.stdout.read(fsz)
            if not buf or len(buf) < fsz:
                break
            count += 1
            bgr = yuv420p_to_bgr(buf, w, h, meta['cs'], meta['range'])
            yield _apply_rotation(bgr, meta['rotation'])
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
