#!/usr/bin/env python3
"""DEC-130 multi-class retrain — one CenterNet detecting ball + pins + arrows + foul-dots, + lane-geometry head.
Classes: 0=ball, 1=pins, 2=arrows, 3=foul_dots. Ball boxes are per-frame (auto/zeroshot); the landmark classes are
per-clip STATIC (dec130/dataset/landmarks/<clip>.json) applied to every frame of that clip. Strong brightness/
contrast augmentation so the markers (low contrast on pale lanes) are learned robustly and generalise to the pale/
portrait clips where classical darkness detection fails. Reuses train_detector's helpers.

  python -m ops.train_multiclass --data <splits> --landmarks <ds>/landmarks --out <ds>/model_mc --epochs 40 --input 512
"""
from __future__ import annotations
import argparse, json, os, time
import numpy as np
from ops.train_detector import (_import_torch, gaussian_radius, draw_gaussian, focal)

NUM_CLASSES = 4   # ball, pins, arrows, foul_dots
MARK_WH = {1: 18.0, 2: 10.0, 3: 8.0}   # nominal marker box size (px) for arrows/dots (points -> small boxes)


def build_model_mc():
    torch, nn, F, tv = _import_torch()

    class Up(nn.Module):
        def __init__(self, cin, cout):
            super().__init__()
            self.conv = nn.Sequential(nn.Conv2d(cin, cout, 3, 1, 1), nn.BatchNorm2d(cout), nn.ReLU(inplace=True))
        def forward(self, x):
            return self.conv(F.interpolate(x, scale_factor=2, mode='bilinear', align_corners=False))

    class MCNet(nn.Module):
        def __init__(self):
            super().__init__()
            bb = tv.models.mobilenet_v3_large(weights=tv.models.MobileNet_V3_Large_Weights.IMAGENET1K_V1)
            self.features = bb.features
            self.up1 = Up(960, 256); self.up2 = Up(256, 128); self.up3 = Up(128, 64)
            self.hm = nn.Conv2d(64, NUM_CLASSES, 1); self.wh = nn.Conv2d(64, 2, 1); self.reg = nn.Conv2d(64, 2, 1)
            self.hm.bias.data.fill_(-2.19)
            self.lane = nn.Sequential(nn.AdaptiveAvgPool2d(1), nn.Flatten(),
                                      nn.Linear(960, 256), nn.ReLU(inplace=True), nn.Linear(256, 6))
        def forward(self, x):
            f = self.features(x); lane = self.lane(f); u = self.up3(self.up2(self.up1(f)))
            return torch.sigmoid(self.hm(u)), self.wh(u), self.reg(u), lane
    return MCNet()


