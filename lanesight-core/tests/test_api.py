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


def test_arsenal_persistence_current_and_update():
    hh = {'X-Dev-User': 'ars1'}
    b1 = client.post('/me/arsenal', json={'name': 'Old Hammer', 'weight_lb': 15, 'layout': '45x4x40',
                                          'surface': '2000 abralon', 'make_current': True}, headers=hh).json()
    assert b1['name'] == 'Old Hammer' and b1['is_current'] is True and b1['ball_configuration_id']
    assert b1['layout'] == '45x4x40' and b1['surface'] == '2000 abralon'
    client.post('/me/arsenal', json={'name': 'Storm Bionic', 'weight_lb': 15}, headers=hh)
    lst = client.get('/me/arsenal', headers=hh).json()
    assert {x['name'] for x in lst} == {'Old Hammer', 'Storm Bionic'}
    assert sum(1 for x in lst if x['is_current']) == 1
    b2 = next(x for x in lst if x['name'] == 'Storm Bionic')
    client.patch(f"/me/arsenal/{b2['id']}", json={'is_current': True, 'surface': '4000 abralon'}, headers=hh)
    by_id = {x['id']: x for x in client.get('/me/arsenal', headers=hh).json()}
    assert by_id[b2['id']]['is_current'] and not by_id[b1['id']]['is_current']
    assert by_id[b2['id']]['surface'] == '4000 abralon'
    assert client.patch('/me/arsenal/nope', json={'surface': 'x'}, headers=hh).status_code == 404


def test_feedback_store_generic_submit_and_versions():
    hh = {'X-Dev-User': 'fb1'}
    sid = client.post('/sessions', json={}, headers=hh).json()['id']
    store = get_store()
    shot = store.create_shot('fb1', sid, {})
    r = client.post('/feedback', headers=hh, json={
        'source': 'shot_note', 'shot_id': shot['id'], 'session_id': sid,
        'tags': ['Missed right', 'Light'], 'text': 'felt light', 'app_phase': 'beta', 'app_version': 'ios-9'})
    assert r.status_code == 200
    row = r.json()
    assert row['source'] == 'shot_note' and row['triage_status'] == 'new'
    assert row['shot_id'] == shot['id'] and row['tags'] == ['Missed right', 'Light']
    assert row['app_phase'] == 'beta' and row['app_version'] == 'ios-9'
    # core/rules/formula are server-authoritative
    assert row['core_version'] and row['formula_version'] == 'L-dev-0'
    assert any(f['id'] == row['id'] for f in store.list_feedback('fb1'))
    # unknown source rejected; a note for someone else's shot 404s
    assert client.post('/feedback', headers=hh, json={'source': 'bogus'}).status_code == 400
    assert client.post('/feedback', headers=hh, json={'source': 'shot_note', 'shot_id': 'nope'}).status_code == 404

def test_feedback_store_no_client_delete():
    # there is no DELETE route for feedback (owner-only removal).
    assert client.delete('/feedback', headers={'X-Dev-User': 'fb1'}).status_code in (404, 405)

def test_session_feedback_routes_into_store():
    hh = {'X-Dev-User': 'fb2'}
    sid = client.post('/sessions', json={}, headers=hh).json()['id']
    fb = client.post(f'/sessions/{sid}/feedback', headers=hh,
                     json={'rating': 4, 'tags': ['Bug'], 'text': 'camera drifted'}).json()
    rows = get_store().list_feedback('fb2')
    routed = next(r for r in rows if r['id'] == fb['id'])
    assert routed['source'] == 'session_feedback' and routed['rating'] == 4
    assert routed['session_id'] == sid and routed['formula_version'] == 'L-dev-0'

def test_advice_rating_routes_into_store():
    hh = {'X-Dev-User': 'fb3'}
    sid = client.post('/sessions', json={}, headers=hh).json()['id']
    store = get_store()
    shot = store.create_shot('fb3', sid, {'capture_mode': 'shot'})
    r = client.patch(f"/shots/{shot['id']}", headers=hh, json={'thumbs': 'down', 'advice_text': 'advice was off'})
    assert r.status_code == 200
    adv = [f for f in store.list_feedback('fb3') if f['source'] == 'advice_rating']
    assert len(adv) == 1 and adv[0]['thumbs'] == 'down' and adv[0]['shot_id'] == shot['id']
    assert adv[0]['text'] == 'advice was off' and adv[0]['session_id'] == sid

def test_account_delete_anonymizes_feedback():
    hh = {'X-Dev-User': 'fbdel'}
    sid = client.post('/sessions', json={}, headers=hh).json()['id']
    store = get_store()
    shot = store.create_shot('fbdel', sid, {})
    client.post('/feedback', headers=hh, json={
        'source': 'shot_note', 'shot_id': shot['id'], 'session_id': sid, 'text': 'keep this text',
        'user_ref': 'ref-xyz', 'diagnostics': {'fps': 120, 'device': 'iPhone of John', 'email': 'j@x.com'}})
    assert client.delete('/me', headers=hh).json()['deleted'] is True
    # feedback is RETAINED but de-identified
    kept = [f for f in store.feedback_rows if f.get('user_ref') == 'ref-xyz']
    assert len(kept) == 1
    row = kept[0]
    assert row['user_id'] is None and row['anonymized_at'] is not None
    assert row['text'] == 'keep this text'                 # free text kept
    assert row['shot_id'] is None and row['session_id'] is None    # links nulled
    assert row['diagnostics'] == {'fps': 120}              # identifying fields stripped, timings kept
    assert store.list_feedback('fbdel') == []              # nothing still owned by the deleted user


def test_shot_persists_ball_link_and_full_intent():
    hh = {'X-Dev-User': 'ars2'}
    sid = client.post('/sessions', json={'mode': 'practice'}, headers=hh).json()['id']
    b = client.post('/me/arsenal', json={'name': 'Test Ball', 'make_current': True}, headers=hh).json()
    store = get_store()
    cur = store.current_ball('ars2')
    assert cur['id'] == b['id'] and cur['ball_configuration_id'] == b['ball_configuration_id']
    shot = store.create_shot('ars2', sid, {'intent': {'feet_board': 20, 'arrows_board': 15, 'breakpoint_board': 8},
                                           'ball_configuration_id': b['ball_configuration_id'], 'user_ball_id': b['id']})
    intent = store.get_shot_intent('ars2', shot['id'])
    assert intent['arrows_board'] == 15 and intent['feet_board'] == 20
