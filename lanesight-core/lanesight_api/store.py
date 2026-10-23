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


# profiles has columns display_name/handed/style/units/usbc_id/dob/delivery_style/approach_steps. The app
# speaks name/handedness/location/dob(datetime); normalize inbound (map aliases, drop unknowns incl. a
# location with no column) so a key mismatch can't 500, and echo the app's aliases back on read.
_PROFILE_COLS = {'display_name', 'handed', 'style', 'units', 'usbc_id', 'dob', 'delivery_style', 'approach_steps'}


def _profile_in(data: dict) -> dict:
    d = dict(data or {})
    out = {}
    if d.get('display_name') is not None or d.get('name') is not None:
        out['display_name'] = d.get('display_name', d.get('name'))
    h = d.get('handed', d.get('handedness'))
    if h is not None:
        out['handed'] = {'right': 'R', 'left': 'L', 'r': 'R', 'l': 'L'}.get(str(h).strip().lower())
    if d.get('dob'):
        out['dob'] = str(d['dob'])[:10]          # ISO datetime -> YYYY-MM-DD for the date column
    for k in ('style', 'units', 'usbc_id', 'delivery_style', 'approach_steps'):
        if d.get(k) is not None:
            out[k] = d[k]
    return {k: v for k, v in out.items() if v is not None and k in _PROFILE_COLS}


def _profile_out(row: dict | None) -> dict | None:
    if not row:
        return row
    r = dict(row)
    r['handedness'] = {'R': 'right', 'L': 'left'}.get(r.get('handed'))   # alias the app reads
    r.setdefault('name', r.get('display_name'))
    return r


