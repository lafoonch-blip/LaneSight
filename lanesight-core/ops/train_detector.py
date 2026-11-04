#!/usr/bin/env python3
"""DEC-130 — CenterNet-style single-class (ball) detector. MobileNetV3-Large backbone (torchvision, BSD) + a
light decoder to stride-4 heads: heatmap (1), size wh (2), offset (2). Anchor/NMS-free -> clean Core ML export
and small-object friendly (the ball is tiny far down-lane). Trains on the harvested stabilized frames.

  python -m ops.train_detector --data <ds>/splits --out <ds>/model --epochs 40 --input 512
Eval (recall @ center-dist tolerance) prints each epoch; best-val checkpoint saved to <out>/ball_centernet.pt.
"""
from __future__ import annotations
import argparse, json, os, math, time
import numpy as np


def _import_torch():
    import torch, torch.nn as nn, torch.nn.functional as F
    import torchvision
    return torch, nn, F, torchvision


# ---------------- model ----------------
def build_model():
    torch, nn, F, tv = _import_torch()

    class Up(nn.Module):
        def __init__(self, cin, cout):
            super().__init__()
            self.conv = nn.Sequential(nn.Conv2d(cin, cout, 3, 1, 1), nn.BatchNorm2d(cout), nn.ReLU(inplace=True))
        def forward(self, x):
            return self.conv(F.interpolate(x, scale_factor=2, mode='bilinear', align_corners=False))

    class BallNet(nn.Module):
        def __init__(self):
            super().__init__()
            bb = tv.models.mobilenet_v3_large(weights=tv.models.MobileNet_V3_Large_Weights.IMAGENET1K_V1)
            self.features = bb.features                   # stride 32, 960 ch at the end
            self.up1 = Up(960, 256); self.up2 = Up(256, 128); self.up3 = Up(128, 64)   # stride 32 -> 4
            self.hm = nn.Conv2d(64, 1, 1); self.wh = nn.Conv2d(64, 2, 1); self.reg = nn.Conv2d(64, 2, 1)
            self.hm.bias.data.fill_(-2.19)                # focal-loss prior
            # DEC-130 lane-geometry head: global regression of 6 normalized lane params
            # [foul_lx, foul_ly, foul_rx, foul_ry, vp_x, vp_y] (vp may be off-frame -> plain regression).
            self.lane = nn.Sequential(nn.AdaptiveAvgPool2d(1), nn.Flatten(),
                                      nn.Linear(960, 256), nn.ReLU(inplace=True), nn.Linear(256, 6))
        def forward(self, x):
            f = self.features(x)
            lane = self.lane(f)
            u = self.up3(self.up2(self.up1(f)))
            return torch.sigmoid(self.hm(u)), self.wh(u), self.reg(u), lane
    return BallNet()


# ---------------- data ----------------
def gaussian_radius(h, w, min_overlap=0.3):
    a1, b1, c1 = 1, (h + w), w * h * (1 - min_overlap) / (1 + min_overlap)
    r1 = (b1 + math.sqrt(max(b1 * b1 - 4 * a1 * c1, 0))) / 2
    return max(0, int(r1))


def draw_gaussian(hm, cx, cy, radius):
    radius = max(1, radius); d = 2 * radius + 1
    sig = d / 6.0
    ax = np.arange(-radius, radius + 1)
    g = np.exp(-(ax[None, :] ** 2 + ax[:, None] ** 2) / (2 * sig * sig))
    H, W = hm.shape
    l, r = min(cx, radius), min(W - cx, radius + 1)
    t, b = min(cy, radius), min(H - cy, radius + 1)
    if r <= -l or b <= -t:
        return
    masked = hm[cy - t:cy + b, cx - l:cx + r]
    gg = g[radius - t:radius + b, radius - l:radius + r]
    np.maximum(masked, gg, out=masked)


