"""Persistence. MemoryStore (default; offline + tests) and PgStore (when a db_url is configured; writes to
the real Supabase tables with the service role). The API logic is identical either way; only the e2e needs
the live backend. All per-user reads are scoped by user_id in code (the service role bypasses RLS, so the
service must enforce ownership itself).
"""
from __future__ import annotations
import csv
import hashlib
import hmac
import io
import os
import time
import uuid
from .config import settings


def _ts_epoch(v):
    """Supabase timestamptz (ISO string) -> epoch seconds, matching the session API contract (MemoryStore uses
    time.time(); iOS SessionRow decodes started_at/ended_at as Double). Numbers/None pass through."""
    if v is None or isinstance(v, (int, float)):
        return v
    try:
        from datetime import datetime
        return datetime.fromisoformat(str(v).replace('Z', '+00:00')).timestamp()
    except Exception:
        return None


def _epoch_session(row):
    if row is not None:
        row['started_at'] = _ts_epoch(row.get('started_at'))
        row['ended_at'] = _ts_epoch(row.get('ended_at'))
    return row


def _new_id():
    return uuid.uuid4().hex


# DEC-098 §2 (M4): pseudonymous user id. A server-held salt turns the raw auth user_id into a stable
# opaque ref the ops layer and exports key on, so the raw id never leaves the owner boundary. The fixed
# dev fallback keeps MemoryStore/tests deterministic; live sets LANESIGHT_USER_REF_SALT.
_USER_REF_SALT = os.environ.get('LANESIGHT_USER_REF_SALT') or 'lanesight-dev-user-ref-salt'


def _user_ref(user_id):
    if not user_id:
        return None
    return hmac.new(_USER_REF_SALT.encode(), str(user_id).encode(), hashlib.sha256).hexdigest()


# Home Recent activity scope (DEC-055): only completed practice sessions, achievement unlocks, and
# LaneSight tier (rank) changes. Anything else (e.g. personal_best score milestones, and never uploads)
# is excluded from the feed. Enforced in both stores' list_activity.
_ACTIVITY_KINDS = ('session_completed', 'achievement_unlocked', 'tier_promotion', 'tier_demotion')


# profiles has columns display_name/first_name/last_name/phone/handed/style/units/usbc_id/dob/delivery_style/
# approach_steps + grip/PAP (DEC-087). The app speaks name/handedness/location/dob(datetime); normalize
# inbound (map aliases, drop unknowns incl. a location with no column) so a key mismatch can't 500, and echo
# the app's aliases back on read. Email is NEVER a profile column — it lives in auth (DEC-087 §3).
_PROFILE_COLS = {'display_name', 'first_name', 'last_name', 'phone', 'handed', 'style', 'units', 'usbc_id',
                 'dob', 'delivery_style', 'approach_steps', 'form_baseline', 'location', 'is_staged',
                 'staged_kind', 'grip_middle_pitch_in', 'grip_span_in', 'pap_over_in', 'pap_up_in'}

# Bowler-level grip + PAP, stored in inches (DEC-074/087). Coerced to float on the way in.
_PROFILE_NUMERIC = ('grip_middle_pitch_in', 'grip_span_in', 'pap_over_in', 'pap_up_in')


def _compose_display_name(first, last) -> str:
    return ' '.join(p for p in (first, last) if p and str(p).strip()).strip()


def _profile_in(data: dict) -> dict:
    d = dict(data or {})
    out = {}
    if d.get('display_name') is not None or d.get('name') is not None:
        out['display_name'] = d.get('display_name', d.get('name'))
    for k in ('first_name', 'last_name'):
        if d.get(k) is not None:
            out[k] = str(d[k]).strip() or None
    if d.get('phone') is not None:
        out['phone'] = str(d['phone']).strip() or None      # "" clears the phone
    h = d.get('handed', d.get('handedness'))
    if h is not None:
        out['handed'] = {'right': 'R', 'left': 'L', 'r': 'R', 'l': 'L'}.get(str(h).strip().lower())
    if d.get('dob'):
        out['dob'] = str(d['dob'])[:10]          # ISO datetime -> YYYY-MM-DD for the date column
    for k in _PROFILE_NUMERIC:
        if d.get(k) is not None:
            out[k] = float(d[k])
    for k in ('style', 'units', 'usbc_id', 'delivery_style', 'approach_steps', 'form_baseline', 'location',
              'is_staged', 'staged_kind'):
        if d.get(k) is not None:
            out[k] = d[k]
    # keep only known columns; a cleared field (phone='') is intentionally kept as None below via the store
    return {k: v for k, v in out.items() if k in _PROFILE_COLS and (v is not None or k == 'phone')}


def _profile_out(row: dict | None) -> dict | None:
    if not row:
        return row
    r = dict(row)
    r['handedness'] = {'R': 'right', 'L': 'left'}.get(r.get('handed'))   # alias the app reads
    r.setdefault('name', r.get('display_name'))
    # Older rows (pre-020) may have only display_name — derive first/last the same way the migration does.
    if r.get('first_name') is None and r.get('display_name'):
        parts = str(r['display_name']).split(' ', 1)
        r['first_name'] = parts[0]
        r['last_name'] = parts[1] if len(parts) > 1 else None
    r['has_avatar'] = bool(r.get('avatar_path'))                         # the app shows the photo when set
    return r