class MemoryStore:
    def __init__(self):
        self.sessions, self.shots, self.snapshots, self.feedback = {}, {}, {}, {}
        self.profiles, self.sensors, self.arsenal = {}, {}, {}
        # score/tier/achievement/benchmark engine state (SCORE_TIERS §7, BENCHMARKS §6)
        self.tier_state = {}          # user_id -> state dict
        self.tier_events = {}         # user_id -> [event]
        self.ach_progress = {}        # (user_id, ach_id, level) -> progress
        self.ach_unlocks = {}         # (user_id, ach_id, level) -> unlock
        self.ach_pins = {}            # user_id -> [{achievement_id, kind, position}]
        self.activity = {}            # user_id -> [item]
        self.notifications = {}       # user_id -> [row]
        self.findings = {}            # user_id -> [row]
        self.baselines = {}           # (user_id, metric, view) -> row
        self.surface = {}             # user_ball_id -> [event]

    def list_arsenal(self, user_id):
        return [b for b in self.arsenal.values() if b['user_id'] == user_id]

    def add_ball(self, user_id, data):
        b = dict(id=_new_id(), user_id=user_id, **(data or {}))
        self.arsenal[b['id']] = b
        return b

    # profile / sensors / catalog (MemoryStore: in-memory; catalog/oil are empty offline)
    def get_profile(self, user_id):
        return _profile_out(self.profiles.get(user_id))

    def put_profile(self, user_id, data):
        p = dict(self.profiles.get(user_id, {}), user_id=user_id, **_profile_in(data))
        self.profiles[user_id] = p
        return _profile_out(p)

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

    # ----------------------------------------------------------------- rules / engine config (owner-only)
    def achievement_defs(self, active_only=False):
        from .rules_seed import achievement_definitions, active_definitions
        return active_definitions() if active_only else achievement_definitions()

    def engine_config(self):
        from .rules_seed import ENGINE_CONFIG
        return dict(ENGINE_CONFIG)

    def score_formula_params(self):
        """L-dev-0 params with the owner-editable power ranges merged in (DEC-048)."""
        from lanesight_core.score import DEFAULT_LDEV0_PARAMS
        params = dict(DEFAULT_LDEV0_PARAMS)
        pr = self.engine_config().get('power_ref_ranges')
        if pr:
            params['power_ref_ranges'] = pr
        return params

    # ----------------------------------------------------------------- shot history read-back (for scoring)
    def read_shot_records(self, user_id, window_days=None):
        """Ordered valid ShotRecords for the user, with intents + handed. Offline: from memory."""
        shots = sorted(self.user_shots(user_id), key=lambda s: s.get('created_at') or 0)
        now = time.time()
        records, intents, handed = [], {}, 'R'
        for sh in shots:
            rec = sh.get('record')
            if not rec or not rec.get('metrics'):
                continue
            if (window_days is not None and sh.get('created_at')
                    and (now - sh['created_at']) > window_days * 86400):
                continue
            rec = dict(rec)
            rec.setdefault('shot_id', sh['id'])
            records.append(rec)
            if sh.get('intent'):
                intents[rec['shot_id']] = sh['intent']
            if sh.get('handed'):
                handed = sh['handed']
        return records, intents, handed

    def completed_sessions(self, user_id):
        return [s for s in self.list_sessions(user_id) if s.get('ended_at')]

    def arsenal_count(self, user_id):
        return len(self.list_arsenal(user_id))

    def session_shots(self, user_id, session_id):
        """Rows for the live Session screen: id, state, key metrics, status."""
        out = []
        for sh in sorted(self.shots_for_session(session_id), key=lambda s: s.get('created_at') or 0):
            if sh.get('user_id') != user_id:
                continue
            rec = sh.get('record') or {}
            metrics = rec.get('metrics') or {}
            key = {k: (metrics.get(k) or {}).get('value')
                   for k in ('ball_speed', 'rev_rate', 'entry_board', 'entry_angle', 'arrows_board')}
            if rec and metrics:
                state = 'analyzed'
            elif (sh.get('result') or {}).get('ok') is False:
                state = 'failed'
            else:
                state = 'pending'
            out.append(dict(id=sh['id'], state=state, created_at=sh.get('created_at'),
                            classification=(rec.get('insights') or {}).get('classification'),
                            source=sh.get('source'), metrics=key))
        return out

    # ----------------------------------------------------------------- tier state / events
    def get_tier_state(self, user_id):
        return self.tier_state.get(user_id)

    def save_tier_state(self, user_id, state):
        self.tier_state[user_id] = dict(state, user_id=user_id, updated_at=time.time())
        return self.tier_state[user_id]

    def add_tier_event(self, user_id, event):
        row = dict(id=_new_id(), user_id=user_id, created_at=time.time(), **event)
        self.tier_events.setdefault(user_id, []).append(row)
        return row

    # ----------------------------------------------------------------- achievement progress / unlocks
    def upsert_ach_progress(self, user_id, progress):
        key = (user_id, progress['achievement_id'], progress.get('level', 1))
        self.ach_progress[key] = dict(progress, user_id=user_id, level=progress.get('level', 1),
                                      last_event_at=time.time())
        return self.ach_progress[key]

    def list_ach_progress(self, user_id):
        return [p for (u, _a, _l), p in self.ach_progress.items() if u == user_id]

    def get_ach_unlock(self, user_id, ach_id, level=1):
        return self.ach_unlocks.get((user_id, ach_id, level))

    def add_ach_unlock(self, user_id, ach_id, level, value, evidence_ref, rule_version=1):
        key = (user_id, ach_id, level)
        if key in self.ach_unlocks:
            return self.ach_unlocks[key], False
        row = dict(id=_new_id(), user_id=user_id, achievement_id=ach_id, level=level,
                   unlocked_at=time.time(), value=value, evidence_ref=evidence_ref or {},
                   rule_version=rule_version, revoked_at=None)
        self.ach_unlocks[key] = row
        return row, True

    def list_ach_unlocks(self, user_id):
        return [u for (uid, _a, _l), u in self.ach_unlocks.items()
                if uid == user_id and not u.get('revoked_at')]

    def get_pins(self, user_id):
        return list(self.ach_pins.get(user_id) or [])

    def set_pins(self, user_id, pins):
        clean = []
        for p in (pins or []):
            if p.get('kind') in ('showcase', 'pursuit') and 1 <= int(p.get('position', 0)) <= 3:
                clean.append({'achievement_id': p['achievement_id'], 'kind': p['kind'],
                              'position': int(p['position'])})
        self.ach_pins[user_id] = clean
        return clean

    # ----------------------------------------------------------------- activity / notifications
    def add_activity(self, user_id, kind, ref_id, payload):
        items = self.activity.setdefault(user_id, [])
        if any(i['kind'] == kind and i['ref_id'] == ref_id for i in items):
            return None
        row = dict(id=_new_id(), user_id=user_id, kind=kind, ref_id=ref_id,
                   payload=payload, created_at=time.time())
        items.append(row)
        return row

    def list_activity(self, user_id):
        return sorted(self.activity.get(user_id) or [], key=lambda r: r['created_at'], reverse=True)

    def add_notification(self, user_id, kind, ref_id, priority, payload):
        rows = self.notifications.setdefault(user_id, [])
        if any(r['kind'] == kind and r['ref_id'] == ref_id for r in rows):
            return None
        row = dict(id=_new_id(), user_id=user_id, kind=kind, ref_id=ref_id, priority=priority,
                   payload=payload, created_at=time.time(), delivered_at=None, dismissed_at=None)
        rows.append(row)
        return row

    def list_notifications(self, user_id, undelivered=False):
        rows = [r for r in (self.notifications.get(user_id) or []) if not r.get('dismissed_at')]
        if undelivered:
            rows = [r for r in rows if not r.get('delivered_at')]
        return sorted(rows, key=lambda r: (-r['priority'], r['created_at']))

    def mark_notification(self, user_id, notif_id, field):
        for r in (self.notifications.get(user_id) or []):
            if r['id'] == notif_id:
                r[field] = time.time()
                return r
        return None

    # ----------------------------------------------------------------- findings / baselines (benchmarks)
    def upsert_baseline(self, user_id, metric, row, view='all'):
        key = (user_id, metric, view)
        self.baselines[key] = dict(row, user_id=user_id, metric=metric, view=view, computed_at=time.time())
        return self.baselines[key]

    def list_baselines(self, user_id):
        return [b for (u, _m, _v), b in self.baselines.items() if u == user_id]

    def add_finding(self, user_id, row):
        r = dict(id=_new_id(), user_id=user_id, created_at=time.time(), **row)
        self.findings.setdefault(user_id, []).append(r)
        return r

    def list_findings(self, user_id):
        return sorted(self.findings.get(user_id) or [], key=lambda r: r['created_at'], reverse=True)

    # ----------------------------------------------------------------- arsenal surface events
    def add_surface_event(self, user_id, user_ball_id, data):
        ball = self.arsenal.get(user_ball_id)
        if not ball or ball.get('user_id') != user_id:
            return None
        row = dict(id=_new_id(), user_ball_id=user_ball_id, event_at=time.time(),
                   **{k: v for k, v in (data or {}).items() if k in ('grit', 'polish', 'product', 'notes')})
        self.surface.setdefault(user_ball_id, []).append(row)
        return row

    # ----------------------------------------------------------------- account deletion
    def delete_user(self, user_id):
        for sid in [s['id'] for s in self.list_sessions(user_id)]:
            self.sessions.pop(sid, None)
            self.feedback.pop(sid, None)
        for shid in [s['id'] for s in self.user_shots(user_id)]:
            self.shots.pop(shid, None)
        for d in (self.profiles, self.sensors):
            d.pop(user_id, None)
        self.arsenal = {k: v for k, v in self.arsenal.items() if v.get('user_id') != user_id}
        self.snapshots.pop(user_id, None)
        self.tier_state.pop(user_id, None)
        self.tier_events.pop(user_id, None)
        self.ach_progress = {k: v for k, v in self.ach_progress.items() if k[0] != user_id}
        self.ach_unlocks = {k: v for k, v in self.ach_unlocks.items() if k[0] != user_id}
        self.ach_pins.pop(user_id, None)
        self.activity.pop(user_id, None)
        self.notifications.pop(user_id, None)
        self.findings.pop(user_id, None)
        self.baselines = {k: v for k, v in self.baselines.items() if k[0] != user_id}
        return True


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
        self._post('score_snapshot', {'id': snapshot.get('id'), 'user_id': user_id,
                   'formula_version': snapshot.get('formula_version'),
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
        return _profile_out(rows[0]) if rows else None

    def put_profile(self, user_id, data):
        row = {'user_id': user_id, **_profile_in(data)}
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

    # ----------------------------------------------------------------- rules / engine config (service role)
    def achievement_defs(self, active_only=False):
        q = 'select=*&order=id' + ('&status=eq.active' if active_only else '')
        return self._get('achievement_definition', q)

    def engine_config(self):
        return {r['key']: r['value'] for r in self._get('engine_config', 'select=key,value')}

    def score_formula_params(self):
        from lanesight_core.score import DEFAULT_LDEV0_PARAMS
        rows = self._get('score_formula_version', "id=eq.L-dev-0&select=params")
        params = dict(rows[0]['params']) if rows else dict(DEFAULT_LDEV0_PARAMS)
        pr = self.engine_config().get('power_ref_ranges')
        if pr:
            params['power_ref_ranges'] = pr
        return params

    # ----------------------------------------------------------------- shot history read-back (from Supabase)
    def read_shot_records(self, user_id, window_days=None):
        import datetime as _dt
        q = f'user_id=eq.{user_id}&select=id,handed,created_at&order=created_at'
        if window_days is not None:
            since = (_dt.datetime.now(_dt.timezone.utc) - _dt.timedelta(days=window_days)).isoformat()
            q += f'&created_at=gte.{since}'
        shots = self._get('shots', q)
        if not shots:
            return [], {}, 'R'
        ids = ','.join(s['id'] for s in shots)
        meas = self._get('measurements', f'shot_id=in.({ids})&source=eq.lanesight_video'
                                          '&select=shot_id,metric,value,status,confidence,note')
        ints = self._get('shot_intents', f'shot_id=in.({ids})&select=shot_id,arrows_board,breakpoint_board')
        by_shot = {}
        for m in meas:
            by_shot.setdefault(m['shot_id'], {})[m['metric']] = {
                'value': m.get('value'), 'status': m.get('status'),
                'confidence': m.get('confidence'), 'note': m.get('note')}
        intents = {i['shot_id']: {'arrows_board': i.get('arrows_board'),
                                  'breakpoint_board': i.get('breakpoint_board')}
                   for i in ints if i.get('arrows_board') is not None or i.get('breakpoint_board') is not None}
        records, handed = [], 'R'
        for s in shots:
            metrics = by_shot.get(s['id'])
            if not metrics:
                continue
            records.append({'shot_id': s['id'], 'metrics': metrics})
            if s.get('handed'):
                handed = s['handed']
        return records, intents, handed

    def completed_sessions(self, user_id):
        return self._get('sessions', f'user_id=eq.{user_id}&ended_at=not.is.null&select=id,ended_at,mode')

    def session_shots(self, user_id, session_id):
        rows = self._get('shots', f'user_id=eq.{user_id}&session_id=eq.{session_id}'
                                  '&select=id,created_at,classification,source,record&order=created_at')
        out = []
        for sh in rows:
            rec = sh.get('record') or {}
            metrics = rec.get('metrics') or {}
            key = {k: (metrics.get(k) or {}).get('value')
                   for k in ('ball_speed', 'rev_rate', 'entry_board', 'entry_angle', 'arrows_board')}
            out.append(dict(id=sh['id'], state='analyzed' if metrics else 'pending',
                            created_at=sh.get('created_at'), classification=sh.get('classification'),
                            source=sh.get('source'), metrics=key))
        return out

    # ----------------------------------------------------------------- tier state / events
    def get_tier_state(self, user_id):
        rows = self._get('user_tier_state', f'user_id=eq.{user_id}&select=*')
        return rows[0] if rows else None

    def save_tier_state(self, user_id, state):
        row = {'user_id': user_id,
               **{k: state.get(k) for k in ('tier', 'score', 'best_score', 'best_score_at',
                                            'first_qualified_score', 'below_floor_sessions')}}
        self._req('user_tier_state', 'POST', row, prefer='resolution=merge-duplicates,return=minimal')
        return row

    def add_tier_event(self, user_id, event):
        row = {'id': _new_id(), 'user_id': user_id,
               **{k: event.get(k) for k in ('from_tier', 'to_tier', 'kind', 'first_time', 'score', 'snapshot_id')}}
        self._post('tier_event', row)
        return row

    # ----------------------------------------------------------------- achievement progress / unlocks
    def upsert_ach_progress(self, user_id, progress):
        row = {'user_id': user_id, 'achievement_id': progress['achievement_id'],
               'level': progress.get('level', 1), 'status': progress['status'],
               'current_value': progress.get('current_value'), 'best_value': progress.get('best_value'),
               'target_value': progress.get('target_value'), 'qualifying_count': progress.get('qualifying_count'),
               'sample_count': progress.get('sample_count'), 'unavailable_reason': progress.get('unavailable_reason'),
               'evidence_ref': progress.get('evidence_ref')}
        self._req('user_achievement_progress', 'POST', row,
                  prefer='resolution=merge-duplicates,return=minimal')
        return row

    def list_ach_progress(self, user_id):
        return self._get('user_achievement_progress', f'user_id=eq.{user_id}&select=*')

    def get_ach_unlock(self, user_id, ach_id, level=1):
        rows = self._get('user_achievement_unlock',
                         f'user_id=eq.{user_id}&achievement_id=eq.{ach_id}&level=eq.{level}&select=*')
        return rows[0] if rows else None

    def add_ach_unlock(self, user_id, ach_id, level, value, evidence_ref, rule_version=1):
        existing = self.get_ach_unlock(user_id, ach_id, level)
        if existing:
            return existing, False
        row = {'id': _new_id(), 'user_id': user_id, 'achievement_id': ach_id, 'level': level,
               'value': value, 'evidence_ref': evidence_ref or {}, 'rule_version': rule_version}
        self._req('user_achievement_unlock', 'POST', row, prefer='resolution=ignore-duplicates,return=minimal')
        return row, True

    def list_ach_unlocks(self, user_id):
        return self._get('user_achievement_unlock', f'user_id=eq.{user_id}&revoked_at=is.null&select=*')

    def get_pins(self, user_id):
        return self._get('user_achievement_pin', f'user_id=eq.{user_id}&select=achievement_id,kind,position')

    def set_pins(self, user_id, pins):
        self._req(f'user_achievement_pin?user_id=eq.{user_id}', 'DELETE')
        clean = []
        for p in (pins or []):
            if p.get('kind') in ('showcase', 'pursuit') and 1 <= int(p.get('position', 0)) <= 3:
                clean.append({'user_id': user_id, 'achievement_id': p['achievement_id'],
                              'kind': p['kind'], 'position': int(p['position'])})
        if clean:
            self._req('user_achievement_pin', 'POST', clean)
        return clean

    # ----------------------------------------------------------------- activity / notifications
    def add_activity(self, user_id, kind, ref_id, payload):
        row = {'id': _new_id(), 'user_id': user_id, 'kind': kind, 'ref_id': ref_id, 'payload': payload}
        self._req('activity_item', 'POST', row, prefer='resolution=ignore-duplicates,return=minimal')
        return row

    def list_activity(self, user_id):
        return self._get('activity_item', f'user_id=eq.{user_id}&select=*&order=created_at.desc')

    def add_notification(self, user_id, kind, ref_id, priority, payload):
        row = {'id': _new_id(), 'user_id': user_id, 'kind': kind, 'ref_id': ref_id,
               'priority': priority, 'payload': payload}
        self._req('notification', 'POST', row, prefer='resolution=ignore-duplicates,return=minimal')
        return row

    def list_notifications(self, user_id, undelivered=False):
        q = f'user_id=eq.{user_id}&dismissed_at=is.null&select=*&order=priority.desc,created_at'
        if undelivered:
            q += '&delivered_at=is.null'
        return self._get('notification', q)

    def mark_notification(self, user_id, notif_id, field):
        col = 'delivered_at' if field == 'delivered_at' else 'dismissed_at'
        import datetime as _dt
        self._req(f'notification?id=eq.{notif_id}&user_id=eq.{user_id}', 'PATCH',
                  {col: _dt.datetime.now(_dt.timezone.utc).isoformat()})
        return {'id': notif_id, col: 'set'}

    # ----------------------------------------------------------------- findings / baselines
    def upsert_baseline(self, user_id, metric, row, view='all'):
        body = {'user_id': user_id, 'metric': metric, 'view': view,
                **{k: row.get(k) for k in ('median', 'mad', 'sd', 'n')}, 'window_kind': 'rolling_90'}
        self._req('personal_baseline', 'POST', body)
        return body

    def list_baselines(self, user_id):
        return self._get('personal_baseline', f'user_id=eq.{user_id}&select=*')

    def add_finding(self, user_id, row):
        body = {'id': _new_id(), 'user_id': user_id,
                **{k: row.get(k) for k in ('shot_id', 'session_id', 'metric', 'benchmark_layer',
                                           'benchmark_version', 'level_status', 'consistency_status',
                                           'confidence', 'rule_id', 'rule_version')}}
        self._post('finding', body)
        return body

    def list_findings(self, user_id):
        return self._get('finding', f'user_id=eq.{user_id}&select=*&order=created_at.desc')

    # ----------------------------------------------------------------- arsenal surface events
    def add_surface_event(self, user_id, user_ball_id, data):
        balls = self._get('user_balls', f'id=eq.{user_ball_id}&user_id=eq.{user_id}&select=id')
        if not balls:
            return None
        row = {'id': _new_id(), 'user_ball_id': user_ball_id,
               **{k: v for k, v in (data or {}).items() if k in ('grit', 'polish', 'product', 'notes')}}
        self._post('surface_events', row)
        return row

    # ----------------------------------------------------------------- account deletion (admin API)
    def delete_user(self, user_id):
        import urllib.request
        base = self._rest.rsplit('/rest/', 1)[0] if '/rest/' in self._rest else self._rest.rstrip('/')
        url = f'{base}/auth/v1/admin/users/{user_id}'
        req = urllib.request.Request(url, method='DELETE', headers={
            'apikey': self._key, 'Authorization': f'Bearer {self._key}'})
        with urllib.request.urlopen(req, timeout=30) as r:
            if r.status not in (200, 204):
                raise RuntimeError(f'admin delete user -> {r.status}')
        return True


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
