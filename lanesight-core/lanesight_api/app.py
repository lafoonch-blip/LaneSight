"""FastAPI app for the Mac service (HANDOFF §3). Binds to localhost; exposed only via `tailscale serve`.
The end-to-end shot path (sessions -> shots upload -> serial analyze job -> result -> score recompute ->
summary -> feedback -> CSV) is implemented; the remaining §3 endpoints are declared and return 501 until
their DB-backed handlers land, so the OpenAPI contract lists the full surface honestly.
"""
from __future__ import annotations
import json
import os
import time
from pathlib import Path

import shutil

from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, Response
from fastapi.responses import FileResponse

from . import API_VERSION, APP_COMPAT
from . import engines
from . import userauth
from .auth import current_user
from .config import settings
from .jobs import SerialJobQueue
from .store import get_store, session_csv
from lanesight_core.models.shot import ALGO_VERSION
from lanesight_core.score import SCORE_VERSION
from lanesight_core.benchmarks import BENCHMARK_VERSION
from lanesight_core.form import spot_check

DATA_ROOT = Path(os.environ.get('LANESIGHT_DATA', os.path.expanduser('~/LaneSightData')))
_queue = SerialJobQueue()
app = FastAPI(title='LaneSight API', version=API_VERSION)


# ----------------------------------------------------------------- analysis job
def _analyze_job(shot_id: str, src: str, handed: str | None, user_id: str, session_id: str | None,
                 mode: str = 'shot', is_upload: bool = False):
    def run(job):
        t0 = time.monotonic()
        out_prefix = str(DATA_ROOT / 'out' / shot_id)
        os.makedirs(os.path.dirname(out_prefix), exist_ok=True)
        store = get_store()
        if mode == 'form':
            # Form clips (rear / bowler-facing) run the pose pipeline, not the ball CV. Their measurements use
            # source 'lanesight_form', which read_shot_records excludes, so a form shot never feeds the ball
            # L-dev-0 score / Accuracy — hence we skip after_shot_analyzed and return a minimal footer.
            from lanesight_core.form import analyze_form_clip
            from lanesight_core.form.pose import pose_backend
            rec = analyze_form_clip(src, out_prefix=out_prefix, handed=handed, pose_backend=pose_backend)
            rec['shot_id'] = shot_id
            job.timings['analyze'] = time.monotonic() - t0
            # Form-only engine step (baselines -> watch -> focus -> footer). Runs BEFORE save so the current
            # delivery is counted once; never touches the ball L-dev-0 score / Accuracy.
            # Standalone uploads (DEC-055) still render the form card (focus/footer), but persist=False
            # keeps them out of the user's Stats baselines.
            form_footer = engines.after_form_analyzed(store, user_id, session_id, rec,
                                                      analyze_seconds=job.timings['analyze'],
                                                      persist=not is_upload)
            store.save_shot_result(shot_id, rec, {'ok': True, 'mode': 'form'})
            return dict(shot_id=shot_id, mode='form', status=rec.get('status'), view=rec.get('view'),
                        focus=form_footer.get('focus'), key_frames=form_footer.get('key_frames'),
                        footer=form_footer.get('footer'))
        from lanesight_runner.core import analyze_clip
        rec, probe, timings = analyze_clip(src, out_prefix, handed=handed, timings={})
        rec['shot_id'] = shot_id
        for k, v in (timings or {}).items():
            job.timings[k] = v
        job.timings['analyze'] = time.monotonic() - t0
        # Recompute insights with the thrown intent + session history (SHOT_REVIEW #5 / handoff C.4): the CV
        # pipeline computes insights with neither, so without this an upload/session target never produces an
        # EXECUTION_MISS and the transition read never fires. Pins come from the measured read; the user can
        # override via POST /shots/{id}/pins. suggested_target ("Apply this move") is derived inside the recompute.
        sh = store.get_shot(user_id, shot_id)
        if sh and (sh.get('intent') or sh.get('session_id')):
            pr = rec.get('pins') or {}
            if pr.get('readable'):
                standing, unc = set(pr.get('standing') or []), set(pr.get('uncertain') or [])
            else:
                standing, unc = None, set()
            _recompute_insights(store, user_id, sh, rec, standing, unc)
        store.save_shot_result(shot_id, rec, {'ok': True})
        # Standalone uploads (DEC-055) are analyzed and viewable, but never feed the LaneSight Score,
        # tiers, achievements or findings — so skip the post-shot engine entirely (no footer nudges).
        if is_upload:
            return dict(shot_id=shot_id)
        # After each analyzed shot: recompute score over the 90-day window, run achievements, findings.
        footer = engines.after_shot_analyzed(store, user_id, session_id, rec)
        return dict(shot_id=shot_id, **footer)

    return _queue.submit('analyze', run)


