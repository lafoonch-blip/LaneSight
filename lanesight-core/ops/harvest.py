#!/usr/bin/env python3
"""DEC-130 dataset harvest — drive auto-labels (source #1) + zero-shot (source #2) across the eval manifest,
into one detector dataset. Clip paths come from manifest_all.json (clip = path under --data-root).

  python -m ops.harvest --mode auto   --split <baseline_full_split.json> --out <dataset>/auto
  python -m ops.harvest --mode zeroshot --split <...> --out <dataset>/zeroshot

'auto' harvests the clips the engine tracks (full frames+labels, strided); 'zeroshot' harvests the failing clips
(OWLv2 + motion gating). Writes frames/<clip>__<i>.jpg + labels/<clip>__<i>.json and a manifest.jsonl index.
"""
from __future__ import annotations
import argparse, json, os, traceback


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--mode', choices=['auto', 'zeroshot'], required=True)
    ap.add_argument('--split', required=True, help='baseline_full_split.json (good/zero lists)')
    ap.add_argument('--manifest', default='validation/cv_eval/manifest_all.json')
    ap.add_argument('--data-root', default=os.path.expanduser('~/LaneSightData'))
    ap.add_argument('--out', required=True)
    ap.add_argument('--stride', type=int, default=3)      # auto: every 3rd tracked frame
    ap.add_argument('--max-frames', type=int, default=60)
    ap.add_argument('--n', type=int, default=40)          # zeroshot: frames to sample
    ap.add_argument('--limit', type=int, default=None)
    a = ap.parse_args()

    split = json.load(open(a.split))
    man = {c['id']: c for c in json.load(open(a.manifest))['clips']}
    ids = split['good'] if a.mode == 'auto' else split['zero']
    if a.limit:
        ids = ids[:a.limit]
    os.makedirs(a.out, exist_ok=True)
    fr_dir, lb_dir = os.path.join(a.out, 'frames'), os.path.join(a.out, 'labels')
    os.makedirs(fr_dir, exist_ok=True); os.makedirs(lb_dir, exist_ok=True)
    index = open(os.path.join(a.out, 'manifest.jsonl'), 'a')

    import cv2
    if a.mode == 'auto':
        from ops.autolabel import extract
    else:
        from ops.zeroshot_label import run as zrun

    ok = fail = nframes = 0
    for cid in ids:
        entry = man.get(cid)
        if not entry:
            print(f'{cid}: not in manifest', flush=True); continue
        clip = os.path.join(a.data_root, entry['clip'])
        if not os.path.exists(clip):
            print(f'{cid}: missing {clip}', flush=True); continue
        try:
            import tempfile
            with tempfile.TemporaryDirectory() as td:
                if a.mode == 'auto':
                    saved = extract(clip, cid, td, stride=a.stride, max_frames=a.max_frames, audit_only=False)
                    for (i, img, lab) in saved:
                        base = f'{cid}__{i}'
                        cv2.imwrite(os.path.join(fr_dir, base + '.jpg'), img, [cv2.IMWRITE_JPEG_QUALITY, 90])
                        lab2 = dict(lab, clip=cid, camera_class=entry.get('camera_class'), source='auto')
                        json.dump(lab2, open(os.path.join(lb_dir, base + '.json'), 'w'))
                        index.write(json.dumps({'img': base + '.jpg', 'label': base + '.json',
                                                'clip': cid, 'camera_class': entry.get('camera_class'),
                                                'source': 'auto'}) + '\n')
                        nframes += 1
                else:
                    saved, _nf = zrun(clip, cid, td, n=a.n, thr=0.10, audit_only=False)
                    for (i, img, lab) in saved:
                        base = f'{cid}__{i}'
                        cv2.imwrite(os.path.join(fr_dir, base + '.jpg'), img, [cv2.IMWRITE_JPEG_QUALITY, 90])
                        lab2 = dict(lab, clip=cid, camera_class=entry.get('camera_class'), source='zeroshot')
                        json.dump(lab2, open(os.path.join(lb_dir, base + '.json'), 'w'))
                        index.write(json.dumps({'img': base + '.jpg', 'label': base + '.json',
                                                'clip': cid, 'camera_class': entry.get('camera_class'),
                                                'source': 'zeroshot'}) + '\n')
                        nframes += 1
            index.flush()
            ok += 1
            print(f'{cid}: OK ({a.mode}) total_frames={nframes}', flush=True)
        except Exception as e:
            fail += 1
            print(f'{cid}: FAILED {type(e).__name__}: {e}', flush=True)
            traceback.print_exc()
    index.close()
    print(f'\nHARVEST {a.mode} DONE: {ok} clips ok, {fail} failed, {nframes} frames -> {a.out}', flush=True)


if __name__ == '__main__':
    main()
