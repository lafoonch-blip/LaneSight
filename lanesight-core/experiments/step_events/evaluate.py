"""Evaluate the event-based step detector on the DEV form clips only (form_steps labels, everything EXCEPT
IMG_8980, which is held out and never opened here). Reports per-event recall/precision (hit = within ±3 frames
of a labeled plant), timing-error distribution, exact-count accuracy, split by visibility mode; writes a
timeline PNG per clip. OFFLINE experiment — reads production pose output, changes no production path.

    cd lanesight-core && source .venv/bin/activate && python experiments/step_events/evaluate.py
"""
from __future__ import annotations
import json, os
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from experiments.step_events.detector import analyze_clip

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(os.path.dirname(HERE))
LABELS = os.path.join(CORE, 'validation', 'form_steps_labels.json')
PLOTS = os.path.join(HERE, 'plots')
CLIP_DIR = os.environ.get('LANESIGHT_FORM_CLIPS', os.path.expanduser('~/LaneSightData/training_videos'))
SUBS = ['', 'Form Videos', '11:1 Shots']
HIT_FRAMES = 3
# DEV set only — IMG_8980 is HELD OUT and deliberately absent.
DEV_CLIPS = ['IMG_8824', 'IMG_8825', 'IMG_8826', 'IMG_8846', 'IMG_8847', 'IMG_8848']


def find_clip(cid):
    for s in SUBS:
        for e in ('MOV', 'mov', 'MP4', 'mp4'):
            p = os.path.join(CLIP_DIR, s, f'{cid}.{e}')
            if os.path.exists(p):
                return p


def labeled_plants(lab):
    return [lab[f'step{k}_s'] for k in range(1, 7) if lab.get(f'step{k}_s') is not None]


def match(dets_s, labels_s, fps):
    """greedy nearest match detected<->labeled; hit if |Δframes|<=HIT_FRAMES. Returns (hits, errs_frames,
    matched_label_idx, matched_det_idx)."""
    used_l = set()
    errs = []
    mdet = set()
    mlab = set()
    pairs = []
    for di, d in enumerate(dets_s):
        for li, l in enumerate(labels_s):
            pairs.append((abs(d - l), di, li))
    pairs.sort()
    for dist, di, li in pairs:
        if di in mdet or li in used_l:
            continue
        fe = (dets_s[di] - labels_s[li]) * fps
        if abs(fe) <= HIT_FRAMES:
            mdet.add(di); used_l.add(li); mlab.add(li); errs.append(fe)
    return len(mlab), errs, mlab, mdet


def timeline_png(cid, res, lab, path):
    dbg = res.get('debug') or {}
    tt = dbg.get('tt')
    fps = res['fps']
    fig, ax = plt.subplots(figsize=(11, 4.2))
    if tt is not None and len(tt):
        def norm(a):
            a = np.asarray(a); r = a.max() - a.min()
            return (a - a.min()) / r if r > 1e-9 else a * 0
        ax.plot(tt, norm(dbg['advL']), color='#2a7fff', lw=1.4, label='L leg advance (rel hip)')
        ax.plot(tt, norm(dbg['advR']), color='#ff7f2a', lw=1.4, label='R leg advance (rel hip)')
        ax.plot(tt, norm(dbg['hipf']), color='#999', lw=1.2, ls=':', label='hip forward translation')
    for i, p in enumerate(labeled_plants(lab)):
        ax.axvline(p, color='#111', lw=1.6, alpha=0.8, label='labeled plant' if i == 0 else None)
    for i, s in enumerate(res.get('steps') or []):
        ax.axvline(s['t_s'], color='#d62728', lw=1.4, ls='--', alpha=0.9,
                   label='detected step' if i == 0 else None)
        ax.annotate(s['leg'], (s['t_s'], 1.02), color='#d62728', fontsize=8, ha='center')
    win = res.get('window')
    if win:
        ax.axvspan(win[0], win[1], color='#f0f0f0', zorder=0)
    ax.set_title(f"{cid}  mode={res.get('visibility_mode')}  detected={res.get('step_count')}  "
                 f"labeled={len(labeled_plants(lab))} (true 5)  fps={fps:.0f}")
    ax.set_xlabel('time (s)'); ax.set_ylabel('normalized signal'); ax.set_ylim(-0.1, 1.15)
    ax.legend(loc='upper left', fontsize=7, ncol=2)
    fig.tight_layout(); fig.savefig(path, dpi=110); plt.close(fig)