# The engine versions that produced the results a piece of feedback is about. core/rules/formula are
# server-authoritative (the client can't be trusted to know them); app_version/app_phase come from the
# build + Beta–Prod toggle and stay as the client sent them (default phase 'dev' for this build).
_FEEDBACK_SOURCES = {'shot_note', 'session_feedback', 'advice_rating', 'form_note', 'general'}


def _stamp_versions(data: dict) -> dict:
    d = dict(data or {})
    d['core_version'] = ALGO_VERSION
    d['rules_version'] = BENCHMARK_VERSION
    d['formula_version'] = SCORE_VERSION
    return d


def _ball_link(store, user, meta):
    """The ball configuration + user ball a shot was thrown with: explicit from the app, else the current ball."""
    cfg, ub = meta.get('ball_configuration_id'), meta.get('user_ball_id')
    if not (cfg and ub) and hasattr(store, 'current_ball'):
        cur = store.current_ball(user) or {}
        cfg = cfg or cur.get('ball_configuration_id')
        ub = ub or cur.get('id')
    return cfg, ub


def _intent_view(intent):
    """Normalize a stored intent into the keys the execution check reads (handoff C.4). execution_check compares
    intent[laydown_board/arrows_board/breakpoint_board] against the shot's actuals; accept either naming
    (arrows_board or board_at_15ft) so the check actually runs instead of being silently skipped."""
    if not intent:
        return None
    iv = {k: v for k, v in dict(intent).items() if v is not None}
    if 'arrows_board' not in iv and iv.get('board_at_15ft') is not None:
        iv['arrows_board'] = iv['board_at_15ft']
    if 'laydown_board' not in iv and iv.get('board_at_0ft') is not None:
        iv['laydown_board'] = iv['board_at_0ft']
    return iv or None


def _shot_view_from_record(rec, standing, uncertain=None):
    """Rebuild the insight input from a stored record's measured values, with the given standing pins. Used to
    recompute insights when the user reports their leave (POST /shots/{id}/pins). standing None = unreadable."""
    M = rec.get('metrics') or {}
    val = lambda k: (M.get(k) or {}).get('value')
    return dict(entry_board=val('entry_board'), entry_angle_deg=val('entry_angle'),
                board_at_15ft=val('arrows_board'), board_at_0ft=val('laydown_board'),
                breakpoint_board=val('breakpoint_board'),
                speed_early=val('speed_early'), speed_late=val('speed_late'),
                trajectory=rec.get('trajectory'),
                pins_standing=standing, pins_uncertain=(set(uncertain) if uncertain else set()))


def _session_history(store, user_id, sh):
    """Earlier analyzed shots in the same session as light dicts, for the transition read + big-move confirmation."""
    sid = sh.get('session_id')
    if not sid:
        return []
    try:
        rows = store.session_shots(user_id, sid)
    except Exception:
        return []
    hist = []
    for r in rows:
        if r.get('id') == sh.get('id'):
            continue
        eb = (r.get('metrics') or {}).get('entry_board')
        if eb is not None:
            hist.append(dict(entry_board=eb, classification=r.get('classification')))
    return hist


