#!/usr/bin/env python3
"""DEC-130 training-data source #2 — ZERO-SHOT pre-labels on clips the current engine FAILS.

Open-vocabulary detection (OWLv2, Apache-2.0) finds the ball on the engine's STABILISED frames (stabilise still
succeeds on the failing clips — they fail later at find_lanes/track), filtered by TEMPORAL consistency (the ball
is one object moving smoothly down-lane, growing as it nears the camera-far pins / shrinking toward the vanishing
region). Survivors are written as ball-box labels + a contact sheet for SELF-AUDIT (view it; fix or drop).

Pins / lane landmarks are a second pass (OWLv2 'bowling pins' + SAM2 lane mask) — ball first, since speed needs it.

Validated (self-audit, failing upload 14b234c8): motion gating fixes OWLv2 locking onto the static pin deck —
early/mid-lane ball boxes are clean (the speed-critical region). KNOWN CAVEAT: near pin impact the pins move and
can pass the motion gate, so the late tail is ambiguous; the batch harvest trims to the pre-impact, monotonically-
shrinking trajectory. Far-lane balls (<~8 px) are often missed — synthetic data (source #3) covers those.

  python -m ops.zeroshot_label <clip-id|path> [--out <dir>] [--n 60] [--thr 0.12] [--audit-only]
"""
from __future__ import annotations
import argparse, json, os
import numpy as np
import cv2

_MODEL = {'proc': None, 'net': None, 'dev': None}


def _load():
    if _MODEL['net'] is None:
        import torch
        from transformers import Owlv2Processor, Owlv2ForObjectDetection
        dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
        _MODEL['proc'] = Owlv2Processor.from_pretrained("google/owlv2-base-patch16-ensemble")
        _MODEL['net'] = Owlv2ForObjectDetection.from_pretrained("google/owlv2-base-patch16-ensemble").to(dev).eval()
        _MODEL['dev'] = dev
    return _MODEL['proc'], _MODEL['net'], _MODEL['dev']


def owl_detect(img_bgr, queries, thr=0.12, topk=5):
    """Return [(x,y,w,h,score,label)] for the open-vocab queries on one BGR frame."""
    import torch
    proc, net, dev = _load()
    rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    from PIL import Image
    pil = Image.fromarray(rgb)
    inp = proc(text=[queries], images=pil, return_tensors="pt").to(dev)
    with torch.no_grad():
        out = net(**inp)
    tgt = torch.tensor([[pil.height, pil.width]], device=dev)
    res = proc.post_process_grounded_object_detection(out, threshold=thr, target_sizes=tgt)[0]
    dets = []
    for box, score, lab in zip(res['boxes'].cpu().numpy(), res['scores'].cpu().numpy(), res['labels'].cpu().numpy()):
        x0, y0, x1, y1 = box
        dets.append((float(x0), float(y0), float(x1 - x0), float(y1 - y0), float(score), queries[int(lab)]))
    dets.sort(key=lambda d: -d[4])
    return dets[:topk]


def stabilized_frames(clip_path, n=60):
    """Get up to n evenly-spaced stabilised frames (i, t, frame) via the engine front-end — works even when the
    engine's track is empty (the clip fails at lane/track, AFTER stabilise)."""
    import tempfile, pickle
    from ops.autolabel import run_engine_capture
    with tempfile.TemporaryDirectory() as td:
        _track, probe, analyzed, stab_pkl, _blobs = run_engine_capture(clip_path, os.path.join(td, 'ev'))
        S = pickle.load(open(stab_pkl, 'rb'))
        Hs = S['Hs']; refH, refW = S['bg'].shape[:2]
        cap = cv2.VideoCapture(analyzed)
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or len(Hs)
        total = min(total, len(Hs))
        idxs = np.linspace(0, total - 1, min(n, total)).astype(int)
        fps = probe.get('measured_fps') or probe.get('nominal_fps') or 60.0
        out = []
        for i in idxs:
            cap.set(cv2.CAP_PROP_POS_FRAMES, int(i))
            ok, fr = cap.read()
            if not ok or fr is None:
                continue
            stab = cv2.warpPerspective(fr, Hs[int(i)].astype(np.float64), (refW, refH))
            out.append((int(i), float(i) / fps, stab))
        cap.release()
    return out, (refW, refH), S['bg']


def _motion_mask(stab, bg):
    """Moving-foreground mask: max-channel abs diff vs the stabilised background plate (the ball moves, the pins
    and lane markings don't). Returns a uint8 0/255 mask."""
    d = np.abs(stab.astype(np.int16) - bg.astype(np.int16)).max(axis=2).astype(np.uint8)
    _, m = cv2.threshold(d, 28, 255, cv2.THRESH_BINARY)
    return cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))


def _box_motion_frac(mask, x, y, w, h):
    x0, y0 = max(0, int(x)), max(0, int(y))
    x1, y1 = min(mask.shape[1], int(x + w)), min(mask.shape[0], int(y + h))
    if x1 <= x0 or y1 <= y0:
        return 0.0
    roi = mask[y0:y1, x0:x1]
    return float((roi > 0).mean())


