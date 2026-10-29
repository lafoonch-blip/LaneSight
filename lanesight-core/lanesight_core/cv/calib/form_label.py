"""Form (approach/swing) event labeling for the CV accuracy eval set — DEC-094 Form Gate A.

Sibling of `ball_label.py`: reuses its scrub + event-stamp + label-I/O primitives, but instead of a ball track
it stamps the five swing/approach event TIMES the Form engine must hit. **Gate A for Form = the engine's
detected event times vs these labels.** No clicking — scrub to each moment and press its number key.

GUI run (needs a display):
  python -m lanesight_core.cv.calib.form_label CLIP --id IMG_8846 [--labels-dir validation/cv_eval/labels]
       [--step 0.05] [--t0 .. --t1 ..]
Event keys (stamp the current frame time; press again to clear):
  1 ball_start · 2 pushaway_end · 3 top_of_swing · 4 slide_stop · 5 release  (all shown on screen)
Nav: n/space +step · p -step · . +1s · , -1s   |   s save · q save+quit.  On start, prints unlabeled FORM clips.

Pure helpers (empty_form_labels / form_event_count / unlabeled_form_clips) are unit-tested headlessly; the GUI
is a thin shell over them and over ball_label's shared primitives.
"""
from __future__ import annotations
from pathlib import Path

from . import ball_label as bl   # shared: sample_times, set_event, save/load, label_path, _load_manifest

SCHEMA_VERSION = 1

# number-key -> events-dict key, in swing order (so pressing 1..5 walks the approach)
FORM_EVENTS = [('1', 'ball_start_s'), ('2', 'pushaway_end_s'), ('3', 'top_of_swing_s'),
               ('4', 'slide_stop_s'), ('5', 'release_s')]
FORM_EVENT_KEYS = {k: v for k, v in FORM_EVENTS}


def empty_form_labels(clip: str, fps: float) -> dict:
    return {'schema': SCHEMA_VERSION, 'clip': clip, 'fps': fps, 'mode': 'form',
            'events': {v: None for _, v in FORM_EVENTS}, 'view': None, 'step_count': None, 'reference': None}


def form_event_count(labels: dict) -> int:
    """How many of the five swing events have a stamped time."""
    return sum(1 for v in (labels.get('events') or {}).values() if v is not None)


def unlabeled_form_clips(manifest: dict, labels_dir) -> list:
    """Manifest clips marked mode=='form' with no usable label yet (no file, or 0 stamped events). Order kept."""
    out = []
    for entry in (manifest.get('clips') or []):
        if entry.get('mode') != 'form':
            continue
        sid = Path(str(entry.get('clip') or '')).stem
        lab = bl.load(labels_dir, sid)
        if lab is None or form_event_count(lab) == 0:
            out.append(sid)
    return out


# ------------------------------------------------------------------ GUI (needs a display)

def run(clip, shot_id, labels_dir='validation/cv_eval/labels', step_s=0.05, t0=None, t1=None):  # pragma: no cover
    import cv2
    cap = cv2.VideoCapture(clip)
    fps = cap.get(cv2.CAP_PROP_FPS) or 60.0
    dur = (cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0) / fps
    t0 = 0.0 if t0 is None else t0
    t1 = dur if t1 is None else t1
    times = bl.sample_times(t0, min(t1, dur), step_s)
    labels = bl.load(labels_dir, shot_id) or empty_form_labels(__import__('os').path.basename(clip), fps)
    labels.setdefault('mode', 'form')
    labels.setdefault('events', {v: None for _, v in FORM_EVENTS})
    state = {'i': 0}
    cache = {'i': -1, 'img': None}
    jump = max(1, int(round(1.0 / step_s)))
    cv2.namedWindow('form')
    HELP = ["Form events — stamp THIS frame, press again to clear:",
            "1 ball_start  2 pushaway_end  3 top_of_swing  4 slide_stop  5 release",
            "n/space +step  p -step  . +1s  , -1s   |   s save   q save+quit"]
    while True:
        i = state['i']; t = times[i]
        if cache['i'] != i:
            cap.set(cv2.CAP_PROP_POS_MSEC, t * 1000.0)
            ok, f = cap.read(); cache.update(i=i, img=f if ok else None)
        if cache['img'] is not None:
            frame = cache['img'].copy()
            ev = labels['events']
            es = lambda v: (f"{ev.get(v):.2f}" if ev.get(v) is not None else "—")
            cv2.putText(frame, f"{shot_id} t={t:.2f}s [{i+1}/{len(times)}]  stamped {form_event_count(labels)}/5",
                        (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
            for j, line in enumerate(HELP):
                cv2.putText(frame, line, (20, 72 + 26 * j), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (200, 200, 200), 1)
            summ = "   ".join(f"{k} {name.replace('_s', '')} {es(name)}" for k, name in FORM_EVENTS)
            cv2.putText(frame, summ, (20, 72 + 26 * len(HELP)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (120, 220, 255), 1)
            cv2.imshow('form', frame)
        k = cv2.waitKey(20) & 0xFF
        if k == 255:
            continue
        if k in (ord('q'), 27):
            break
        elif k in (ord('n'), ord(' ')):
            state['i'] = min(i + 1, len(times) - 1)
        elif k == ord('p'):
            state['i'] = max(i - 1, 0)
        elif k == ord('.'):
            state['i'] = min(i + jump, len(times) - 1)
        elif k == ord(','):
            state['i'] = max(i - jump, 0)
        elif 0 <= k < 128 and chr(k) in FORM_EVENT_KEYS:
            name = FORM_EVENT_KEYS[chr(k)]
            v = bl.set_event(labels, name, t)
            print(f"{name} {'= %.2fs' % v if v is not None else 'cleared'}")
        elif k == ord('s'):
            print('saved', bl.save(labels_dir, shot_id, labels))
    bl.save(labels_dir, shot_id, labels)
    cap.release(); cv2.destroyAllWindows()


def _main():  # pragma: no cover
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('clip')
    ap.add_argument('--id', required=True)
    ap.add_argument('--labels-dir', default='validation/cv_eval/labels')
    ap.add_argument('--manifest', default='validation/cv_eval/manifest.json')
    ap.add_argument('--step', type=float, default=0.05)
    ap.add_argument('--t0', type=float, default=None)
    ap.add_argument('--t1', type=float, default=None)
    a = ap.parse_args()
    todo = unlabeled_form_clips(bl._load_manifest(a.manifest), a.labels_dir)
    print(f"unlabeled FORM clips ({len(todo)}): {', '.join(todo)}" if todo else "all FORM clips have labels.")
    run(a.clip, a.id, a.labels_dir, a.step, a.t0, a.t1)


if __name__ == '__main__':  # pragma: no cover
    _main()
