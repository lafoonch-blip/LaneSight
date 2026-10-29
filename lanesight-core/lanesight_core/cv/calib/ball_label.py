"""Per-frame ball labeling for the CV accuracy eval set (DEC-094 §1).

Extends the calib labeling tool family (shares `view_to_image` / `image_to_view` and the same safeguards as
`label_tool.py`) with the ONE thing the landmark tool doesn't do: mark the ball's **center** and **contact
point** on frames sampled ~every 0.1 s along the full roll, so a tracker/detector can be scored against real
observations. Same rules as the landmark tool:

- Coordinates are ORIGINAL-frame pixels, never scaled-preview coords.
- A position is recorded only when the ball is actually visible. If it isn't, mark the frame `occluded` — never
  guess a position (an interpolated point is not a measurement; DEC-094 §2).

Writes `validation/cv_eval/labels/<id>.json` in the schema documented in `validation/cv_eval/README.md`.

GUI run (needs a display):
  python -m lanesight_core.cv.calib.ball_label CLIP --id IMG_8929 [--labels-dir validation/cv_eval/labels]
       [--step 0.1] [--t0 16.5 --t1 21.0]     # --t0/--t1 restrict sampling to the shot window (skip dead frames)
Keys: n/space +.1s · p -.1s · . +1s · , -1s (scrub past pre-shot frames fast) · clicks 1st=center 2nd=contact ·
      o occluded (ONLY for an in-roll frame where the ball is briefly hidden) · c clear this sample ·
      x clear every sample before here (wipe pre-shot frames you labeled by mistake) · s save · q save+quit.
      Events (stamp the current frame time; press again to clear): r=release · f=foul_cross · t=touchdown ·
      i=first_pin_contact — all shown on screen. b/a = type standing pins before/after in the terminal
      (e.g. "10" or "4 7"; blank = all down / strike). On start, prints which manifest clips are still unlabeled.
Only label frames from release to the pins. Frames before the ball is thrown are NOT part of the track — scrub
past them, don't mark them occluded. The live view redraws continuously, so a marker appears the instant you click.

The pure functions below (sampling + label I/O + upsert) carry the logic and are unit-tested headlessly; the GUI
loop is a thin shell over them.
"""
from __future__ import annotations
import json
import os
from pathlib import Path

# shared view<->image transform + safeguards from the landmark tool (same tool family, not a new one)
from .label_tool import view_to_image, image_to_view  # noqa: F401  (image_to_view used by the GUI)

SCHEMA_VERSION = 1


# ------------------------------------------------------------------ pure helpers (testable headless)

def sample_times(t0: float, t1: float, step_s: float = 0.1):
    """Sample times [t0, t1] every step_s, rounded to the step grid (stable keys). t1 inclusive within eps."""
    if step_s <= 0 or t1 < t0:
        return []
    n = int(round((t1 - t0) / step_s))
    return [round(t0 + i * step_s, 3) for i in range(n + 1)]


def empty_labels(clip: str, fps: float) -> dict:
    return {'schema': SCHEMA_VERSION, 'clip': clip, 'fps': fps,
            'events': {'foul_cross_s': None, 'first_pin_contact_s': None, 'release_s': None, 'touchdown_s': None},
            'pins_before': list(range(1, 11)), 'pins_after': None,
            'balls': [], 'ruby': None, 'reference': None}


def _key(t: float) -> float:
    return round(float(t), 3)


def find_ball(labels: dict, t: float):
    """The ball sample at time t (within half a millisecond), or None."""
    for b in labels.get('balls', []):
        if abs(b.get('t', -1) - _key(t)) < 5e-4:
            return b
    return None


def upsert_ball(labels: dict, t: float, center=None, contact=None, occluded: bool = False) -> dict:
    """Set/replace the ball sample at time t. An occluded frame stores no position (center/contact forced None)
    — never guess a hidden ball. Returns the sample dict. Keeps `balls` sorted by time."""
    if occluded:
        center = contact = None
    b = find_ball(labels, t)
    if b is None:
        b = {'t': _key(t)}
        labels.setdefault('balls', []).append(b)
    b['center'] = (list(center) if center is not None else None)
    b['contact'] = (list(contact) if contact is not None else None)
    b['occluded'] = bool(occluded)
    labels['balls'].sort(key=lambda s: s['t'])
    return b


def clear_ball(labels: dict, t: float) -> None:
    labels['balls'] = [b for b in labels.get('balls', []) if abs(b.get('t', -1) - _key(t)) >= 5e-4]


def clear_before(labels: dict, t: float) -> int:
    """Drop every ball sample strictly before time t — the pre-shot frames that aren't part of the roll and
    should never have been labeled. Returns how many were removed."""
    balls = labels.get('balls', [])
    kept = [b for b in balls if b.get('t', 0) >= _key(t) - 5e-4]
    labels['balls'] = kept
    return len(balls) - len(kept)


