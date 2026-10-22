"""Persistence. MemoryStore (default; offline + tests) and PgStore (when a db_url is configured; writes to
the real Supabase tables with the service role). The API logic is identical either way; only the e2e needs
the live backend. All per-user reads are scoped by user_id in code (the service role bypasses RLS, so the
service must enforce ownership itself).
"""
from __future__ import annotations
import csv
import io
import time
import uuid
from .config import settings


def _new_id():
    return uuid.uuid4().hex


class MemoryStore:
    def __init__(self):
        self.sessions, self.shots, self.snapshots, self.feedback = {}, {}, {}, {}

    # sessions
    def create_session(self, user_id, data):
        s = dict(id=_new_id(), user_id=user_id, started_at=time.time(), ended_at=None, **data)
        self.sessions[s['id']] = s
        return s

    def list_sessions(self, user_id):
        return [s for s in self.sessions.values() if s['user_id'] == user_id]

    def get_session(self, user_id, sid):
        s = self.sessions.get(sid)
        return s if s and s['user_id'] == user_id else None

    def end_session(self, user_id, sid):
        s = self.get_session(user_id, sid)
        if not s:
            return None
        s['ended_at'] = time.time()
        shots = self.shots_for_session(sid)
        return dict(session_id=sid, shots=len(shots), ended_at=s['ended_at'])

    # shots
    def create_shot(self, user_id, session_id, meta):
        sh = dict(id=_new_id(), user_id=user_id, session_id=session_id, created_at=time.time(),
                  record=None, result=None, **meta)
        self.shots[sh['id']] = sh
        return sh

    def save_shot_result(self, shot_id, record, result):
        sh = self.shots.get(shot_id)
        if sh:
            sh['record'] = record
            sh['result'] = result

    def get_shot(self, user_id, shot_id):
        sh = self.shots.get(shot_id)
        return sh if sh and sh['user_id'] == user_id else None

    def patch_shot(self, user_id, shot_id, patch):
        sh = self.get_shot(user_id, shot_id)
        if sh:
            sh.update(patch)
        return sh

    def shots_for_session(self, session_id):
        return [sh for sh in self.shots.values() if sh['session_id'] == session_id]

    def user_shots(self, user_id):
        return [sh for sh in self.shots.values() if sh['user_id'] == user_id]

    # score
    def save_snapshot(self, user_id, snapshot):
        self.snapshots.setdefault(user_id, []).append(dict(snapshot, computed_at=time.time()))

    def latest_score(self, user_id):
        snaps = self.snapshots.get(user_id) or []
        return snaps[-1] if snaps else None

    def score_history(self, user_id):
        return list(self.snapshots.get(user_id) or [])

    # feedback
    def save_feedback(self, user_id, session_id, fb):
        row = dict(id=_new_id(), user_id=user_id, session_id=session_id, created_at=time.time(), **fb)
        self.feedback.setdefault(session_id, []).append(row)
        return row


class PgStore(MemoryStore):
    """Writes through to Postgres (service role via db_url) while keeping the same interface.
    NOTE: validated only by the live e2e (needs the Keychain db_url). Until then it is code-reviewed,
    not run. Falls back to the in-memory structures for reads not yet backed here."""
    def __init__(self, db_url):
        super().__init__()
        self._db_url = db_url

    def _conn(self):
        import psycopg
        return psycopg.connect(self._db_url, autocommit=True)

    def create_session(self, user_id, data):
        s = super().create_session(user_id, data)
        with self._conn() as c:
            c.execute("insert into sessions (id, user_id, mode, lane_pair, oil_pattern_id) "
                      "values (%s,%s,%s,%s,%s)",
                      (s['id'], user_id, data.get('mode', 'practice'), data.get('lane_pair'),
                       data.get('oil_pattern_id')))
        return s

    def save_feedback(self, user_id, session_id, fb):
        row = super().save_feedback(user_id, session_id, fb)
        with self._conn() as c:
            c.execute("insert into session_feedback (id, session_id, user_id, rating, tags, text, "
                      "diagnostics, app_version, core_version, formula_version) "
                      "values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                      (row['id'], session_id, user_id, fb.get('rating'), fb.get('tags', []),
                       fb.get('text'), __import__('json').dumps(fb.get('diagnostics')),
                       fb.get('app_version'), fb.get('core_version'), fb.get('formula_version')))
        return row

    def save_snapshot(self, user_id, snapshot):
        super().save_snapshot(user_id, snapshot)
        with self._conn() as c:
            import json
            c.execute("insert into score_snapshot (user_id, formula_version, trigger, session_id, eligible, "
                      "score, s_perf, a_acc, c_cons, p_power, eligibility, inputs, tier) "
                      "values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                      (user_id, snapshot.get('formula_version'), snapshot.get('trigger', 'shot'),
                       snapshot.get('session_id'), snapshot.get('eligible'), snapshot.get('score'),
                       snapshot.get('s_perf'), snapshot.get('a_acc'), snapshot.get('c_cons'),
                       snapshot.get('p_power'), json.dumps(snapshot.get('eligibility')),
                       json.dumps(snapshot.get('inputs')), snapshot.get('tier')))


def session_csv(shots: list[dict], feedback: list[dict]) -> str:
    """CSV export: all metrics, statuses, reasons, timings, sensor flag, feedback (HANDOFF §3 Export)."""
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(['shot_id', 'metric', 'value', 'unit', 'status', 'note', 'sensor_used', 'sensor_id'])
    for sh in shots:
        rec = sh.get('record') or {}
        metrics = rec.get('metrics', {})
        if not metrics:
            w.writerow([sh['id'], '', '', '', 'no_result', '', sh.get('sensor_used'), sh.get('sensor_id')])
        for name, mm in metrics.items():
            w.writerow([sh['id'], name, mm.get('value'), mm.get('unit'), mm.get('status'),
                        mm.get('note'), sh.get('sensor_used'), sh.get('sensor_id')])
    w.writerow([])
    w.writerow(['feedback_rating', 'tags', 'text'])
    for fb in feedback:
        w.writerow([fb.get('rating'), '|'.join(fb.get('tags', [])), fb.get('text')])
    return buf.getvalue()


_store = None


def get_store():
    global _store
    if _store is None:
        s = settings()
        _store = PgStore(s.db_url) if s.db_url else MemoryStore()
    return _store
