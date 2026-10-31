#!/usr/bin/env python3
"""In-CONTAINER CV diagnostic (2026-10-29) — runs inside the production image (Cloud Run Job) to root-cause the
server-vs-Mac lane-geometry gap (DEC-107) and to be the seed of the in-container cv_eval Gate A.

Mac dev (opencv macOS wheel + ffmpeg 9) reads IMG_8753 early-speed ~18.7 / z@9.82≈13.28; the server reads
~16.04 / z≈11.40 — a ~0.858× down-lane scale. We RULED OUT opencv VERSION (4.10 == 5.0 on the Mac) and the
system ffprobe (identical pts). This dumps the SAME facts from inside the Linux container so we can confirm the
remaining suspect: the Linux opencv wheel's bundled decoder produces different pixels → different geometry.

No DB/secrets needed (analyze_clip is DB-free). The clip is fetched from CLIP_URL (a signed/public URL; set
CLIP_AUTH to send an Authorization header). Prints one JSON blob to stdout → Cloud Run logs.
"""
import json
import os
import subprocess
import sys
import urllib.request


def frame_decode_diag(clip, n=300):
    """Decode frame `n` of `clip` three ways and return hashes + per-channel stats so a Mac vs Linux run can be
    diffed to LOCALIZE the gap (DEC-107): (1) raw YUV420P via ffmpeg (native decode, NO colour conversion —
    should be bit-identical cross-platform), (2) BGR24 via ffmpeg swscale, (3) BGR via cv2.VideoCapture. If the
    YUV hashes match but the BGR hashes/means differ, the divergence is the YUV->BGR colour conversion."""
    import hashlib, numpy as np, cv2, json as _json
    d = {'frame': n}
    # clip colour metadata (matrix/range/transfer drive the YUV->RGB conversion)
    try:
        pr = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                             'stream=width,height,color_space,color_range,color_transfer,color_primaries,pix_fmt',
                             '-of', 'json', clip], capture_output=True, text=True).stdout
        d['meta'] = (_json.loads(pr).get('streams') or [{}])[0]
    except Exception as e:
        d['meta'] = f'err {e}'

    def _ff(pixfmt):
        r = subprocess.run(['ffmpeg', '-v', 'error', '-i', clip, '-vf', f"select=eq(n\\,{n})",
                            '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', pixfmt, '-'], capture_output=True)
        return r.stdout
    try:
        yuv = _ff('yuv420p')
        d['yuv420p'] = {'bytes': len(yuv), 'md5': hashlib.md5(yuv).hexdigest(),
                        'mean': round(float(np.frombuffer(yuv, np.uint8).mean()), 4) if yuv else None}
    except Exception as e:
        d['yuv420p'] = f'err {e}'
    try:
        bgr = _ff('bgr24')
        a = np.frombuffer(bgr, np.uint8) if bgr else np.array([])
        d['bgr_ffmpeg'] = {'bytes': len(bgr), 'md5': hashlib.md5(bgr).hexdigest(),
                           'mean_bgr': [round(float(a[i::3].mean()), 3) for i in range(3)] if a.size else None}
    except Exception as e:
        d['bgr_ffmpeg'] = f'err {e}'
    try:
        cap = cv2.VideoCapture(clip)
        if hasattr(cv2, 'CAP_PROP_ORIENTATION_AUTO'):
            cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1)
        cap.set(cv2.CAP_PROP_POS_FRAMES, n)
        ok, f = cap.read(); cap.release()
        if ok:
            d['bgr_cv2'] = {'shape': list(f.shape), 'md5': hashlib.md5(np.ascontiguousarray(f)).hexdigest(),
                            'mean_bgr': [round(float(f[..., i].mean()), 3) for i in range(3)]}
        else:
            d['bgr_cv2'] = 'read failed'
    except Exception as e:
        d['bgr_cv2'] = f'err {e}'
    return d