def main():
    assert 'IMG_8980' not in DEV_CLIPS, 'IMG_8980 is held out'
    os.makedirs(PLOTS, exist_ok=True)
    labels = json.load(open(LABELS))['clips']
    rows = []
    agg = {'tp': 0, 'det': 0, 'lab': 0, 'errs': [], 'bymode': {}}
    for cid in DEV_CLIPS:
        lab = labels[cid]
        fps = lab['fps']
        plants = labeled_plants(lab)
        path = find_clip(cid)
        res = analyze_clip(path, log=lambda *a: None)
        mode = res.get('visibility_mode')
        dets = [s['t_s'] for s in (res.get('steps') or [])]
        if mode == 'insufficient':
            rows.append(dict(clip=cid, mode=mode, det=None, lab=len(plants), recall=None, prec=None,
                             errs=[], count_exact=None, reason=res.get('reason')))
            timeline_png(cid, res, lab, os.path.join(PLOTS, f'{cid}.png'))
            continue
        hits, errs, mlab, mdet = match(dets, plants, fps)
        recall = hits / len(plants) if plants else 0.0
        prec = hits / len(dets) if dets else 0.0
        count_exact = (res.get('step_count') == len(plants))
        rows.append(dict(clip=cid, mode=mode, det=res.get('step_count'), lab=len(plants),
                         recall=recall, prec=prec, errs=errs, count_exact=count_exact,
                         conf=res.get('confidence'), true5=(res.get('step_count') == 5)))
        agg['tp'] += hits; agg['det'] += len(dets); agg['lab'] += len(plants); agg['errs'] += errs
        bm = agg['bymode'].setdefault(mode, {'tp': 0, 'det': 0, 'lab': 0})
        bm['tp'] += hits; bm['det'] += len(dets); bm['lab'] += len(plants)
        timeline_png(cid, res, lab, os.path.join(PLOTS, f'{cid}.png'))

    # ---- report ----
    print(f'HIT = detected step within ±{HIT_FRAMES} frames of a labeled plant. DEV clips only (IMG_8980 held out).\n')
    print(f'{"clip":10s} {"mode":11s} {"det":>3s} {"lab":>3s} {"recall":>7s} {"prec":>6s} {"cnt=lab":>7s} {"cnt=5":>5s}  timing Δf')
    for r in rows:
        if r['mode'] == 'insufficient':
            print(f'{r["clip"]:10s} {r["mode"]:11s}  —   {r["lab"]:>3d}     —      —       —      —   ({r["reason"]})')
            continue
        te = ', '.join(f'{e:+.0f}' for e in sorted(r['errs'])) or '—'
        print(f'{r["clip"]:10s} {r["mode"]:11s} {r["det"]:>3d} {r["lab"]:>3d} {r["recall"]*100:6.0f}% '
              f'{r["prec"]*100:5.0f}% {str(r["count_exact"]):>7s} {str(r["true5"]):>5s}  [{te}]')
    R = agg['tp'] / agg['lab'] if agg['lab'] else 0.0
    Pr = agg['tp'] / agg['det'] if agg['det'] else 0.0
    errs = np.array(agg['errs']) if agg['errs'] else np.array([])
    scored = [r for r in rows if r['mode'] != 'insufficient']
    cnt_exact = sum(1 for r in scored if r['count_exact'])
    print('\nOVERALL (dev):')
    print(f'  event recall {R*100:.0f}%  ({agg["tp"]}/{agg["lab"]}),  precision {Pr*100:.0f}%  ({agg["tp"]}/{agg["det"]})')
    if len(errs):
        print(f'  timing error (frames): mean {errs.mean():+.1f}, median {np.median(errs):+.1f}, '
              f'std {errs.std():.1f}, |Δ| p90 {np.percentile(np.abs(errs),90):.1f}')
    print(f'  exact count (==labeled visible): {cnt_exact}/{len(scored)}   '
          f'(==true 5: {sum(1 for r in scored if r["true5"])}/{len(scored)})')
    print('  by visibility mode:')
    for mode, bm in sorted(agg['bymode'].items()):
        rr = bm['tp'] / bm['lab'] if bm['lab'] else 0.0
        pp = bm['tp'] / bm['det'] if bm['det'] else 0.0
        print(f'    {mode:11s} recall {rr*100:.0f}% ({bm["tp"]}/{bm["lab"]}), precision {pp*100:.0f}% ({bm["tp"]}/{bm["det"]})')
    print(f'\n  stop-rule gate: event recall >= 90% ? -> {"PASS" if R >= 0.90 else "FAIL (write up + stop)"}')
    print(f'  PNGs: {PLOTS}')
    return rows, dict(recall=R, precision=Pr, errs=errs)


if __name__ == '__main__':
    main()