class DS:
    def __init__(self, jsonl, input_sz=512, stride=4, train=True):
        self.rows = [json.loads(l) for l in open(jsonl)]
        self.input = input_sz; self.stride = stride; self.out = input_sz // stride; self.train = train

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, i):
        import cv2
        r = self.rows[i]
        img = cv2.imread(r['img'])
        if img is None:
            img = np.zeros((self.input, self.input, 3), np.uint8)
        H0, W0 = img.shape[:2]
        s = self.input / max(H0, W0)
        nw, nh = int(round(W0 * s)), int(round(H0 * s))
        rz = cv2.resize(img, (nw, nh))
        canvas = np.zeros((self.input, self.input, 3), np.uint8)
        canvas[:nh, :nw] = rz
        # simple train aug: horizontal flip
        flip = self.train and (i * 2654435761 % 2 == 0)
        if flip:
            canvas = canvas[:, ::-1].copy()
        O = self.out
        hm = np.zeros((O, O), np.float32); wh = np.zeros((2, O, O), np.float32)
        reg = np.zeros((2, O, O), np.float32); mask = np.zeros((O, O), np.float32)
        for (bx, by, bw, bh, cls) in r['boxes']:
            cx = (bx + bw / 2) * s; cy = (by + bh / 2) * s
            if flip:
                cx = self.input - 1 - cx
            fx, fy = cx / self.stride, cy / self.stride
            ix, iy = int(fx), int(fy)
            if not (0 <= ix < O and 0 <= iy < O):
                continue
            rad = gaussian_radius(max(1, bh * s / self.stride), max(1, bw * s / self.stride))
            draw_gaussian(hm, ix, iy, rad)
            wh[0, iy, ix] = bw * s / self.stride; wh[1, iy, ix] = bh * s / self.stride
            reg[0, iy, ix] = fx - ix; reg[1, iy, ix] = fy - iy
            mask[iy, ix] = 1.0
        # lane-geometry target [foul_lx,foul_ly,foul_rx,foul_ry,vp_x,vp_y] normalized by input; mask 0 if absent
        lane = np.zeros(6, np.float32); lane_m = np.float32(0.0)
        lm = r.get('landmarks')
        if lm and lm.get('foul') and lm.get('vp'):
            (flx, fly), (frx, fry) = lm['foul'][0], lm['foul'][1]
            vx, vy = lm['vp']
            pts = np.array([[flx, fly], [frx, fry], [vx, vy]], np.float32) * s
            if flip:
                pts[:, 0] = self.input - 1 - pts[:, 0]
                pts[[0, 1]] = pts[[1, 0]]                 # swap L/R endpoints under flip
            lane = (pts.reshape(-1) / self.input).astype(np.float32)
            lane_m = np.float32(1.0)
        x = canvas.astype(np.float32)[:, :, ::-1] / 255.0          # BGR->RGB
        x = (x - np.array([0.485, 0.456, 0.406])) / np.array([0.229, 0.224, 0.225])
        return (x.transpose(2, 0, 1).astype(np.float32), hm, wh, reg, mask, lane, lane_m)


def focal(pred, gt):
    import torch
    pos = gt.eq(1).float(); neg = (1 - pos)
    nw = torch.pow(1 - gt, 4)
    p = torch.clamp(pred, 1e-6, 1 - 1e-6)
    ploss = torch.log(p) * torch.pow(1 - p, 2) * pos
    nloss = torch.log(1 - p) * torch.pow(p, 2) * nw * neg
    n = pos.sum()
    return -(ploss.sum() + nloss.sum()) / torch.clamp(n, min=1.0)


def collate(batch):
    import torch
    xs, hms, whs, regs, masks, lanes, lms = zip(*batch)
    return (torch.from_numpy(np.stack(xs)), torch.from_numpy(np.stack(hms)),
            torch.from_numpy(np.stack(whs)), torch.from_numpy(np.stack(regs)),
            torch.from_numpy(np.stack(masks)), torch.from_numpy(np.stack(lanes)),
            torch.from_numpy(np.stack(lms)))