def _recompute_insights(store, user_id, sh, rec, standing, uncertain=None):
    """Recompute strike insights for a stored record with the thrown intent + session history (so the execution
    check and transition read run — the CV pipeline computes neither). Mutates rec['insights'] and returns it."""
    from lanesight_core.insights.adjust import strike_adjustment, suggested_target
    handed = rec.get('handed') or sh.get('handed') or 'R'
    intent = _intent_view(sh.get('intent'))
    sv = _shot_view_from_record(rec, standing, uncertain)
    ins = strike_adjustment(sv, handed, intent=intent, history=_session_history(store, user_id, sh))
    rec['insights'] = ins
    if intent:
        geom = (store.engine_config() or {}).get('line_geometry') if hasattr(store, 'engine_config') else None
        bp_ft = ((rec.get('key_points') or {}).get('breakpoint') or {}).get('z_ft')
        st = suggested_target(ins, intent, geometry=geom, breakpoint_ft=bp_ft)
        if st:
            ins['suggested_target'] = st
    return ins


# ----------------------------------------------------------------- health (no auth)
@app.get('/health')
def health():
    s = settings()
    reachable = s.supabase_reachable()          # None in memory mode, True/False in live mode
    # Fail visibly: a live build that can't reach Supabase is 'degraded' (the dev panel shows it red);
    # we never silently fall back to memory. A build running in memory mode is flagged too.
    if s.mode == 'live':
        status = 'ok' if reachable else 'degraded'
    else:
        status = 'ok'
    return {'status': status, 'supabase_reachable': reachable,
            'versions': {'api': API_VERSION, 'app_compat': APP_COMPAT,
                         'core': ALGO_VERSION, 'rules': BENCHMARK_VERSION, 'formula': SCORE_VERSION},
            'config': s.redacted()}


# ----------------------------------------------------------------- auth (email/password, no bearer)
@app.post('/auth/signup')
def auth_signup(body: dict):
    try:
        sess = userauth.signup(body['email'], body['password'])
    except KeyError:
        raise HTTPException(400, 'email and password required')
    except userauth.AuthError as e:
        raise HTTPException(e.status if 400 <= e.status < 600 else 400, str(e.body)[:300])
    get_store().put_profile(sess['user_id'], {})      # ensure a profiles row so session/shot FKs hold
    return sess

@app.post('/auth/signin')
def auth_signin(body: dict):
    try:
        return userauth.signin(body['email'], body['password'])
    except KeyError:
        raise HTTPException(400, 'email and password required')
    except userauth.AuthError:
        raise HTTPException(401, 'invalid email or password')

@app.post('/auth/refresh')
def auth_refresh(body: dict):
    try:
        return userauth.refresh(body['refresh_token'])
    except (KeyError, userauth.AuthError):
        raise HTTPException(401, 'could not refresh session')


# ----------------------------------------------------------------- sessions
@app.post('/sessions')
def create_session(body: dict | None = None, user=Depends(current_user)):
    return get_store().create_session(user, body or {})

@app.get('/sessions')
def list_sessions(user=Depends(current_user)):
    return get_store().list_sessions(user)

@app.get('/sessions/{sid}')
def get_session(sid: str, user=Depends(current_user)):
    s = get_store().get_session(user, sid)
    if not s:
        raise HTTPException(404, 'session not found')
    return s

@app.post('/sessions/{sid}/end')
def end_session(sid: str, user=Depends(current_user)):
    store = get_store()
    summary = store.end_session(user, sid)
    if not summary:
        raise HTTPException(404, 'session not found')
    snap, tier, ach = engines.at_session_end(store, user, sid)
    summary['score'] = {'eligible': snap['eligible'], 'score': snap['score'], 'tier': snap['tier']}
    summary['tier_event'] = tier.get('event')
    summary['personal_best'] = tier.get('personal_best')
    # extra unlocks batched into the summary (SCORE_TIERS §6)
    summary['unlocked'] = ach['unlocked']
    summary['notifications'] = store.list_notifications(user, undelivered=True)
    return summary


