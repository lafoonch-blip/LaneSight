#!/usr/bin/env python3
"""DEC-130 — assemble the detector dataset from harvested auto + zeroshot labels into train/val/holdout jsonl.

Each output row: {img, w, h, boxes:[[x,y,w,h,cls]], landmarks:{foul,left_edge,right_edge,vp}|null, clip,
camera_class, source}. cls 0 = ball. Split is CLIP-AWARE (never leak frames of one clip across splits):
  - holdout: the frozen eval clips (IMG_8751-54 + any id in --holdout) — never trained on.
  - val: ~12% of the remaining clips (round-robin by camera_class for balance).
  - train: the rest.

  python -m ops.make_dataset --roots <ds>/auto <ds>/zeroshot --out <ds>/splits [--holdout IMG_8751,...]
"""
from __future__ import annotations
import argparse, json, os, collections


def load_rows(root):
    mpath = os.path.join(root, 'manifest.jsonl')
    if not os.path.exists(mpath):
        return []
    rows = []
    for ln in open(mpath):
        e = json.loads(ln)
        lab = json.load(open(os.path.join(root, 'labels', e['label'])))
        b = lab.get('ball')
        if not b:
            continue
        rows.append({'img': os.path.join(root, 'frames', e['img']),
                     'w': lab.get('img_w'), 'h': lab.get('img_h'),
                     'boxes': [[b[0], b[1], b[2], b[3], 0]],
                     'landmarks': ({'foul': lab['foul'], 'left_edge': lab['left_edge'],
                                    'right_edge': lab['right_edge'], 'vp': lab['vp']}
                                   if lab.get('foul') and e.get('source') == 'auto' else None),
                     'clip': e['clip'], 'camera_class': e.get('camera_class'), 'source': e.get('source')})
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--roots', nargs='+', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--holdout', default='IMG_8751,IMG_8752,IMG_8753,IMG_8754,IMG_8964,IMG_8981')
    ap.add_argument('--val-frac', type=float, default=0.12)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    holdo = set(a.holdout.split(',')) if a.holdout else set()

    rows = []
    for r in a.roots:
        rows += load_rows(r)
    by_clip = collections.defaultdict(list)
    for row in rows:
        by_clip[row['clip']].append(row)
    clips = sorted(by_clip)
    # clip -> camera_class
    cc = {c: by_clip[c][0]['camera_class'] for c in clips}

    hold_clips = [c for c in clips if c in holdo]
    pool = [c for c in clips if c not in holdo]
    # round-robin val pick within each camera_class for balance
    by_cc = collections.defaultdict(list)
    for c in pool:
        by_cc[cc[c]].append(c)
    val_clips = []
    for klass, cs in by_cc.items():
        cs = sorted(cs)
        k = max(1, int(round(len(cs) * a.val_frac))) if len(cs) > 2 else 0
        val_clips += cs[:k]
    val_set = set(val_clips)
    train_clips = [c for c in pool if c not in val_set]

    def write(name, cl):
        n = 0
        with open(os.path.join(a.out, name + '.jsonl'), 'w') as f:
            for c in cl:
                for row in by_clip[c]:
                    f.write(json.dumps(row) + '\n'); n += 1
        return n

    nt = write('train', train_clips); nv = write('val', val_clips); nh = write('holdout', hold_clips)
    stats = {'train': {'clips': len(train_clips), 'frames': nt},
             'val': {'clips': len(val_clips), 'frames': nv},
             'holdout': {'clips': len(hold_clips), 'frames': nh, 'ids': hold_clips},
             'by_camera_class_train': dict(collections.Counter(cc[c] for c in train_clips)),
             'sources': dict(collections.Counter(r['source'] for r in rows)),
             'total_frames': len(rows)}
    json.dump(stats, open(os.path.join(a.out, 'stats.json'), 'w'), indent=1)
    print(json.dumps(stats, indent=1))


if __name__ == '__main__':
    main()
