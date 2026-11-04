#!/usr/bin/env python3
"""DEC-130 training-data source #1 — AUTO-LABELS from clips the current engine already tracks.

Design: the detector replaces find_lanes + ball-track, operating on the STABILISED frames both engines already
produce (the failures are LANE_GEOMETRY_UNUSABLE / BALL_TRACK_NOT_FOUND, both AFTER stabilise). So labels live in
reference/stabilised coordinates — no un-projection needed, and the existing geometry/measurement already runs there.

We run the real engine entry (`lanesight_runner.core.analyze_clip`, which trims + HDR->SDR + stabilises exactly
as production), capture the linked+extended ball track (stabilised coords), and read the selected lane geometry.
The analysed SDR/trimmed clip's frame i (decode order) == the track point's i; we warp that frame to reference by
Hs[i] to get the stabilised frame the track lives on.

Per tracked frame we emit (reference/stabilised pixels):
  ball box [x,y,w,h] (cx,top,w from the track; ball ~circular so h=w), foul-line endpoints, left/right lane-edge
  polylines, vanishing point.

Outputs under <out>/<clip_id>/: frames/<i>.jpg, labels/<i>.json, contact_sheet.png (SELF-AUDIT), meta.json.

  python -m ops.autolabel IMG_8751 --out validation/cv_eval/autolabels [--stride N] [--max-frames M] [--audit-only]
"""
from __future__ import annotations
import argparse, json, os, pickle, tempfile
import numpy as np
import cv2

from lanesight_core.cv.lanes import foul_corners, lane_x


def run_engine_capture(clip_path, out_prefix):
    """Run production analyze_clip; capture the fullest linked/extended ball track (stabilised coords).
    Returns (track, probe, analyzed_video, stab_pkl, blobs_pkl)."""
    from lanesight_core.cv import pipeline as P
    cap = {'t': None}
    _link, _ef = P.link, P.extend_forward
    def wl(C, vp, **k):
        r = _link(C, vp, **k)
        if r and (cap['t'] is None or len(r) > len(cap['t'])): cap['t'] = r
        return r
    def wef(C, track, lane, vp, **k):
        r = _ef(C, track, lane, vp, **k)
        if r and (cap['t'] is None or len(r) > len(cap['t'])): cap['t'] = r
        return r
    P.link, P.extend_forward = wl, wef
    try:
        from lanesight_runner.core import analyze_clip
        rec, probe, _tim = analyze_clip(clip_path, out_prefix)
    finally:
        P.link, P.extend_forward = _link, _ef
    analyzed = ((probe.get('window') or {}).get('analyzed_file')
                or (out_prefix + '_sdr.mov' if os.path.exists(out_prefix + '_sdr.mov') else None)
                or (out_prefix + '_trim.mov' if os.path.exists(out_prefix + '_trim.mov') else clip_path))
    # The engine's cache prefix FOLLOWS the analysed file (so an SDR/trimmed copy never reuses another clip's
    # cache) — so <analyzed-stem>_stab.pkl / _blobs.pkl, not <out_prefix>_*. Fall back to out_prefix just in case.
    astem = os.path.splitext(analyzed)[0]
    stab = astem + '_stab.pkl' if os.path.exists(astem + '_stab.pkl') else out_prefix + '_stab.pkl'
    blobs = astem + '_blobs.pkl' if os.path.exists(astem + '_blobs.pkl') else out_prefix + '_blobs.pkl'
    return cap['t'] or [], probe, analyzed, stab, blobs


def lane_landmarks_ref(lane, vp, yf):
    xa_f, xb_f = lane_x(lane, yf)
    y_top = max(float(vp[1]) + 10.0, yf - 0.9 * (yf - float(vp[1])))
    ys = np.linspace(yf, y_top, 8)
    return {'foul': [[xa_f, yf], [xb_f, yf]],
            'left_edge': [[lane_x(lane, y)[0], y] for y in ys],
            'right_edge': [[lane_x(lane, y)[1], y] for y in ys],
            'vp': [float(vp[0]), float(vp[1])]}


