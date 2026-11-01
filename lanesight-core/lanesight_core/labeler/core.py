"""Tasks, clip lookup, frame decoding and label storage for the LaneSight Labeler (no web code here).

Task file (validation/label_tasks/<id>.json):
{
  "id": "pin_anchor_truth",                       # optional; defaults to the file name
  "title": "Pin anchor: foul line + pin contact",
  "instructions": "Shown at the top of the page.",
  "clips": [ {"id": "IMG_8751", "hints": {"foul_cross": 1601}, "static": {"view": "side"}}, "IMG_8752", ... ],
  "events": [ {"id": "foul_cross", "label": "Ball crosses the foul line", "help": "...",
               "export_key": "foul_cross_frame", "export_unit": "frame"}, ... ],        # export_unit: frame|seconds
  "fields": [ {"id": "step_count", "label": "Approach steps", "type": "int", "export_key": "step_count"} ],
  "export": {"path": "lanesight-core/validation/form_labels.json", "wrap": "clips", "add_fps": true}   # optional
}
Labels file (validation/labels/<id>.json):
{ "task": id, "updated_at": iso, "clips": { clip: { "events": {ev: {"frame": int|null, "t_s": float|null,
  "status": "set"|"not_visible"}}, "fields": {f: value}, "fps": float, "done": bool } } }
"""
from __future__ import annotations

import datetime as _dt
import glob
import json
import os
import tempfile
import threading
from collections import OrderedDict

VIDEO_EXT = ('.mov', '.mp4', '.m4v')
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
CORE_ROOT = os.path.join(REPO_ROOT, 'lanesight-core')
TASK_DIR = os.path.join(CORE_ROOT, 'validation', 'label_tasks')
LABEL_DIR = os.path.join(CORE_ROOT, 'validation', 'labels')
DEFAULT_SEARCH = [os.path.expanduser('~/LaneSightData')]


# ---------------------------------------------------------------- tasks
def _norm_clip(c):
    if isinstance(c, str):
        return {'id': c, 'hints': {}, 'static': {}}
    return {'id': c['id'], 'hints': c.get('hints') or {}, 'static': c.get('static') or {}}


def load_task(path):
    with open(path) as f:
        t = json.load(f)
    t.setdefault('id', os.path.splitext(os.path.basename(path))[0])
    t.setdefault('title', t['id'])
    t.setdefault('instructions', '')
    t['clips'] = [_norm_clip(c) for c in t.get('clips', [])]
    t['events'] = [dict(e) for e in t.get('events', [])]
    for e in t['events']:
        e.setdefault('label', e['id']); e.setdefault('help', '')
    t['fields'] = [dict(x) for x in t.get('fields', [])]
    for x in t['fields']:
        x.setdefault('label', x['id']); x.setdefault('type', 'text')
    t['_path'] = path
    return t


def load_tasks(task_dir=TASK_DIR):
    out = OrderedDict()
    for p in sorted(glob.glob(os.path.join(task_dir, '*.json'))):
        try:
            t = load_task(p)
        except (ValueError, KeyError) as e:          # a broken task file shouldn't take the app down
            t = {'id': os.path.basename(p), 'title': os.path.basename(p), 'error': str(e), 'clips': [],
                 'events': [], 'fields': [], 'instructions': '', '_path': p}
        out[t['id']] = t
    return out


# ---------------------------------------------------------------- clip lookup
class ClipFinder:
    """Find a clip file by its id (file stem, case-insensitive) anywhere under the search roots, including
    sub-folders with spaces (e.g. 'training_videos/form videos'). Rebuilds its index when a clip is missing."""

    def __init__(self, roots=None):
        self.roots = [os.path.expanduser(r) for r in (roots or DEFAULT_SEARCH)]
        self._index = None
        self._lock = threading.Lock()

    def _build(self):
        idx = {}
        for root in self.roots:
            for dirpath, dirnames, files in os.walk(root):
                dirnames[:] = [d for d in dirnames if not d.startswith('.') and not d.startswith('_')]
                for fn in files:
                    stem, ext = os.path.splitext(fn)
                    if ext.lower() in VIDEO_EXT:
                        idx.setdefault(stem.lower(), os.path.join(dirpath, fn))   # first hit wins
        return idx

    def find(self, clip_id):
        with self._lock:
            if self._index is None or clip_id.lower() not in self._index:
                self._index = self._build()
            return self._index.get(clip_id.lower())


