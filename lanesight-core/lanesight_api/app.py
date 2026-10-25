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
def _analyze_job(shot_id: str, src: str, handed: str | None, user_id: str, session_id: str, mode: str = 'shot'):
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
            form_footer = engines.after_form_analyzed(store, user_id, session_id, rec,
                                                      analyze_seconds=job.timings['analyze'])
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
        # The shot card's "Apply this move": turn the (intent-independent) recommended move into the target
        # line for the next shot, using the intent actually thrown. Computed here from stored data — the CV
        # path is unchanged. None when nothing actionable or no intent was set.
        intent = store.get_shot_intent(user_id, shot_id) if hasattr(store, 'get_shot_intent') else None
        if intent:
            from lanesight_core.insights.adjust import suggested_target
            geom = (store.engine_config() or {}).get('line_geometry') if hasattr(store, 'engine_config') else None
            # TODO(form): when rear-view form analysis measures the bowler's actual stance distance, override
            # geom['approach_offset_ft'] with that per-shot measured value and fall back to this config only
            # when it's unavailable. (Owner's current config value is their measured ~12 ft.)
            bp_ft = ((rec.get('key_points') or {}).get('breakpoint') or {}).get('z_ft')  # measured this shot
            st = suggested_target(rec.get('insights') or {}, intent, geometry=geom, breakpoint_ft=bp_ft)
            if st:
                rec.setdefault('insights', {})['suggested_target'] = st
        store.save_shot_result(shot_id, rec, {'ok': True})
        # After each analyzed shot: recompute score over the 90-day window, run achievements, findings.
        footer = engines.after_shot_analyzed(store, user_id, session_id, rec)
        return dict(shot_id=shot_id, **footer)

    return _queue.submit('analyze', run)


def _ball_link(store, user, meta):
    """The ball configuration + user ball a shot was thrown with: explicit from the app, else the current ball."""
    cfg, ub = meta.get('ball_configuration_id'), meta.get('user_ball_id')
    if not (cfg and ub) and hasattr(store, 'current_ball'):
        cur = store.current_ball(user) or {}
        cfg = cfg or cur.get('ball_configuration_id')
        ub = ub or cur.get('id')
    return cfg, ub


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
    sh = get_store().patch_shot(user, shot_id, body or {})
    if not sh:
        raise HTTPException(404, 'shot not found')
    return sh


# Key-position stills for the Form screen's KEY POSITIONS row. Owner-scoped; only frames the pose exported
# exist on disk (recorded in the form record's key_frames), so a missing frame is an honest 404.
_FORM_FRAME_KEYS = {'ball_start', 'top_of_swing', 'release', 'finish'}


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
@app.post('/sessions/{sid}/feedback')
def feedback(sid: str, body: dict, user=Depends(current_user)):
    if not get_store().get_session(user, sid):
        raise HTTPException(404, 'session not found')
    return get_store().save_feedback(user, sid, body or {})

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


# ----------------------------------------------------------------- Photos upload (same serial analyze path)
@app.post('/uploads')
async def upload_clip(sid: str = Form(...), file: UploadFile = File(...), metadata: str = Form('{}'),
                      user=Depends(current_user)):
    store = get_store()
    if not store.get_session(user, sid):
        raise HTTPException(404, 'session not found')
    meta = json.loads(metadata or '{}')
    cfg, ub = _ball_link(store, user, meta)
    shot = store.create_shot(user, sid, {'intent': meta.get('intent'), 'capture_mode': meta.get('capture_mode'),
                                         'source': 'upload', 'sensor_used': meta.get('sensor_used'),
                                         'sensor_id': meta.get('sensor_id'), 'handed': meta.get('handed'),
                                         'ball_configuration_id': cfg, 'user_ball_id': ub})
    dest = DATA_ROOT / 'sessions' / sid
    dest.mkdir(parents=True, exist_ok=True)
    path = dest / f"{shot['id']}.mov"
    with open(path, 'wb') as f:
        f.write(await file.read())
    job = _analyze_job(shot['id'], str(path), meta.get('handed'), user, sid,
                       mode=(meta.get('capture_mode') or 'shot'))
    return {'shot_id': shot['id'], 'job_id': job.id, 'source': 'upload'}


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
    store.delete_user(user)                                   # auth user + cascaded rows (live)
    for sid in session_ids:                                   # remove the user's videos on this Mac
        shutil.rmtree(DATA_ROOT / 'sessions' / sid, ignore_errors=True)
    for shid in shot_ids:
        for f in (DATA_ROOT / 'out').glob(f'{shid}*'):
            try:
                f.unlink()
            except OSError:
                pass
    return {'deleted': True}
