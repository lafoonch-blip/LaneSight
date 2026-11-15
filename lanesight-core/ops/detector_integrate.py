#!/usr/bin/env python3
"""DEC-130 — integrate the learned detector into the EXISTING measurement pipeline.

The detector (ops/train_detector CenterNet: ball heatmap + lane-geometry params) runs on the engine's STABILISED
frames and replaces ONLY find_lanes + blob extraction. We build:
  - a `lane` dict (left/right edge lines to the VP + the foul line) from the detector's 6 lane params, and
  - per-frame `candidates()`-format points from the ball detections,
then hand them to the UNCHANGED link -> extend -> detect_impact -> refine -> compute (+ DEC-128 plausibility/
honesty gates stay in pipeline.analyze). So a clip the classical front-end fails can still yield honest metrics.

This is the server/Python reference; the iOS port mirrors it in Swift (OnDeviceTracker) with the Core ML model.
"""
from __future__ import annotations
import numpy as np

from lanesight_core.cv.track import contact_row, exp_diam, lane_x, BALL_IN, LANE_IN  # noqa
from lanesight_core.cv import track as T


def lane_from_params(p, img_w, img_h):
    """6 normalized params [foul_lx,foul_ly,foul_rx,foul_ry,vp_x,vp_y] -> a lane dict compatible with the engine:
    left/right edges as x=a*y+b (each line foul_pt -> VP), foul line as y=c*x+d. Returns (lane, vp).
    The params are normalized by max(H,W) (training letterboxes the frame into a square with uniform scale
    s=input/max(H,W) and divides pixel coords by max(H,W)), so denormalize ALL by max(img_w,img_h)."""
    scale = float(max(img_w, img_h))
    flx, fly, frx, fry, vx, vy = (p * scale).tolist()
    def line_xy(x0, y0, x1, y1):            # x = a*y + b through (x0,y0),(x1,y1)
        if abs(y1 - y0) < 1e-6:
            y1 += 1e-3
        a = (x1 - x0) / (y1 - y0); b = x0 - a * y0
        return [a, b]
    left = line_xy(flx, fly, vx, vy); right = line_xy(frx, fry, vx, vy)
    # foul line y = c*x + d through the two foul endpoints
    if abs(frx - flx) < 1e-6:
        frx += 1e-3
    c = (fry - fly) / (frx - flx); d = fly - c * flx
    y_near = max(fly, fry); y_far = vy
    # y_rng = the lane band's vertical extent (VP/top .. foul/bottom), for classify_capture_view (DEC-061).
    lane = {'left': left, 'right': right, 'foul': [c, d], 'yNear': y_near, 'yFar': y_far,
            'y_rng': [float(max(0.0, min(y_far, y_near))), float(y_near)]}
    vp = np.array([vx, vy], np.float64)
    return lane, vp


def candidates_from_detections(dets, lane, fps):
    """dets: list of (i, ball_box[x,y,w,h]) in stabilised px. Build the per-frame candidates() structure the engine
    links. Returns C = list-per-frame (here one candidate per detected frame)."""
    by_frame = {}
    for (i, box) in dets:
        x, y, w, h = box
        cx = x + w / 2.0; top = y
        ct = contact_row(lane, top)
        xa, xb = lane_x(lane, ct)
        if xb - xa <= 1:
            continue
        D = exp_diam(lane, ct)
        frac = (cx - xa) / (xb - xa)
        by_frame.setdefault(i, []).append(dict(t=i / fps, i=i, cx=cx, top=top, ct=ct, D=D, w=w,
                                               frac=frac, merged=False))
    # C must be a list indexed by frame order; the engine iterates C as list-of-lists
    maxi = max(by_frame) if by_frame else -1
    C = [by_frame.get(i, []) for i in range(maxi + 1)]
    return C


def ball_track_from_detector(dets, lane_params_per_frame, img_w, img_h, fps):
    """Aggregate per-frame lane params (median -> a stable lane), build candidates, and LINK with the engine's
    linker. Returns (track, lane, vp, C). Caller runs extend/impact/refine/compute as usual."""
    lp = np.median(np.array(lane_params_per_frame), axis=0)   # robust lane across frames
    lane, vp = lane_from_params(lp, img_w, img_h)
    C = candidates_from_detections(dets, lane, fps)
    track = T.link(C, vp)
    return track, lane, vp, C


# ---------------- the learned front-end injected into pipeline.analyze (DEC-130) ----------------

