"""lanesight_api offline tests (MemoryStore + dev auth). The live Supabase e2e (examples/e2e_dev_build.py)
needs the Keychain creds + a real down-lane clip; here we exercise the plumbing in-memory, using a stored
validation ShotRecord as a stand-in for an analyzed result so the score + export wiring runs for real."""
import os, json, pathlib, tempfile

os.environ['LANESIGHT_API_DEV'] = '1'                      # dev auth
os.environ['LANESIGHT_FORCE_MEMORY'] = '1'                 # never touch the live project from tests
os.environ['LANESIGHT_DATA'] = tempfile.mkdtemp()          # keep uploads out of ~/LaneSightData

import pytest
from fastapi.testclient import TestClient
from lanesight_api.app import app
from lanesight_api.store import get_store

client = TestClient(app)
H = {'X-Dev-User': 'u1'}
_VAL = pathlib.Path(__file__).resolve().parents[1] / 'validation' / 'IMG_8751_shot.json'


def test_health_no_auth():
    r = client.get('/health')
    assert r.status_code == 200
    v = r.json()['versions']
    assert v['api'] and v['core'] and v['formula'] == 'L-dev-0'
    assert r.json()['config']['mode'] == 'memory'

def test_auth_required():
    assert client.post('/sessions', json={}).status_code == 401      # no X-Dev-User

def test_spot_check_never_blocks():
    r = client.post('/spot-check', json={'framing': {'lane_visible_fraction': 0.2, 'foul_line_visible': True}}, headers=H)
    assert r.status_code == 200 and r.json()['blocks'] is False

def test_session_score_feedback_export_flow():
    sid = client.post('/sessions', json={'mode': 'practice'}, headers=H).json()['id']
    # inject a real analyzed record (validation ShotRecord) as a stand-in for the CV job output
    store = get_store()
    rec = json.loads(_VAL.read_text())
    shot = store.create_shot('u1', sid, {'intent': {'arrows_board': 15.0, 'breakpoint_board': 8.0}})
    rec['shot_id'] = shot['id']
    store.save_shot_result(shot['id'], rec, {'ok': True})

    score = client.get('/me/score', headers=H).json()
    # one shot, default params -> not eligible (power ranges unset), honest building state
    assert score['eligible'] is False and score['score'] is None
    assert 's_perf' in score and 'eligibility' in score

    fb = client.post(f'/sessions/{sid}/feedback', json={'rating': 5, 'tags': ['Idea'], 'text': 'felt good'}, headers=H)
    assert fb.status_code == 200

    csv = client.get(f'/sessions/{sid}/export.csv', headers=H)
    assert csv.status_code == 200 and 'shot_id,metric,value' in csv.text
    assert 'ball_speed' in csv.text and 'feedback_rating' in csv.text

def test_end_session_returns_score_block():
    sid = client.post('/sessions', json={}, headers=H).json()['id']
    r = client.post(f'/sessions/{sid}/end', headers=H)
    assert r.status_code == 200 and 'score' in r.json()

def test_profile_put_get():
    client.put('/me/profile', json={'handed': 'R', 'delivery_style': 'one_handed_thumb', 'approach_steps': 4}, headers=H)
    p = client.get('/me/profile', headers=H).json()
    assert p['handed'] == 'R' and p['delivery_style'] == 'one_handed_thumb' and p['user_id'] == 'u1'

def test_sensors_crud():
    s = client.post('/me/sensors', json={'name': 'My blue sensor', 'is_default': True}, headers=H).json()
    assert s['name'] == 'My blue sensor' and s['user_id'] == 'u1'
    assert any(x['id'] == s['id'] for x in client.get('/me/sensors', headers=H).json())
    assert client.delete(f"/me/sensors/{s['id']}", headers=H).json()['deleted'] is True
    assert all(x['id'] != s['id'] for x in client.get('/me/sensors', headers=H).json())

def test_catalog_and_oil_shape_offline():
    # MemoryStore has no catalog/oil; endpoints must still respond with a list (live reads tested separately)
    assert client.get('/catalog/balls', headers=H).json() == []
    assert client.get('/oil-patterns', headers=H).json() == []

def test_arsenal_add_list():
    b = client.post('/me/arsenal', json={'nickname': 'Phaze', 'weight_lb': 15}, headers=H).json()
    assert b['nickname'] == 'Phaze' and b['user_id'] == 'u1'
    assert any(x['id'] == b['id'] for x in client.get('/me/arsenal', headers=H).json())

def test_upload_enqueues_serial_job():
    sid = client.post('/sessions', json={}, headers=H).json()['id']
    # dummy bytes are not a video; the job will fail with a reason — we assert the queue plumbing, not CV
    r = client.post(f'/sessions/{sid}/shots', headers=H,
                    files={'file': ('x.mov', b'not-a-video', 'video/quicktime')},
                    data={'metadata': json.dumps({'handed': 'R', 'capture_mode': 'shot'})})
    assert r.status_code == 200
    body = r.json()
    assert body['shot_id'] and body['job_id']
    job = client.get(f"/jobs/{body['job_id']}", headers=H)
    assert job.status_code == 200 and job.json()['state'] in ('queued', 'running', 'done', 'failed')