def extract(clip_path, clip_id, out_dir, stride=1, max_frames=None, audit_only=False):
    cdir = os.path.join(out_dir, clip_id)
    os.makedirs(cdir, exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        prefix = os.path.join(td, 'ev')
        track, probe, analyzed, stab_pkl, blobs_pkl = run_engine_capture(clip_path, prefix)
        if not track:
            raise RuntimeError('engine produced no track for this clip')
        S = pickle.load(open(stab_pkl, 'rb'))
        Hs = S['Hs']; refH, refW = S['bg'].shape[:2]
        G = lane = vp = None
        if os.path.exists(blobs_pkl):
            d = pickle.load(open(blobs_pkl, 'rb')); G, lane, vp = d['G'], d['lane'], d['G']['vp']
        if lane is None:
            raise RuntimeError('no lane geometry cached')
        F = foul_corners(lane); yf = float(F[:, 1].max())
        land = lane_landmarks_ref(lane, vp, yf)
        pts = [c for c in track if 'i' in c][::stride]
        if max_frames and len(pts) > max_frames:
            idx = np.linspace(0, len(pts) - 1, max_frames).astype(int)
            pts = [pts[k] for k in idx]
        cap = cv2.VideoCapture(analyzed)
        fr_dir, lb_dir = os.path.join(cdir, 'frames'), os.path.join(cdir, 'labels')
        os.makedirs(fr_dir, exist_ok=True); os.makedirs(lb_dir, exist_ok=True)
        saved = []
        for c in pts:
            i = int(c['i'])
            cap.set(cv2.CAP_PROP_POS_FRAMES, i)
            ok, frame = cap.read()
            if not ok or frame is None:
                continue
            stab = cv2.warpPerspective(frame, Hs[i].astype(np.float64), (refW, refH))
            w = float(c['w']); bx = float(c['cx']) - w / 2.0; by = float(c['top'])
            label = {'frame': i, 't': float(c['t']),
                     'ball': [round(bx, 1), round(by, 1), round(w, 1), round(w, 1)],
                     'foul': [[round(x, 1), round(y, 1)] for x, y in land['foul']],
                     'left_edge': [[round(x, 1), round(y, 1)] for x, y in land['left_edge']],
                     'right_edge': [[round(x, 1), round(y, 1)] for x, y in land['right_edge']],
                     'vp': [round(land['vp'][0], 1), round(land['vp'][1], 1)],
                     'img_w': refW, 'img_h': refH, 'space': 'stabilized'}
            if not audit_only:
                cv2.imwrite(os.path.join(fr_dir, f'{i}.jpg'), stab, [cv2.IMWRITE_JPEG_QUALITY, 92])
                json.dump(label, open(os.path.join(lb_dir, f'{i}.json'), 'w'))
            saved.append((i, stab, label))
        cap.release()
    if not audit_only:
        json.dump({'clip': clip_id, 'n_frames': len(saved), 'img_w': refW, 'img_h': refH,
                   'src': clip_path}, open(os.path.join(cdir, 'meta.json'), 'w'), indent=1)
    return saved


def contact_sheet(saved, out_path, cols=4, cell=360):
    if not saved:
        return None
    n = len(saved); rows = (n + cols - 1) // cols
    sheet = np.zeros((rows * cell, cols * cell, 3), np.uint8)
    for k, (i, img, lab) in enumerate(saved):
        im = img.copy()
        def Pt(p): return (int(round(p[0])), int(round(p[1])))
        x, y, w, h = lab['ball']
        cv2.rectangle(im, Pt((x, y)), Pt((x + w, y + h)), (0, 255, 0), 3)
        if len(lab['foul']) == 2:
            cv2.line(im, Pt(lab['foul'][0]), Pt(lab['foul'][1]), (255, 255, 0), 2)
        for edge in (lab['left_edge'], lab['right_edge']):
            for a, b in zip(edge[:-1], edge[1:]):
                cv2.line(im, Pt(a), Pt(b), (0, 255, 255), 2)
        vpp = lab['vp']
        if 0 <= vpp[0] < im.shape[1] and 0 <= vpp[1] < im.shape[0]:
            cv2.circle(im, Pt(vpp), 6, (0, 0, 255), -1)
        H0, W0 = im.shape[:2]; s = cell / max(H0, W0)
        rz = cv2.resize(im, (int(W0 * s), int(H0 * s)))
        cv2.putText(rz, f'f{i}', (6, 22), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
        r, cc = divmod(k, cols)
        sheet[r * cell:r * cell + rz.shape[0], cc * cell:cc * cell + rz.shape[1]] = rz
    cv2.imwrite(out_path, sheet)
    return out_path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ids', nargs='+')
    ap.add_argument('--clips-dir', default=os.path.expanduser('~/LaneSightData/training_videos'))
    ap.add_argument('--out', default='validation/cv_eval/autolabels')
    ap.add_argument('--stride', type=int, default=1)
    ap.add_argument('--max-frames', type=int, default=None)
    ap.add_argument('--audit-only', action='store_true')
    a = ap.parse_args()
    for cid in a.ids:
        stem = os.path.splitext(cid)[0]
        cand = None
        for ext in ('.mov', '.MOV', '.mp4', ''):
            p = os.path.join(a.clips_dir, stem + ext) if ext else os.path.join(a.clips_dir, cid)
            if os.path.exists(p): cand = p; break
        if not cand:
            print(f'{cid}: NOT FOUND under {a.clips_dir}'); continue
        try:
            saved = extract(cand, stem, a.out, a.stride, a.max_frames, a.audit_only)
        except Exception as e:
            print(f'{cid}: FAILED {type(e).__name__}: {e}'); continue
        sheet = contact_sheet(saved, os.path.join(a.out, stem, 'contact_sheet.png')) if saved else None
        print(f'{stem}: {len(saved)} labeled frames · sheet={sheet}')


if __name__ == '__main__':
    main()