# ----------------------------------------------------------------- shots
@app.post('/sessions/{sid}/shots')
async def create_shot(sid: str, file: UploadFile = File(...), metadata: str = Form('{}'),
                      user=Depends(current_user)):
    s = get_store().get_session(user, sid)
    if not s:
        raise HTTPException(404, 'session not found')
    meta = json.loads(metadata or '{}')
    store = get_store()
    cfg, ub = _ball_link(store, user, meta)
    shot = store.create_shot(user, sid, {'intent': meta.get('intent'), 'capture_mode': meta.get('capture_mode'),
                                         'source': meta.get('source', 'live'), 'sensor_used': meta.get('sensor_used'),
                                         'sensor_id': meta.get('sensor_id'), 'handed': meta.get('handed'),
                                         'ball_configuration_id': cfg, 'user_ball_id': ub})
    dest = DATA_ROOT / 'sessions' / sid
    dest.mkdir(parents=True, exist_ok=True)
    path = dest / f"{shot['id']}.mov"
    with open(path, 'wb') as f:
        f.write(await file.read())
    job = _analyze_job(shot['id'], str(path), meta.get('handed'), user, sid,
                       mode=(meta.get('capture_mode') or 'shot'))
    return {'shot_id': shot['id'], 'job_id': job.id}

@app.get('/jobs/{job_id}')
def get_job(job_id: str, user=Depends(current_user)):
    job = _queue.get(job_id)
    if not job:
        raise HTTPException(404, 'job not found')
    return job.public()

@app.get('/shots/{shot_id}')
def get_shot(shot_id: str, user=Depends(current_user)):
    sh = get_store().get_shot(user, shot_id)
    if not sh:
        raise HTTPException(404, 'shot not found')
    return sh

@app.patch('/shots/{shot_id}')
def patch_shot(shot_id: str, body: dict, user=Depends(current_user)):
    store = get_store()
    patch = dict(body or {})
    # Advice 👍/👎 on next-shot advice is carried on the shot patch; route it into the retained feedback
    # store (DEC-059) as an 'advice_rating' row rather than mutating the measured shot. The outcome tables
    # keep their measurement role; this is write-and-keep and never changes runtime behavior.
    thumbs = patch.pop('thumbs', None)
    advice_text = patch.pop('advice_text', None)
    sh = store.get_shot(user, shot_id)
    if not sh:
        raise HTTPException(404, 'shot not found')
    if thumbs in ('up', 'down'):
        rec = sh.get('record') or {}
        store.add_feedback(user, _stamp_versions({
            'source': 'advice_rating', 'shot_id': shot_id, 'session_id': sh.get('session_id'),
            'recommendation_id': patch.pop('recommendation_id', None),
            'capture_mode': sh.get('capture_mode'), 'is_upload': sh.get('source') == 'upload',
            'thumbs': thumbs, 'text': advice_text,
            'app_phase': patch.pop('app_phase', None), 'app_version': patch.pop('app_version', None),
            'context': {'advice': (rec.get('insights') or {}).get('suggested_target'),
                        'intent': sh.get('intent')}}))
    if patch:
        sh = store.patch_shot(user, shot_id, patch)
    return sh


# Key-position stills for the Form screen's KEY POSITIONS row. Owner-scoped; only frames the pose exported
# exist on disk (recorded in the form record's key_frames), so a missing frame is an honest 404.
_FORM_FRAME_KEYS = {'ball_start', 'end_pushaway', 'top_of_swing', 'release'}   # DEC-057 key positions


@app.get('/shots/{shot_id}/frame/{key}')
def get_shot_frame(shot_id: str, key: str, user=Depends(current_user)):
    if key not in _FORM_FRAME_KEYS:
        raise HTTPException(404, 'unknown frame key')
    if not get_store().get_shot(user, shot_id):        # owner-scoped
        raise HTTPException(404, 'shot not found')
    path = DATA_ROOT / 'out' / f'{shot_id}_form_{key}.jpg'
    if not path.exists():
        raise HTTPException(404, 'frame not available')
    return FileResponse(str(path), media_type='image/jpeg')