# ---------------------------------------------------------------- frames
class FrameSource:
    """Exact-index frame access for one clip. Frames are numbered 0..n-1 in decode order — the same numbering
    the pipeline uses (sequential decode). Sequential reads are cached, so stepping ±1 and playback are
    instant; a big jump re-seeks a little before the target and reads forward."""

    def __init__(self, path, cache_frames=240):
        import cv2
        self.cv2 = cv2
        self.path = path
        self.cap = cv2.VideoCapture(path)
        if not self.cap.isOpened():
            raise IOError(f'cannot open video: {path}')
        self.fps = float(self.cap.get(cv2.CAP_PROP_FPS) or 0.0)
        self.n = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        self.pos = 0                       # index of the next frame cap.read() returns
        self.cache = OrderedDict()         # idx -> (jpeg bytes, pts seconds, w, h)
        self.cache_frames = cache_frames
        self.lock = threading.Lock()
        self._verify = False
        self.seek_fallbacks = 0
        self.pts0 = None
        ok, frame = self.cap.read()        # learn the first frame's timestamp (and cache frame 0)
        if ok:
            self.pts0 = self.cap.get(cv2.CAP_PROP_POS_MSEC) / 1000.0
            self._store(0, frame, round(self.pts0, 4))
            self.pos = 1

    def _store(self, idx, frame, pts):
        ok, buf = self.cv2.imencode('.jpg', frame, [self.cv2.IMWRITE_JPEG_QUALITY, 88])
        h, w = frame.shape[:2]
        self.cache[idx] = (buf.tobytes(), pts, w, h)
        self.cache.move_to_end(idx)
        while len(self.cache) > self.cache_frames:
            self.cache.popitem(last=False)

    def _reopen_at(self, start):
        cv2 = self.cv2
        if start <= 0:
            self.cap.release(); self.cap = cv2.VideoCapture(self.path); self.pos = 0
            return
        self.cap.set(cv2.CAP_PROP_POS_FRAMES, start)
        got = int(round(self.cap.get(cv2.CAP_PROP_POS_FRAMES)))
        if got != start:                    # seek not exact on this codec: fall back to decoding from 0
            self.cap.release(); self.cap = cv2.VideoCapture(self.path); self.pos = 0
        else:
            self.pos = start
            self._verify = True             # check the first frame's timestamp after this seek

    def _seek_landed_right(self, pts):
        """A seek can report the requested index yet land elsewhere (long-GOP HEVC). The decoded frame's
        timestamp must match the requested index (within half a frame); otherwise decode from 0 instead."""
        if not self.fps or self.pts0 is None:
            return True
        return abs((pts - self.pts0) * self.fps - self.pos) < 0.5

    def get(self, idx, lookahead=12):
        """JPEG bytes + metadata for frame idx (clamped to the clip). Reads a few frames ahead for smooth stepping."""
        cv2 = self.cv2
        with self.lock:
            if self.n:
                idx = max(0, min(idx, self.n - 1))
            if idx in self.cache:
                self.cache.move_to_end(idx)
                jpg, pts, w, h = self.cache[idx]
                return {'jpeg': jpg, 'index': idx, 'pts': pts, 'w': w, 'h': h}
            if idx < self.pos or idx - self.pos > 150:
                self._reopen_at(max(0, idx - 30))
            want = idx + lookahead
            while self.pos <= want:
                ok, frame = self.cap.read()
                if not ok:
                    if self.n == 0 or self.pos < self.n:
                        self.n = self.pos   # real end of stream
                    break
                pts = self.cap.get(cv2.CAP_PROP_POS_MSEC) / 1000.0   # timestamp of the frame just read
                if self.pos == 0 and self.pts0 is None:
                    self.pts0 = pts
                if self._verify:
                    self._verify = False
                    if not self._seek_landed_right(pts):
                        self.cap.release(); self.cap = cv2.VideoCapture(self.path); self.pos = 0
                        self.seek_fallbacks += 1
                        continue
                self._store(self.pos, frame, round(pts, 4))
                self.pos += 1
            if idx in self.cache:
                jpg, pts, w, h = self.cache[idx]
                return {'jpeg': jpg, 'index': idx, 'pts': pts, 'w': w, 'h': h}
            if self.n and idx >= self.n:
                return self.get(self.n - 1, lookahead=0)
            raise IOError(f'frame {idx} not decodable in {self.path}')

    def close(self):
        with self.lock:
            self.cap.release()


class FramePool:
    """Keeps a few clips open (LRU) so switching between clips stays fast."""

    def __init__(self, keep=4):
        self.keep = keep
        self.open = OrderedDict()
        self.lock = threading.Lock()

    def source(self, path):
        with self.lock:
            if path in self.open:
                self.open.move_to_end(path)
                return self.open[path]
            src = FrameSource(path)
            self.open[path] = src
            while len(self.open) > self.keep:
                _, old = self.open.popitem(last=False)
                old.close()
            return src


