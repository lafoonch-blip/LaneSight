#!/usr/bin/env python3
"""DEC-130 — run the multi-class detector (ball/pins/arrows/foul-dots) and extract the STATIC landmarks from the
stabilised background (one inference per clip; pins/arrows/dots don't move until impact). Returns per-class peak
detections (local maxima above threshold) in full-frame stabilised coords. Replaces the unreliable classical
brightness/OWLv2 pin+marker detection in the live path. Torch checkpoint (server) or Core ML (on-device)."""
from __future__ import annotations
import numpy as np

CLASS = {'ball': 0, 'pins': 1, 'arrows': 2, 'foul_dots': 3}


def _local_maxima(hm, thr, nms=3):
    """Peaks of a heatmap above thr, with a simple max-pool NMS. Returns [(y, x, score)]."""
    import cv2
    mx = cv2.dilate(hm, np.ones((2 * nms + 1, 2 * nms + 1), np.float32))
    peaks = (hm >= mx) & (hm >= thr)
    ys, xs = np.where(peaks)
    return sorted([(int(y), int(x), float(hm[y, x])) for y, x in zip(ys, xs)], key=lambda p: -p[2])


class MCDetector:
    def __init__(self, ckpt=None, mlpackage=None):
        self.backend = None
        if mlpackage:
            import coremltools as ct
            self.ml = ct.models.MLModel(mlpackage); self.backend = 'coreml'
            self.input = 512
        elif ckpt:
            import torch
            from ops.train_multiclass import build_model_mc
            c = torch.load(ckpt, map_location='cpu'); self.input = c.get('input', 512)
            self.dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
            self.net = build_model_mc(); self.net.load_state_dict(c['model']); self.net.eval().to(self.dev)
            self.torch = torch; self.backend = 'torch'
        else:
            raise ValueError('MCDetector needs ckpt or mlpackage')

    def _infer_hm(self, img_bgr):
        """Return (heatmaps[C,O,O], scale s) for one BGR image letterboxed to the input square."""
        import cv2
        H0, W0 = img_bgr.shape[:2]; s = self.input / max(H0, W0)
        nw, nh = int(round(W0 * s)), int(round(H0 * s))
        canvas = np.zeros((self.input, self.input, 3), np.uint8); canvas[:nh, :nw] = cv2.resize(img_bgr, (nw, nh))
        x = canvas.astype(np.float32)[:, :, ::-1] / 255.0
        x = (x - np.array([0.485, 0.456, 0.406])) / np.array([0.229, 0.224, 0.225])
        x = x.transpose(2, 0, 1)[None].astype(np.float32)
        if self.backend == 'coreml':
            o = self.ml.predict({'image': x}); hm = o['heatmap'][0]
        else:
            with self.torch.no_grad():
                ph, _, _, _ = self.net(self.torch.from_numpy(x).to(self.dev))
            hm = ph[0].cpu().numpy()
        return hm, s

    def detect(self, bg_bgr, cls, thr=0.3, maxn=20):
        """Detections for one class on the (stabilised) background. Returns [(cx,cy,score)] in full-frame coords."""
        hm, s = self._infer_hm(bg_bgr)
        O = hm.shape[1]; st = self.input // O
        peaks = _local_maxima(hm[CLASS[cls]], thr)[:maxn]
        out = []
        for (y, x, score) in peaks:
            cx = x * st / s; cy = y * st / s          # letterbox -> full-frame
            out.append((cx, cy, score))
        return out

    def pins_boxes(self, bg_bgr, thr=0.18, pin_wh=(18, 42)):
        """Pin detections as boxes [x,y,w,h] (pins are tall). Peaks are pin centres. Threshold is low because pins
        are STATIC in the ball-free background — the downstream tight target-lane + cluster filter (pin_detect)
        rejects the occasional spurious low-confidence peak, so a lower threshold recovers more of the deck."""
        pw, ph = pin_wh
        return [[cx - pw / 2, cy - ph / 2, pw, ph] for (cx, cy, sc) in self.detect(bg_bgr, 'pins', thr)]