@app.post('/shots/{shot_id}/pins')
def report_pins(shot_id: str, body: dict, user=Depends(current_user)):
    """The user reports their actual leave when the deck couldn't be read (handoff C.2). Body:
    {strike: bool} | {pins: [int 1..10]} | {leave: "split"|"other"}. Stores the leave as source 'user',
    recomputes insights, and returns the updated shot so the card re-renders from the new state."""
    store = get_store()
    sh = store.get_shot(user, shot_id)
    if not sh:
        raise HTTPException(404, 'shot not found')
    rec = sh.get('record')
    if not rec:
        raise HTTPException(409, 'shot not analyzed yet')
    b = body or {}
    leave = b.get('leave')
    if b.get('strike'):
        standing = set()                                   # strike: nothing standing
    elif b.get('pins'):
        try:
            standing = {int(p) for p in b['pins']}
        except (TypeError, ValueError):
            raise HTTPException(422, 'pins must be integers 1..10')
        if not standing <= set(range(1, 11)):
            raise HTTPException(422, 'pins must be 1..10')
    else:
        standing = None                                    # a reported leave (split/other) without specific pins
    ins = _recompute_insights(store, user, sh, rec, standing)
    if standing is None and leave in ('split', 'other'):
        ins['note'] = f"You reported a {leave}. Pick the standing pins to get a line move."
    rec['pins'] = dict(rec.get('pins') or {}, readable=True, source='user', unread_reason=None,
                       strike=(standing == set()), leave_type=leave, uncertain=[],
                       standing=(sorted(standing) if standing is not None else None),
                       pins_down_min=(10 - len(standing)) if standing is not None else None,
                       pins_down_max=(10 - len(standing)) if standing is not None else None)
    store.save_shot_result(shot_id, rec, sh.get('result') or {'ok': True})
    return store.get_shot(user, shot_id)


# ----------------------------------------------------------------- spot check (advisory, never blocks)
@app.post('/spot-check')
def do_spot_check(body: dict | None = None, user=Depends(current_user)):
    return spot_check((body or {}).get('framing', {}))


# ----------------------------------------------------------------- score
@app.get('/me/score')
def me_score(user=Depends(current_user)):
    store = get_store()
    snap = store.latest_score(user)
    return snap or engines.recompute_score(store, user, trigger='shot')

@app.get('/me/score/history')
def me_score_history(user=Depends(current_user)):
    return get_store().score_history(user)


# ----------------------------------------------------------------- feedback + export
# One retained feedback store (DEC-059). Write-and-keep: nothing here is read to change a measurement,
# rule, score or advice, and there is NO client delete — removing feedback is an owner action only.
@app.post('/sessions/{sid}/feedback')
def feedback(sid: str, body: dict, user=Depends(current_user)):
    if not get_store().get_session(user, sid):
        raise HTTPException(404, 'session not found')
    # keep the session-end submission working; routing into the feedback table happens in the store.
    return get_store().save_feedback(user, sid, _stamp_versions(body or {}))

@app.post('/feedback')
def submit_feedback(body: dict, user=Depends(current_user)):
    """Submit a feedback row for any source (shot_note, advice_rating, form_note, general). Shot notes
    autosave: resend with the same `id` to update the row. Links to shot/session are optional and are
    kept only while the source exists; the row itself is retained if they're deleted."""
    store = get_store()
    data = _stamp_versions(body or {})
    src = data.get('source') or 'general'
    if src not in _FEEDBACK_SOURCES:
        raise HTTPException(400, f'unknown feedback source {src!r}')
    data['source'] = src
    # defense in depth (the service role bypasses RLS): a linked shot/session must belong to the caller.
    if data.get('shot_id') and not store.get_shot(user, data['shot_id']):
        raise HTTPException(404, 'shot not found')
    if data.get('session_id') and not store.get_session(user, data['session_id']):
        raise HTTPException(404, 'session not found')
    return store.add_feedback(user, data)

@app.get('/sessions/{sid}/export.csv')
def export_csv(sid: str, user=Depends(current_user)):
    store = get_store()
    if not store.get_session(user, sid):
        raise HTTPException(404, 'session not found')
    csv_text = session_csv(store.shots_for_session(sid), store.feedback.get(sid, []))
    return Response(csv_text, media_type='text/csv')


# ----------------------------------------------------------------- profile / sensors / catalog / oil
@app.get('/me/profile')
def get_profile(user=Depends(current_user)):
    return get_store().get_profile(user) or {'user_id': user}

@app.put('/me/profile')
def put_profile(body: dict, user=Depends(current_user)):
    return get_store().put_profile(user, body or {})


# ----------------------------------------------------------------- profile photo (handoff G)
_AVATAR_MAX_BYTES = 10 * 1024 * 1024
_AVATAR_DIR = DATA_ROOT / 'avatars'