# ---------------------------------------------------------------- labels
def _now():
    return _dt.datetime.now().astimezone().isoformat(timespec='seconds')


def _atomic_write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix='.tmp')
    with os.fdopen(fd, 'w') as f:
        json.dump(obj, f, indent=2)
        f.write('\n')
    os.replace(tmp, path)


class LabelStore:
    def __init__(self, label_dir=LABEL_DIR, repo_root=REPO_ROOT):
        self.label_dir = label_dir
        self.repo_root = repo_root
        self.lock = threading.Lock()

    def path(self, task_id):
        return os.path.join(self.label_dir, f'{task_id}.json')

    def load(self, task_id):
        p = self.path(task_id)
        if os.path.exists(p):
            with open(p) as f:
                return json.load(f)
        return {'task': task_id, 'updated_at': None, 'clips': {}}

    @staticmethod
    def _clip(data, clip_id):
        return data['clips'].setdefault(clip_id, {'events': {}, 'fields': {}, 'done': False})

    def update(self, task, clip_id, change, fps=None):
        """change: {"event": id, "frame": int|None, "status": "set"|"not_visible"|"clear"}
                 | {"field": id, "value": any} | {"done": bool}"""
        with self.lock:
            data = self.load(task['id'])
            c = self._clip(data, clip_id)
            if fps:
                c['fps'] = fps
            if 'event' in change:
                ev = change['event']
                if ev not in {e['id'] for e in task['events']}:
                    raise ValueError(f'unknown event {ev}')
                st = change.get('status', 'set')
                if st == 'clear':
                    c['events'].pop(ev, None)
                elif st == 'not_visible':
                    c['events'][ev] = {'frame': None, 't_s': None, 'status': 'not_visible'}
                elif st == 'set':
                    fr = int(change['frame'])
                    if fr < 0:
                        raise ValueError('frame must be >= 0')
                    f = c.get('fps') or fps
                    c['events'][ev] = {'frame': fr, 't_s': round(fr / f, 4) if f else None, 'status': 'set'}
                else:
                    raise ValueError(f'bad status {st}')
            elif 'field' in change:
                fld = next((x for x in task['fields'] if x['id'] == change['field']), None)
                if fld is None:
                    raise ValueError(f"unknown field {change['field']}")
                v = change.get('value')
                if v in ('', None):
                    c['fields'].pop(fld['id'], None)
                else:
                    if fld['type'] == 'int':
                        v = int(v)
                    elif fld['type'] == 'float':
                        v = float(v)
                    c['fields'][fld['id']] = v
            elif 'done' in change:
                c['done'] = bool(change['done'])
            else:
                raise ValueError('nothing to change')
            c['complete'] = clip_complete(task, c)
            data['updated_at'] = _now()
            _atomic_write(self.path(task['id']), data)
            self._export(task, data)
            return data

    def _export(self, task, data):
        ex = task.get('export')
        if not ex or not ex.get('path'):
            return
        out = {}
        for clip in task['clips']:
            cid = clip['id']
            c = data['clips'].get(cid, {})
            row = dict(clip.get('static') or {})
            for e in task['events']:
                key = e.get('export_key') or e['id']
                v = (c.get('events') or {}).get(e['id'])
                if not v or v.get('status') != 'set':
                    row[key] = None
                elif e.get('export_unit') == 'seconds':
                    row[key] = v.get('t_s')
                else:
                    row[key] = v.get('frame')
            for x in task['fields']:
                row[x.get('export_key') or x['id']] = (c.get('fields') or {}).get(x['id'])
            if ex.get('add_fps'):
                row['fps'] = c.get('fps')
            out[cid] = row
        doc = {ex['wrap']: out} if ex.get('wrap') else out
        doc = {'_source': f"LaneSight Labeler task '{task['id']}' ({os.path.relpath(self.path(task['id']), self.repo_root)}); "
                          f"null = not labeled or not visible", **doc}
        _atomic_write(os.path.join(self.repo_root, ex['path']), doc)


def clip_complete(task, c):
    """A clip is complete when every event is set or marked not visible and every required field has a value
    (or the labeler explicitly marked the clip done)."""
    if c.get('done'):
        return True
    evs = c.get('events') or {}
    if any(e['id'] not in evs for e in task['events']):
        return False
    flds = c.get('fields') or {}
    return all(x['id'] in flds for x in task['fields'] if x.get('required'))


def task_progress(task, data):
    done = sum(1 for cl in task['clips'] if clip_complete(task, (data['clips'].get(cl['id']) or {})))
    return done, len(task['clips'])
