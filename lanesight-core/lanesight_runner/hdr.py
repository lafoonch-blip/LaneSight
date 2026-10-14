"""HDR (iPhone HLG, BT.2020) -> 8-bit SDR BT.709, done in numpy so it works with any ffmpeg build
(Homebrew's ffmpeg has no zscale/libplacebo tone mapping).

Per frame: ffmpeg decodes to 16-bit RGB (BT.2020 matrix, full range) -> HLG inverse OETF -> HLG OOTF
(system gamma 1.2, 1000-nit display) -> BT.2020 to BT.709 primaries (linear) -> Hable tone map on max(R,G,B)
(hue-preserving, like ffmpeg tonemap desat=0) with 203-nit reference white -> BT.709 OETF -> 8-bit.
Frames are processed in parallel threads (numpy releases the GIL) and piped to an H.264 encoder.
Frame TIMES are never taken from the output: the analysis reads them from the original clip."""
from __future__ import annotations
import subprocess, shutil
from concurrent.futures import ThreadPoolExecutor
import numpy as np

A, B, C = 0.17883277, 0.28466892, 0.55991073          # HLG constants (ITU-R BT.2100)
GAMMA = 1.2                                             # HLG system gamma at 1000 nits
PEAK_NITS, REF_WHITE_NITS = 1000.0, 203.0
M2020_709 = np.array([[1.6605, -0.5876, -0.0728],
                      [-0.1246, 1.1329, -0.0083],
                      [-0.0182, -0.1006, 1.1187]], np.float32)
Y2020 = np.array([0.2627, 0.6780, 0.0593], np.float32)

def _hlg_inverse_oetf(e):
    e = np.asarray(e, np.float64)
    return np.where(e <= 0.5, e * e / 3.0, (np.exp((e - C) / A) + B) / 12.0)

def _hable(x):
    a, b, c, d, e, f = 0.15, 0.50, 0.10, 0.20, 0.02, 0.30
    return ((x * (a * x + c * b) + d * e) / (x * (a * x + b) + d * f)) - e / f

def _bt709_oetf(l):
    return np.where(l < 0.018, 4.5 * l, 1.099 * np.power(l, 0.45) - 0.099)

LUT_IN = _hlg_inverse_oetf(np.arange(65536) / 65535.0).astype(np.float32)        # 16-bit code -> scene linear
_SCALE = PEAK_NITS / REF_WHITE_NITS                                                 # display linear, 1.0 = ref white
_PEAK = _SCALE                                                                      # brightest possible value
_HABLE_NORM = float(_hable(np.float64(_PEAK)))
_OUT_N = 4096
LUT_OUT = np.clip(np.round(255 * _bt709_oetf(np.linspace(0, 1, _OUT_N))), 0, 255).astype(np.uint8)

_N = 4096
_q = (np.arange(_N) / (_N - 1)) ** 2                       # sqrt-spaced bins: fine steps near black
OOTF_LUT = (np.power(np.maximum(_q, 1e-6), GAMMA - 1.0) * _SCALE).astype(np.float32)        # y -> gain
_s = _q * _PEAK
GAIN_LUT = np.where(_s > 1e-6, _hable(_s) / _HABLE_NORM / np.maximum(_s, 1e-6), 1.0 / _HABLE_NORM * 2.0).astype(np.float32)

def _idx(x, scale):
    return np.minimum(np.sqrt(np.maximum(x * scale, 0)) * (_N - 1) + 0.5, _N - 1).astype(np.int32)

def tonemap_frame(rgb16: np.ndarray) -> np.ndarray:
    """(H, W, 3) uint16 BT.2020 HLG RGB -> (H, W, 3) uint8 BT.709 SDR RGB."""
    import cv2
    lin = LUT_IN[rgb16]                                           # scene linear, 0..1
    y = cv2.transform(lin, Y2020[None, :])                        # (H, W) luminance
    lin *= OOTF_LUT[_idx(y, 1.0)][..., None]                      # OOTF -> display linear (ref white = 1)
    lin = cv2.transform(lin, M2020_709)
    np.maximum(lin, 0, out=lin)
    sig = np.maximum(np.maximum(lin[..., 0], lin[..., 1]), lin[..., 2])
    lin *= GAIN_LUT[_idx(sig, 1.0 / _PEAK)][..., None]            # Hable on max(R,G,B): hue preserved
    return LUT_OUT[np.minimum(lin * (_OUT_N - 1) + 0.5, _OUT_N - 1).astype(np.int32)]

def convert(src: str, dst: str, width: int, height: int, threads: int = 0, batch: int = 32) -> dict:
    """width/height: frame size AFTER rotation (ffmpeg auto-rotates when decoding). Returns frames written."""
    enc = (['-c:v', 'h264_videotoolbox', '-b:v', '40M'] if _has_encoder('h264_videotoolbox')
           else ['-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '16'])
    dec = subprocess.Popen(['ffmpeg', '-v', 'error', '-i', src, '-map', '0:v:0', '-an', '-fps_mode', 'passthrough',
                            '-vf', 'scale=in_color_matrix=bt2020:in_range=tv:out_range=pc,format=rgb48le',
                            '-f', 'rawvideo', '-'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{width}x{height}',
                            '-r', '60', '-i', '-', *enc, '-pix_fmt', 'yuv420p',
                            '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', dst],
                           stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    fsize = width * height * 3 * 2; n = 0
    pool = ThreadPoolExecutor(max_workers=threads or None)
    try:
        while True:
            frames = []
            for _ in range(batch):
                buf = dec.stdout.read(fsize)
                if len(buf) < fsize: break
                frames.append(np.frombuffer(buf, np.uint16).reshape(height, width, 3))
            if not frames: break
            for f in pool.map(tonemap_frame, frames):
                out.stdin.write(f.tobytes()); n += 1
            if len(frames) < batch: break
    finally:
        pool.shutdown()
        out.stdin.close(); out.wait(); dec.stdout.close(); dec.wait()
    if dec.returncode != 0: raise RuntimeError(f'HDR decode failed: {dec.stderr.read().decode()[-300:]}')
    if out.returncode != 0: raise RuntimeError(f'SDR encode failed: {out.stderr.read().decode()[-300:]}')
    return dict(frames=n, encoder=enc[1])

def _has_encoder(name):
    if not shutil.which('ffmpeg'): return False
    r = subprocess.run(['ffmpeg', '-hide_banner', '-encoders'], capture_output=True, text=True)
    return any(line.split()[1:2] == [name] for line in r.stdout.splitlines() if len(line.split()) > 1)