def _iso_now():
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat()


def _process_avatar(data: bytes) -> bytes:
    """Decode (Pillow; HEIC/HEIF falls back to the Mac host's `sips`), apply EXIF orientation then STRIP all
    metadata (incl. GPS), centre-crop square, 512 px, re-encode JPEG. Raises ValueError if unreadable."""
    from io import BytesIO
    from PIL import Image, ImageOps
    try:
        img = Image.open(BytesIO(data)); img.load()
    except Exception:
        import subprocess, tempfile, os as _os
        with tempfile.TemporaryDirectory() as td:          # HEIC (no pillow-heif): transcode with sips
            src, dst = _os.path.join(td, 'in'), _os.path.join(td, 'out.jpg')
            with open(src, 'wb') as f:
                f.write(data)
            r = subprocess.run(['sips', '-s', 'format', 'jpeg', src, '--out', dst], capture_output=True)
            if r.returncode != 0 or not _os.path.exists(dst):
                raise ValueError('unsupported image format')
            img = Image.open(dst); img.load()
    img = ImageOps.exif_transpose(img).convert('RGB')       # honor orientation, drop alpha
    s = min(img.size); left = (img.width - s) // 2; top = (img.height - s) // 2
    img = img.crop((left, top, left + s, top + s)).resize((512, 512), Image.LANCZOS)
    out = BytesIO()
    img.save(out, format='JPEG', quality=85)                # no exif= argument -> metadata/GPS stripped
    return out.getvalue()


@app.put('/me/avatar')
async def put_avatar(file: UploadFile = File(...), user=Depends(current_user)):
    data = await file.read()
    if len(data) > _AVATAR_MAX_BYTES:
        raise HTTPException(413, 'image too large (max 10 MB)')
    try:
        jpeg = _process_avatar(data)
    except ValueError:
        raise HTTPException(415, 'unsupported image — send HEIC, JPEG or PNG')
    _AVATAR_DIR.mkdir(parents=True, exist_ok=True)
    rel = f'avatars/{user}.jpg'
    (DATA_ROOT / rel).write_bytes(jpeg)
    ts = _iso_now()
    get_store().set_avatar(user, rel, ts)
    return {'has_avatar': True, 'avatar_updated_at': ts}


@app.get('/me/avatar')
def get_avatar(user=Depends(current_user)):
    path = (get_store().get_avatar(user) or {}).get('avatar_path')
    full = (DATA_ROOT / path) if path else None
    if not full or not full.exists():
        raise HTTPException(404, 'no avatar set')
    return FileResponse(str(full), media_type='image/jpeg')


@app.delete('/me/avatar')
def delete_avatar(user=Depends(current_user)):
    store = get_store()
    path = (store.get_avatar(user) or {}).get('avatar_path')
    if path:
        try:
            (DATA_ROOT / path).unlink()
        except OSError:
            pass
    store.clear_avatar(user)
    return {'has_avatar': False}


@app.get('/me/sensors')
def list_sensors(user=Depends(current_user)):
    return get_store().list_sensors(user)

@app.post('/me/sensors')
def add_sensor(body: dict, user=Depends(current_user)):
    return get_store().add_sensor(user, body or {})      # user-entered name + default flag (no brand names, DEC-049)

@app.delete('/me/sensors/{sensor_id}')
def delete_sensor(sensor_id: str, user=Depends(current_user)):
    return {'deleted': get_store().delete_sensor(user, sensor_id)}

@app.get('/catalog/balls')
def catalog_balls(q: str | None = None, user=Depends(current_user)):
    return get_store().catalog_balls(q)

@app.get('/oil-patterns')
def oil_patterns(user=Depends(current_user)):
    return get_store().oil_patterns()

@app.get('/me/arsenal')
def get_arsenal(user=Depends(current_user)):
    return get_store().list_arsenal(user)

@app.post('/me/arsenal')
def add_ball(body: dict, user=Depends(current_user)):
    return get_store().add_ball(user, body or {})

@app.patch('/me/arsenal/{ball_id}')
def update_ball(ball_id: str, body: dict, user=Depends(current_user)):
    row = get_store().update_ball(user, ball_id, body or {})   # set current, layout, surface, weight, nickname, retire
    if not row:
        raise HTTPException(404, 'ball not found')
    return row

