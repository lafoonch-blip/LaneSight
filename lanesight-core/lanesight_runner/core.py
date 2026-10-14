"""Runner core: watch folder -> copy -> probe -> lanesight-core analysis -> store -> notify + speak.
One clip is analyzed at a time; clips that arrive meanwhile wait in the queue."""
from __future__ import annotations
import json, os, queue, shutil, subprocess, threading, time, traceback
from .db import DB, now
from .probe import probe, convert_sdr, ClipError, VIDEO_EXT
from . import card as cardmod

def default_analyzer(video, out_prefix, handed=None, log=print, timing_video=None):
    """Real analysis: lanesight-core pipeline. Returns the JSON-safe ShotRecord dict."""
    from lanesight_core.cv.pipeline import analyze, _json_default
    rec = analyze(video, out_prefix, handed=handed, log=log, timing_video=timing_video)
    return json.loads(json.dumps(rec.to_dict(), default=_json_default))

class Speaker:
    def __init__(self, enabled=True):
        self.cmd = shutil.which('say'); self.enabled = enabled and self.cmd is not None
    def say(self, text):
        if self.enabled and text:
            subprocess.Popen([self.cmd, text], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

class Runner:
    def __init__(self, data_dir, watch_dir=None, analyzer=default_analyzer, speaker=None, check_decoder=True,
                 stable_s=2.0, poll_s=1.0):
        self.data_dir = os.path.abspath(os.path.expanduser(data_dir)); os.makedirs(self.data_dir, exist_ok=True)
        self.watch_dir = os.path.abspath(os.path.expanduser(watch_dir)) if watch_dir else None
        self.db = DB(os.path.join(self.data_dir, 'lanesight_runner.db'))
        self.analyzer, self.speaker, self.check_decoder = analyzer, speaker or Speaker(), check_decoder
        self.stable_s, self.poll_s = stable_s, poll_s
        self.q: queue.Queue[int] = queue.Queue()
        self.version = 0; self.cv = threading.Condition()
        self._seen: set = set(); self._pending: dict = {}
        self._stop = threading.Event()
        self.watch_error = None

    # notifications
    def bump(self):
        with self.cv:
            self.version += 1; self.cv.notify_all()

    def wait_version(self, v, timeout=15.0):
        with self.cv:
            self.cv.wait_for(lambda: self.version != v, timeout=timeout); return self.version

    # lifecycle
    def start(self):
        for s in self.db.unfinished_shots():       # resume after a restart
            self.db.update_shot(s['id'], status='queued'); self.q.put(s['id'])
        threading.Thread(target=self._work, daemon=True, name='analyzer').start()
        if self.watch_dir:
            self._seen = self._snapshot()           # ignore files already there at startup
            threading.Thread(target=self._watch, daemon=True, name='watcher').start()

    def stop(self): self._stop.set()

    # watch folder
    def _snapshot(self):
        out = set()
        try:
            for e in os.scandir(self.watch_dir):
                if e.is_file() and os.path.splitext(e.name)[1].lower() in VIDEO_EXT:
                    st = e.stat(); out.add((e.path, st.st_size, st.st_mtime))
        except OSError as ex:
            self.watch_error = f"can't read {self.watch_dir}: {ex}. On macOS, allow Terminal to access Downloads " \
                               "(System Settings > Privacy & Security > Files and Folders)."
        return out

    def poll_once(self):
        """One watch pass (also called directly by tests). A new video file is ingested once its size has been stable
        for stable_s seconds while a session is active. Files present at startup, or that arrive while no session is
        active, are ignored. (File dates aren't used: AirDrop can keep the original recording date.)"""
        sess = self.db.active_session()
        cur = self._snapshot(); t = time.time()
        if not sess:
            self._seen |= cur; self._pending.clear(); return
        for key in cur - self._seen:
            path, size, mtime = key
            if os.path.basename(path).startswith('.') or size == 0: continue
            first = self._pending.setdefault(path, (size, t))
            if first[0] != size: self._pending[path] = (size, t); continue
            if t - first[1] >= self.stable_s:
                self._pending.pop(path, None); self._seen.add(key)
                self.ingest(path, sess)
        for p in list(self._pending):
            if not os.path.exists(p): self._pending.pop(p)

    def _watch(self):
        while not self._stop.is_set():
            try: self.poll_once()
            except Exception: traceback.print_exc()
            self._stop.wait(self.poll_s)

    # ingest
    def ingest(self, path, sess=None, original_name=None):
        sess = sess or self.db.active_session()
        if not sess: raise RuntimeError('no active session')
        d = os.path.join(self.data_dir, 'sessions', str(sess['id'])); os.makedirs(d, exist_ok=True)
        n = len(self.db.shots(sess['id'])) + 1
        ext = os.path.splitext(original_name or path)[1].lower() or '.mov'
        dst = os.path.join(d, f'shot_{n:03d}{ext}')
        while os.path.exists(dst): n += 1; dst = os.path.join(d, f'shot_{n:03d}{ext}')
        shutil.copy2(path, dst)                    # never modify the original
        sid = self.db.add_shot(sess, original_name or os.path.basename(path), dst)
        self.q.put(sid); self.bump()
        self.speaker.say(f'Shot {self.db.shot(sid)["n"]} received.')
        return sid

    # analysis
    def _work(self):
        while not self._stop.is_set():
            try: sid = self.q.get(timeout=0.5)
            except queue.Empty: continue
            try: self.process(sid)
            except Exception: traceback.print_exc()

    def process(self, sid):
        shot = self.db.shot(sid)
        if not shot: return
        sess = self.db.session(shot['session_id'])
        self.db.update_shot(sid, status='processing', started_at=now(), error=None); self.bump()
        t0 = time.time(); steps = []
        def log(msg): steps.append(dict(t_s=round(time.time() - t0, 2), msg=str(msg))); print(f'[shot {sid}] {msg}', flush=True)
        timings = {}
        try:
            t = time.time(); p = probe(shot['clip_path'], check_decoder=self.check_decoder)
            timings['probe_s'] = round(time.time() - t, 2)
            log(f"probe: {p['codec']} {p['width']}x{p['height']} {p['measured_fps']} fps{' HDR' if p.get('hdr') else ''}")
            out_prefix = os.path.splitext(shot['clip_path'])[0]
            video = shot['clip_path']
            if p.get('hdr'):
                t = time.time(); video = out_prefix + '_sdr.mov'
                p['sdr_conversion'] = convert_sdr(shot['clip_path'], video)
                p['decoded_frames'] = probe(video, check_decoder=self.check_decoder).get('decoded_frames')
                timings['convert_s'] = round(time.time() - t, 2)
                log(f"HDR -> SDR in {timings['convert_s']}s ({p['sdr_conversion']['encoder']}; frame times from the original)")
            self.db.update_shot(sid, probe_json=p)
            t = time.time()
            # cache prefix follows the analyzed file, so an SDR copy never reuses a cache built from HDR frames
            kw = dict(timing_video=shot['clip_path']) if video != shot['clip_path'] else {}
            rec = self.analyzer(video, os.path.splitext(video)[0], handed=sess.get('handed'), log=log, **kw)
            timings['analyze_s'] = round(time.time() - t, 2)
            rec.setdefault('context', {}).update(session_id=sess['id'], shot_n=shot['n'], ball=shot.get('ball_name'))
            timings['total_s'] = round(time.time() - t0, 2); timings['steps'] = steps
            self.db.update_shot(sid, status='done', record_json=rec, timings_json=timings, finished_at=now())
            self.render(sid)
        except ClipError as e:
            timings['total_s'] = round(time.time() - t0, 2); timings['steps'] = steps
            self.db.update_shot(sid, status='failed', error=f'Clip rejected: {e}', timings_json=timings, finished_at=now())
        except Exception as e:
            timings['total_s'] = round(time.time() - t0, 2); timings['steps'] = steps
            self.db.update_shot(sid, status='failed', error=f'Analysis failed: {e}', timings_json=timings, finished_at=now())
            traceback.print_exc()
        self.bump()
        c = self.card(sid)
        if c: self.speaker.say(c.get('speech'))

    # views
    def cards(self, session_id):
        sess = self.db.session(session_id); shots = self.db.shots(session_id)
        return sess, shots, cardmod.build_cards(sess, shots)

    def card(self, sid):
        shot = self.db.shot(sid)
        if not shot: return None
        _, _, cards = self.cards(shot['session_id'])
        return next((c for c in cards if c['id'] == sid), None)

    def replay_path(self, sid):
        shot = self.db.shot(sid); return os.path.splitext(shot['clip_path'])[0] + '_replay.png'

    def render(self, sid):
        """Replay PNG with the effective (possibly corrected) pins and current recommendation."""
        shot = self.db.shot(sid); c = self.card(sid)
        if not shot or not shot.get('record') or not c: return
        from lanesight_core.replay.render import shot_png
        rec = dict(shot['record'])
        if c.get('pins') is not None:
            rec['pins'] = dict(rec.get('pins') or {}, standing=c['pins']['standing'], uncertain=c['pins']['uncertain'], strike=c['pins']['strike'])
        rec['insights'] = c.get('insights') or {}
        try: shot_png(rec, self.replay_path(sid))
        except Exception: traceback.print_exc()

    def state(self, session_id=None):
        sess = self.db.session(session_id) if session_id else self.db.active_session()
        out = dict(version=self.version, watch_dir=self.watch_dir, watch_error=self.watch_error, speech=self.speaker.enabled,
                   speech_available=self.speaker.cmd is not None, queue=self.q.qsize(), session=None, cards=[], stats=None,
                   sessions=[dict(id=s['id'], started_at=s['started_at'], ended_at=s['ended_at'], kind=s['kind'],
                                  ball_name=s['ball_name'], shot_count=s['shot_count']) for s in self.db.sessions()[:20]])
        if sess:
            sess, shots, cards = self.cards(sess['id'])
            out.update(session=sess, cards=cards, stats=cardmod.session_stats(cards, shots))
        return out