def observed_count(labels: dict) -> int:
    """How many samples have a real (non-occluded) center — the ground-truth observation count."""
    return sum(1 for b in labels.get('balls', []) if not b.get('occluded') and b.get('center') is not None)


# event hotkey -> events-dict key (stamped from the current frame time while scrubbing)
EVENT_KEYS = {'r': 'release_s', 'f': 'foul_cross_s', 't': 'touchdown_s', 'i': 'first_pin_contact_s'}


def set_event(labels: dict, event_key: str, t: float):
    """Stamp an event at time t (rounded to the sample grid). Pressing again on the same frame CLEARS it
    (toggle), so a mis-stamp is easy to undo. Returns the new value (float or None)."""
    ev = labels.setdefault('events', {})
    cur = ev.get(event_key)
    ev[event_key] = None if (cur is not None and abs(cur - _key(t)) < 5e-4) else _key(t)
    return ev[event_key]


def parse_pins(s):
    """Parse a standing-pins string into a sorted unique list of 1..10: '10' -> [10], '4 7'/'4,7' -> [4, 7],
    blank -> [] (all down / strike). Returns None if any token is invalid, so the caller keeps the old value."""
    s = (s or '').strip()
    if not s:
        return []                                    # blank = nothing standing = all down
    out = set()
    for tok in s.replace(',', ' ').split():
        if not tok.isdigit() or not (1 <= int(tok) <= 10):
            return None
        out.add(int(tok))
    return sorted(out)


def unlabeled_clips(manifest: dict, labels_dir) -> list:
    """Manifest clip ids (`Path(clip).stem`) with no usable label yet — no file, or a file with 0 observed
    ball samples. Returned in manifest order, so the labeler can print what's left to do at startup."""
    out = []
    for entry in (manifest.get('clips') or []):
        sid = Path(str(entry.get('clip') or '')).stem
        lab = load(labels_dir, sid)
        if lab is None or observed_count(lab) == 0:
            out.append(sid)
    return out


def _load_manifest(manifest_path):
    try:
        return json.load(open(manifest_path))
    except Exception:
        return {'clips': []}


def label_path(labels_dir, shot_id: str) -> Path:
    return Path(labels_dir) / f"{shot_id}.json"


def load(labels_dir, shot_id: str):
    p = label_path(labels_dir, shot_id)
    return json.load(open(p)) if p.exists() else None


def save(labels_dir, shot_id: str, labels: dict) -> str:
    os.makedirs(labels_dir, exist_ok=True)
    p = label_path(labels_dir, shot_id)
    json.dump(labels, open(p, 'w'), indent=2)
    return str(p)


# ------------------------------------------------------------------ GUI (needs a display)

