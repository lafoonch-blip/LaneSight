#!/usr/bin/env python3
"""DEC-130 — export the CenterNet ball detector to Core ML and measure latency (the <15 ms/frame gate).

  python -m ops.export_coreml --ckpt <model>/ball_centernet.pt --out <model>/BallDetector.mlpackage [--input 512]

Exports an mlprogram (fp16) with ALL compute units (ANE+GPU+CPU). Prints measured prediction latency on this Mac
(an approximation of on-device ANE) and a parity check (CoreML vs torch heatmap argmax) on a random input.
"""
from __future__ import annotations
import argparse, os, time
import numpy as np


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ckpt', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--input', type=int, default=None)
    ap.add_argument('--iters', type=int, default=50)
    a = ap.parse_args()
    import torch
    import coremltools as ct
    from ops.train_detector import build_model

    ck = torch.load(a.ckpt, map_location='cpu')
    inp = a.input or ck.get('input', 512)
    model = build_model(); model.load_state_dict(ck['model']); model.eval()
    ex = torch.rand(1, 3, inp, inp)
    with torch.no_grad():
        ts = torch.jit.trace(model, ex)
    mlmodel = ct.convert(
        ts, inputs=[ct.TensorType(name='image', shape=(1, 3, inp, inp))],
        outputs=[ct.TensorType(name='heatmap'), ct.TensorType(name='wh'), ct.TensorType(name='offset'),
                 ct.TensorType(name='lane')],
        compute_precision=ct.precision.FLOAT16, compute_units=ct.ComputeUnit.ALL,
        convert_to='mlprogram', minimum_deployment_target=ct.target.iOS17)
    mlmodel.save(a.out)
    print(f"[coreml] saved {a.out} (input {inp})")

    # latency
    xd = {'image': ex.numpy().astype(np.float32)}
    for _ in range(5):
        mlmodel.predict(xd)
    t0 = time.perf_counter()
    for _ in range(a.iters):
        out = mlmodel.predict(xd)
    dt = (time.perf_counter() - t0) / a.iters * 1000
    print(f"[coreml] latency ~{dt:.1f} ms/frame over {a.iters} iters (Mac ANE/GPU; approximates iPhone ANE)")

    # parity: CoreML heatmap peak vs torch
    with torch.no_grad():
        th, tw, tr, tl = model(ex)
    ch = out['heatmap'][0, 0]
    tp = np.unravel_index(th[0, 0].numpy().argmax(), th[0, 0].shape)
    cp = np.unravel_index(ch.argmax(), ch.shape)
    print(f"[coreml] argmax parity torch={tp} coreml={cp} d={np.hypot(tp[0]-cp[0], tp[1]-cp[1]):.1f}px (stride-4 cells)")
    print(f"[coreml] GATE <15ms: {'PASS' if dt < 15 else 'OVER — tune input/backbone'} ({dt:.1f} ms)")


if __name__ == '__main__':
    main()
