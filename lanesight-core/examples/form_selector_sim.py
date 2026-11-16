"""DEC-131 step 2 — offline delivery-selector simulation. Caches MediaPipe landmarks per clip (pose is slow), then
scores several candidate burst-selection formulas and reports, per clip, which burst each picks vs the labeled
release (form_labels.json E7). Lets us tune a landmark-robust + direction-aware selector without re-running pose or
the device gate. The winning formula is then ported verbatim into _find_delivery (server) + FormEngine (iOS).

Usage: python examples/form_selector_sim.py            # all labeled clips + the 01:03 clip (cached after first run)
       FORCE=1 python examples/form_selector_sim.py    # re-extract (ignore cache)
"""
from __future__ import annotations
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from lanesight_core.form import pose as P

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(HERE)
LABELS = json.load(open(os.path.join(CORE, 'validation', 'form_labels.json')))['clips']
CACHE = os.path.expanduser('~/LaneSightData/form/lm_cache')
os.makedirs(CACHE, exist_ok=True)
TRAIN = os.path.expanduser('~/LaneSightData/training_videos')
SUBS = ['', 'Form Videos', '11:1 Shots']

# clip -> (path, labeled_release_s). 01:03 has no label; "correct" = not the 0-6 s pre-shot region.
CLIPS = []
for name in LABELS:
    for sub in SUBS:
        for ext in ('.MOV', '.mov', '.mp4'):
            p = os.path.join(TRAIN, sub, name + ext)
            if os.path.exists(p):
                CLIPS.append((name, p, LABELS[name].get('E7_release_s')))
                break
        else:
            continue
        break
CLIPS.append(('IMG_0103', os.path.expanduser('~/LaneSightData/form/IMG_bad_0103.mov'), None))


def load(name, path):
    cp = os.path.join(CACHE, name + '.npz')
    if os.path.exists(cp) and not os.environ.get('FORCE'):
        d = np.load(cp)
        return d['t'], d['lms']
    t, lms = P.extract_landmarks(path, log=lambda *a: None)
    np.savez_compressed(cp, t=t, lms=lms)
    return t, lms