class DSMC:
    def __init__(self, jsonl, landmark_dir, input_sz=512, stride=4, train=True):
        self.rows = [json.loads(l) for l in open(jsonl)]
        self.ldir = landmark_dir; self.input = input_sz; self.stride = stride; self.out = input_sz // stride; self.train = train
        self._lm = {}

    def landmarks(self, clip):
        if clip not in self._lm:
            # the ball-label clip id may carry a _trim / _sdr / _trim_sdr suffix the landmark file (keyed by the
            # original clip id) lacks — try the exact id then progressively strip those suffixes.
            cands = [clip]
            for suf in ('_trim_sdr', '_sdr', '_trim'):
                if clip.endswith(suf):
                    cands.append(clip[: -len(suf)])
            cands.append(clip.replace('_trim', '').replace('_sdr', ''))
            val = None
            for c in cands:
                p = os.path.join(self.ldir, c + '.json')
                if os.path.exists(p):
                    try:
                        val = json.load(open(p)); break
                    except Exception:
                        pass
            self._lm[clip] = val
        return self._lm[clip]

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, i):
        import cv2
        r = self.rows[i]; img = cv2.imread(r['img'])
        if img is None:
            img = np.zeros((self.input, self.input, 3), np.uint8)
        H0, W0 = img.shape[:2]; s = self.input / max(H0, W0)
        nw, nh = int(round(W0 * s)), int(round(H0 * s))
        canvas = np.zeros((self.input, self.input, 3), np.uint8); canvas[:nh, :nw] = cv2.resize(img, (nw, nh))
        flip = self.train and (i * 2654435761 % 2 == 0)
        if flip:
            canvas = canvas[:, ::-1].copy()
        # brightness/contrast jitter (train) — simulate pale/dim lanes so low-contrast markers are learned robustly
        if self.train:
            a = 0.6 + ((i * 48271) % 1000) / 1000.0 * 0.9      # contrast 0.6..1.5
            b = -40 + ((i * 69621) % 1000) / 1000.0 * 90       # brightness -40..+50
            canvas = np.clip(canvas.astype(np.float32) * a + b, 0, 255).astype(np.uint8)
        O = self.out
        hm = np.zeros((NUM_CLASSES, O, O), np.float32); wh = np.zeros((2, O, O), np.float32)
        reg = np.zeros((2, O, O), np.float32); mask = np.zeros((O, O), np.float32)

        def put(cls, cx_px, cy_px, bw_px, bh_px, set_wh):
            cx = cx_px * s; cy = cy_px * s
            if flip:
                cx = self.input - 1 - cx
            fx, fy = cx / self.stride, cy / self.stride; ix, iy = int(fx), int(fy)
            if not (0 <= ix < O and 0 <= iy < O):
                return
            rad = gaussian_radius(max(1, bh_px * s / self.stride), max(1, bw_px * s / self.stride))
            draw_gaussian(hm[cls], ix, iy, rad)
            if set_wh:
                wh[0, iy, ix] = bw_px * s / self.stride; wh[1, iy, ix] = bh_px * s / self.stride
                reg[0, iy, ix] = fx - ix; reg[1, iy, ix] = fy - iy; mask[iy, ix] = 1.0

        for (bx, by, bw, bh, cls) in r['boxes']:            # ball (per-frame)
            put(0, bx + bw / 2, by + bh / 2, bw, bh, True)
        lm = self.landmarks(r['clip'])
        if lm:
            for (x, y, w, h) in (lm.get('pins') or []):
                put(1, x + w / 2, y + h / 2, w, h, False)
            for (x, y) in (lm.get('arrows') or []):
                put(2, x, y, MARK_WH[2], MARK_WH[2], False)
            for (x, y) in (lm.get('foul_dots') or []):
                put(3, x, y, MARK_WH[3], MARK_WH[3], False)
        # lane target
        lane = np.zeros(6, np.float32); lane_m = np.float32(0.0)
        lmk = r.get('landmarks')
        if lmk and lmk.get('foul') and lmk.get('vp'):
            (flx, fly), (frx, fry) = lmk['foul'][0], lmk['foul'][1]; vx, vy = lmk['vp']
            pts = np.array([[flx, fly], [frx, fry], [vx, vy]], np.float32) * s
            if flip:
                pts[:, 0] = self.input - 1 - pts[:, 0]; pts[[0, 1]] = pts[[1, 0]]
            lane = (pts.reshape(-1) / self.input).astype(np.float32); lane_m = np.float32(1.0)
        x = canvas.astype(np.float32)[:, :, ::-1] / 255.0
        x = (x - np.array([0.485, 0.456, 0.406])) / np.array([0.229, 0.224, 0.225])
        return (x.transpose(2, 0, 1).astype(np.float32), hm, wh, reg, mask, lane, lane_m)


def collate(b):
    import torch
    xs, hms, whs, regs, masks, lanes, lms = zip(*b)
    return tuple(torch.from_numpy(np.stack(v)) for v in (xs, hms, whs, regs, masks, lanes, lms))