@app.post('/me/arsenal/{ball_id}/surface')
def add_surface(ball_id: str, body: dict | None = None, user=Depends(current_user)):
    row = get_store().add_surface_event(user, ball_id, body or {})
    if not row:
        raise HTTPException(404, 'ball not found')
    return row


# ----------------------------------------------------------------- live session screen
@app.get('/sessions/{sid}/shots')
def session_shots(sid: str, user=Depends(current_user)):
    store = get_store()
    if not store.get_session(user, sid):
        raise HTTPException(404, 'session not found')
    return store.session_shots(user, sid)


# ----------------------------------------------------------------- Photos upload (standalone, DEC-055)
@app.post('/uploads')
async def upload_clip(file: UploadFile = File(...), metadata: str = Form('{}'),
                      user=Depends(current_user)):
    """Analyze a clip from Photos as a STANDALONE upload (DEC-055). It is never attached to a session
    (session_id stays null), so it never shows in Recent sessions / activity and never feeds Stats, the
    LaneSight Score, tiers or achievements. Same serial analyze path; the shot result is viewable and is
    listed under Lab › Uploads (GET /me/uploads)."""
    store = get_store()
    meta = json.loads(metadata or '{}')
    cfg, ub = _ball_link(store, user, meta)
    # De-duplicate by content hash (handoff E): an identical re-upload returns the existing shot instead of
    # running a second analysis. Read the bytes once; reuse them for the write below.
    import hashlib
    data = await file.read()
    content_hash = hashlib.sha256(data).hexdigest()
    dup = store.find_upload_by_hash(user, content_hash) if hasattr(store, 'find_upload_by_hash') else None
    if dup:
        return {'shot_id': dup['id'], 'duplicate': True, 'source': 'upload'}
    shot = store.create_shot(user, None, {'intent': meta.get('intent'), 'capture_mode': meta.get('capture_mode'),
                                          'source': 'upload', 'sensor_used': meta.get('sensor_used'),
                                          'sensor_id': meta.get('sensor_id'), 'handed': meta.get('handed'),
                                          'ball_configuration_id': cfg, 'user_ball_id': ub})
    if hasattr(store, 'set_content_hash'):
        store.set_content_hash(shot['id'], content_hash)
    dest = DATA_ROOT / 'uploads'
    dest.mkdir(parents=True, exist_ok=True)
    path = dest / f"{shot['id']}.mov"
    with open(path, 'wb') as f:
        f.write(data)
    job = _analyze_job(shot['id'], str(path), meta.get('handed'), user, None,
                       mode=(meta.get('capture_mode') or 'shot'), is_upload=True)
    return {'shot_id': shot['id'], 'job_id': job.id, 'source': 'upload'}


@app.get('/me/uploads')
def me_uploads(user=Depends(current_user)):
    """Standalone upload analyses for the Lab › Uploads list (DEC-055). Newest first; each row opens its
    shot result. Never includes live/session shots."""
    return get_store().list_uploads(user)


# ----------------------------------------------------------------- stats
@app.get('/me/stats')
def me_stats(view: str = 'throw', range: str | None = None, user=Depends(current_user)):
    return engines.user_stats(get_store(), user, view=view, range_=range)


# ----------------------------------------------------------------- achievements
def _grouped_achievements(store, user):
    engines.run_achievements(store, user, 'read')             # idempotent: keep progress fresh
    defs = store.achievement_defs()
    prog = {(p['achievement_id'], p.get('level', 1)): p for p in store.list_ach_progress(user)}
    unlocked = {u['achievement_id'] for u in store.list_ach_unlocks(user)}
    cats: dict[str, list] = {}
    active_unlocked = 0
    for d in defs:
        p = prog.get((d['id'], 1), {})
        is_unlocked = d['id'] in unlocked
        if is_unlocked and d['status'] == 'active':
            active_unlocked += 1
        cats.setdefault(d['category'], []).append({
            'id': d['id'], 'name': d['name'], 'description': d['description'], 'category': d['category'],
            'status': d['status'], 'inactive_reason': d.get('inactive_reason'),
            'progress_status': 'unlocked' if is_unlocked else p.get('status', 'locked'),
            'current_value': p.get('current_value'), 'target_value': p.get('target_value'),
            'best_value': p.get('best_value'), 'qualifying_count': p.get('qualifying_count'),
            'sample_count': p.get('sample_count'), 'unavailable_reason': p.get('unavailable_reason'),
            'unlocked': is_unlocked})
    return {'unlocked_count': active_unlocked, 'categories': cats, 'pins': store.get_pins(user)}

