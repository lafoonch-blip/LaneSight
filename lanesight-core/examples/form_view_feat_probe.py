"""Search for a robust rear-vs-side (down_lane) discriminator across all 9 cached clips. dy/dx of the hip centroid
is framing-dependent (fails b6cfd17c one way, 8846-48 the other). Orientation cue: in a SIDE/profile view the two
shoulders (and hips) overlap in x → small shoulder-width / torso-height; in a REAR/frontal view they spread →
large. That cue is travel-independent. Report several features over the approach window + full clip per clip."""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from lanesight_core.form import pose as P

CACHE = os.path.expanduser('~/LaneSightData/form/lm_cache')
TRUTH = {'IMG_8824': 'down_lane', 'IMG_8825': 'down_lane', 'IMG_8826': 'down_lane', 'IMG_8980': 'down_lane',
         'IMG_8846': 'rear', 'IMG_8847': 'rear', 'IMG_8848': 'rear',
         'side_b6cfd17c': 'rear', 'rear_ee17c156': 'down_lane'}


def feats(t, lms, lo=None, hi=None):
    if lo is not None:
        m = (t >= lo) & (t <= hi); t, lms = t[m], lms[m]
    vis = lms[:, :, 3]
    ok = ((vis[:, P.L_SHOULDER] > P.MIN_VIS) & (vis[:, P.R_SHOULDER] > P.MIN_VIS)
          & (vis[:, P.L_HIP] > P.MIN_VIS) & (vis[:, P.R_HIP] > P.MIN_VIS))
    if ok.sum() < 8:
        return None
    f = lms[ok]
    hx = (f[:, P.L_HIP, 0] + f[:, P.R_HIP, 0]) / 2
    hy = (f[:, P.L_HIP, 1] + f[:, P.R_HIP, 1]) / 2
    dx = float(np.nanmax(hx) - np.nanmin(hx)); dy = float(np.nanmax(hy) - np.nanmin(hy))
    shoulder_w = np.abs(f[:, P.L_SHOULDER, 0] - f[:, P.R_SHOULDER, 0])
    hip_w = np.abs(f[:, P.L_HIP, 0] - f[:, P.R_HIP, 0])
    sh_mid_y = (f[:, P.L_SHOULDER, 1] + f[:, P.R_SHOULDER, 1]) / 2
    torso = np.abs(hy - sh_mid_y)                                  # hip-to-shoulder vertical ~ torso height
    sw_ratio = float(np.nanmedian(shoulder_w / np.maximum(torso, 1e-3)))
    hw_ratio = float(np.nanmedian(hip_w / np.maximum(torso, 1e-3)))
    return dict(ratio=dy / max(dx, 1e-3), sw_ratio=sw_ratio, hw_ratio=hw_ratio, n=int(ok.sum()))


def main():
    _orig = P.extract_landmarks
    print(f'{"clip":16s} {"truth":9s} | {"full dy/dx":>9s} {"full sw/t":>9s} {"full hw/t":>9s} '
          f'| {"appr dy/dx":>9s} {"appr sw/t":>9s} {"appr hw/t":>9s}')
    for name, truth in TRUTH.items():
        p = os.path.join(CACHE, name + '.npz')
        if not os.path.exists(p):
            continue
        d = np.load(p); t, lms = d['t'], d['lms']
        P.extract_landmarks = lambda *a, _t=t, _l=lms, **k: (_t, _l)
        rec = P.analyze(name, handed='right', log=lambda *a: None)
        ev = (rec['_extras'].get('events') or {})
        fs, aend = ev.get('first_step'), (ev.get('hold_start') or ev.get('slide_stop'))
        ff = feats(t, lms)
        af = feats(t, lms, fs, aend) if (fs and aend) else None
        def g(d, k): return (d[k] if d else 0.0)
        print(f'{name:16s} {truth:9s} | {g(ff,"ratio"):9.3f} {g(ff,"sw_ratio"):9.3f} {g(ff,"hw_ratio"):9.3f} '
              f'| {g(af,"ratio"):9.3f} {g(af,"sw_ratio"):9.3f} {g(af,"hw_ratio"):9.3f}')
    P.extract_landmarks = _orig


if __name__ == '__main__':
    main()
