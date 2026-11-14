#!/usr/bin/env python3
"""DEC-130 — render a learned-engine result on a real clip for the report: the detected ball track + lane
geometry on a representative stabilised frame, with the measured metrics panel. Proof of "real results".

  python -m ops.visualize_result <clip-id|path> --ckpt <ball_centernet.pt> --out <png> [--clips-dir ...]
"""
from __future__ import annotations
import argparse, os, tempfile
import numpy as np
import cv2


def render(clip, out_png, ckpt=None, mlpackage=None, clips_dir=None):
    from ops.detector_integrate import LearnedDetector
    from lanesight_runner.core import analyze_clip
    from lanesight_core.cv.pipeline import analyze
    det = LearnedDetector(ckpt=ckpt, mlpackage=mlpackage)

    def learned(video, out_prefix, handed=None, log=print, timing_video=None, core_end_s=None, cv_timings=None):
        return analyze(video, out_prefix, handed=handed, log=log, timing_video=timing_video,
                       core_end_s=core_end_s, timings=cv_timings, detector=det)

    with tempfile.TemporaryDirectory() as td:
        rec, probe, _ = analyze_clip(clip, os.path.join(td, 'ev'), analyzer=learned)
        analyzed = ((probe.get('window') or {}).get('analyzed_file')
                    or os.path.join(td, 'ev') + '_sdr.mov')
        # a mid-track stabilised frame
        p = det._prepared
        S = None
        import glob, pickle
        for pk in glob.glob(os.path.join(td, '*_stab.pkl')):
            S = pickle.load(open(pk, 'rb')); break
        dets = p['dets'] if p else []
        mid = dets[len(dets) // 2] if dets else None
        frame = None
        if S is not None and mid is not None:
            cap = cv2.VideoCapture(analyzed); cap.set(cv2.CAP_PROP_POS_FRAMES, int(mid[0]))
            ok, fr = cap.read(); cap.release()
            if ok:
                frame = cv2.warpPerspective(fr, S['Hs'][int(mid[0])].astype(np.float64),
                                            (S['bg'].shape[1], S['bg'].shape[0]))
        if frame is None and S is not None:
            frame = S['bg'].copy()
        if frame is None:
            frame = np.zeros((1920, 1080, 3), np.uint8)
        # overlay: every detected ball box (track), lane edges, foul line, vp
        if p:
            from ops.detector_integrate import lane_from_params
            lp = np.median(np.array(p['lane_params']), axis=0)
            lane, vp = lane_from_params(lp, p['img_w'], p['img_h'])
            from lanesight_core.cv.track import lane_x
            for yy in np.linspace(max(vp[1], 0) + 10, p['img_h'] - 2, 120):
                xl, xr = lane_x(lane, float(yy))
                for xx in (xl, xr):
                    if 0 <= xx < p['img_w']:
                        cv2.circle(frame, (int(xx), int(yy)), 1, (0, 255, 255), -1)
            for (i, box) in dets:
                x, y, w, h = box
                cv2.rectangle(frame, (int(x), int(y)), (int(x + w), int(y + h)), (0, 255, 0), 2)
        # metrics panel
        m = rec.get('metrics') or {}
        def val(k):
            v = m.get(k)
            return (v.get('value') if isinstance(v, dict) else v)
        lines = [f"clip: {os.path.basename(clip)}",
                 f"ball_speed: {val('ball_speed')}",
                 f"foul->pins: {val('speed_avg_foul_to_pins')}",
                 f"rev_rate: {val('rev_rate')}",
                 f"reason: {rec.get('reason_code') or 'ok'}"]
        y0 = 40
        for ln in lines:
            cv2.putText(frame, str(ln), (20, y0), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 0), 5)
            cv2.putText(frame, str(ln), (20, y0), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2)
            y0 += 44
        cv2.imwrite(out_png, frame)
        return {'metrics': {k: val(k) for k in ('ball_speed', 'speed_avg_foul_to_pins', 'rev_rate')},
                'reason_code': rec.get('reason_code'), 'n_dets': len(dets), 'out': out_png}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('clip')
    ap.add_argument('--ckpt', default=None); ap.add_argument('--mlpackage', default=None)
    ap.add_argument('--clips-dir', default=os.path.expanduser('~/LaneSightData'))
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    clip = a.clip
    if not os.path.exists(clip):
        for dp, _dn, fn in os.walk(a.clips_dir):
            for f in fn:
                if os.path.splitext(f)[0] == os.path.splitext(os.path.basename(a.clip))[0]:
                    clip = os.path.join(dp, f); break
    r = render(clip, a.out, a.ckpt, a.mlpackage, a.clips_dir)
    print(r)


if __name__ == '__main__':
    main()