def bursts_and_feats(t, lms):
    n = len(t)
    Rx, Ry = P._point(lms, P.R_FOOT_PTS, 0), P._point(lms, P.R_FOOT_PTS, 1)
    Lx, Ly = P._point(lms, P.L_FOOT_PTS, 0), P._point(lms, P.L_FOOT_PTS, 1)
    Rs, Ls = P._speed(Rx, Ry, t), P._speed(Lx, Ly, t)
    footvis = np.nan_to_num(lms[:, [P.L_ANKLE, P.R_ANKLE, P.L_FOOT, P.R_FOOT], 3], nan=0.0).mean(1)
    Ms = P._smooth(np.fmax(np.nan_to_num(Rs, nan=9.0), np.nan_to_num(Ls, nan=9.0)), 9)
    hot = np.nan_to_num(Ms, nan=0.0) > P.BURST_MOTION
    wy_l = P._smooth(P._point(lms, (P.L_WRIST,), 1), 5)
    wy_r = P._smooth(P._point(lms, (P.R_WRIST,), 1), 5)
    sh_x = (P._point(lms, (P.L_SHOULDER,), 0) + P._point(lms, (P.R_SHOULDER,), 0)) / 2
    sh_y = (P._point(lms, (P.L_SHOULDER,), 1) + P._point(lms, (P.R_SHOULDER,), 1)) / 2
    hip_y = (P._point(lms, (P.L_HIP,), 1) + P._point(lms, (P.R_HIP,), 1)) / 2
    body_cy = (sh_y + hip_y) / 2
    torso = np.abs(hip_y - sh_y)
    shw = np.abs(P._point(lms, (P.L_SHOULDER,), 0) - P._point(lms, (P.R_SHOULDER,), 0))
    out = []
    i = 0
    while i < n:
        if hot[i]:
            j = i
            while j < n and hot[j]:
                j += 1
            t0, t1 = t[i], t[min(j - 1, n - 1)]
            dur = t1 - t0
            vis = float(footvis[(t >= t0) & (t <= t1)].mean())
            if P.BURST_MIN_S <= dur <= P.BURST_MAX_S and vis >= P.FOOTVIS_MIN:
                wm = (t >= t0 - 1.5) & (t <= t1 + 1.0)
                raw = max([float(np.nanmax(w[wm]) - np.nanmin(w[wm]))
                           for w in (wy_l, wy_r) if np.sum(~np.isnan(w[wm])) >= 4] or [0.0])

                def _med(a, m):
                    v = a[m][~np.isnan(a[m])]
                    return float(np.median(v)) if len(v) else np.nan

                def _edge(a, m):
                    idx = np.where(m)[0]
                    if len(idx) < 4:
                        return np.nan, np.nan
                    k = max(2, len(idx) // 5)
                    return float(np.nanmean(a[idx[:k]])), float(np.nanmean(a[idx[-k:]]))
                shw_m = _med(shw, wm)
                torso_m = _med(torso, wm)
                bm = (t >= t0 - 0.4) & (t <= t1 + 0.4)
                bx0, bx1 = _edge(sh_x, bm)
                by0, by1 = _edge(body_cy, bm)
                trav = float(np.hypot((bx1 - bx0), (by1 - by0)))
                bodydy = by1 - by0
                out.append(dict(t0=t0, t1=t1, dur=dur, vis=vis, raw=raw, shw=shw_m,
                                torso=torso_m, trav=trav, bodydy=bodydy))
            i = j
        else:
            i += 1
    return out


# body-scale floor: below this the figure is too small/edge-on for a stable ratio
FLOOR = 0.03

FORMULAS = {
    'F0_server_raw': lambda b: b['vis'] * (0.15 * min(b['dur'], 2.5) + b['raw']),
    'F1_vis*raw/shw': lambda b: b['vis'] * b['raw'] / max(b['shw'], FLOOR),
    'F2_vis*raw/torso': lambda b: b['vis'] * b['raw'] / max(b['torso'], FLOOR),
    'F3_vis*(dur+raw/shw)': lambda b: b['vis'] * (0.15 * min(b['dur'], 2.5) + b['raw'] / max(b['shw'], FLOOR)),
    'F4_F1*dirpen': lambda b: b['vis'] * b['raw'] / max(b['shw'], FLOOR) / (1.0 + 4.0 * max(0.0, b['bodydy'] - 0.08)),
    'F5_F1*trav': lambda b: b['vis'] * b['raw'] / max(b['shw'], FLOOR) * (0.5 + b['trav']),
}


def _f6(floor):
    return lambda b: b['vis'] * (0.15 * min(b['dur'], 2.5) + b['raw'] / max(b['shw'], floor)) \
                     / (1.0 + 4.0 * max(0.0, b['bodydy'] - 0.08))


for _fl in (0.030, 0.020, 0.015, 0.010):
    FORMULAS[f'F6_dirpen_fl{_fl:.3f}'] = _f6(_fl)


def main():
    results = {k: [] for k in FORMULAS}
    for name, path, rel in CLIPS:
        t, lms = load(name, path)
        feats = bursts_and_feats(t, lms)
        if not feats:
            print(f'{name}: no bursts'); continue
        print(f'\n{name}  release_label={rel}  bursts={len(feats)}')
        for k, fn in FORMULAS.items():
            scored = sorted(((fn(b), b) for b in feats), key=lambda x: x[0], reverse=True)
            best = scored[0][1]
            margin = scored[0][0] / scored[1][0] if len(scored) > 1 and scored[1][0] > 1e-9 else float('inf')
            mid = (best['t0'] + best['t1']) / 2
            if rel is not None:
                ok = abs(mid - rel) <= 1.2 or (best['t0'] - 0.5 <= rel <= best['t1'] + 1.0)
            else:
                ok = best['t0'] >= 10.0           # 01:03: anything past the 0-6 s pre-shot region
            results[k].append(ok)
            mtxt = '  inf' if margin == float('inf') else f'{margin:5.2f}x'
            print(f'  {k:22s} picks [{best["t0"]:5.1f},{best["t1"]:5.1f}]  margin {mtxt}  {"OK " if ok else "BAD"}')
    print('\n==== formula scorecard (correct picks / clips) ====')
    for k in FORMULAS:
        r = results[k]
        print(f'  {k:22s} {sum(r)}/{len(r)}  ' + ''.join('.' if x else 'X' for x in r))


if __name__ == '__main__':
    main()
