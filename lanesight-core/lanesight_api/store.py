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
        self.profiles, self.sensors, self.arsenal = {}, {}, {}

    def list_arsenal(self, user_id):
        return [b for b in self.arsenal.values() if b['user_id'] == user_id]

    def add_ball(self, user_id, data):
        b = dict(id=_new_id(), user_id=user_id, **(data or {}))
        self.arsenal[b['id']] = b
        return b

    # profile / sensors / catalog (MemoryStore: in-memory; catalog/oil are empty offline)
    def get_profile(self, user_id):
        return self.profiles.get(user_id)

    def put_profile(self, user_id, data):
        p = dict(self.profiles.get(user_id, {}), user_id=user_id, **(data or {}))
        self.profiles[user_id] = p
        return p

    def list_sensors(self, user_id):
        return [s for s in self.sensors.values() if s['user_id'] == user_id]

    def add_sensor(self, user_id, data):
        s = dict(id=_new_id(), user_id=user_id, **(data or {}))
        self.sensors[s['id']] = s
        return s

    def delete_sensor(self, user_id, sensor_id):
        s = self.sensors.get(sensor_id)
        if s and s['user_id'] == user_id:
            del self.sensors[sensor_id]
            return True
        return False

    def catalog_balls(self, q=None, limit=50):
        return []

    def oil_patterns(self):
        return []

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
    """Writes through to Supabase via PostgREST (the service_role key over the REST base in `rest_url`),
    keeping the same interface. The service role bypasses RLS, so ownership is enforced here in code.
    In-memory structures still mirror writes so reads work without extra round-trips."""
    def __init__(self, rest_url, service_key):
        super().__init__()
        self._rest = rest_url.rstrip('/') + '/'
        self._key = service_key

    def _post(self, table, row):
        import json, urllib.request
        body = json.dumps(row).encode()
        req = urllib.request.Request(self._rest + table, data=body, method='POST', headers={
            'apikey': self._key, 'Authorization': f'Bearer {self._key}',
            'Content-Type': 'application/json', 'Prefer': 'return=minimal'})
        with urllib.request.urlopen(req, timeout=30) as r:
            if r.status not in (200, 201, 204):
                raise RuntimeError(f'PostgREST {table} -> {r.status}')

    def create_session(self, user_id, data):
        s = super().create_session(user_id, data)
        self._post('sessions', {'id': s['id'], 'user_id': user_id, 'mode': data.get('mode', 'practice'),
                                'lane_pair': data.get('lane_pair'), 'oil_pattern_id': data.get('oil_pattern_id')})
        return s

    def save_feedback(self, user_id, session_id, fb):
        row = super().save_feedback(user_id, session_id, fb)
        self._post('session_feedback', {'id': row['id'], 'session_id': session_id, 'user_id': user_id,
                   'rating': fb.get('rating'), 'tags': fb.get('tags', []), 'text': fb.get('text'),
                   'diagnostics': fb.get('diagnostics'), 'app_version': fb.get('app_version'),
                   'core_version': fb.get('core_version'), 'formula_version': fb.get('formula_version')})
        return row

    def save_snapshot(self, user_id, snapshot):
        super().save_snapshot(user_id, snapshot)
        self._post('score_snapshot', {'user_id': user_id, 'formula_version': snapshot.get('formula_version'),
                   'trigger': snapshot.get('trigger', 'shot'), 'session_id': snapshot.get('session_id'),
                   'eligible': snapshot.get('eligible'), 'score': snapshot.get('score'),
                   's_perf': snapshot.get('s_perf'), 'a_acc': snapshot.get('a_acc'),
                   'c_cons': snapshot.get('c_cons'), 'p_power': snapshot.get('p_power'),
                   'eligibility': snapshot.get('eligibility'), 'inputs': snapshot.get('inputs'),
                   'tier': snapshot.get('tier')})

    def create_shot(self, user_id, session_id, meta):
        sh = MemoryStore.create_shot(self, user_id, session_id, meta)
        self._req('shots', 'POST', {'id': sh['id'], 'user_id': user_id, 'session_id': session_id,
                  'record': {}, 'handed': meta.get('handed'), 'capture_mode': meta.get('capture_mode'),
                  'source': meta.get('source', 'live'), 'sensor_used': meta.get('sensor_used'),
                  'sensor_id': meta.get('sensor_id')})
        intent = meta.get('intent') or {}
        if intent.get('arrows_board') is not None or intent.get('breakpoint_board') is not None:
            self._req('shot_intents', 'POST', {'shot_id': sh['id'], 'arrows_board': intent.get('arrows_board'),
                      'breakpoint_board': intent.get('breakpoint_board')})
        return sh

    def save_shot_result(self, shot_id, record, result):
        MemoryStore.save_shot_result(self, shot_id, record, result)
        insights = record.get('insights') or {}
        self._req(f'shots?id=eq.{shot_id}', 'PATCH', {
            'record': record, 'trajectory': record.get('trajectory'), 'key_points': record.get('key_points'),
            'classification': insights.get('classification')})
        rows = [{'shot_id': shot_id, 'metric': name, 'value': mm.get('value'), 'unit': mm.get('unit'),
                 'confidence': mm.get('confidence'), 'status': mm.get('status'),
                 'source': mm.get('source', 'lanesight_video'),
                 'algorithm_version': mm.get('algorithm_version'), 'note': mm.get('note')}
                for name, mm in (record.get('metrics') or {}).items()]
        if rows:
            self._req('measurements', 'POST', rows, prefer='resolution=merge-duplicates,return=minimal')

    # --- reads / profile / sensors / catalog (PostgREST) ---
    def _get(self, table, query=''):
        import json, urllib.request
        url = self._rest + table + (('?' + query) if query else '')
        req = urllib.request.Request(url, headers={'apikey': self._key, 'Authorization': f'Bearer {self._key}',
                                                   'Accept': 'application/json'})
        with urllib.request.urlopen(req, timeout=30) as r:
            txt = r.read().decode()
        return json.loads(txt) if txt.strip() else []

    def _req(self, path, method, body=None, prefer='return=minimal'):
        import json, urllib.request
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self._rest + path, data=data, method=method, headers={
            'apikey': self._key, 'Authorization': f'Bearer {self._key}',
            'Content-Type': 'application/json', 'Prefer': prefer})
        with urllib.request.urlopen(req, timeout=30) as r:
            if r.status not in (200, 201, 204):
                raise RuntimeError(f'PostgREST {method} {path} -> {r.status}')

    def get_profile(self, user_id):
        rows = self._get('profiles', f'user_id=eq.{user_id}&select=*')
        return rows[0] if rows else None

    def put_profile(self, user_id, data):
        row = {'user_id': user_id, **{k: v for k, v in (data or {}).items() if k != 'user_id'}}
        self._req('profiles', 'POST', row, prefer='resolution=merge-duplicates,return=minimal')
        return self.get_profile(user_id)

    def list_sensors(self, user_id):
        return self._get('sensor_devices', f'user_id=eq.{user_id}&select=*')

    def add_sensor(self, user_id, data):
        row = {'id': _new_id(), 'user_id': user_id, **(data or {})}
        self._req('sensor_devices', 'POST', row)
        return row

    def delete_sensor(self, user_id, sensor_id):
        self._req(f'sensor_devices?id=eq.{sensor_id}&user_id=eq.{user_id}', 'DELETE')
        return True

    def catalog_balls(self, q=None, limit=50):
        qp = ('select=id,manufacturer,name,coverstock,core_type,ls_hook,ls_length,ls_backend,image_url'
              f'&order=manufacturer,name&limit={int(limit)}')
        if q:
            from urllib.parse import quote
            qq = quote(str(q), safe='')
            qp += f'&or=(name.ilike.*{qq}*,manufacturer.ilike.*{qq}*)'
        return self._get('ball_models', qp)

    def oil_patterns(self):
        return self._get('oil_patterns', 'select=*&order=name')

    def list_arsenal(self, user_id):
        return self._get('user_balls',
                         f'user_id=eq.{user_id}&select=*,ball_models(manufacturer,name,image_url)&order=created_at')

    def add_ball(self, user_id, data):
        row = {'id': _new_id(), 'user_id': user_id,
               **{k: v for k, v in (data or {}).items()
                  if k in ('ball_model_id', 'nickname', 'serial', 'weight_lb', 'color_desc')}}
        self._req('user_balls', 'POST', row)
        return row


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
        _store = PgStore(s.db_url, s.service_role) if (s.db_url and s.service_role) else MemoryStore()
    return _store
