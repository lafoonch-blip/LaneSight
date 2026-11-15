#!/usr/bin/env python3
"""DEC-130 — score a learned-engine cv_eval run vs the production baseline and the foul-cross->pin-contact speed
truth, per camera group. Produces the coverage/accuracy table for the Done bar.

Speed truth (DEC-064 convention): 59.44 ft / ((pin_frame - foul_frame)/fps) * 3600/5280 mph, from
validation/labels/speed_truth_1101.json (the 11/1 set) + validation/early_lane_speed_truth.json (IMG_8751-54,
foul->arrows 12 ft segment). Compared to the engine's `speed_avg_foul_to_pins` (same time-based definition).

  python -m ops.score_learned --learned <learned.json> --baseline <baseline.json> --out <md>
"""
from __future__ import annotations
import argparse, json, os
from collections import defaultdict

Z_FOUL_PINS = 59.44    # ft, foul line to head pin (DEC-064)
Z_FOUL_ARROWS = 12.0   # ft, foul line to the arrows (IMG_8751-54 early-lane truth)


def _foul_pins_from_events(clips):
    """{clip_id: truth_mph} from an events dict with foul_cross.t_s + first_pin_contact.t_s (59.44 ft average)."""
    out = {}
    for cid, v in clips.items():
        if cid.startswith('_') or not isinstance(v, dict):
            continue
        ev = v.get('events') or {}
        fs = (ev.get('foul_cross') or {}).get('t_s'); ps = (ev.get('first_pin_contact') or {}).get('t_s')
        if fs is not None and ps is not None and ps > fs:
            out[cid] = Z_FOUL_PINS / (ps - fs) * 3600 / 5280
    return out


def truth_speeds():
    """{clip_id: truth_mph} — foul-cross -> first-pin-contact (59.44 ft average), the SAME definition as the
    engine's speed_avg_foul_to_pins. 11/1 set (speed_truth_1101) + IMG_8751-54 (pin_anchor_truth)."""
    out = {}
    base = os.path.join(os.path.dirname(__file__), '..', 'validation')
    for fname in ('labels/speed_truth_1101.json', 'labels/pin_anchor_truth.json'):
        p = os.path.join(base, fname)
        if os.path.exists(p):
            d = json.load(open(p))
            out.update(_foul_pins_from_events(d.get('clips') or d))
    return out


def load(path):
    r = json.load(open(path))
    by = {}
    for rr in r['results']:
        obs = rr.get('observations') or {}
        m = rr.get('metrics') or {}
        by[rr['id']] = {'status': rr.get('status'), 'track': sum(obs.values()),
                        'cc': rr.get('camera_class'),
                        'f2p': m.get('speed_avg_foul_to_pins'), 'ball_speed': m.get('ball_speed'),
                        'rev': m.get('rev_rate')}
    return by


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--learned', required=True)
    ap.add_argument('--baseline', default='ops/perf_reports/cv_eval_all118_dec130.json')
    ap.add_argument('--manifest', default='validation/cv_eval/manifest_all.json')
    ap.add_argument('--tol', type=float, default=0.5)
    ap.add_argument('--out', default=None)
    a = ap.parse_args()
    truth = truth_speeds()
    learned = load(a.learned)
    baseline = load(a.baseline) if os.path.exists(a.baseline) else {}
    man = {c['id']: c for c in json.load(open(a.manifest))['clips']}

    # per camera group coverage (has a measured foul->pins speed) + accuracy on labeled clips
    groups = defaultdict(lambda: {'n': 0, 'base_cov': 0, 'learn_cov': 0,
                                  'labeled': 0, 'base_hit': 0, 'learn_hit': 0,
                                  'base_err': [], 'learn_err': []})
    rows = []
    for cid, L in learned.items():
        cc = L['cc'] or man.get(cid, {}).get('camera_class', '?')
        g = groups[cc]; g['n'] += 1
        B = baseline.get(cid, {})
        base_speed = (B.get('f2p') or {}).get('value') if isinstance(B.get('f2p'), dict) else B.get('f2p')
        learn_speed = (L.get('f2p') or {}).get('value') if isinstance(L.get('f2p'), dict) else L.get('f2p')
        if base_speed is not None: g['base_cov'] += 1
        if learn_speed is not None: g['learn_cov'] += 1
        t = truth.get(cid)
        if t is not None:
            g['labeled'] += 1
            if base_speed is not None:
                e = base_speed - t; g['base_err'].append(abs(e))
                if abs(e) <= a.tol: g['base_hit'] += 1
            if learn_speed is not None:
                e = learn_speed - t; g['learn_err'].append(abs(e))
                if abs(e) <= a.tol: g['learn_hit'] += 1
            rows.append((cid, cc, round(t, 2),
                         round(base_speed, 2) if base_speed else None,
                         round(learn_speed, 2) if learn_speed else None))

    def mae(v): return round(sum(v) / len(v), 2) if v else None
    lines = ['# DEC-130 learned vs baseline vs truth\n',
             f'Speed = foul-cross->pin-contact (time-based). Tolerance ±{a.tol} mph.\n',
             '## Coverage (clips with a measured foul->pins speed) + accuracy, per camera group\n',
             '| camera group | clips | base cov | learn cov | labeled | base MAE | learn MAE | base ≤tol | learn ≤tol |',
             '|---|---|---|---|---|---|---|---|---|']
    tot = defaultdict(int); tbe = []; tle = []
    for cc, g in sorted(groups.items(), key=lambda kv: -kv[1]['n']):
        lines.append(f"| {cc} | {g['n']} | {g['base_cov']}/{g['n']} | {g['learn_cov']}/{g['n']} | "
                     f"{g['labeled']} | {mae(g['base_err'])} | {mae(g['learn_err'])} | "
                     f"{g['base_hit']}/{g['labeled']} | {g['learn_hit']}/{g['labeled']} |")
        for k in ('n', 'base_cov', 'learn_cov', 'labeled', 'base_hit', 'learn_hit'):
            tot[k] += g[k]
        tbe += g['base_err']; tle += g['learn_err']
    lines.append(f"| **TOTAL** | {tot['n']} | {tot['base_cov']}/{tot['n']} | {tot['learn_cov']}/{tot['n']} | "
                 f"{tot['labeled']} | {mae(tbe)} | {mae(tle)} | {tot['base_hit']}/{tot['labeled']} | "
                 f"{tot['learn_hit']}/{tot['labeled']} |")
    lines.append('\n## Per-labeled-clip speed (mph)\n')
    lines.append('| clip | camera | truth | baseline | learned |')
    lines.append('|---|---|---|---|---|')
    for (cid, cc, t, b, l) in sorted(rows, key=lambda r: r[1]):
        lines.append(f'| {cid} | {cc} | {t} | {b} | {l} |')
    md = '\n'.join(lines)
    print(md)
    if a.out:
        open(a.out, 'w').write(md)
        print(f'\nwrote {a.out}')


if __name__ == '__main__':
    main()
