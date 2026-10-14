"""Clip checks before analysis. Timing metrics depend on real frame timestamps, so a clip whose timestamps
can't be trusted fails here with a reason instead of producing a speed.

lanesight-core reads frame times with ffprobe and frames with OpenCV, and pairs them by index. If the two
disagree on the frame count, every timestamp after the first dropped frame is wrong, so that is a hard failure."""
from __future__ import annotations
import json, subprocess
import numpy as np

VIDEO_EXT = {'.mov', '.mp4', '.m4v'}
HDR_TRANSFERS = {'arib-std-b67', 'smpte2084'}     # HLG (iPhone HDR Video), PQ

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
    hdr = s.get('color_transfer') in HDR_TRANSFERS
    out = dict(codec=s.get('codec_name'), width=w, height=h, rotation=rot, short_side_px=min(w, h),
               pix_fmt=s.get('pix_fmt'), color_transfer=s.get('color_transfer'), hdr=hdr,
               nominal_fps=_rate(s.get('avg_frame_rate')), measured_fps=round(fps, 2), frames=int(len(pts)),
               duration_s=round(float(pts[-1] - pts[0]), 2), variable_frame_rate=spread > 0.2,
               max_frame_gap_ms=round(1000 * float(d.max()), 1))
    if check_decoder and not hdr:       # HDR clips are decoded after conversion to SDR (see convert_sdr)
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
    if hdr: warnings.append('HDR clip: converted to SDR before analysis, which adds time. '
                            'Turn off iPhone Settings > Camera > Record Video > HDR Video')
    out['warnings'] = warnings
    return out


def frame_times(path):
    """Presentation timestamps of every frame, the same way lanesight-core reads them (stabilize.pts)."""
    r = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'frame=pts_time',
                        '-of', 'csv=p=0', path], capture_output=True, text=True)
    return np.array([float(x.strip(',')) for x in r.stdout.split() if x.strip(',')])

TONEMAP = ('zscale=t=linear:npl=203,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,'
           'zscale=t=bt709:m=bt709:r=tv,format=yuv420p')

def _has(kind, name):
    r = subprocess.run(['ffmpeg', '-hide_banner', f'-{kind}'], capture_output=True, text=True)
    return any(line.split()[1:2] == [name] for line in r.stdout.splitlines() if len(line.split()) > 1)

def convert_sdr(src, dst, max_shift_s=0.002):
    """HDR (HLG/PQ) -> 8-bit SDR BT.709 with tone mapping, keeping every frame and its timestamp.
    OpenCV decodes HDR without tone mapping, so colours come out washed out and lane/ball colour models fail.
    The output is verified: same frame count, every frame time within max_shift_s of the original; else ClipError."""
    if not _has('filters', 'zscale'):
        raise ClipError('HDR clip, and this ffmpeg has no zscale filter to convert it. '
                        'Turn off HDR Video on the iPhone (Settings > Camera > Record Video)')
    enc = (['-c:v', 'h264_videotoolbox', '-b:v', '40M'] if _has('encoders', 'h264_videotoolbox')
           else ['-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '16'])
    r = subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', src, '-map', '0:v:0', '-an', '-fps_mode', 'passthrough',
                        '-video_track_timescale', '600', '-vf', TONEMAP, *enc,
                        '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', dst],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise ClipError(f'HDR to SDR conversion failed: {r.stderr.strip()[-300:]}')
    a, b = frame_times(src), frame_times(dst)
    if len(a) != len(b):
        raise ClipError(f'HDR conversion changed the frame count ({len(a)} -> {len(b)}); timing would be wrong')
    shift = float(np.abs((a - a[0]) - (b - b[0])).max())
    if shift > max_shift_s:
        raise ClipError(f'HDR conversion moved frame times by up to {1000 * shift:.1f} ms; timing would be wrong')
    return dict(encoder=enc[1], max_shift_ms=round(1000 * shift, 2), frames=len(b))