def main():
    out = {'python': sys.version.split()[0]}
    try:
        import cv2, numpy as np
        out['cv2'] = cv2.__version__
        out['numpy'] = np.__version__
        # opencv's bundled ffmpeg/backends (the decode path is cv2.VideoCapture, NOT system ffmpeg)
        bi = cv2.getBuildInformation()
        for line in bi.splitlines():
            if 'FFMPEG' in line and ':' in line and 'YES' in line.upper():
                out.setdefault('cv2_ffmpeg', line.strip()); break
    except Exception as e:
        print(json.dumps({'error': f'import cv2/numpy: {e}'})); return
    try:
        out['system_ffmpeg'] = subprocess.run(['ffmpeg', '-version'], capture_output=True, text=True).stdout.splitlines()[0]
    except Exception as e:
        out['system_ffmpeg'] = f'err {e}'

    url = os.environ.get('CLIP_URL')
    if not url:
        print(json.dumps({**out, 'error': 'set CLIP_URL'})); return
    headers = {}
    auth = os.environ.get('CLIP_AUTH')
    if auth == 'metadata':   # fetch a GCS access token from the Cloud Run metadata server (Job's service account)
        mreq = urllib.request.Request('http://metadata.google.internal/computeMetadata/v1/instance/'
                                      'service-accounts/default/token', headers={'Metadata-Flavor': 'Google'})
        tok = json.loads(urllib.request.urlopen(mreq, timeout=10).read())['access_token']
        headers['Authorization'] = f'Bearer {tok}'
    elif auth:
        headers['Authorization'] = auth
    clip = '/tmp/diag_clip.mov'
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=120) as r, open(clip, 'wb') as f:
        f.write(r.read())
    out['clip_bytes'] = os.path.getsize(clip)

    # frame-level facts (compare to the Mac: nb_frames=885, pts 880@16.67ms + 4@18.33ms, cv2 FRAME_COUNT=885)
    try:
        pr = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-count_packets',
                             '-show_entries', 'stream=r_frame_rate,avg_frame_rate,nb_read_packets,duration',
                             '-of', 'json', clip], capture_output=True, text=True)
        out['ffprobe'] = (json.loads(pr.stdout).get('streams') or [{}])[0]
    except Exception as e:
        out['ffprobe'] = f'err {e}'
    cap = cv2.VideoCapture(clip)
    out['cv2_frame_count'] = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    out['cv2_fps'] = round(cap.get(cv2.CAP_PROP_FPS), 4)
    cap.release()
    try:
        from lanesight_core.cv.stabilize import pts
        ts = np.array(pts(clip)); d = np.diff(ts)
        u, c = np.unique(np.round(d, 5), return_counts=True)
        out['pts'] = {'n': len(ts), 'span': round(float(ts[-1] - ts[0]), 4),
                      'intervals': sorted([(int(cc), float(uu)) for cc, uu in zip(c, u)], reverse=True)[:3]}
    except Exception as e:
        out['pts'] = f'err {e}'

    # STEP 1 (DEC-107 localize): per-frame YUV/BGR decode diff (run the SAME on Mac + container, diff the output)
    try:
        out['frame_diag'] = frame_decode_diag(clip, int(os.environ.get('DIAG_FRAME', '300')))
    except Exception as e:
        out['frame_diag'] = f'err {type(e).__name__}: {e}'

    # run the pipeline + dump the geometry signal (z@t≈9.82 is the key: Mac 13.28 vs server 11.40)
    try:
        import tempfile
        from lanesight_runner.core import analyze_clip
        rec, _, _ = analyze_clip(clip, os.path.join(tempfile.mkdtemp(), 'x'), log=lambda *a: None)
        d = rec.to_dict() if hasattr(rec, 'to_dict') else rec
        m = d.get('metrics') or {}; ev = d.get('events') or {}
        traj = (d.get('trajectory') or {}).get('lane') or []
        z982 = next((round(p['z_ft'], 2) for p in traj if abs(p['t'] - 9.82) < 0.01), None)
        out['result'] = {'ball_speed_early': (m.get('ball_speed') or {}).get('value'),
                         't_release': ev.get('t_release'), 't_impact': ev.get('t_impact'),
                         'z_at_9_82': z982, 'n_traj': len(traj)}
    except Exception as e:
        out['result'] = f'err {type(e).__name__}: {e}'
    print(json.dumps(out, indent=2))


if __name__ == '__main__':
    main()
