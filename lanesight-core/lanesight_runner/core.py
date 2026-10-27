"""Runner core: watch folder -> copy -> probe -> lanesight-core analysis -> store -> notify + speak.
One clip is analyzed at a time; clips that arrive meanwhile wait in the queue."""
from __future__ import annotations
import glob, json, os, queue, shutil, subprocess, threading, time, traceback
from .db import DB, now
from .probe import probe, convert_sdr, ClipError, VIDEO_EXT
from .trim import detect_window, trim_clip, METRIC_TAIL_S
from .oil import find as oil_find, oil_field
from . import card as cardmod

def default_analyzer(video, out_prefix, handed=None, log=print, timing_video=None, core_end_s=None, cv_timings=None):
    """Real analysis: lanesight-core pipeline. Returns the JSON-safe ShotRecord dict.
    cv_timings: optional dict that receives CV sub-stage wall times (profiling only; no effect on results)."""
    from lanesight_core.cv.pipeline import analyze, _json_default
    rec = analyze(video, out_prefix, handed=handed, log=log, timing_video=timing_video, core_end_s=core_end_s,
                  timings=cv_timings)
    return json.loads(json.dumps(rec.to_dict(), default=_json_default))


def analyze_once(src, out_prefix, p, handed, log, timings, use_window, analyzer, check_decoder=False):
    """One analysis attempt: trim to the shot window (speed-up; see trim.py), convert HDR->SDR if needed,
    then run `analyzer`. Trimming is best-effort; a window/trim failure falls back to the whole clip. Pipeline
    errors propagate so the caller can retry whole-clip (the window may have cut the shot). The pin-settle tail
    is excluded from the stabiliser (core_end_s) only when the clip was trimmed with a detected burst, and
    core_end_s / timing_video are passed only when they apply, so a minimal analyzer signature still works."""
    analysis_src = src
    if use_window:
        try:
            t = time.time(); t0w, t1w, win = detect_window(src, log=log)
            timings['window_s'] = round(time.time() - t, 2); p['window'] = win
            if t0w is not None:
                trimmed = out_prefix + '_trim.mov'; trim_clip(src, trimmed, t0w, t1w)
                analysis_src = trimmed; win['trimmed'] = True; win['trim_file'] = trimmed
                log(f"trimmed {win['dur']}s clip to {win['window']} (burst {win.get('burst')})")
            else:
                log(f"no trim ({win.get('reason')})")
        except Exception as e:
            log(f"windowing skipped: {e}")
    timing_src = analysis_src; video = analysis_src
    if p.get('hdr'):
        t = time.time(); video = os.path.splitext(analysis_src)[0] + '_sdr.mov'
        conv = convert_sdr(analysis_src, video); p['sdr_conversion'] = conv
        p['decoded_frames'] = probe(video, check_decoder=check_decoder).get('decoded_frames')
        timings['convert_s'] = round(time.time() - t, 2)
        log(f"HDR -> SDR in {timings['convert_s']}s ({conv['method']}, {conv['frames']} frames; times from the original)")
    # the browser-playable artifact: SDR 8-bit for HDR clips, else the trimmed clip itself
    if (p.get('window') or {}).get('trimmed'): p['window']['analyzed_file'] = video
    t = time.time()
    # cache prefix follows the analyzed file, so an SDR/trimmed copy never reuses a cache built from other frames
    kw = dict(timing_video=timing_src) if video != timing_src else {}
    win = p.get('window') or {}
    if win.get('trimmed') and win.get('burst'):   # exclude the pin-settle tail from the stabiliser (metric stability)
        kw['core_end_s'] = round(win['burst'][1] - win['window'][0] + METRIC_TAIL_S, 2)
    # profiling only: hand the analyzer a dict to record CV sub-stage times, if it accepts one (no result impact)
    try:
        import inspect
        if 'cv_timings' in inspect.signature(analyzer).parameters:
            kw['cv_timings'] = timings.setdefault('cv', {})
    except (TypeError, ValueError):
        pass
    # DEC-092 P0: count clip decodes across the whole analyze (confirms repeated decode is the bottleneck).
    try:
        from lanesight_core.cv.stabilize import reset_decode_stats, decode_stats
        reset_decode_stats()
    except Exception:
        decode_stats = None
    try:
        rec = analyzer(video, os.path.splitext(video)[0], handed=handed, log=log, **kw)
    finally:
        timings['analyze_s'] = round(time.time() - t, 2)
        if decode_stats:
            timings['decode'] = decode_stats()        # {passes, frames, seconds} even on failure
    return rec


