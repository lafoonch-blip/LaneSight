"""Score the foot-strike detector against per-plant ground truth (validation/form_steps_labels.json).

For each clip: match the detector's strikes to the VISIBLE labeled plants (null = not visible / off-frame,
not scored) in FRAMES; report per-plant error, missed visible plants, spurious extra strikes, and the count.
Gate (DEC-120): every visible plant within ±2 frames; detected count == visible-plant count. (The physical
approach is 5 steps on every labeled clip; some early plants are off-frame so not every clip exposes 5.)

    cd lanesight-core && source .venv/bin/activate && python examples/form_steps_baseline.py
"""
from __future__ import annotations
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__)); CORE = os.path.dirname(HERE)
LABELS = os.path.join(CORE, 'validation', 'form_steps_labels.json')
CLIP_DIR = os.environ.get('LANESIGHT_FORM_CLIPS', os.path.expanduser('~/LaneSightData/training_videos'))
SUBS = ['', 'Form Videos', '11:1 Shots']
GATE = 2
HOLDOUT = {'IMG_8980'}


def find_clip(cid):
    for s in SUBS:
        for e in ('MOV', 'mov', 'MP4', 'mp4'):
            p = os.path.join(CLIP_DIR, s, f'{cid}.{e}')
            if os.path.exists(p):
                return p


def main(argv):
    from lanesight_core.form import pose
    labels = json.load(open(LABELS))['clips']
    ids = [a for a in argv if not a.startswith('-')] or sorted(labels)
    print(f'gate: every visible plant ±{GATE} frames, detected count == visible-plant count\n')
    summ = []
    for cid in ids:
        lab = labels[cid]
        fps = lab.get('fps') or 30.0
        vis = [(k, lab[f'step{k}_s']) for k in range(1, 7) if lab.get(f'step{k}_s') is not None]
        p = find_clip(cid)
        tag = ' [HELD OUT]' if cid in HOLDOUT else ''
        print('=' * 90)
        print(f'{cid}{tag} view={lab.get("view")} fps={fps:.2f}  step_count(GT)={lab.get("step_count")}  visible plants={len(vis)}')
        if not p:
            print('  clip not found'); continue
        rec = pose.analyze(p, handed='right', log=lambda *a: None)
        strikes = [s[0] for s in (rec['_extras'].get('strikes') or [])]
        # greedy nearest match labeled->detected
        used = set(); rows = []; matched = 0
        for k, gt in vis:
            best = None
            for i, dt in enumerate(strikes):
                if i in used:
                    continue
                fe = (dt - gt) * fps
                if best is None or abs(fe) < abs(best[1]):
                    best = (i, fe, dt)
            if best and abs(best[1]) <= 8:     # consider it the match candidate if within 8 frames
                used.add(best[0]); rows.append((k, gt, best[2], best[1])); matched += 1 if abs(best[1]) <= GATE else 0
            else:
                rows.append((k, gt, None, None))
        spurious = [strikes[i] for i in range(len(strikes)) if i not in used]
        det_n = len(strikes)
        print(f'  detected strikes={det_n} at {[round(x,2) for x in strikes]}')
        for k, gt, dt, fe in rows:
            if dt is None:
                print(f'    step{k}: label {gt:.3f}s  -> NO MATCH (missed)')
            else:
                flag = 'PASS' if abs(fe) <= GATE else 'off'
                print(f'    step{k}: label {gt:.3f}s  det {dt:.3f}s  Δ{fe:+.1f}f  [{flag}]')
        if spurious:
            print(f'    SPURIOUS (unmatched detections): {[round(x,2) for x in spurious]}')
        within = all(dt is not None and abs(fe) <= GATE for _, _, dt, fe in rows)
        count_ok = det_n == len(vis)
        print(f'  => visible-plant match: {matched}/{len(vis)} within ±{GATE}f; count {det_n} vs visible {len(vis)} [{ "OK" if count_ok else "MISS"}]; all-plants-pass={within}')
        summ.append((cid, matched, len(vis), det_n, within and count_ok, cid in HOLDOUT))
    print('\n' + '=' * 90); print('SUMMARY (foot-strike detector vs per-plant truth)')
    for cid, m, v, d, ok, ho in summ:
        print(f'  {cid}{" [HELD OUT]" if ho else ""}: {m}/{v} plants ±{GATE}f, detected {d} (visible {v}) -> {"PASS" if ok else "FAIL"}')


if __name__ == '__main__':
    main(sys.argv[1:])
