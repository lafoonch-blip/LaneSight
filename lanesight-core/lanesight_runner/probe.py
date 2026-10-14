"""Clip checks before analysis. Timing metrics depend on real frame timestamps, so a clip whose timestamps
can't be trusted fails here with a reason instead of producing a speed.

lanesight-core reads frame times with ffprobe and frames with OpenCV, and pairs them by index. If the two
disagree on the frame count, every timestamp after the first dropped frame is wrong, so that is a hard failure."""
from __future__ import annotations
import json, subprocess
import numpy as np

VIDEO_EXT = {'.mov', '.mp4', '.m4v'}

class ClipError(Exception):
    pass

def _ffprobe(args, path):
    r = subprocess.run(['ffprobe', '-v', 'error', *args, '-of', 'json', path], capture_output=True, text=True)
    if r.returncode != 0:
        raise ClipError(f"ffprobe could not read the file: {r.stderr.strip()[:200]}")
    return json.loads(r.stdout or '{}')

def _rate(s):
    try:
        a, b = s.split('/'); return float(a) / float(b) if float(b) else None
    except Exception:
        return None

def probe(path, check_decoder=True) -> dict:
    info = _ffprobe(['-select_streams', 'v:0', '-show_streams', '-show_format'], path)
    streams = info.get('streams') or []
    if not streams:
        raise ClipError('no video stream in this file')
    s = streams[0]
    w, h = int(s.get('width') or 0), int(s.get('height') or 0)
    rot = 0
    for sd in s.get('side_data_list') or []:
        if 'rotation' in sd: rot = int(sd['rotation'])
    if 'rotate' in (s.get('tags') or {}): rot = int(s['tags']['rotate'])
    pk = _ffprobe(['-select_streams', 'v:0', '-show_entries', 'packet=pts_time'], path)
    pts = np.array(sorted(float(p['pts_time']) for p in pk.get('packets', []) if p.get('pts_time') not in (None, 'N/A')))
    if len(pts) < 30:
        raise ClipError(f'only {len(pts)} timestamped frames; clip too short or timestamps missing')
    d = np.diff(pts)
    if np.any(d <= 0):
        raise ClipError('duplicate or out-of-order frame timestamps; timing metrics would be wrong')
    med = float(np.median(d))
    fps = 1.0 / med
    spread = float((np.percentile(d, 95) - np.percentile(d, 5)) / med)
    out = dict(codec=s.get('codec_name'), width=w, height=h, rotation=rot, short_side_px=min(w, h),
               nominal_fps=_rate(s.get('avg_frame_rate')), measured_fps=round(fps, 2), frames=int(len(pts)),
               duration_s=round(float(pts[-1] - pts[0]), 2), variable_frame_rate=spread > 0.2,
               max_frame_gap_ms=round(1000 * float(d.max()), 1))
    if check_decoder:
        import cv2
        cap = cv2.VideoCapture(path)
        if not cap.isOpened():
            raise ClipError(f"OpenCV can't decode this clip ({out['codec']}). Re-export as H.264 "
                            "(iPhone: Settings > Camera > Formats > Most Compatible) or transcode with ffmpeg.")
        ok, _ = cap.read()
        n = 1 if ok else 0
        while ok:
            ok = cap.grab()
            n += 1 if ok else 0
        cap.release()
        out['decoded_frames'] = n
        if n == 0:
            raise ClipError(f"OpenCV opened the clip but decoded no frames ({out['codec']})")
        if abs(n - len(pts)) > max(1, 0.002 * len(pts)):
            raise ClipError(f'decoder returned {n} frames but the file has {len(pts)} timestamps; '
                            'frame times would be misaligned, so timing metrics are not trustworthy')
    warnings = []
    if fps < 55: warnings.append(f'{fps:.0f} fps: loft is unavailable and late speed is less accurate below 60 fps')
    if out['short_side_px'] < 1000: warnings.append(f"{out['short_side_px']}p: below 1080p, board metrics are less accurate")
    if out['variable_frame_rate']: warnings.append('variable frame rate: timing uses the real frame timestamps')
    out['warnings'] = warnings
    return out
