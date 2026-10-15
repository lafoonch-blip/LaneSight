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

def _encoder():
    return (['-c:v', 'h264_videotoolbox', '-b:v', '40M'] if _has('encoders', 'h264_videotoolbox')
            else ['-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '16'])

# BT.2020 -> BT.709 primaries, linear RGB
_BT2020_TO_709 = np.array([[1.6605, -0.5876, -0.0728],
                           [-0.1246, 1.1329, -0.0083],
                           [-0.0182, -0.1006, 1.1187]], np.float32)

def _hlg_to_709(rgb_u8):
    """One HLG (arib-std-b67, BT.2020) R'G'B' frame -> 8-bit SDR BT.709. The decoder gives the HLG-encoded
    signal with the BT.2020 matrix applied but no transfer/gamut conversion, so colours read washed out and
    desaturated (hue is also off). Invert the HLG OETF to scene-linear, convert the gamut, re-apply BT.709 gamma."""
    e = rgb_u8.astype(np.float32) / 255.0
    a, b, c = 0.17883277, 0.28466892, 0.55991073          # ARIB STD-B67 inverse OETF
    lin = np.where(e <= 0.5, e * e / 3.0, (np.exp((e - c) / a) + b) / 12.0)
    lin = np.clip(lin @ _BT2020_TO_709.T, 0, 1)
    v = np.where(lin < 0.018, 4.5 * lin, 1.099 * np.power(lin, 0.45) - 0.099)   # BT.709 OETF
    return np.clip(v * 255, 0, 255).astype(np.uint8)

def _convert_sdr_numpy(src, dst, transfer):
    """Zscale-free HDR -> SDR: decode with OpenCV (the same decoder the pipeline uses, so colours match the model
    and the frame count lines up), tone-map each frame in numpy, re-encode to H.264 with ffmpeg. Used when this
    ffmpeg was built without zscale. Only HLG (iPhone HDR Video) is handled; PQ needs a different inverse curve
    and is refused rather than guessed at."""
    if transfer != 'arib-std-b67':
        raise ClipError(f'HDR clip uses the {transfer} transfer, which this build can only convert with an '
                        'ffmpeg that has the zscale filter. Turn off HDR Video on the iPhone, or install ffmpeg with libzimg.')
    import cv2
    cap = cv2.VideoCapture(src)
    if not cap.isOpened():
        raise ClipError(f"OpenCV can't decode this HDR clip for conversion. Re-export as H.264 or turn off HDR Video.")
    ok, bgr = cap.read()
    if not ok:
        cap.release(); raise ClipError('OpenCV opened the HDR clip but decoded no frames')
    h, w = bgr.shape[:2]
    enc = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
                            '-s', f'{w}x{h}', '-r', '60', '-i', '-', '-an', '-video_track_timescale', '600',
                            *_encoder(), '-pix_fmt', 'yuv420p',
                            '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', dst],
                           stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
    n = 0
    try:
        while ok:
            enc.stdin.write(_hlg_to_709(bgr[..., ::-1]).tobytes())   # BGR -> RGB in, RGB out
            n += 1
            ok, bgr = cap.read()
    finally:
        cap.release(); enc.stdin.close(); enc.wait()
    if n == 0 or enc.returncode != 0:
        raise ClipError('HDR to SDR conversion failed (numpy tone-map path produced no output)')
    return n

def convert_sdr(src, dst):
    """HDR (HLG/PQ) -> 8-bit SDR BT.709 with tone mapping, every frame kept in order.
    OpenCV decodes HDR without tone mapping, so colours come out washed out and lane/ball colour models fail.
    Uses ffmpeg's zscale tone-map when available, else a portable numpy HLG inverse (no libzimg needed).
    Frame TIMES are always read from the original clip (analyze(timing_video=src)), so the encoder's timebase
    can't shift them; this function verifies the frame count matches exactly, else ClipError."""
    enc = _encoder()
    if _has('filters', 'zscale'):
        r = subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', src, '-map', '0:v:0', '-an', '-fps_mode', 'passthrough',
                            '-video_track_timescale', '600', '-vf', TONEMAP, *enc,
                            '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', dst],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise ClipError(f'HDR to SDR conversion failed: {r.stderr.strip()[-300:]}')
        method = f'zscale+{enc[1]}'
    else:
        transfer = (_ffprobe(['-select_streams', 'v:0', '-show_entries', 'stream=color_transfer'], src)
                    .get('streams') or [{}])[0].get('color_transfer')
        _convert_sdr_numpy(src, dst, transfer)
        method = f'hlg-numpy+{enc[1]}'
    a, b = frame_times(src), frame_times(dst)
    if len(a) != len(b):
        raise ClipError(f'HDR conversion changed the frame count ({len(a)} -> {len(b)}); frames would not line up with their times')
    return dict(encoder=enc[1], method=method, frames=len(b), timing_source='original clip')