def evaluate(model, dl, dev, stride, tol_frac=0.03):
    import torch
    model.eval(); hit = tot = 0; lane_err = [];
    with torch.no_grad():
        for x, hm, wh, reg, mask, lane, lm in dl:
            x = x.to(dev); ph, pw, pr, pl = model(x)
            B, _, O, _ = ph.shape
            for b in range(B):
                gt = mask[b].numpy()
                ys, xs = np.where(gt > 0)
                if len(xs):
                    tot += 1
                    h = ph[b, 0].cpu().numpy()
                    py, px = np.unravel_index(h.argmax(), h.shape)
                    if math.hypot(px - xs[0], py - ys[0]) <= tol_frac * O:
                        hit += 1
                if float(lm[b]) > 0:               # lane param MAE (normalized units) where GT present
                    lane_err.append(float(torch.abs(pl[b].cpu() - lane[b]).mean()))
    return hit / max(tot, 1), tot, (sum(lane_err) / len(lane_err) if lane_err else None)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True); ap.add_argument('--out', required=True)
    ap.add_argument('--epochs', type=int, default=40); ap.add_argument('--input', type=int, default=512)
    ap.add_argument('--bs', type=int, default=16); ap.add_argument('--lr', type=float, default=2.5e-4)
    ap.add_argument('--lane_w', type=float, default=1.0, help='weight on the lane-geometry regression loss')
    a = ap.parse_args()
    torch, nn, F, tv = _import_torch()
    from torch.utils.data import DataLoader
    dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
    os.makedirs(a.out, exist_ok=True)
    tr = DS(os.path.join(a.data, 'train.jsonl'), a.input, train=True)
    va = DS(os.path.join(a.data, 'val.jsonl'), a.input, train=False)
    dltr = DataLoader(tr, batch_size=a.bs, shuffle=True, num_workers=4, collate_fn=collate, drop_last=True)
    dlva = DataLoader(va, batch_size=a.bs, shuffle=False, num_workers=2, collate_fn=collate)
    model = build_model().to(dev)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, a.epochs)
    print(f"[train] dev={dev} train={len(tr)} val={len(va)} input={a.input}", flush=True)
    best = 0.0
    for ep in range(a.epochs):
        model.train(); t0 = time.perf_counter(); tl = 0; nb = 0
        for x, hm, wh, reg, mask, lane, lm in dltr:
            x, hm = x.to(dev), hm.to(dev); wh, reg, mask = wh.to(dev), reg.to(dev), mask.to(dev)
            lane, lm = lane.to(dev), lm.to(dev)
            ph, pw, pr, pl = model(x)
            lh = focal(ph[:, 0], hm)
            m = mask.unsqueeze(1)
            lw = (F.l1_loss(pw * m, wh * m, reduction='sum') / torch.clamp(m.sum(), min=1))
            lr_ = (F.l1_loss(pr * m, reg * m, reduction='sum') / torch.clamp(m.sum(), min=1))
            # lane loss only on frames that carry landmarks (auto-labels); masked by lm
            ll = (F.l1_loss(pl * lm[:, None], lane * lm[:, None], reduction='sum') / torch.clamp(lm.sum() * 6, min=1))
            loss = lh + 0.1 * lw + lr_ + a.lane_w * ll
            opt.zero_grad(); loss.backward(); opt.step()
            tl += float(loss); nb += 1
        sched.step()
        rec, n, lane_mae = evaluate(model, dlva, dev, 4)
        score = rec - (lane_mae or 0)        # select on recall minus lane error (both matter for geometry)
        print(f"[train] ep {ep+1}/{a.epochs} loss {tl/max(nb,1):.3f} val_recall {rec:.3f} (n={n}) "
              f"lane_mae {lane_mae if lane_mae is None else round(lane_mae,4)} {time.perf_counter()-t0:.0f}s", flush=True)
        if score >= best:
            best = score
            torch.save({'model': model.state_dict(), 'input': a.input, 'stride': 4, 'val_recall': rec,
                        'lane_mae': lane_mae}, os.path.join(a.out, 'ball_centernet.pt'))
    print(f"[train] DONE best_val_recall {best:.3f} -> {a.out}/ball_centernet.pt", flush=True)


if __name__ == '__main__':
    main()