class LearnedDetector:
    """A learned front-end for pipeline.analyze(detector=...). Runs the CenterNet (torch checkpoint OR Core ML)
    over the STABILISED frames once, then serves .geometry(video, S) and .candidates(S, lane, vp). Replaces ONLY
    find_lanes + blob extraction; everything downstream is the unchanged engine."""

    def __init__(self, ckpt=None, mlpackage=None, input_sz=512, score_thr=0.30, stride_sample=1):
        self.input = input_sz; self.thr = score_thr; self.stride_sample = stride_sample
        self.backend = None; self._prepared = None
        if mlpackage:
            import coremltools as ct
            self.ml = ct.models.MLModel(mlpackage); self.backend = 'coreml'
            self.input = input_sz
        elif ckpt:
            import torch
            from ops.train_detector import build_model
            ck = torch.load(ckpt, map_location='cpu'); self.input = ck.get('input', input_sz)
            self.net = build_model(); self.net.load_state_dict(ck['model']); self.net.eval()
            self.torch = torch; self.backend = 'torch'
        else:
            raise ValueError('LearnedDetector needs ckpt or mlpackage')

    def _infer(self, stab_bgr):
        """One stabilised BGR frame -> (ball_box[x,y,w,h]|None, score, lane6). Letterbox to square input."""
        import numpy as _np, cv2
        H0, W0 = stab_bgr.shape[:2]; s = self.input / max(H0, W0)
        nw, nh = int(round(W0 * s)), int(round(H0 * s))
        canvas = _np.zeros((self.input, self.input, 3), _np.uint8)
        canvas[:nh, :nw] = cv2.resize(stab_bgr, (nw, nh))
        x = canvas.astype(_np.float32)[:, :, ::-1] / 255.0
        x = (x - _np.array([0.485, 0.456, 0.406])) / _np.array([0.229, 0.224, 0.225])
        x = x.transpose(2, 0, 1)[None].astype(_np.float32)
        if self.backend == 'coreml':
            o = self.ml.predict({'image': x})
            hm, wh, reg, lane = o['heatmap'][0, 0], o['wh'][0], o['offset'][0], o['lane'][0]
        else:
            with self.torch.no_grad():
                ph, pw, pr, pl = self.net(self.torch.from_numpy(x))
            hm = ph[0, 0].numpy(); wh = pw[0].numpy(); reg = pr[0].numpy(); lane = pl[0].numpy()
        O = hm.shape[0]; st = self.input // O
        py, px = _np.unravel_index(hm.argmax(), hm.shape); score = float(hm.max())
        box = None
        if score >= self.thr:
            ox, oy = reg[:, py, px]; bw, bh = wh[:, py, px]
            cx = (px + ox) * st / s; cy = (py + oy) * st / s     # back to stabilised px (undo letterbox scale)
            bw = bw * st / s; bh = bh * st / s
            box = [cx - bw / 2, cy - bh / 2, bw, bh]
        return box, score, lane.astype(_np.float32)             # lane is normalized to input square

    def detect_in_crop(self, stab_bgr, cx, cy, crop=320):
        """Follow-up #3: run the detector on a NATIVE-resolution crop centred at (cx,cy) — the far-lane ball is
        ~8px and vanishes when the whole frame is downsized to the input, but at native res in a crop it is
        detectable. Returns (ball_cx, ball_cy, w, h, score) in full stabilised-frame coords, or None."""
        import numpy as _np
        H, W = stab_bgr.shape[:2]
        x0 = int(max(cx - crop / 2, 0)); y0 = int(max(cy - crop / 2, 0))
        x1 = int(min(x0 + crop, W)); y1 = int(min(y0 + crop, H))
        sub = stab_bgr[y0:y1, x0:x1]
        if sub.shape[0] < 16 or sub.shape[1] < 16:
            return None
        box, score, _lane = self._infer(sub)      # _infer letterboxes the crop to the input square
        if box is None:
            return None
        bx, by, bw, bh = box
        return (x0 + bx + bw / 2, y0 + by + bh / 2, bw, bh, score)

    def prepare(self, video, S):
        if self._prepared is not None and self._prepared.get('video') == video:
            return                                    # already inferred for THIS clip (eval reuses one detector)
        import cv2, numpy as _np
        Hs = S['Hs']; refH, refW = S['bg'].shape[:2]
        fps = (S.get('fps') or (1.0 / _np.median(_np.diff(S['ts']))) if len(S.get('ts', [])) > 1 else 60.0)
        cap = cv2.VideoCapture(video)
        total = min(int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or len(Hs), len(Hs))
        dets = []; lane_params = []
        for i in range(0, total, self.stride_sample):
            cap.set(cv2.CAP_PROP_POS_FRAMES, i)
            ok, fr = cap.read()
            if not ok or fr is None:
                continue
            stab = cv2.warpPerspective(fr, Hs[i].astype(_np.float64), (refW, refH))
            box, score, lane6 = self._infer(stab)
            lane_params.append(lane6)
            if box is not None:
                dets.append((i, box))
        cap.release()
        self._prepared = {'dets': dets, 'lane_params': lane_params, 'fps': float(fps),
                          'img_w': refW, 'img_h': refH, 'video': video}

    def geometry(self, video, S):
        self.prepare(video, S)
        p = self._prepared
        # HYBRID (DEC-130): the classical find_lanes is sub-pixel accurate WHEN it succeeds (baseline speed MAE
        # 0.24 mph), so prefer it for metric-grade depth geometry — the learned detector's value is BALL detection
        # (candidates come from the detector regardless of which lane is used). Fall back to the learned lane head
        # only when classical lane detection fails (the clips DEC-130 is really for). force_learned_lane=True
        # pins the learned lane (ablation).
        if not getattr(self, 'force_learned_lane', False):
            try:
                from lanesight_core.cv.lanes import find_lanes
                G = find_lanes(S['bg'])
                if G and G.get('lanes'):
                    return G
            except Exception:
                pass
        if not p['lane_params']:
            from lanesight_core.failures import AnalysisFailure
            raise AnalysisFailure('LANE_GEOMETRY_UNUSABLE', 'detector produced no lane geometry', stage='lane')
        lp = np.median(np.array(p['lane_params']), axis=0)
        lane, vp = lane_from_params(lp, p['img_w'], p['img_h'])
        return {'vp': vp, 'lanes': [lane], 'mask': None}

    def candidates(self, S, lane, vp):
        p = self._prepared
        return candidates_from_detections(p['dets'], lane, p['fps'])