@app.get('/me/achievements')
def me_achievements(user=Depends(current_user)):
    return _grouped_achievements(get_store(), user)

@app.get('/me/achievements/{ach_id}')
def me_achievement_detail(ach_id: str, user=Depends(current_user)):
    store = get_store()
    engines.run_achievements(store, user, 'read')
    d = next((x for x in store.achievement_defs() if x['id'] == ach_id), None)
    if not d:
        raise HTTPException(404, 'achievement not found')
    p = next((x for x in store.list_ach_progress(user)
              if x['achievement_id'] == ach_id and x.get('level', 1) == 1), {})
    unlock = store.get_ach_unlock(user, ach_id, 1)
    evidence = (p.get('evidence_ref') or {}).get('shot_ids', []) if p else []
    return {'id': d['id'], 'name': d['name'], 'description': d['description'], 'category': d['category'],
            'status': d['status'], 'inactive_reason': d.get('inactive_reason'),
            'progress': {k: p.get(k) for k in ('status', 'current_value', 'target_value', 'best_value',
                                               'qualifying_count', 'sample_count', 'unavailable_reason')},
            'evidence_shot_ids': evidence,
            'unlocked': bool(unlock), 'unlocked_at': (unlock or {}).get('unlocked_at'),
            'rule_version': d.get('rule_version', 1)}

@app.put('/me/achievements/pins')
def me_achievement_pins(body: dict, user=Depends(current_user)):
    return {'pins': get_store().set_pins(user, (body or {}).get('pins', []))}


# ----------------------------------------------------------------- notifications
@app.get('/me/notifications')
def me_notifications(undelivered: int = 0, user=Depends(current_user)):
    return get_store().list_notifications(user, undelivered=bool(undelivered))

@app.post('/me/notifications/{notif_id}/delivered')
def notification_delivered(notif_id: str, user=Depends(current_user)):
    r = get_store().mark_notification(user, notif_id, 'delivered_at')
    if not r:
        raise HTTPException(404, 'notification not found')
    return r

@app.post('/me/notifications/{notif_id}/dismiss')
def notification_dismiss(notif_id: str, user=Depends(current_user)):
    r = get_store().mark_notification(user, notif_id, 'dismissed_at')
    if not r:
        raise HTTPException(404, 'notification not found')
    return r


# ----------------------------------------------------------------- recent activity
@app.get('/me/activity')
def me_activity(user=Depends(current_user)):
    return get_store().list_activity(user)


# ----------------------------------------------------------------- account deletion
@app.delete('/me')
def delete_me(user=Depends(current_user)):
    store = get_store()
    session_ids = [s['id'] for s in store.list_sessions(user)]
    shot_ids = [sh['id'] for sh in store.user_shots(user)]
    avatar_path = (store.get_avatar(user) or {}).get('avatar_path') if hasattr(store, 'get_avatar') else None
    store.delete_user(user)                                   # auth user + cascaded rows (live)
    if avatar_path:                                           # remove the user's photo on this Mac
        try:
            (DATA_ROOT / avatar_path).unlink()
        except OSError:
            pass
    for sid in session_ids:                                   # remove the user's videos on this Mac
        shutil.rmtree(DATA_ROOT / 'sessions' / sid, ignore_errors=True)
    for shid in shot_ids:
        for f in (DATA_ROOT / 'out').glob(f'{shid}*'):
            try:
                f.unlink()
            except OSError:
                pass
        # standalone upload clips live under uploads/<shot_id>.mov (DEC-055), not under a session dir
        try:
            (DATA_ROOT / 'uploads' / f'{shid}.mov').unlink()
        except OSError:
            pass
    return {'deleted': True}