class MemoryStore:
    def __init__(self):
        self.sessions, self.shots, self.snapshots, self.feedback = {}, {}, {}, {}
        self.feedback_rows = []       # the one retained feedback store (DEC-059); survives shot/session/account deletion
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
        d = dict(data or {})
        make_current = bool(d.pop('make_current', False) or d.pop('is_current', False))
        name = d.get('nickname') or d.get('name')
        b = dict(id=_new_id(), user_id=user_id, ball_configuration_id=_new_id(), is_current=False, retired=False,
                 ball_model_id=d.get('ball_model_id'), nickname=name, name=name,
                 weight_lb=d.get('weight_lb'), color_desc=d.get('color_desc'),
                 layout_system=d.get('layout_system'), layout=d.get('layout'), surface=d.get('surface'))
        self.arsenal[b['id']] = b
        if make_current:
            self.set_current_ball(user_id, b['id'])
        return self.arsenal[b['id']]

    def set_current_ball(self, user_id, ball_id):
        if not (self.arsenal.get(ball_id) or {}).get('user_id') == user_id:
            return None
        for b in self.arsenal.values():
            if b.get('user_id') == user_id:
                b['is_current'] = (b['id'] == ball_id)
        return self.arsenal[ball_id]

    def update_ball(self, user_id, ball_id, patch):
        b = self.arsenal.get(ball_id)
        if not b or b.get('user_id') != user_id:
            return None
        p = dict(patch or {})
        if p.pop('is_current', False) or p.pop('make_current', False):
            self.set_current_ball(user_id, ball_id)
        if p.get('name') is not None:
            b['nickname'] = b['name'] = p['name']
        for k in ('nickname', 'weight_lb', 'color_desc', 'ball_model_id', 'layout_system', 'layout', 'surface', 'retired'):
            if p.get(k) is not None:
                b[k] = p[k]
        b.setdefault('name', b.get('nickname'))
        return self.arsenal[ball_id]

    def current_ball(self, user_id):
        return next((b for b in self.arsenal.values()
                     if b.get('user_id') == user_id and b.get('is_current')), None)

    def get_shot_intent(self, user_id, shot_id):
        sh = self.get_shot(user_id, shot_id)
        return (sh or {}).get('intent') or None

    def last_setup(self, user_id):
        """Last-used ball + oil + target for prefilling Setup (MVP-09): the user's most recent LIVE shot's ball
        and intent, and that session's oil pattern. Nulls when there's no live history yet."""
        live = [sh for sh in self.shots.values()
                if sh.get('user_id') == user_id and (sh.get('source') or 'live') != 'upload' and sh.get('session_id')]
        shot = max(live, key=lambda s: s.get('created_at') or 0, default=None)
        if not shot:
            return {'user_ball_id': None, 'ball_configuration_id': None, 'oil_pattern_id': None, 'intent': None}
        sess = self.sessions.get(shot.get('session_id')) or {}
        return {'user_ball_id': shot.get('user_ball_id'),
                'ball_configuration_id': shot.get('ball_configuration_id'),
                # DEC-097: recommendations/ball-reaction read the oil stored ON the shot (fallback: the session's,
                # for shots recorded before per-shot oil existed) — never the session's current value.
                'oil_pattern_id': shot.get('oil_pattern_id') or sess.get('oil_pattern_id'),
                'intent': self.get_shot_intent(user_id, shot['id'])}

    # profile / sensors / catalog (MemoryStore: in-memory; catalog/oil are empty offline)
    def get_profile(self, user_id):
        return _profile_out(self.profiles.get(user_id))

    def put_profile(self, user_id, data):
        patch = _profile_in(data)
        p = dict(self.profiles.get(user_id, {}), user_id=user_id, **patch)
        # Keep display_name = "First Last" for existing readers whenever either name changes (DEC-087).
        if 'first_name' in patch or 'last_name' in patch:
            dn = _compose_display_name(p.get('first_name'), p.get('last_name'))
            if dn:
                p['display_name'] = dn
        self.profiles[user_id] = p
        return _profile_out(p)

    def get_notify_prefs(self, user_id):
        p = self.profiles.get(user_id) or {}
        return {'coaching_launch': bool(p.get('notify_coaching_launch'))}      # DEC-084

    def set_notify_pref(self, user_id, key, value):
        if key != 'coaching_launch':
            return self.get_notify_prefs(user_id)
        p = dict(self.profiles.get(user_id, {}), user_id=user_id,
                 notify_coaching_launch=bool(value), notify_coaching_launch_at=time.time())
        self.profiles[user_id] = p
        return self.get_notify_prefs(user_id)

    def set_avatar(self, user_id, path, updated_at):
        self.profiles[user_id] = dict(self.profiles.get(user_id, {}), user_id=user_id,
                                      avatar_path=path, avatar_updated_at=updated_at)

    def get_avatar(self, user_id):
        p = self.profiles.get(user_id) or {}
        return {'avatar_path': p.get('avatar_path'), 'avatar_updated_at': p.get('avatar_updated_at')}

    def clear_avatar(self, user_id):
        p = self.profiles.get(user_id)
        if p:
            p['avatar_path'] = None
            p['avatar_updated_at'] = None

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

    # Storage (clip upload path). MemoryStore simulates a bucket on local disk so the endpoints can be
    # exercised offline; PgStore talks to real Supabase Storage. The clip never persists — it's downloaded,
    # analyzed, then deleted.
    def _local_storage_path(self, bucket, path):
        import tempfile
        return os.path.join(tempfile.gettempdir(), 'ls_storage', bucket, path)

    def storage_signed_upload_url(self, bucket, path):
        p = self._local_storage_path(bucket, path)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        return {'path': path, 'upload_url': 'file://' + p}

    def storage_download(self, bucket, path):
        with open(self._local_storage_path(bucket, path), 'rb') as f:
            return f.read()

    def storage_delete(self, bucket, path):
        try:
            os.remove(self._local_storage_path(bucket, path))
        except OSError:
            pass

    def storage_upload(self, bucket, path, data, content_type='application/octet-stream'):
        p = self._local_storage_path(bucket, path)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'wb') as f:
            f.write(data)
        return {'path': path}

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
        meta = dict(meta)
        # DEC-097: lock the oil pattern on the shot at record time. Prefer the value the app sent for THIS clip;
        # otherwise backfill from the session's current oil so the shot keeps a concrete pattern.
        if meta.get('oil_pattern_id') is None and session_id:
            meta['oil_pattern_id'] = (self.sessions.get(session_id) or {}).get('oil_pattern_id')
        sh = dict(id=_new_id(), user_id=user_id, session_id=session_id, created_at=time.time(),
                  record=None, result=None, **meta)
        self.shots[sh['id']] = sh
        return sh

    def save_shot_result(self, shot_id, record, result, algo_version=None):
        sh = self.shots.get(shot_id)
        if sh:
            sh['record'] = record
            sh['result'] = result
            sh['analysis_status'] = 'analyzed'      # DEC-086
            sh['failure_code'] = None
            sh['failure_stage'] = None
            sh['algorithm_version'] = algo_version
            sh['analyzed_at'] = time.time()

    def mark_shot_failed(self, shot_id, code, stage):
        """DEC-086: record a failed analysis on the shot row (so Lab › Uploads can show 'Couldn't analyze')."""
        sh = self.shots.get(shot_id)
        if sh:
            sh['analysis_status'] = 'failed'
            sh['failure_code'] = code
            sh['failure_stage'] = stage
            sh['result'] = {'ok': False, 'failure_code': code}
            sh['analyzed_at'] = time.time()

    def log_analysis_attempt(self, row):
        """DEC-086: append one analysis-attempt row (success or failure). Retained, never FK-cascaded.
        DEC-098 §2: fills user_ref (pseudonym) from user_id when the caller didn't."""
        if not hasattr(self, 'analysis_attempts'):
            self.analysis_attempts = []
        r = dict(row); r.setdefault('id', _new_id()); r.setdefault('created_at', time.time())
        if r.get('user_ref') is None and r.get('user_id'):
            r['user_ref'] = _user_ref(r.get('user_id'))
        self.analysis_attempts.append(r)
        return r

    # ----------------------------------------------------------------- §2 instrumentation (DEC-098)
    def log_api_request(self, row):
        """DEC-098 §2 (M2): record one API request. Best-effort; pseudonymises user_id -> user_ref and never
        stores the raw id, bodies or tokens (the caller already excludes those)."""
        if not hasattr(self, 'api_requests'):
            self.api_requests = []
        r = dict(row)
        if r.get('user_id') is not None:
            r['user_ref'] = r.get('user_ref') or _user_ref(r.pop('user_id'))
        r.pop('user_id', None)
        r.setdefault('id', _new_id()); r.setdefault('created_at', time.time())
        self.api_requests.append(r)
        return r

    def log_events(self, rows):
        """DEC-098 §2 (M3): ingest product events, idempotent on client_event_id (a retried batch never
        double-counts). Pseudonymises user_id. Returns the number of NEW rows inserted."""
        if not hasattr(self, 'product_events'):
            self.product_events = []
        seen = {e.get('client_event_id') for e in self.product_events if e.get('client_event_id')}
        inserted = 0
        for row in (rows or []):
            cid = row.get('client_event_id')
            if cid and cid in seen:
                continue
            r = dict(row)
            if r.get('user_id') is not None:
                r['user_ref'] = r.get('user_ref') or _user_ref(r.pop('user_id'))
            r.pop('user_id', None)
            r.setdefault('id', _new_id()); r.setdefault('created_at', time.time())
            self.product_events.append(r)
            if cid:
                seen.add(cid)
            inserted += 1
        return inserted

    def record_storage_snapshot(self, rows):
        """DEC-098 §2 (M5): record storage/DB size snapshot rows (written by ops/storage_snapshot.py)."""
        if not hasattr(self, 'storage_snapshots'):
            self.storage_snapshots = []
        out = []
        for row in (rows or []):
            r = dict(row); r.setdefault('id', _new_id()); r.setdefault('captured_at', time.time())
            self.storage_snapshots.append(r); out.append(r)
        return out

    def get_shot(self, user_id, shot_id):
        sh = self.shots.get(shot_id)
        return sh if sh and sh['user_id'] == user_id else None

    def patch_shot(self, user_id, shot_id, patch):
        sh = self.get_shot(user_id, shot_id)
        if sh:
            sh.update(patch)
        return sh

    def set_content_hash(self, shot_id, content_hash):
        sh = self.shots.get(shot_id)
        if sh:
            sh['content_hash'] = content_hash

    def find_upload_by_hash(self, user_id, content_hash):
        """An earlier standalone upload with the same clip bytes (DEC-055 dedupe), or None."""
        if not content_hash:
            return None
        return next((sh for sh in self.shots.values()
                     if sh.get('user_id') == user_id and sh.get('source') == 'upload'
                     and sh.get('content_hash') == content_hash), None)

    def find_shot_by_hash(self, user_id, content_hash, session_id):
        """A shot already analyzed from the same clip bytes in this session — live-shot retry idempotency: a
        dropped-connection re-send carries identical bytes, so return the existing shot instead of duplicating."""
        if not content_hash or session_id is None:
            return None
        return next((sh for sh in self.shots.values()
                     if sh.get('user_id') == user_id and sh.get('session_id') == session_id
                     and sh.get('content_hash') == content_hash), None)

    def shots_for_session(self, session_id):
        return [sh for sh in self.shots.values() if sh['session_id'] == session_id]

    def user_shots(self, user_id):
        return [sh for sh in self.shots.values() if sh['user_id'] == user_id]

    def reset_user_data(self, user_id):
        """Clear ALL per-user data (keeps the profile row, so is_staged/staged_kind survive). Used by the
        staged-account seed --reset; the caller guards on is_staged. Idempotent."""
        self.sessions = {k: v for k, v in self.sessions.items() if v.get('user_id') != user_id}
        self.shots = {k: v for k, v in self.shots.items() if v.get('user_id') != user_id}
        self.snapshots.pop(user_id, None)
        self.feedback_rows = [f for f in self.feedback_rows if f.get('user_id') != user_id]
        self.arsenal = {k: v for k, v in self.arsenal.items() if v.get('user_id') != user_id}
        self.sensors = {k: v for k, v in self.sensors.items() if v.get('user_id') != user_id}
        self.tier_state.pop(user_id, None)
        self.tier_events.pop(user_id, None)
        self.ach_progress = {k: v for k, v in self.ach_progress.items() if k[0] != user_id}
        self.ach_unlocks = {k: v for k, v in self.ach_unlocks.items() if k[0] != user_id}
        self.ach_pins.pop(user_id, None)
        self.activity.pop(user_id, None)
        self.notifications.pop(user_id, None)
        self.findings.pop(user_id, None)
        self.baselines = {k: v for k, v in self.baselines.items() if k[0] != user_id}

    # score
    def save_snapshot(self, user_id, snapshot):
        self.snapshots.setdefault(user_id, []).append(dict(snapshot, computed_at=time.time()))

    def latest_score(self, user_id):
        snaps = self.snapshots.get(user_id) or []
        return snaps[-1] if snaps else None

    def score_history(self, user_id):
        return list(self.snapshots.get(user_id) or [])

    # feedback — one retained store for every source (DEC-059 / FEEDBACK_STORE_SPEC). Write-and-keep:
    # nothing reads it to change a measurement, rule, score or advice.
    _FEEDBACK_SOURCES = ('shot_note', 'session_feedback', 'advice_rating', 'form_note', 'general')

    def add_feedback(self, user_id, data):
        """Write one feedback row (any source). Links (shot/session/recommendation) are kept while the
        source exists and set null when it's deleted; the row itself is retained. triage_* are owner-only
        and start at their defaults."""
        d = dict(data or {})
        tags = d.get('tags')
        row = dict(
            id=d.get('id') or _new_id(), user_id=user_id, user_ref=d.get('user_ref'),
            source=d.get('source') or 'general', app_phase=d.get('app_phase') or 'dev',
            app_version=d.get('app_version'), core_version=d.get('core_version'),
            rules_version=d.get('rules_version'), formula_version=d.get('formula_version'),
            session_id=d.get('session_id'), shot_id=d.get('shot_id'),
            recommendation_id=d.get('recommendation_id'), capture_mode=d.get('capture_mode'),
            is_upload=bool(d.get('is_upload', False)), rating=d.get('rating'), thumbs=d.get('thumbs'),
            tags=list(tags) if tags else [], text=d.get('text'), context=d.get('context'),
            diagnostics=d.get('diagnostics'), triage_status='new', owner_notes=None, action_ref=None,
            anonymized_at=None, created_at=time.time(), updated_at=time.time(),
            # mirror migration 018's trigger: staged feedback is flagged from the author's profile so it is
            # excluded from feedback review/analytics (DEC-063).
            is_staged=bool((self.profiles.get(user_id) or {}).get('is_staged')))
        self.feedback_rows.append(row)
        return row

    def list_feedback(self, user_id):
        return [r for r in self.feedback_rows if r.get('user_id') == user_id]

    def save_feedback(self, user_id, session_id, fb):
        row = dict(id=_new_id(), user_id=user_id, session_id=session_id, created_at=time.time(), **fb)
        self.feedback.setdefault(session_id, []).append(row)
        # route session-end feedback into the retained store, same id (DEC-059 §7)
        self.add_feedback(user_id, {
            'id': row['id'], 'source': 'session_feedback', 'session_id': session_id,
            'app_phase': fb.get('app_phase'), 'app_version': fb.get('app_version'),
            'core_version': fb.get('core_version'), 'rules_version': fb.get('rules_version'),
            'formula_version': fb.get('formula_version'), 'rating': fb.get('rating'),
            'tags': fb.get('tags'), 'text': fb.get('text'), 'context': fb.get('context'),
            'diagnostics': fb.get('diagnostics')})
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
            if sh.get('source') == 'upload':            # uploads are standalone; never feed the score (DEC-055)
                continue
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

    def shot_points(self, user_id):
        """Per-shot context for metric-detail stats (MVP-08): live analyzed shots annotated with session, ball,
        oil pattern, time and record. Uploads excluded (DEC-055)."""
        out = []
        for sh in sorted(self.user_shots(user_id), key=lambda s: s.get('created_at') or 0):
            if sh.get('source') == 'upload':
                continue
            rec = sh.get('record')
            if not rec or not rec.get('metrics'):
                continue
            sess = self.sessions.get(sh.get('session_id')) or {}
            out.append(dict(shot_id=sh['id'], created_at=sh.get('created_at'), session_id=sh.get('session_id'),
                            ball=sh.get('ball_configuration_id') or sh.get('user_ball_id'),
                            pattern=sh.get('oil_pattern_id') or sess.get('oil_pattern_id'), record=rec))  # DEC-097 per-shot oil
        return out

    def read_form_records(self, user_id, window_days=None):
        """Prior FORM shot records for the user (source 'lanesight_form'), ordered oldest->newest. A form
        record is discriminated by its 'form_version' key, so it never mixes with ball shots. Offline: memory."""
        shots = sorted(self.user_shots(user_id), key=lambda s: s.get('created_at') or 0)
        now = time.time()
        out = []
        for sh in shots:
            if sh.get('source') == 'upload':            # standalone form uploads never feed Stats (DEC-055)
                continue
            rec = sh.get('record')
            if not rec or not rec.get('form_version') or not rec.get('metrics'):
                continue
            if (window_days is not None and sh.get('created_at')
                    and (now - sh['created_at']) > window_days * 86400):
                continue
            rec = dict(rec)
            rec.setdefault('shot_id', sh['id'])
            out.append(rec)
        return out

    def form_rules(self):
        from .rules_seed import FORM_RULES
        return [dict(r) for r in FORM_RULES]

    def drills(self):
        from .rules_seed import DRILLS
        return [dict(d) for d in DRILLS]

    # Form swing-timing baseline (DEC-057 §0.4): stored on the profile as jsonb. Shapes:
    #   {'mode': 'entered', 'pushaway_time':…, 'backswing_time':…, 'downswing_time':…, 'release_time':…,
    #    'total':…, 'set_at':…}  — the values the bowler typed in Profile › Form baseline.
    #   {'mode': 'average'}      — "use my average": the engine fills it from the view='form' baselines.
    # None  — no baseline set yet (the Form card shows "building" + a prompt).
    def get_form_baseline(self, user_id):
        return (self.get_profile(user_id) or {}).get('form_baseline')

    def set_form_baseline(self, user_id, baseline):
        return self.put_profile(user_id, {'form_baseline': baseline})

    def completed_sessions(self, user_id):
        return [s for s in self.list_sessions(user_id) if s.get('ended_at')]

    def arsenal_count(self, user_id):
        return len(self.list_arsenal(user_id))

    def _ball_oil_names(self, user_id):
        """(ball_names, oil_names): id -> display name, for annotating shot rows with the ball/oil used
        (DEC-097). Ball keyed by both user_ball_id and ball_configuration_id; oil by pattern id."""
        oil = {p['id']: p.get('name') for p in (self.oil_patterns() or []) if p.get('id')}
        ball = {}
        for b in (self.list_arsenal(user_id) or []):
            label = b.get('name') or b.get('nickname') or b.get('model_name')
            for k in (b.get('ball_configuration_id'), b.get('id')):
                if k:
                    ball[k] = label
        return ball, oil

    def session_shots(self, user_id, session_id):
        """Rows for the live Session screen: id, state, key metrics, status, and the ball/oil used (DEC-097)."""
        ball_names, oil_names = self._ball_oil_names(user_id)
        sess_oil = (self.sessions.get(session_id) or {}).get('oil_pattern_id')
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
            ball_id = sh.get('user_ball_id') or sh.get('ball_configuration_id')
            oil_id = sh.get('oil_pattern_id') or sess_oil          # pre-DEC-097 shots fall back to the session oil
            out.append(dict(id=sh['id'], state=state, created_at=sh.get('created_at'),
                            classification=(rec.get('insights') or {}).get('classification'),
                            source=sh.get('source'), metrics=key,
                            user_ball_id=sh.get('user_ball_id'), oil_pattern_id=oil_id,
                            ball_name=ball_names.get(ball_id), oil_name=oil_names.get(oil_id)))
        return out

    def session_records(self, user_id, session_id):
        """Full analyzed ShotRecord dicts for a session (for the summary aggregates / typical comparison)."""
        out = []
        for sh in sorted(self.shots_for_session(session_id), key=lambda s: s.get('created_at') or 0):
            if sh.get('user_id') != user_id:
                continue
            rec = sh.get('record') or {}
            if rec.get('metrics'):
                out.append(rec)
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
        # Scope to the Home Recent activity kinds (DEC-055): completed practice sessions, achievement
        # unlocks and tier changes only — no uploads, no personal-best or other event types.
        rows = [r for r in (self.activity.get(user_id) or []) if r.get('kind') in _ACTIVITY_KINDS]
        return sorted(rows, key=lambda r: r['created_at'], reverse=True)

    def list_uploads(self, user_id):
        """Standalone upload analyses (DEC-055): shots with source='upload', newest first. Shape mirrors
        session_shots rows so Lab › Uploads can show speed/entry and a SHOT/FORM badge; each opens its result."""
        out = []
        for sh in sorted(self.user_shots(user_id), key=lambda s: s.get('created_at') or 0, reverse=True):
            if sh.get('source') != 'upload':
                continue
            rec = sh.get('record') or {}
            metrics = rec.get('metrics') or {}
            key = {k: (metrics.get(k) or {}).get('value')
                   for k in ('ball_speed', 'rev_rate', 'entry_board', 'entry_angle', 'arrows_board')}
            state = sh.get('analysis_status') or (                         # DEC-086; legacy fallback
                'analyzed' if (rec and metrics)
                else ('failed' if (sh.get('result') or {}).get('ok') is False else 'pending'))
            out.append(self._upload_row(sh, state, key, (rec.get('insights') or {}).get('classification')))
        return out

    @staticmethod
    def _upload_row(sh, state, key, classification):
        """Shared Lab › Uploads row shape (identical types in both stores — the ISO/epoch drift broke this)."""
        from lanesight_core.failures import failure_block
        row = dict(id=sh['id'], state=state, created_at=_ts_epoch(sh.get('created_at')),
                   capture_mode=sh.get('capture_mode') or 'shot', classification=classification,
                   source='upload', metrics=key,
                   failure_code=sh.get('failure_code'), failure_stage=sh.get('failure_stage'),
                   failure_title=None, failure_message=None, tip=None)
        if state == 'failed':
            fb = failure_block(sh.get('failure_code') or 'UNKNOWN_LEGACY', sh.get('failure_stage') or 'internal')
            row['failure_title'], row['failure_message'], row['tip'] = fb['user_title'], fb['user_message'], fb.get('tip')
        return row

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
    @staticmethod
    def _anonymize_diagnostics(diag):
        """Drop identifying fields (device name, email, IP) but keep the rest (timings, fps...)."""
        if not isinstance(diag, dict):
            return diag
        drop = {'device', 'device_name', 'device_id', 'email', 'ip', 'ip_address'}
        return {k: v for k, v in diag.items() if k not in drop}

    def anonymize_feedback(self, user_id):
        """DEC-059: deleting the account KEEPS the feedback but de-identifies it — user_id -> null,
        anonymized_at set, identifying diagnostics stripped. user_ref and free text are kept so the
        owner can still group and read it. Links to deleted shots/sessions are nulled (ON DELETE SET NULL)."""
        n = 0
        for r in self.feedback_rows:
            if r.get('user_id') == user_id:
                r['user_id'] = None
                r['anonymized_at'] = time.time()
                r['session_id'] = None
                r['shot_id'] = None
                r['recommendation_id'] = None
                r['diagnostics'] = self._anonymize_diagnostics(r.get('diagnostics'))
                n += 1
        return n

    def delete_user(self, user_id):
        self.anonymize_feedback(user_id)                      # keep feedback (de-identified), never delete it
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

    # Sessions are DB-backed (not just the in-memory mirror), so past sessions survive a cold Cloud Run
    # instance — needed for SessionReview, GET /sessions, and the 'vs your typical' comparison (MVP-07).
    def get_session(self, user_id, sid):
        rows = self._get('sessions', f'id=eq.{sid}&user_id=eq.{user_id}&select=*')
        return _epoch_session(rows[0]) if rows else None

    def list_sessions(self, user_id):
        # Embed each session's shot capture modes so the app can route a form session to the Form-session
        # screen (Active Session·Form / Form summary) vs the shot session review. 'form' only when the
        # session's shots are form (and not mixed with ball shots); else 'shot'; None when it has no shots.
        rows = self._get('sessions', f'user_id=eq.{user_id}&select=*,shots(capture_mode)&order=started_at.desc')
        out = []
        for r in rows:
            modes = {s.get('capture_mode') for s in (r.pop('shots', None) or []) if s.get('capture_mode')}
            r['capture_mode'] = ('form' if (modes and modes <= {'form'}) else ('shot' if modes else None))
            out.append(_epoch_session(r))
        return out

    def end_session(self, user_id, sid):
        if not self.get_session(user_id, sid):
            return None
        from datetime import datetime, timezone
        now = datetime.now(timezone.utc)
        self._req(f'sessions?id=eq.{sid}', 'PATCH', {'ended_at': now.isoformat()})   # ISO for the DB column
        return dict(session_id=sid, shots=len(self.session_shots(user_id, sid)),
                    ended_at=now.timestamp())                                        # epoch for the API contract

    # Shots are DB-backed (not just the in-memory mirror) — so a shot card opens from a past session / activity
    # and survives a cold Cloud Run instance. GET /shots/{id} returned 404 for seeded / post-restart shots before.
    def get_shot(self, user_id, shot_id):
        rows = self._get('shots', f'id=eq.{shot_id}&user_id=eq.{user_id}&select=*')
        if not rows:
            return None
        sh = rows[0]
        sh['created_at'] = _ts_epoch(sh.get('created_at'))
        return sh

    def patch_shot(self, user_id, shot_id, patch):
        if not self.get_shot(user_id, shot_id):
            return None
        self._req(f'shots?id=eq.{shot_id}', 'PATCH', patch)   # persist the sensor answer / feedback flag
        return self.get_shot(user_id, shot_id)

    _FEEDBACK_COLS = ('id', 'source', 'app_phase', 'app_version', 'core_version', 'rules_version',
                      'formula_version', 'user_id', 'user_ref', 'session_id', 'shot_id',
                      'recommendation_id', 'capture_mode', 'is_upload', 'rating', 'thumbs', 'tags',
                      'text', 'context', 'diagnostics')

    def add_feedback(self, user_id, data):
        row = super().add_feedback(user_id, data)      # mirror in memory + normalize
        self._post('feedback', {k: row.get(k) for k in self._FEEDBACK_COLS})
        return row

    def save_feedback(self, user_id, session_id, fb):
        # super() mirrors memory AND routes a 'session_feedback' row into feedback via self.add_feedback
        # (PgStore.add_feedback -> the feedback table). Keep the legacy session_feedback table populated too.
        row = super().save_feedback(user_id, session_id, fb)
        self._post('session_feedback', {'id': row['id'], 'session_id': session_id, 'user_id': user_id,
                   'rating': fb.get('rating'), 'tags': fb.get('tags', []), 'text': fb.get('text'),
                   'diagnostics': fb.get('diagnostics'), 'app_version': fb.get('app_version'),
                   'core_version': fb.get('core_version'), 'formula_version': fb.get('formula_version')})
        return row

    def score_history(self, user_id):
        # Cloud Run is stateless (the in-memory snapshots from MemoryStore don't survive a cold start), so
        # the durable history lives in the score_snapshot table. Return it oldest→newest with computed_at as
        # an epoch float, matching MemoryStore (used by the Score trend and the DEC-083 30-day part deltas).
        rows = self._get('score_snapshot', f'user_id=eq.{user_id}&order=computed_at.asc'
                         '&select=id,computed_at,eligible,score,s_perf,a_acc,c_cons,p_power,eligibility,tier')
        return [dict(r, computed_at=_ts_epoch(r.get('computed_at'))) for r in rows]

    def latest_score(self, user_id):
        rows = self._get('score_snapshot', f'user_id=eq.{user_id}&order=computed_at.desc&limit=1'
                         '&select=id,computed_at,eligible,score,s_perf,a_acc,c_cons,p_power,eligibility,tier')
        return dict(rows[0], computed_at=_ts_epoch(rows[0].get('computed_at'))) if rows else None

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
                  'sensor_id': meta.get('sensor_id'),
                  'ball_configuration_id': meta.get('ball_configuration_id'), 'user_ball_id': meta.get('user_ball_id'),
                  'oil_pattern_id': sh.get('oil_pattern_id')})     # DEC-097 per-shot oil (backfilled from session above)
        # per-shot intent actually USED (feet/laydown/arrows/breakpoint) + the SUGGESTED boards it came from
        # (if "Apply this move" was used, before any edit). created_at defaults so the Accuracy engine can
        # require "intent set before the shot".
        intent = meta.get('intent') or {}
        suggested = meta.get('suggested') or {}
        cols = {k: intent.get(k) for k in ('feet_board', 'laydown_board', 'arrows_board', 'breakpoint_board', 'breakpoint_ft')}
        cols.update(suggested_feet_board=suggested.get('feet_board'),
                    suggested_arrows_board=suggested.get('arrows_board'),
                    suggested_breakpoint_board=suggested.get('breakpoint_board'))
        if any(v is not None for v in cols.values()):
            self._req('shot_intents', 'POST', {'shot_id': sh['id'], **cols})
        return sh

    def set_content_hash(self, shot_id, content_hash):
        # Best-effort: the content_hash column lands in migration 016. Until then this no-ops (and dedupe stays
        # off) rather than failing the upload, so applying 016 is non-breaking.
        try:
            self._req(f'shots?id=eq.{shot_id}', 'PATCH', {'content_hash': content_hash})
        except Exception:
            pass

    def find_upload_by_hash(self, user_id, content_hash):
        if not content_hash:
            return None
        try:
            rows = self._get('shots', f"user_id=eq.{user_id}&source=eq.upload&"
                                       f"content_hash=eq.{content_hash}&select=*&limit=1")
        except Exception:
            return None                                    # column absent (pre-016) -> dedupe disabled
        return rows[0] if rows else None

    def find_shot_by_hash(self, user_id, content_hash, session_id):
        if not content_hash or session_id is None:
            return None
        try:
            rows = self._get('shots', f"user_id=eq.{user_id}&session_id=eq.{session_id}&"
                                       f"content_hash=eq.{content_hash}&select=*&limit=1")
        except Exception:
            return None
        return rows[0] if rows else None

    def save_shot_result(self, shot_id, record, result, algo_version=None):
        MemoryStore.save_shot_result(self, shot_id, record, result, algo_version)
        insights = record.get('insights') or {}
        import datetime as _dt
        self._req(f'shots?id=eq.{shot_id}', 'PATCH', {
            'record': record, 'trajectory': record.get('trajectory'), 'key_points': record.get('key_points'),
            'classification': insights.get('classification'),
            'analysis_status': 'analyzed', 'failure_code': None, 'failure_stage': None,   # DEC-086
            'algorithm_version': algo_version,
            'analyzed_at': _dt.datetime.now(_dt.timezone.utc).isoformat()})
        rows = [{'shot_id': shot_id, 'metric': name, 'value': mm.get('value'), 'unit': mm.get('unit'),
                 'confidence': mm.get('confidence'), 'status': mm.get('status'),
                 'source': mm.get('source', 'lanesight_video'),
                 'algorithm_version': mm.get('algorithm_version'), 'note': mm.get('note')}
                for name, mm in (record.get('metrics') or {}).items()]
        if rows:
            self._req('measurements', 'POST', rows, prefer='resolution=merge-duplicates,return=minimal')

    def mark_shot_failed(self, shot_id, code, stage):
        MemoryStore.mark_shot_failed(self, shot_id, code, stage)
        import datetime as _dt
        self._req(f'shots?id=eq.{shot_id}', 'PATCH', {
            'analysis_status': 'failed', 'failure_code': code, 'failure_stage': stage,
            'analyzed_at': _dt.datetime.now(_dt.timezone.utc).isoformat()})

    def log_analysis_attempt(self, row):
        """DEC-086: one row per analysis attempt (success + failure) in the retained analysis_attempt table.
        Best-effort — the caller swallows errors so logging can never fail an analysis.
        DEC-098 §2: fills user_ref (pseudonym) and carries the cost jsonb the API computed."""
        body = {k: v for k, v in (row or {}).items() if v is not None}
        body.setdefault('id', _new_id())
        if body.get('user_ref') is None and body.get('user_id'):
            body['user_ref'] = _user_ref(body.get('user_id'))
        self._req('analysis_attempt', 'POST', body, prefer='return=minimal')
        return body

    def log_api_request(self, row):
        """DEC-098 §2 (M2): POST one api_request row (pseudonymised, no raw user_id/bodies/tokens)."""
        r = {k: v for k, v in (row or {}).items() if v is not None}
        if r.get('user_id'):
            r['user_ref'] = r.get('user_ref') or _user_ref(r.pop('user_id'))
        r.pop('user_id', None)
        r.setdefault('id', _new_id())
        self._req('api_request', 'POST', r, prefer='return=minimal')
        return r

    def log_events(self, rows):
        """DEC-098 §2 (M3): POST product_event rows, idempotent on client_event_id (ignore-duplicates)."""
        batch = []
        for row in (rows or []):
            r = {k: v for k, v in (row or {}).items() if v is not None}
            if r.get('user_id'):
                r['user_ref'] = r.get('user_ref') or _user_ref(r.pop('user_id'))
            r.pop('user_id', None)
            r.setdefault('id', _new_id())
            batch.append(r)
        if batch:
            self._req('product_event', 'POST', batch, prefer='resolution=ignore-duplicates,return=minimal')
        return len(batch)

    def record_storage_snapshot(self, rows):
        """DEC-098 §2 (M5): POST storage_snapshot rows."""
        batch = [{**{k: v for k, v in r.items() if v is not None}, 'id': r.get('id') or _new_id()}
                 for r in (rows or [])]
        if batch:
            self._req('storage_snapshot', 'POST', batch, prefer='return=minimal')
        return batch

    # --- reads / profile / sensors / catalog (PostgREST) ---
    def _get(self, table, query=''):
        import json, urllib.request, urllib.error
        url = self._rest + table + (('?' + query) if query else '')
        req = urllib.request.Request(url, headers={'apikey': self._key, 'Authorization': f'Bearer {self._key}',
                                                   'Accept': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                txt = r.read().decode()
        except urllib.error.HTTPError as e:
            raise RuntimeError(f'PostgREST GET {table} -> {e.code}: {e.read().decode()[:300]}')
        return json.loads(txt) if txt.strip() else []

    def _req(self, path, method, body=None, prefer='return=minimal'):
        import json, urllib.request, urllib.error
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self._rest + path, data=data, method=method, headers={
            'apikey': self._key, 'Authorization': f'Bearer {self._key}',
            'Content-Type': 'application/json', 'Prefer': prefer})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                if r.status not in (200, 201, 204):
                    raise RuntimeError(f'PostgREST {method} {path} -> {r.status}')
        except urllib.error.HTTPError as e:
            raise RuntimeError(f'PostgREST {method} {path} -> {e.code}: {e.read().decode()[:300]}')

    def get_profile(self, user_id):
        rows = self._get('profiles', f'user_id=eq.{user_id}&select=*')
        return _profile_out(rows[0]) if rows else None

    def put_profile(self, user_id, data):
        patch = _profile_in(data)
        row = {'user_id': user_id, **patch}
        # Maintain display_name = "First Last" from the merged (existing + patch) names (DEC-087).
        if 'first_name' in patch or 'last_name' in patch:
            existing = self.get_profile(user_id) or {}
            dn = _compose_display_name(patch.get('first_name', existing.get('first_name')),
                                       patch.get('last_name', existing.get('last_name')))
            if dn:
                row['display_name'] = dn
        self._req('profiles', 'POST', row, prefer='resolution=merge-duplicates,return=minimal')
        return self.get_profile(user_id)

    def get_notify_prefs(self, user_id):                                       # DEC-084
        try:
            rows = self._get('profiles', f'user_id=eq.{user_id}&select=notify_coaching_launch')
            return {'coaching_launch': bool(rows and rows[0].get('notify_coaching_launch'))}
        except Exception:                 # column lands in migration 021; tolerate its absence
            return {'coaching_launch': False}

    def set_notify_pref(self, user_id, key, value):
        if key == 'coaching_launch':
            import datetime as _dt
            try:
                self._req('profiles', 'POST',
                          {'user_id': user_id, 'notify_coaching_launch': bool(value),
                           'notify_coaching_launch_at': _dt.datetime.now(_dt.timezone.utc).isoformat()},
                          prefer='resolution=merge-duplicates,return=minimal')
            except Exception:
                pass
        return self.get_notify_prefs(user_id)

    def set_avatar(self, user_id, path, updated_at):
        self._req('profiles', 'POST', {'user_id': user_id, 'avatar_path': path, 'avatar_updated_at': updated_at},
                  prefer='resolution=merge-duplicates,return=minimal')

    def get_avatar(self, user_id):
        rows = self._get('profiles', f'user_id=eq.{user_id}&select=avatar_path,avatar_updated_at')
        return rows[0] if rows else {'avatar_path': None, 'avatar_updated_at': None}

    def clear_avatar(self, user_id):
        self._req(f'profiles?user_id=eq.{user_id}', 'PATCH', {'avatar_path': None, 'avatar_updated_at': None})

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
        qp = ('select=id,manufacturer,name,coverstock,core_type,rg,diff,factory_finish,'
              'ls_hook,ls_length,ls_backend,image_url'
              f'&order=manufacturer,name&limit={int(limit)}')
        if q:
            from urllib.parse import quote
            qq = quote(str(q), safe='')
            qp += f'&or=(name.ilike.*{qq}*,manufacturer.ilike.*{qq}*)'
        return self._get('ball_models', qp)

    def oil_patterns(self):
        return self._get('oil_patterns', 'select=*&order=name')

    @staticmethod
    def _arsenal_row(b):
        """Flatten a user_balls row (+embedded model + latest configuration) into the app's arsenal shape."""
        model = b.get('ball_models') or {}
        cfgs = sorted(b.get('ball_configurations') or [], key=lambda c: c.get('version') or 0)
        cfg = cfgs[-1] if cfgs else {}
        name = (f"{model.get('manufacturer', '')} {model.get('name', '')}".strip() or b.get('nickname'))
        return {'id': b['id'], 'name': name, 'nickname': b.get('nickname'), 'ball_model_id': b.get('ball_model_id'),
                'manufacturer': model.get('manufacturer'), 'model_name': model.get('name'),
                'image_url': model.get('image_url'), 'weight_lb': b.get('weight_lb'), 'color_desc': b.get('color_desc'),
                # Factory specs from the embedded catalog model (for the Ball setup view/edit screen).
                'coverstock': model.get('coverstock'), 'core_type': model.get('core_type'),
                'rg': model.get('rg'), 'diff': model.get('diff'), 'factory_finish': model.get('factory_finish'),
                'is_current': b.get('is_current', False), 'retired': b.get('retired', False),
                'ball_configuration_id': cfg.get('id'), 'layout_system': cfg.get('layout_system'),
                'layout': cfg.get('layout'), 'surface': cfg.get('surface')}

    _ARSENAL_SELECT = ('select=id,nickname,weight_lb,color_desc,is_current,retired,ball_model_id,created_at,'
                       'ball_models(manufacturer,name,image_url,coverstock,core_type,rg,diff,factory_finish),'
                       'ball_configurations(id,version,layout_system,layout,surface)')

    def list_arsenal(self, user_id):
        rows = self._get('user_balls', f'user_id=eq.{user_id}&{self._ARSENAL_SELECT}&order=created_at')
        return [self._arsenal_row(b) for b in rows]

    def _arsenal_one(self, user_id, ball_id):
        rows = self._get('user_balls', f'id=eq.{ball_id}&user_id=eq.{user_id}&{self._ARSENAL_SELECT}')
        return self._arsenal_row(rows[0]) if rows else None

    def add_ball(self, user_id, data):
        d = dict(data or {})
        make_current = bool(d.get('make_current') or d.get('is_current'))
        ball_id, cfg_id = _new_id(), _new_id()
        self._req('user_balls', 'POST', {'id': ball_id, 'user_id': user_id, 'ball_model_id': d.get('ball_model_id'),
                  'nickname': d.get('nickname') or d.get('name'), 'serial': d.get('serial'),
                  'weight_lb': d.get('weight_lb'), 'color_desc': d.get('color_desc'), 'is_current': False})
        self._req('ball_configurations', 'POST', {'id': cfg_id, 'user_ball_id': ball_id, 'version': 1,
                  'layout_system': d.get('layout_system'), 'layout': d.get('layout'), 'surface': d.get('surface')})
        if make_current:
            self.set_current_ball(user_id, ball_id)
        return self._arsenal_one(user_id, ball_id)

    def set_current_ball(self, user_id, ball_id):
        if not self._get('user_balls', f'id=eq.{ball_id}&user_id=eq.{user_id}&select=id'):
            return None
        self._req(f'user_balls?user_id=eq.{user_id}&is_current=is.true', 'PATCH', {'is_current': False})
        self._req(f'user_balls?id=eq.{ball_id}&user_id=eq.{user_id}', 'PATCH', {'is_current': True})
        return self._arsenal_one(user_id, ball_id)

    def update_ball(self, user_id, ball_id, patch):
        if not self._get('user_balls', f'id=eq.{ball_id}&user_id=eq.{user_id}&select=id'):
            return None
        p = dict(patch or {})
        if p.pop('is_current', False) or p.pop('make_current', False):
            self.set_current_ball(user_id, ball_id)
        ball_cols = {k: p[k] for k in ('nickname', 'serial', 'weight_lb', 'color_desc', 'ball_model_id', 'retired') if k in p}
        if p.get('name') is not None:
            ball_cols['nickname'] = p['name']
        if ball_cols:
            self._req(f'user_balls?id=eq.{ball_id}&user_id=eq.{user_id}', 'PATCH', ball_cols)
        cfg_cols = {k: p[k] for k in ('layout_system', 'layout', 'surface') if k in p}
        if cfg_cols:
            self._req(f'ball_configurations?user_ball_id=eq.{ball_id}', 'PATCH', cfg_cols)
        return self._arsenal_one(user_id, ball_id)

    def current_ball(self, user_id):
        rows = self._get('user_balls', f'user_id=eq.{user_id}&is_current=is.true&{self._ARSENAL_SELECT}&limit=1')
        return self._arsenal_row(rows[0]) if rows else None

    def get_shot_intent(self, user_id, shot_id):
        if not self._get('shots', f'id=eq.{shot_id}&user_id=eq.{user_id}&select=id'):
            return None
        rows = self._get('shot_intents', f'shot_id=eq.{shot_id}'
                         '&select=feet_board,laydown_board,arrows_board,breakpoint_board,breakpoint_ft')
        return rows[0] if rows else None

    def last_setup(self, user_id):
        try:
            rows = self._get('shots', f"user_id=eq.{user_id}&source=neq.upload&session_id=not.is.null&"
                             "order=created_at.desc&limit=1&select=id,session_id,user_ball_id,ball_configuration_id")
        except Exception:
            rows = []
        if not rows:
            return {'user_ball_id': None, 'ball_configuration_id': None, 'oil_pattern_id': None, 'intent': None}
        shot = rows[0]
        oil = None
        try:
            srows = self._get('sessions', f"id=eq.{shot['session_id']}&select=oil_pattern_id")
            oil = srows[0].get('oil_pattern_id') if srows else None
        except Exception:
            pass
        return {'user_ball_id': shot.get('user_ball_id'),
                'ball_configuration_id': shot.get('ball_configuration_id'),
                'oil_pattern_id': oil,
                'intent': self.get_shot_intent(user_id, shot['id'])}

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

    def _get_in(self, table, field, ids, extra, chunk=150):
        """GET rows where `field` is in `ids`, CHUNKED so a large id list can't overflow the request URL
        (PostgREST/proxy ~8-16 KB limit -> a 400 once the window has a few hundred shots). ~150 UUIDs/req."""
        out = []
        for i in range(0, len(ids), chunk):
            batch = ','.join(ids[i:i + chunk])
            out += self._get(table, f'{field}=in.({batch})&{extra}')
        return out

    # ----------------------------------------------------------------- shot history read-back (from Supabase)
    def read_shot_records(self, user_id, window_days=None):
        import datetime as _dt
        from urllib.parse import quote
        q = f'user_id=eq.{user_id}&select=id,handed,created_at,source&order=created_at'
        if window_days is not None:
            # 'Z' (not +00:00) and URL-encode: an unencoded '+'/':' in the timestamp makes PostgREST 400.
            since = (_dt.datetime.now(_dt.timezone.utc) - _dt.timedelta(days=window_days)) \
                .strftime('%Y-%m-%dT%H:%M:%SZ')
            q += f'&created_at=gte.{quote(since, safe="")}'
        shots = [s for s in self._get('shots', q) if s.get('source') != 'upload']  # exclude uploads (DEC-055)
        if not shots:
            return [], {}, 'R'
        ids = [s['id'] for s in shots]
        meas = self._get_in('measurements', 'shot_id', ids,
                            'source=eq.lanesight_video&select=shot_id,metric,value,status,confidence,note')
        ints = self._get_in('shot_intents', 'shot_id', ids, 'select=shot_id,arrows_board,breakpoint_board')
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

    def shot_points(self, user_id):
        rows = self._get('shots', f'user_id=eq.{user_id}&source=neq.upload&order=created_at&'
                         'select=id,created_at,session_id,ball_configuration_id,user_ball_id,record,'
                         'sessions(oil_pattern_id)')
        out = []
        for sh in rows:
            rec = sh.get('record') or {}
            if not rec.get('metrics'):
                continue
            sess = sh.get('sessions') if isinstance(sh.get('sessions'), dict) else {}
            out.append(dict(shot_id=sh['id'], created_at=sh.get('created_at'), session_id=sh.get('session_id'),
                            ball=sh.get('ball_configuration_id') or sh.get('user_ball_id'),
                            pattern=(sess or {}).get('oil_pattern_id'), record=rec))
        return out

    def read_form_records(self, user_id, window_days=None):
        """Prior FORM shot records from Supabase: measurements with source 'lanesight_form' (the pose pipeline),
        so ball-CV measurements never leak into form baselines."""
        import datetime as _dt
        from urllib.parse import quote
        q = f'user_id=eq.{user_id}&select=id,created_at,source&order=created_at'
        if window_days is not None:
            since = (_dt.datetime.now(_dt.timezone.utc) - _dt.timedelta(days=window_days)) \
                .strftime('%Y-%m-%dT%H:%M:%SZ')
            q += f'&created_at=gte.{quote(since, safe="")}'
        shots = [s for s in self._get('shots', q) if s.get('source') != 'upload']  # exclude uploads (DEC-055)
        if not shots:
            return []
        ids = [s['id'] for s in shots]
        meas = self._get_in('measurements', 'shot_id', ids,
                            'source=eq.lanesight_form&select=shot_id,metric,value,status,confidence,note')
        by_shot = {}
        for m in meas:
            by_shot.setdefault(m['shot_id'], {})[m['metric']] = {
                'value': m.get('value'), 'status': m.get('status'),
                'confidence': m.get('confidence'), 'note': m.get('note')}
        out = []
        for s in shots:
            metrics = by_shot.get(s['id'])
            if not metrics:
                continue
            out.append({'shot_id': s['id'], 'form_version': 'form', 'metrics': metrics})
        return out

    def form_rules(self):
        # owner-only table; the service role reads it. Keep only the highest version per rule id.
        rows = self._get('form_rule', 'select=*&order=id,version')
        latest = {}
        for r in rows:
            cur = latest.get(r['id'])
            if cur is None or (r.get('version') or 0) >= (cur.get('version') or 0):
                latest[r['id']] = r
        return list(latest.values())

    def drills(self):
        return self._get('drill', 'select=*')

    def completed_sessions(self, user_id):
        return self._get('sessions', f'user_id=eq.{user_id}&ended_at=not.is.null&select=id,ended_at,mode')

    def session_shots(self, user_id, session_id):
        rows = self._get('shots', f'user_id=eq.{user_id}&session_id=eq.{session_id}'
                                  '&select=id,created_at,classification,source,record,user_ball_id,'
                                  'ball_configuration_id,oil_pattern_id&order=created_at')
        ball_names, oil_names = self._ball_oil_names(user_id)       # DEC-097: ball/oil used, per shot
        sess = self._get('sessions', f'id=eq.{session_id}&select=oil_pattern_id') or [{}]
        sess_oil = (sess[0] or {}).get('oil_pattern_id')
        out = []
        for sh in rows:
            rec = sh.get('record') or {}
            metrics = rec.get('metrics') or {}
            key = {k: (metrics.get(k) or {}).get('value')
                   for k in ('ball_speed', 'rev_rate', 'entry_board', 'entry_angle', 'arrows_board')}
            ball_id = sh.get('user_ball_id') or sh.get('ball_configuration_id')
            oil_id = sh.get('oil_pattern_id') or sess_oil           # pre-DEC-097 rows fall back to the session oil
            out.append(dict(id=sh['id'], state='analyzed' if metrics else 'pending',
                            created_at=sh.get('created_at'), classification=sh.get('classification'),
                            source=sh.get('source'), metrics=key,
                            user_ball_id=sh.get('user_ball_id'), oil_pattern_id=oil_id,
                            ball_name=ball_names.get(ball_id), oil_name=oil_names.get(oil_id)))
        return out

    def session_records(self, user_id, session_id):
        rows = self._get('shots', f'user_id=eq.{user_id}&session_id=eq.{session_id}'
                                  '&select=record&order=created_at')
        return [r['record'] for r in rows if (r.get('record') or {}).get('metrics')]

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
        def _num(v):
            # current/best/target_value are numeric columns; some rule types (e.g. first_tier) carry a
            # non-numeric current (the tier name) -> keep numbers, drop non-numeric to None.
            try:
                return float(v) if v is not None and not isinstance(v, bool) else None
            except (TypeError, ValueError):
                return None
        row = {'user_id': user_id, 'achievement_id': progress['achievement_id'],
               'level': progress.get('level', 1), 'status': progress['status'],
               'current_value': _num(progress.get('current_value')), 'best_value': _num(progress.get('best_value')),
               'target_value': _num(progress.get('target_value')), 'qualifying_count': progress.get('qualifying_count'),
               'sample_count': progress.get('sample_count'), 'unavailable_reason': progress.get('unavailable_reason'),
               'evidence_ref': progress.get('evidence_ref')}
        # composite PK (user_id, achievement_id, level) -> merge-duplicates needs an explicit on_conflict
        self._req('user_achievement_progress?on_conflict=user_id,achievement_id,level', 'POST', row,
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
        # Scope to the Home Recent activity kinds (DEC-055) — practice sessions, achievement unlocks,
        # tier changes only; drop personal-best and any other kinds, and never uploads.
        kinds = ','.join(_ACTIVITY_KINDS)
        return self._get('activity_item',
                         f'user_id=eq.{user_id}&kind=in.({kinds})&select=*&order=created_at.desc')

    def list_uploads(self, user_id):
        rows = self._get('shots', f'user_id=eq.{user_id}&source=eq.upload'
                                  '&select=id,created_at,capture_mode,classification,source,record,'
                                  'analysis_status,failure_code,failure_stage'
                                  '&order=created_at.desc')
        out = []
        for sh in rows:
            rec = sh.get('record') or {}
            metrics = rec.get('metrics') or {}
            key = {k: (metrics.get(k) or {}).get('value')
                   for k in ('ball_speed', 'rev_rate', 'entry_board', 'entry_angle', 'arrows_board')}
            state = sh.get('analysis_status') or ('analyzed' if metrics else 'pending')   # legacy fallback
            out.append(self._upload_row(sh, state, key, sh.get('classification')))
        return out

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
    def anonymize_feedback(self, user_id):
        """DEC-059: de-identify the user's feedback IN PLACE before the auth user is deleted — set
        anonymized_at and strip identifying diagnostics while user_id still matches. The FK
        (user_id / session_id / shot_id ON DELETE SET NULL) nulls the links when the auth user and its
        cascaded rows go. Rows are KEPT."""
        import datetime as _dt
        rows = self._get('feedback', f'user_id=eq.{user_id}&select=id,diagnostics')
        now = _dt.datetime.now(_dt.timezone.utc).isoformat()
        for r in rows:
            self._req(f'feedback?id=eq.{r["id"]}', 'PATCH',
                      {'anonymized_at': now,
                       'diagnostics': self._anonymize_diagnostics(r.get('diagnostics'))})
        return len(rows)

    # ----------------------------------------------------------------- Supabase Storage (clip uploads)
    def _storage_base(self):
        return settings().supabase_base.rstrip('/') + '/storage/v1'

    def _storage_headers(self):
        return {'apikey': self._key, 'Authorization': f'Bearer {self._key}'}

    def storage_signed_upload_url(self, bucket, path):
        """Create a one-shot signed URL the client PUTs the clip to (direct to Storage — no 32 MiB API cap).
        Returns {path, upload_url}. The token in the URL authorizes exactly this object, so no bucket RLS."""
        import urllib.request
        url = f'{self._storage_base()}/object/upload/sign/{bucket}/{path}'
        req = urllib.request.Request(url, method='POST', data=b'{}',
                                     headers={**self._storage_headers(), 'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=30) as r:
            body = __import__('json').loads(r.read())
        rel = body['url'].lstrip('/')                      # "object/upload/sign/{bucket}/{path}?token=..."
        return {'path': path, 'upload_url': f'{self._storage_base()}/{rel}'}

    def storage_download(self, bucket, path):
        """Download a clip (service role) for analysis."""
        import urllib.request
        url = f'{self._storage_base()}/object/authenticated/{bucket}/{path}'
        req = urllib.request.Request(url, headers=self._storage_headers())
        with urllib.request.urlopen(req, timeout=180) as r:
            return r.read()

    def storage_delete(self, bucket, path):
        """Delete a clip after analysis (clips are never retained — DEC-019 replay deferred)."""
        import urllib.request
        url = f'{self._storage_base()}/object/{bucket}/{path}'
        req = urllib.request.Request(url, method='DELETE', headers=self._storage_headers())
        try:
            urllib.request.urlopen(req, timeout=30)
        except Exception as e:
            print(f'storage_delete {path} skipped ({e})')

    def storage_upload(self, bucket, path, data, content_type='application/octet-stream'):
        """Upload bytes to Storage with the service role (create-or-overwrite via x-upsert). For durable images
        (avatars, Form key-position frames) that must survive Cloud Run's scale-to-zero ephemeral disk."""
        import urllib.request
        url = f'{self._storage_base()}/object/{bucket}/{path}'
        req = urllib.request.Request(url, method='POST', data=data,
                                     headers={**self._storage_headers(),
                                              'Content-Type': content_type, 'x-upsert': 'true'})
        with urllib.request.urlopen(req, timeout=60) as r:
            return __import__('json').loads(r.read())

    def reset_user_data(self, user_id):
        """Delete ALL per-user data (keeps the auth user + profile row, so is_staged survives). Used by the
        staged-account seed --reset on live; the caller guards on is_staged. FK-safe order: shots first
        (cascades measurements/shot_intents/pin_states), tier_event before score_snapshot (FK snapshot_id),
        user_balls (cascades configurations/surface_events). Feedback rows for this user are removed here
        (staged feedback is disposable, unlike real feedback which is anonymized on account deletion)."""
        order = ['shots', 'sessions',
                 'tier_event', 'score_snapshot', 'user_tier_state',
                 'user_achievement_unlock', 'user_achievement_progress', 'user_achievement_pin',
                 'activity_item', 'notification', 'finding', 'personal_baseline',
                 'user_balls', 'sensor_devices', 'feedback']
        for table in order:
            try:
                self._req(f'{table}?user_id=eq.{user_id}', 'DELETE')
            except Exception as e:                # a table may not exist in an older schema; keep going
                print(f'reset_user_data: {table} delete skipped ({e})')
        return True

    def delete_user(self, user_id):
        self.anonymize_feedback(user_id)      # keep feedback (de-identified); must run before the auth delete
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
