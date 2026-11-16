"""DEC-131 — compare E8 (slide-stop) anchoring methods on cached landmarks, all labeled clips, vs labels:
  CURRENT: anchor = E6 (wrist bottom-of-arc), search to hold_end.
  NEW:     anchor = slide_plant (E5, a reliable foot event), search bounded to slide_plant + SLIDE_MAX_S.
The NEW method is robust to a wrong/late E6 (the device failure on 8825/8826); this checks it doesn't regress the
clips whose E8 is already right on good landmarks. Also runs each clip through its iOS swing-aware winner window.
"""
from __future__ import annotations
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from lanesight_core.form import pose as P

CACHE = os.path.expanduser('~/LaneSightData/form/lm_cache')
LAB = json.load(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                  'validation', 'form_labels.json')))['clips']
SLIDE_MAX_S = 0.7
CLIPS = ['IMG_8824', 'IMG_8825', 'IMG_8826', 'IMG_8846', 'IMG_8847', 'IMG_8848']


def analyze_e8(t, lms):
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
    E6, E7 = ev.get('E6'), ev.get('E7')
    step_start = P._setup_hold_end(t, Rs, Ls, b0)
    rel_bound = (E7 if E7 is not None else hold_start) + 0.12
    strikes = P._foot_strikes(t, lms, (step_start, rel_bound + 0.1), Rs, Ls)
    plants = [s for s in strikes if step_start <= s[0] <= rel_bound]
    slide_plant = plants[-1][0] if plants else hold_start
    # CURRENT: anchor E6 (else slide_plant), t_to = hold_end
    anc_cur = E6 if E6 is not None else slide_plant
    _, sspeed = P._slide_foot(t, Rs, Ls, anc_cur - 0.3, hold_end, 'right')
    cur = P._slide_stop(t, sspeed, anc_cur, hold_end)
    # NEW: clamp a wrong-late E6 toward the slide plant (the slide stop is ~0.3 s after the plant, never 1.5 s), and
    # bound the search upper limit to slide_plant + SLIDE_MAX_S. A reliable E6 (≈ plant + 0.3-0.4 s) is unchanged.
    anc_raw = E6 if E6 is not None else slide_plant
    anc_new = min(anc_raw, slide_plant + 0.5)
    t_to_new = min(hold_end, slide_plant + SLIDE_MAX_S)
    new = P._slide_stop(t, sspeed, anc_new, t_to_new)   # SAME foot/speed as CUR; only clamp the stop search
    return dict(E6=E6, slide_plant=slide_plant, hold_end=hold_end, cur=cur, new=new)


def main():
    print(f'{"clip":10s} {"labelE8":>8s} | {"E6":>6s} {"E5plant":>7s} | {"CUR":>7s} {"dCUR":>6s} | {"NEW":>7s} {"dNEW":>6s}  (fps*Δ)')
    for name in CLIPS:
        cp = os.path.join(CACHE, name + '.npz')
        if not os.path.exists(cp):
            print(f'{name}: no cache'); continue
        d = np.load(cp); t, lms = d['t'], d['lms']
        fps = 1.0 / float(np.median(np.diff(t)))
        lab = LAB[name].get('E8_slide_stop_s')
        r = analyze_e8(t, lms)
        if r is None:
            print(f'{name}: findDelivery None'); continue
        dcur = (r['cur'] - lab) * fps if r['cur'] else None
        dnew = (r['new'] - lab) * fps if r['new'] else None
        e6 = f"{r['E6']:.2f}" if r['E6'] else "None"
        print(f'{name:10s} {lab:8.3f} | {e6:>6s} {r["slide_plant"]:7.2f} | '
              f'{(r["cur"] or 0):7.3f} {(f"{dcur:+.1f}" if dcur is not None else "n/a"):>6s} | '
              f'{(r["new"] or 0):7.3f} {(f"{dnew:+.1f}" if dnew is not None else "n/a"):>6s}')


if __name__ == '__main__':
    main()
