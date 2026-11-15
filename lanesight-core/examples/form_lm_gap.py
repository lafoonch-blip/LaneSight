"""DEC-131 — measure the iOS↔Python MediaPipe landmark gap. Parses the LMDUMP output from
OnDeviceFormGateTests.testDumpLandmarksForGapAnalysis (FORM_LM_DUMP=1) and compares each dumped iOS frame to the
nearest Python-reference frame (lm_cache/<clip>.npz, produced by form_selector_sim.py). Reports per-clip and
overall per-landmark displacement in normalized units and in pixels (clip display dims via ffprobe), plus the
gap for the landmarks the selector depends on (wrists, shoulders, hips, ankles).

Usage: python examples/form_lm_gap.py <ios_dump.log>
"""
from __future__ import annotations
import os, sys, subprocess, json
import numpy as np

CACHE = os.path.expanduser('~/LaneSightData/form/lm_cache')
TRAIN = os.path.expanduser('~/LaneSightData/training_videos')
SUBS = ['', 'Form Videos', '11:1 Shots']
KEY = {15: 'L_wrist', 16: 'R_wrist', 11: 'L_shoulder', 12: 'R_shoulder',
       23: 'L_hip', 24: 'R_hip', 27: 'L_ankle', 28: 'R_ankle', 31: 'L_foot', 32: 'R_foot'}


def clip_dims(name):
    for sub in SUBS:
        for ext in ('.MOV', '.mov', '.mp4', '.MP4'):
            p = os.path.join(TRAIN, sub, name + ext)
            if os.path.exists(p):
                try:
                    out = subprocess.check_output(
                        ['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                         'stream=width,height:stream_side_data=rotation', '-of', 'json', p], text=True)
                    j = json.loads(out)['streams'][0]
                    w, h = int(j['width']), int(j['height'])
                    return (h, w) if (w > h) else (w, h)      # display is portrait (rotated) for these clips
                except Exception:
                    return None
    return None


def parse(path):
    clips, cur, rows = {}, None, []
    delegate = '?'
    for line in open(path):
        line = line.strip()
        if line.startswith('LMDUMP_DELEGATE'):
            delegate = line.split('cpu=')[-1]
        elif line.startswith('LMDUMP_BEGIN'):
            cur = line.split()[1]; rows = []
        elif line.startswith('LMROW'):
            p = line.split()
            # LMROW <clip> <i> <t> x0,y0 x1,y1 ...
            t = float(p[3])
            xy = np.array([[float(v) for v in tok.split(',')] for tok in p[4:]])  # (33,2)
            rows.append((t, xy))
        elif line.startswith('LMDUMP_END'):
            clips[cur] = rows; cur = None
    return delegate, clips


def main():
    delegate, clips = parse(sys.argv[1])
    print(f'delegate CPU={delegate}\n')
    all_gaps = []
    for name, rows in clips.items():
        cp = os.path.join(CACHE, name + '.npz')
        if not os.path.exists(cp):
            print(f'{name}: no python cache; skip'); continue
        d = np.load(cp); tpy, lpy = d['t'], d['lms'][:, :, :2]       # (M,33,2) normalized x,y
        dims = clip_dims(name)
        per_lm = {k: [] for k in KEY}
        frame_gaps = []
        for t, xy in rows:
            j = int(np.argmin(np.abs(tpy - t)))
            if abs(tpy[j] - t) > 0.05:
                continue
            ref = lpy[j]                                              # (33,2)
            ok = ~np.isnan(ref).any(1) & ~np.isnan(xy).any(1)
            if ok.sum() < 10:
                continue
            dn = np.linalg.norm(xy - ref, axis=1)                    # (33,) normalized
            frame_gaps.append(np.nanmedian(dn[ok]))
            for k in KEY:
                if ok[k]:
                    per_lm[k].append(dn[k])
        if not frame_gaps:
            print(f'{name}: no aligned frames'); continue
        g = np.array(frame_gaps)
        px = f' | ~{np.median(g)*np.hypot(*dims):.0f}px(diag {dims})' if dims else ''
        print(f'{name}: median/frame gap={np.median(g):.4f} p90={np.percentile(g,90):.4f} normalized{px}')
        for k, lab in KEY.items():
            if per_lm[k]:
                a = np.array(per_lm[k])
                pxk = f' ~{np.median(a)*np.hypot(*dims):.0f}px' if dims else ''
                print(f'    {lab:11s} median={np.median(a):.4f}{pxk}')
        all_gaps.extend(frame_gaps)
    if all_gaps:
        print(f'\nOVERALL median per-frame landmark gap = {np.median(all_gaps):.4f} normalized')


if __name__ == '__main__':
    main()