def evaluate(model, dl, dev):
    import torch
    model.eval(); hit = {c: [0, 0] for c in range(NUM_CLASSES)}
    with torch.no_grad():
        for x, hm, wh, reg, mask, lane, lm in dl:
            x = x.to(dev); ph, _, _, _ = model(x)
            B, C, O, _ = ph.shape
            for b in range(B):
                for c in range(C):
                    gt = hm[b, c].numpy()
                    if gt.max() < 0.9:
                        continue
                    gy, gx = np.unravel_index(gt.argmax(), gt.shape)
                    py, px = np.unravel_index(ph[b, c].cpu().numpy().argmax(), (O, O))
                    hit[c][1] += 1
                    if (px - gx) ** 2 + (py - gy) ** 2 <= (0.04 * O) ** 2:
                        hit[c][0] += 1
    return {c: (hit[c][0] / hit[c][1] if hit[c][1] else None) for c in range(NUM_CLASSES)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True); ap.add_argument('--landmarks', required=True)
    ap.add_argument('--out', required=True); ap.add_argument('--epochs', type=int, default=40)
    ap.add_argument('--input', type=int, default=512); ap.add_argument('--bs', type=int, default=16)
    ap.add_argument('--lr', type=float, default=2.5e-4)
    a = ap.parse_args()
    torch, nn, F, tv = _import_torch()
    from torch.utils.data import DataLoader
    dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
    os.makedirs(a.out, exist_ok=True)
    tr = DSMC(os.path.join(a.data, 'train.jsonl'), a.landmarks, a.input, train=True)
    va = DSMC(os.path.join(a.data, 'val.jsonl'), a.landmarks, a.input, train=False)
    dltr = DataLoader(tr, batch_size=a.bs, shuffle=True, num_workers=4, collate_fn=collate, drop_last=True)
    dlva = DataLoader(va, batch_size=a.bs, shuffle=False, num_workers=2, collate_fn=collate)
    model = build_model_mc().to(dev)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, a.epochs)
    print(f"[mc] dev={dev} train={len(tr)} val={len(va)} classes=ball,pins,arrows,dots", flush=True)
    best = 0.0
    for ep in range(a.epochs):
        model.train(); t0 = time.perf_counter(); tl = 0; nb = 0
        for x, hm, wh, reg, mask, lane, lm in dltr:
            x, hm, wh, reg, mask = x.to(dev), hm.to(dev), wh.to(dev), reg.to(dev), mask.to(dev)
            lane, lm = lane.to(dev), lm.to(dev)
            ph, pw, pr, pl = model(x)
            lh = sum(focal(ph[:, c], hm[:, c]) for c in range(NUM_CLASSES))
            m = mask.unsqueeze(1)
            lw = F.l1_loss(pw * m, wh * m, reduction='sum') / torch.clamp(m.sum(), min=1)
            lr_ = F.l1_loss(pr * m, reg * m, reduction='sum') / torch.clamp(m.sum(), min=1)
            ll = F.l1_loss(pl * lm[:, None], lane * lm[:, None], reduction='sum') / torch.clamp(lm.sum() * 6, min=1)
            loss = lh + 0.1 * lw + lr_ + ll
            opt.zero_grad(); loss.backward(); opt.step(); tl += float(loss); nb += 1
        sched.step()
        rec = evaluate(model, dlva, dev)
        score = rec[0] or 0                       # select on ball recall (always labelled)
        rstr = ' '.join(f"{n}={('%.2f' % rec[c]) if rec[c] is not None else '-'}" for c, n in
                        enumerate(['ball', 'pins', 'arr', 'dot']))
        print(f"[mc] ep {ep+1}/{a.epochs} loss {tl/max(nb,1):.3f} {rstr} {time.perf_counter()-t0:.0f}s", flush=True)
        if score >= best:
            best = score
            torch.save({'model': model.state_dict(), 'input': a.input, 'stride': 4, 'num_classes': NUM_CLASSES,
                        'recall': rec}, os.path.join(a.out, 'detector_mc.pt'))
    print(f"[mc] DONE best_ball_recall {best:.3f} -> {a.out}/detector_mc.pt", flush=True)


if __name__ == '__main__':
    main()