def analyze_clip(src, out_prefix, handed=None, analyzer=None, check_decoder=False, log=print, p=None, timings=None):
    """DB-free at-lane analysis for one clip, the same path the runner worker uses: probe -> windowed attempt
    -> retry whole-clip when a wider window could help (not for content failures that look the same whole).
    Returns (rec, probe_dict, timings). Raises ClipError / RuntimeError on failure. Reusable by the eval harness
    so the pipeline is scored exactly as it runs in production."""
    analyzer = analyzer or default_analyzer
    timings = {} if timings is None else timings
    if p is None:
        t = time.time(); p = probe(src, check_decoder=check_decoder); timings['probe_s'] = round(time.time() - t, 2)
    try:
        rec = analyze_once(src, out_prefix, p, handed, log, timings, True, analyzer, check_decoder)
    except (ClipError, RuntimeError) as e:
        # Content/framing failures (the lane or the ball itself) look the same on the full clip, so a retry just
        # re-pays the HDR conversion to fail again. Retry only errors a wider window could fix (e.g. the trim cut
        # the ball's release so the track was too short).
        content = str(e).startswith('lane not detected') or 'ball not tracked to the pins' in str(e)
        if (p.get('window') or {}).get('trimmed') and not content:
            log(f"windowed analysis failed ({e}); retrying on the full clip")
            timings['windowed_error'] = str(e)
            rec = analyze_once(src, out_prefix, p, handed, log, timings, False, analyzer, check_decoder)
        else:
            raise
    return rec, p, timings

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

    def _analyze(self, src, out_prefix, p, handed, log, timings, use_window):
        """Thin wrapper over the module-level analyze_once (shared with the eval harness)."""
        return analyze_once(src, out_prefix, p, handed, log, timings, use_window, self.analyzer, self.check_decoder)

    def _keep_only_trimmed(self, clip_path, keep_file, out_prefix, log=print):
        """After a successful windowed analysis, keep just the ~8 s shot that was analysed in place of the full
        clip and delete the other working copies (saves ~75% disk; irrelevant set-up footage is removed). For HDR
        the kept file is the 8-bit SDR copy, so it plays in a browser and its pixels match trajectory.pixel. The
        stored path is unchanged, so replay/retry still work (a retry re-analyses the already-short clip whole).
        Best-effort: on any error the full clip is left as-is."""
        if not keep_file or not os.path.exists(keep_file): return
        try:
            os.replace(keep_file, clip_path)                       # analysed shot becomes the stored clip
            for f in glob.glob(out_prefix + '_trim*'):             # HDR trim + analysis caches from the trim
                try: os.remove(f)
                except OSError: pass
            log('kept trimmed shot, removed the full clip and working files')
        except OSError as e:
            log(f'could not replace clip with trimmed version: {e}')

    def process(self, sid):
        shot = self.db.shot(sid)
        if not shot: return
        sess = self.db.session(shot['session_id'])
        self.db.update_shot(sid, status='processing', started_at=now(), error=None); self.bump()
        t0 = time.time(); steps = []
        def log(msg):
            steps.append(dict(t_s=round(time.time() - t0, 2), msg=str(msg))); print(f'[shot {sid}] {msg}', flush=True)
            try: self.db.update_shot(sid, timings_json=dict(timings, steps=steps)); self.bump()   # live progress in the header
            except Exception: pass
        timings = {}
        try:
            t = time.time(); p = probe(shot['clip_path'], check_decoder=self.check_decoder)
            timings['probe_s'] = round(time.time() - t, 2)
            log(f"probe: {p['codec']} {p['width']}x{p['height']} {p['measured_fps']} fps{' HDR' if p.get('hdr') else ''}")
            out_prefix = os.path.splitext(shot['clip_path'])[0]
            rec, p, timings = analyze_clip(shot['clip_path'], out_prefix, handed=sess.get('handed'),
                                           analyzer=self.analyzer, check_decoder=self.check_decoder,
                                           log=log, p=p, timings=timings)
            self.db.update_shot(sid, probe_json=p)
            rec.setdefault('context', {}).update(session_id=sess['id'], shot_n=shot['n'], ball=shot.get('ball_name'))
            timings['total_s'] = round(time.time() - t0, 2); timings['steps'] = steps
            self.db.update_shot(sid, status='done', record_json=rec, timings_json=timings, finished_at=now())
            self.render(sid)
            win = p.get('window') or {}
            if win.get('trimmed') and 'windowed_error' not in timings:
                self._keep_only_trimmed(shot['clip_path'], win.get('analyzed_file'), out_prefix, log)
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
            pat = oil_find(sess.get('pattern_name'))                         # a representation of the selected pattern
            if pat: sess = dict(sess, oil=oil_field(pat))
            out.update(session=sess, cards=cards, stats=cardmod.session_stats(cards, shots))
            prev = next((s for s in self.db.sessions() if s['id'] < sess['id'] and s['shot_count']), None)  # for KPI deltas
            if prev:
                _, pshots, pcards = self.cards(prev['id'])
                out['prev_stats'] = cardmod.session_stats(pcards, pshots)
        return out
