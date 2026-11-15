#!/usr/bin/env python3
"""DEC-130 multi-class retrain — harvest STATIC landmark labels (pins, arrows, foul dots) per clip from the
stabilised background (classical detection, geometry-constrained). Static per shot -> one label set applies to
every harvested frame of that clip. Clear lanes give clean labels; pale/portrait lanes give few (the model learns
the appearance from the clear clips + brightness/contrast augmentation and generalises). Writes
<out>/landmarks/<clip>.json = {pins:[[x,y,w,h]], arrows:[[x,y]], foul_dots:[[x,y]], img_w,img_h}.

  python -m ops.landmark_harvest --split <baseline_full_split.json> --out <dec130>/dataset
"""
from __future__ import annotations
import argparse, json, os, tempfile, traceback


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--split', required=True)
    ap.add_argument('--manifest', default='validation/cv_eval/manifest_all.json')
    ap.add_argument('--data-root', default=os.path.expanduser('~/LaneSightData'))
    ap.add_argument('--out', required=True)
    ap.add_argument('--limit', type=int, default=None)
    a = ap.parse_args()
    from lanesight_core.cv.stabilize import stabilize
    from lanesight_core.cv.lanes import find_lanes
    from ops.pin_detect import detect_pins
    from ops.landmark_detect import detect_arrows, detect_foul_dots
    from ops.learned_analyze import _front_end

    split = json.load(open(a.split))
    ids = split.get('good', []) + split.get('zero', [])
    man = {c['id']: c for c in json.load(open(a.manifest))['clips']}
    if a.limit:
        ids = ids[:a.limit]
    ldir = os.path.join(a.out, 'landmarks'); os.makedirs(ldir, exist_ok=True)
    npins = narrows = ndots = ok = 0
    for cid in ids:
        entry = man.get(cid)
        if not entry:
            continue
        clip = os.path.join(a.data_root, entry['clip'])
        if not os.path.exists(clip):
            continue
        try:
            with tempfile.TemporaryDirectory() as td:
                video = _front_end(clip, os.path.join(td, 'ev'))
                S = stabilize(video, log=lambda *x, **k: None)
            G = find_lanes(S['bg'])
            if not G.get('lanes'):
                continue
            lane = G['lanes'][0]; vp = G['vp']
            pins = detect_pins(S, lane, vp)
            arrows = detect_arrows(S['bg'], lane, vp)
            dots = detect_foul_dots(S['bg'], lane, vp)
            rec = {'clip': cid, 'img_w': S['bg'].shape[1], 'img_h': S['bg'].shape[0],
                   'pins': pins['boxes'] if pins else [],
                   'head_pin_row': pins['head_pin_row'] if pins else None,
                   'arrows': [[p[0], p[1]] for p in arrows['points']] if arrows else [],
                   'foul_dots': [[p[0], p[1]] for p in dots['points']] if dots else []}
            json.dump(rec, open(os.path.join(ldir, cid + '.json'), 'w'))
            npins += bool(rec['pins']); narrows += bool(rec['arrows']); ndots += bool(rec['foul_dots']); ok += 1
            print(f"{cid}: pins={len(rec['pins'])} arrows={len(rec['arrows'])} dots={len(rec['foul_dots'])}", flush=True)
        except Exception as e:
            print(f"{cid}: ERR {type(e).__name__}: {e}", flush=True)
            traceback.print_exc()
    print(f"\nLANDMARK HARVEST DONE: {ok} clips; with pins={npins} arrows={narrows} dots={ndots} -> {ldir}", flush=True)


if __name__ == '__main__':
    main()