def temporal_filter(dets_per_frame):
    """Keep one ball per frame forming a smooth down-lane trajectory. dets_per_frame = [(i,t,frame,dets)].
    Pick the detection whose center best continues a RANSAC-ish smooth path in (t -> cy) and (t -> cx)."""
    # gather best-scoring candidate centers per frame, then fit a monotone-ish vertical path (ball rolls toward
    # the pins -> cy decreases in a rear view) and drop outliers > 2.5 robust-sigma.
    pts = []
    for (i, t, frame, dets) in dets_per_frame:
        for (x, y, w, h, s, lab) in dets:
            pts.append((t, x + w / 2.0, y + h / 2.0, w, h, s, i, frame, x, y))
    if len(pts) < 5:
        return []
    pts.sort()
    T = np.array([p[0] for p in pts]); CY = np.array([p[2] for p in pts])
    # robust quadratic fit cy ~ t (ball path is smooth); iteratively reject
    keep = np.ones(len(pts), bool)
    for _ in range(4):
        A = np.polyfit(T[keep], CY[keep], 2)
        resid = CY - np.polyval(A, T)
        sig = 1.4826 * np.median(np.abs(resid[keep] - np.median(resid[keep]))) + 1e-6
        keep = np.abs(resid - np.median(resid[keep])) < 2.5 * sig
    # one best det per frame among kept (highest score)
    best = {}
    for idx, p in enumerate(pts):
        if not keep[idx]:
            continue
        i = p[6]
        if i not in best or p[5] > best[i][5]:
            best[i] = p
    return sorted(best.values(), key=lambda p: p[0])


def run(clip_path, clip_id, out_dir, n=60, thr=0.12, audit_only=False):
    frames, (W, H), bg = stabilized_frames(clip_path, n)
    if not frames:
        raise RuntimeError('no stabilised frames')
    QUERIES = ["a bowling ball", "a dark bowling ball rolling on a lane"]
    dets_per_frame = []
    for (i, t, fr) in frames:
        dets = owl_detect(fr, QUERIES, thr=thr)
        # ball is compact + roughly square; drop very elongated / huge boxes (lane, body)
        dets = [d for d in dets if 0.4 < (d[2] / (d[3] + 1e-6)) < 2.6 and d[2] < 0.25 * W and d[3] < 0.25 * H]
        # MOTION prior: the ball moves vs the stabilised background; static pins/markings don't. Require the box
        # to overlap real motion (>=25%). This is the fix for OWLv2 locking onto the pin deck.
        mask = _motion_mask(fr, bg)
        dets = [d for d in dets if _box_motion_frac(mask, d[0], d[1], d[2], d[3]) >= 0.25]
        dets_per_frame.append((i, t, fr, dets))
    kept = temporal_filter(dets_per_frame)
    cdir = os.path.join(out_dir, clip_id); os.makedirs(cdir, exist_ok=True)
    saved = []
    fr_dir, lb_dir = os.path.join(cdir, 'frames'), os.path.join(cdir, 'labels')
    if not audit_only:
        os.makedirs(fr_dir, exist_ok=True); os.makedirs(lb_dir, exist_ok=True)
    byframe = {f[0]: f for f in frames}
    for p in kept:
        t, cx, cy, w, h, s, i, frame, x, y = p
        label = {'frame': i, 't': t, 'ball': [round(x, 1), round(y, 1), round(w, 1), round(h, 1)],
                 'score': round(s, 3), 'img_w': W, 'img_h': H, 'space': 'stabilized', 'source': 'owlv2'}
        if not audit_only:
            cv2.imwrite(os.path.join(fr_dir, f'{i}.jpg'), frame, [cv2.IMWRITE_JPEG_QUALITY, 92])
            json.dump(label, open(os.path.join(lb_dir, f'{i}.json'), 'w'))
        saved.append((i, frame, label))
    return saved, len(frames)


def contact_sheet(saved, out_path, cols=4, cell=360):
    if not saved:
        return None
    # cap at 16 cells for a readable audit
    saved = saved[:: max(1, len(saved) // 16)][:16] if len(saved) > 16 else saved
    n = len(saved); rows = (n + cols - 1) // cols
    sheet = np.zeros((rows * cell, cols * cell, 3), np.uint8)
    for k, (i, img, lab) in enumerate(saved):
        im = img.copy()
        x, y, w, h = lab['ball']
        cv2.rectangle(im, (int(x), int(y)), (int(x + w), int(y + h)), (0, 255, 0), 3)
        cv2.putText(im, f"{lab['score']:.2f}", (int(x), int(y) - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
        H0, W0 = im.shape[:2]; sc = cell / max(H0, W0)
        rz = cv2.resize(im, (int(W0 * sc), int(H0 * sc)))
        cv2.putText(rz, f'f{i}', (6, 22), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
        r, cc = divmod(k, cols)
        sheet[r * cell:r * cell + rz.shape[0], cc * cell:cc * cell + rz.shape[1]] = rz
    cv2.imwrite(out_path, sheet); return out_path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('clip')
    ap.add_argument('--clips-dir', default=os.path.expanduser('~/LaneSightData'))
    ap.add_argument('--out', default='validation/cv_eval/zeroshot')
    ap.add_argument('--n', type=int, default=60)
    ap.add_argument('--thr', type=float, default=0.12)
    ap.add_argument('--audit-only', action='store_true')
    a = ap.parse_args()
    clip = a.clip
    if not os.path.exists(clip):
        # resolve under clips-dir (recursive by basename stem)
        for dp, dn, fn in os.walk(a.clips_dir):
            for f in fn:
                if os.path.splitext(f)[0] == os.path.splitext(os.path.basename(a.clip))[0]:
                    clip = os.path.join(dp, f); break
    cid = os.path.splitext(os.path.basename(clip))[0]
    saved, nf = run(clip, cid, a.out, a.n, a.thr, a.audit_only)
    sheet = contact_sheet(saved, os.path.join(a.out, cid, 'contact_sheet.png')) if saved else None
    print(f'{cid}: {len(saved)}/{nf} frames with a consistent ball · sheet={sheet}')


if __name__ == '__main__':
    main()
