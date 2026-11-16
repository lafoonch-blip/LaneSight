"""DEC-131 — diagnose E5 (slide plant = last foot strike) vs the labels on cached landmarks. Reports, per clip,
the detected slide_plant, the label E5_slide_start, the frame delta, the number of plants found, and the combined
foot-motion (max of L/R speed) trace around the labelled E5 so we can see whether the detector fires early/late or
misses the slide plant. Full clip + the iOS swing-aware winner window.
"""
from __future__ import annotations
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from lanesight_core.form import pose as P

CACHE = os.path.expanduser('~/LaneSightData/form/lm_cache')
LAB = json.load(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                  'validation', 'form_labels.json')))['clips']
WIN = {'IMG_8825': (16.2, 19.9), 'IMG_8826': (14.8, 18.6)}   # iOS winner windows (dbg)
CLIPS = ['IMG_8824', 'IMG_8825', 'IMG_8826', 'IMG_8846', 'IMG_8847', 'IMG_8848']


def plants_for(t, lms):
    Rx, Ry = P._point(lms, P.R_FOOT_PTS, 0), P._point(lms, P.R_FOOT_PTS, 1)
    Lx, Ly = P._point(lms, P.L_FOOT_PTS, 0), P._point(lms, P.L_FOOT_PTS, 1)
    Rs, Ls = P._speed(Rx, Ry, t), P._speed(Lx, Ly, t)
    d = P._find_delivery(t, lms, Rs, Ls)
    if d is None:
        return None
    (aw, (hold_start, hold_end)) = d
    b0 = aw[0] + 0.4
    torso = P._torso(lms)
    swing_win = (max(t[0], b0 - 0.8), min(hold_start + 0.3, t[-1]))
    ev = P._swing_events(t, lms, {}, swing_win, torso)
    E7 = ev.get('E7')
    step_start = P._setup_hold_end(t, Rs, Ls, b0)
    rel_bound = (E7 if E7 is not None else hold_start) + 0.12
    strikes = P._foot_strikes(t, lms, (step_start, rel_bound + 0.1), Rs, Ls)
    plants = [s for s in strikes if step_start <= s[0] <= rel_bound]
    comb = P._smooth(np.fmax(np.nan_to_num(Rs, nan=9.0), np.nan_to_num(Ls, nan=9.0)), 5)
    E6 = ev.get('E6')
    slide_plant = plants[-1][0] if plants else hold_start
    sf_anchor = E6 if E6 is not None else slide_plant
    foot, slide_speed = P._slide_foot(t, Rs, Ls, sf_anchor - 0.3, hold_end, 'right')
    return dict(plants=plants, step_start=step_start, rel_bound=rel_bound, Rs=Rs, Ls=Ls, comb=comb, t=t,
                slide_speed=slide_speed, foot=foot)


def report(name, t, lms, tag):
    lab = LAB[name]
    e5 = lab.get('E5_slide_start_s')
    fps = 1.0 / float(np.median(np.diff(t)))
    r = plants_for(t, lms)
    if r is None:
        print(f'  [{tag}] delivery None'); return
    plants = r['plants']
    sp = plants[-1][0] if plants else None
    d = (sp - e5) * fps if sp is not None else None
    # refined E5: if a clear slide-foot peak follows the plant AND dominates the motion before it (plant precedes
    # the slide, not the post-slide settle), snap E5 to the peak. Else keep slide_plant.
    refined = sp
    if sp is not None:
        ss = np.nan_to_num(r['slide_speed'], nan=0.0)   # the PROPER slide foot (E6-anchored _slide_foot)
        m_aft = (t >= sp) & (t <= sp + 0.3); m_bef = (t >= sp - 0.3) & (t < sp)
        if m_aft.any() and m_bef.any():
            pk_a = float(np.max(ss[m_aft])); pk_b = float(np.max(ss[m_bef]))
            at = float(ss[int(np.argmin(np.abs(t - sp)))])
            if pk_a > 2.0 * max(at, 0.05) and pk_a > pk_b:    # slide follows the plant → snap E5 to the slide peak
                refined = float(t[m_aft][int(np.argmax(ss[m_aft]))])
    dref = (refined - e5) * fps if refined is not None else None
    pts = ' '.join(f'{p[0]:.2f}{p[1]}' for p in plants)
    print(f'  [{tag}] slide_foot={r["foot"]} slide_plant={sp:.3f} dF={d:+.1f}  REFINED={refined:.3f} dF={dref:+.1f}  '
          f'labelE5={e5:.3f} nPlants={len(plants)} {"[SNAP]" if abs(refined-sp)>1e-6 else ""}')
    print(f'        plants: {pts}')
    # combined foot-motion dips (candidate plants) near label E5
    tt, comb = r['t'], r['comb']
    m = (tt >= e5 - 0.4) & (tt <= e5 + 0.4)
    trace = ' '.join(f'{x:.2f}:{c:.2f}' for x, c in zip(tt[m], comb[m]))
    print(f'        comb-motion near E5: {trace}')


def main():
    for name in CLIPS:
        cp = os.path.join(CACHE, name + '.npz')
        if not os.path.exists(cp):
            print(f'{name}: no cache'); continue
        d = np.load(cp); t, lms = d['t'], d['lms']
        print(f'\n=== {name} (labelE5={LAB[name].get("E5_slide_start_s")}) ===')
        report(name, t, lms, 'FULL')
        if name in WIN:
            w0, w1 = WIN[name]; m = (t >= w0) & (t <= w1)
            report(name, t[m], lms[m], f'iOSwin')


if __name__ == '__main__':
    main()