def run(clip, shot_id, labels_dir='validation/cv_eval/labels', step_s=0.1, t0=None, t1=None):  # pragma: no cover
    """cv2 HighGUI scrub-and-click labeler. Thin shell over the pure helpers above; needs a display."""
    import cv2
    cap = cv2.VideoCapture(clip)
    fps = cap.get(cv2.CAP_PROP_FPS) or 60.0
    dur = (cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0) / fps
    t0 = 0.0 if t0 is None else t0
    t1 = dur if t1 is None else t1
    times = sample_times(t0, min(t1, dur), step_s)
    labels = load(labels_dir, shot_id) or empty_labels(os.path.basename(clip), fps)
    view = {'ox': 0.0, 'oy': 0.0, 'zoom': 1.0}
    jump = max(1, int(round(1.0 / step_s)))            # ~1 s in samples, for skipping dead pre-shot frames fast
    state = {'i': 0, 'click': 'center'}
    cache = {'i': -1, 'img': None}                     # decode a frame only when the sample changes (live redraw)

    def on_mouse(event, x, y, flags, _):
        if event != cv2.EVENT_LBUTTONDOWN:
            return
        ix, iy = view_to_image(x, y, view)
        t = times[state['i']]
        b = find_ball(labels, t) or {}
        center, contact = b.get('center'), b.get('contact')
        if state['click'] == 'center':
            center = (ix, iy); state['click'] = 'contact'
        else:
            contact = (ix, iy); state['click'] = 'center'
        upsert_ball(labels, t, center=center, contact=contact, occluded=False)

    cv2.namedWindow('ball'); cv2.setMouseCallback('ball', on_mouse)
    HELP = ["click: 1st=center 2nd=contact (only where the ball is visible)",
            "n/space +.1s  p -.1s  . +1s  , -1s   |   o occluded(in-roll only)  c clear  x clear-all-before",
            "events (stamp THIS frame, press again to clear): r release  f foul-cross  t touchdown  i first-pin-contact",
            "b / a = type standing pins before / after (terminal)   |   s save   q save+quit  (don't mark pre-shot frames)"]
    while True:
        i = state['i']; t = times[i]
        if cache['i'] != i:                            # (re)decode only on move -> clicks redraw instantly
            cap.set(cv2.CAP_PROP_POS_MSEC, t * 1000.0)
            ok, f = cap.read(); cache.update(i=i, img=f if ok else None)
        if cache['img'] is not None:
            frame = cache['img'].copy()
            b = find_ball(labels, t)
            if b and b.get('center'):
                cv2.circle(frame, tuple(int(v) for v in b['center']), 12, (0, 255, 0), 2)
                cv2.drawMarker(frame, tuple(int(v) for v in b['center']), (0, 255, 0), cv2.MARKER_CROSS, 18, 1)
            if b and b.get('contact'):
                cv2.circle(frame, tuple(int(v) for v in b['contact']), 6, (0, 200, 255), 2)
            tag = 'OCCLUDED' if (b and b.get('occluded')) else f"obs {observed_count(labels)}"
            cv2.putText(frame, f"{shot_id} t={t:.2f}s [{i+1}/{len(times)}] next-click={state['click']} {tag}",
                        (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0) if (b and b.get('center')) else (255, 255, 255), 2)
            for j, line in enumerate(HELP):
                cv2.putText(frame, line, (20, 72 + 26 * j), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (200, 200, 200), 1)
            ev = labels.get('events', {})
            es = lambda k: (f"{ev.get(k):.2f}" if ev.get(k) is not None else "—")
            estr = (f"R release {es('release_s')}   F foul {es('foul_cross_s')}   "
                    f"T touchdown {es('touchdown_s')}   I pin-contact {es('first_pin_contact_s')}")
            pins_after = labels.get('pins_after')
            pstr = (f"pins: before {labels.get('pins_before')}  after "
                    f"{'(not set)' if pins_after is None else (pins_after if pins_after else 'STRIKE')}")
            y0 = 72 + 26 * len(HELP)
            cv2.putText(frame, estr, (20, y0), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (120, 220, 255), 1)
            cv2.putText(frame, pstr, (20, y0 + 26), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (120, 220, 255), 1)
            cv2.imshow('ball', frame)
        k = cv2.waitKey(20) & 0xFF                     # live loop: redraw ~50fps so a click's marker shows at once
        if k == 255:
            continue
        if k in (ord('q'), 27):
            break
        elif k in (ord('n'), ord(' ')):
            state['i'] = min(i + 1, len(times) - 1); state['click'] = 'center'
        elif k == ord('p'):
            state['i'] = max(i - 1, 0); state['click'] = 'center'
        elif k == ord('.'):
            state['i'] = min(i + jump, len(times) - 1); state['click'] = 'center'
        elif k == ord(','):
            state['i'] = max(i - jump, 0); state['click'] = 'center'
        elif k == ord('o'):
            cur = find_ball(labels, t)
            upsert_ball(labels, t, occluded=not (cur and cur.get('occluded')))
        elif k == ord('c'):
            clear_ball(labels, t); state['click'] = 'center'
        elif k == ord('x'):
            n = clear_before(labels, t); print(f"cleared {n} pre-shot sample(s) before {t:.2f}s")
        elif 0 <= k < 128 and chr(k) in EVENT_KEYS:    # r/f/t/i: stamp current frame time as an event (toggle)
            ek = EVENT_KEYS[chr(k)]
            v = set_event(labels, ek, t)
            print(f"{ek} {'= %.2fs' % v if v is not None else 'cleared'}")
        elif k in (ord('b'), ord('a')):                # type standing pins before/after in the terminal
            which = 'pins_before' if k == ord('b') else 'pins_after'
            raw = input(f"standing pins {which.split('_')[1].upper()} (e.g. '10' or '4 7', blank = all down): ")
            pins = parse_pins(raw)
            if pins is None:
                print(f"  invalid pins — keeping {labels.get(which)}")
            else:
                labels[which] = pins
                print(f"  {which} = {pins if pins else 'all down (strike)'}")
        elif k == ord('s'):
            print('saved', save(labels_dir, shot_id, labels))
    save(labels_dir, shot_id, labels)
    cap.release(); cv2.destroyAllWindows()


def _main():  # pragma: no cover
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('clip')
    ap.add_argument('--id', required=True)
    ap.add_argument('--labels-dir', default='validation/cv_eval/labels')
    ap.add_argument('--manifest', default='validation/cv_eval/manifest.json')
    ap.add_argument('--step', type=float, default=0.1)
    ap.add_argument('--t0', type=float, default=None)
    ap.add_argument('--t1', type=float, default=None)
    a = ap.parse_args()
    todo = unlabeled_clips(_load_manifest(a.manifest), a.labels_dir)
    print(f"unlabeled manifest clips ({len(todo)}): {', '.join(todo)}" if todo
          else "all manifest clips have labels.")
    run(a.clip, a.id, a.labels_dir, a.step, a.t0, a.t1)


if __name__ == '__main__':  # pragma: no cover
    _main()
