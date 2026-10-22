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

from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, Response

from . import API_VERSION, APP_COMPAT
from .auth import current_user
from .config import settings
from .jobs import SerialJobQueue
from .store import get_store, session_csv
from lanesight_core.models.shot import ALGO_VERSION
from lanesight_core.score import compute as score_compute, SCORE_VERSION, DEFAULT_LDEV0_PARAMS
from lanesight_core.benchmarks import BENCHMARK_VERSION
from lanesight_core.form import spot_check

DATA_ROOT = Path(os.environ.get('LANESIGHT_DATA', os.path.expanduser('~/LaneSightData')))
_queue = SerialJobQueue()
app = FastAPI(title='LaneSight API', version=API_VERSION)


# ----------------------------------------------------------------- analysis job
def _analyze_job(shot_id: str, src: str, handed: str | None, user_id: str, session_id: str):
    from lanesight_runner.core import analyze_clip

    def run(job):
        t0 = time.monotonic()
        out_prefix = str(DATA_ROOT / 'out' / shot_id)
        os.makedirs(os.path.dirname(out_prefix), exist_ok=True)
        rec, probe, timings = analyze_clip(src, out_prefix, handed=handed, timings={})
        rec['shot_id'] = shot_id
        for k, v in (timings or {}).items():
            job.timings[k] = v
        job.timings['analyze'] = time.monotonic() - t0
        store = get_store()
        store.save_shot_result(shot_id, rec, {'ok': True})
        snap = _recompute_score(user_id, session_id, trigger='shot')
        return {'shot_id': shot_id, 'eligible': snap['eligible'], 'score': snap['score']}

    return _queue.submit('analyze', run)


def _recompute_score(user_id, session_id=None, trigger='shot') -> dict:
    store = get_store()
    shots = [sh for sh in store.user_shots(user_id) if sh.get('record')]
    records = [sh['record'] for sh in shots]
    intents = {sh['record']['shot_id']: sh['intent'] for sh in shots if sh.get('intent')}
    handed = (shots[-1].get('handed') if shots else None) or 'R'
    snap = score_compute(records, intents=intents, params=DEFAULT_LDEV0_PARAMS, handed=handed)
    snap['trigger'] = trigger
    snap['session_id'] = session_id
    store.save_snapshot(user_id, snap)
    return snap


# ----------------------------------------------------------------- health (no auth)
@app.get('/health')
def health():
    return {'status': 'ok', 'versions': {'api': API_VERSION, 'app_compat': APP_COMPAT,
            'core': ALGO_VERSION, 'rules': BENCHMARK_VERSION, 'formula': SCORE_VERSION},
            'config': settings().redacted()}


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
    summary = get_store().end_session(user, sid)
    if not summary:
        raise HTTPException(404, 'session not found')
    snap = _recompute_score(user, sid, trigger='session_end')
    summary['score'] = {'eligible': snap['eligible'], 'score': snap['score'], 'tier': snap['tier']}
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
    shot = store.create_shot(user, sid, {'intent': meta.get('intent'), 'capture_mode': meta.get('capture_mode'),
                                         'source': meta.get('source', 'live'), 'sensor_used': meta.get('sensor_used'),
                                         'sensor_id': meta.get('sensor_id'), 'handed': meta.get('handed')})
    dest = DATA_ROOT / 'sessions' / sid
    dest.mkdir(parents=True, exist_ok=True)
    path = dest / f"{shot['id']}.mov"
    with open(path, 'wb') as f:
        f.write(await file.read())
    job = _analyze_job(shot['id'], str(path), meta.get('handed'), user, sid)
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


# ----------------------------------------------------------------- spot check (advisory, never blocks)
@app.post('/spot-check')
def do_spot_check(body: dict | None = None, user=Depends(current_user)):
    return spot_check((body or {}).get('framing', {}))


# ----------------------------------------------------------------- score
@app.get('/me/score')
def me_score(user=Depends(current_user)):
    snap = get_store().latest_score(user)
    return snap or _recompute_score(user, trigger='shot')

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


# ----------------------------------------------------------------- declared-but-not-yet-implemented (§3)
_TODO = ['GET /me/arsenal', 'POST /me/arsenal', 'POST /me/arsenal/{id}/surface',
         'POST /uploads', 'GET /me/achievements', 'GET /me/achievements/{id}', 'PUT /me/achievements/pins',
         'GET /me/notifications', 'POST /me/notifications/{id}/delivered', 'POST /me/notifications/{id}/dismiss',
         'GET /me/activity', 'GET /me/stats', 'DELETE /me', '/admin/*']

@app.get('/_unimplemented')
def unimplemented(user=Depends(current_user)):
    """Transparency: the §3 endpoints still to implement in a later DV-03 slice."""
    return {'not_implemented': _TODO}
