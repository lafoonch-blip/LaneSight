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

def test_report_pins_recomputes_state():
    from lanesight_core.insights.adjust import STATES
    sid = client.post('/sessions', json={'mode': 'practice'}, headers=H).json()['id']
    store = get_store()
    rec = json.loads(_VAL.read_text())
    shot = store.create_shot('u1', sid, {'handed': 'R'})
    rec['shot_id'] = shot['id']
    rec['pins'] = dict(rec.get('pins') or {}, readable=False, standing=None, strike=None,
                       unread_reason='the view just above the pin deck was blocked')
    store.save_shot_result(shot['id'], rec, {'ok': True})
    sid_shot = shot['id']

    # user reports a strike -> no longer pins_unknown, pins stored as source user
    r = client.post(f'/shots/{sid_shot}/pins', json={'strike': True}, headers=H)
    assert r.status_code == 200
    body = r.json()['record']
    assert body['pins']['strike'] is True and body['pins']['source'] == 'user'
    assert body['insights']['state'] in STATES and body['insights']['state'] != 'pins_unknown'

    # user reports a 10-pin leave -> stored standing, state recomputed
    r = client.post(f'/shots/{sid_shot}/pins', json={'pins': [10]}, headers=H)
    assert r.status_code == 200
    body = r.json()['record']
    assert body['pins']['standing'] == [10] and body['pins']['strike'] is False
    assert body['insights']['state'] in STATES

    # invalid pins rejected
    assert client.post(f'/shots/{sid_shot}/pins', json={'pins': [11]}, headers=H).status_code == 422
    # not-analyzed shot -> 409
    empty = store.create_shot('u1', sid, {})
    assert client.post(f"/shots/{empty['id']}/pins", json={'strike': True}, headers=H).status_code == 409


def test_profile_location_round_trips():
    # handoff G: PUT /me/profile no longer silently drops `location` (column added in 017).
    client.put('/me/profile', json={'name': 'Shayne', 'location': 'Sunset Lanes'}, headers={'X-Dev-User': 'uLoc'})
    p = client.get('/me/profile', headers={'X-Dev-User': 'uLoc'}).json()
    assert p['location'] == 'Sunset Lanes' and p['has_avatar'] is False


def test_avatar_put_get_delete():
    from io import BytesIO
    from PIL import Image
    Hp = {'X-Dev-User': 'uAv'}
    buf = BytesIO(); Image.new('RGB', (900, 600), (180, 40, 40)).save(buf, format='PNG')
    r = client.put('/me/avatar', files={'file': ('p.png', buf.getvalue(), 'image/png')}, headers=Hp)
    assert r.status_code == 200 and r.json()['has_avatar'] is True and r.json()['avatar_updated_at']
    assert client.get('/me/profile', headers=Hp).json()['has_avatar'] is True
    g = client.get('/me/avatar', headers=Hp)
    assert g.status_code == 200 and g.headers['content-type'] == 'image/jpeg'
    # the processed avatar is a 512x512 JPEG
    assert Image.open(BytesIO(g.content)).size == (512, 512)
    assert client.delete('/me/avatar', headers=Hp).json()['has_avatar'] is False
    assert client.get('/me/avatar', headers=Hp).status_code == 404


def test_avatar_rejects_oversize_and_garbage():
    Hp = {'X-Dev-User': 'uAv2'}
    big = b'0' * (10 * 1024 * 1024 + 1)
    assert client.put('/me/avatar', files={'file': ('big.jpg', big, 'image/jpeg')}, headers=Hp).status_code == 413
    assert client.put('/me/avatar', files={'file': ('x.jpg', b'not-an-image', 'image/jpeg')}, headers=Hp).status_code == 415


def test_upload_dedupe_returns_existing_shot():
    import hashlib
    store = get_store()
    data = b'fake-clip-bytes-for-dedupe'
    h = hashlib.sha256(data).hexdigest()
    # seed a prior standalone upload with this content hash
    prior = store.create_shot('u1', None, {'source': 'upload'})
    store.set_content_hash(prior['id'], h)
    # an identical re-upload short-circuits to the existing shot (never runs analysis)
    r = client.post('/uploads', files={'file': ('clip.mov', data, 'video/quicktime')},
                    data={'metadata': '{}'}, headers=H)
    assert r.status_code == 200
    body = r.json()
    assert body.get('duplicate') is True and body['shot_id'] == prior['id'] and 'job_id' not in body


def test_live_shot_dedupe_is_session_scoped():
    # Live-shot retry idempotency (C4): a dropped-connection re-send of the same clip bytes in the same session
    # returns the existing shot; the same bytes in a DIFFERENT session are a genuine new shot, not a duplicate.
    import hashlib
    store = get_store()
    h = hashlib.sha256(b'live-clip-bytes').hexdigest()
    s1 = store.create_session('u_liveidem', {'mode': 'practice'})['id']
    s2 = store.create_session('u_liveidem', {'mode': 'practice'})['id']
    shot = store.create_shot('u_liveidem', s1, {'source': 'live'})
    store.set_content_hash(shot['id'], h)
    assert store.find_shot_by_hash('u_liveidem', h, s1)['id'] == shot['id']   # same bytes, same session -> dup
    assert store.find_shot_by_hash('u_liveidem', h, s2) is None               # same bytes, other session -> new
    assert store.find_shot_by_hash('u_liveidem', None, s1) is None            # no hash -> never dedupe
    assert store.find_shot_by_hash('u_liveidem', h, None) is None             # no session (upload) -> not here


def test_last_setup_prefill():
    # MVP-09: Setup prefills from the most recent LIVE shot's ball + intent and that session's oil; a later
    # standalone upload must not override it.
    store = get_store()
    sid = store.create_session('u_setup', {'mode': 'practice', 'oil_pattern_id': 'oil-42'})['id']
    store.create_shot('u_setup', sid, {'source': 'live', 'user_ball_id': 'ball-9',
                                       'ball_configuration_id': 'cfg-9', 'intent': {'arrows_board': 10.0}})
    store.create_shot('u_setup', None, {'source': 'upload', 'user_ball_id': 'ball-UPLOAD'})
    b = client.get('/me/last-setup', headers={'X-Dev-User': 'u_setup'}).json()
    assert b['user_ball_id'] == 'ball-9' and b['oil_pattern_id'] == 'oil-42'
    assert (b.get('intent') or {}).get('arrows_board') == 10.0


def test_last_setup_empty_for_new_user():
    b = client.get('/me/last-setup', headers={'X-Dev-User': 'u_brandnew'}).json()
    assert b == {'user_ball_id': None, 'ball_configuration_id': None, 'oil_pattern_id': None, 'intent': None}


def _rec_speed(v):
    return {'metrics': {'ball_speed': {'value': v, 'status': 'ok'}}}


def test_session_summary_aggregates_and_typical_building():
    # MVP-07: summary returns per-metric aggregates; typical is 'building' with no comparable sessions.
    store = get_store()
    sid = store.create_session('u_sum', {'mode': 'practice', 'oil_pattern_id': 'oilX'})['id']
    for v in (17.0, 17.4):
        sh = store.create_shot('u_sum', sid, {'source': 'live'})
        store.save_shot_result(sh['id'], _rec_speed(v), {'ok': True})
    r = client.get(f'/sessions/{sid}/summary', headers={'X-Dev-User': 'u_sum'}).json()
    assert r['n_shots'] == 2 and r['metrics']['ball_speed']['n'] == 2
    assert r['typical']['status'] == 'building'


def test_session_summary_typical_ok_with_comparable_sessions():
    store = get_store()
    # three prior comparable sessions (same pattern) each with a shot
    for v in (16.5, 16.9, 17.1):
        psid = store.create_session('u_typ', {'mode': 'practice', 'oil_pattern_id': 'oilT'})['id']
        sh = store.create_shot('u_typ', psid, {'source': 'live'})
        store.save_shot_result(sh['id'], _rec_speed(v), {'ok': True})
    cur = store.create_session('u_typ', {'mode': 'practice', 'oil_pattern_id': 'oilT'})['id']
    sh = store.create_shot('u_typ', cur, {'source': 'live'})
    store.save_shot_result(sh['id'], _rec_speed(18.0), {'ok': True})
    t = client.get(f'/sessions/{cur}/summary', headers={'X-Dev-User': 'u_typ'}).json()['typical']
    assert t['status'] == 'ok' and t['n_sessions'] == 3
    assert abs(t['metrics']['ball_speed'] - 16.83) < 0.05   # mean of the 3 prior sessions


def test_metric_detail_stats():
    # MVP-08: per-metric detail — avg, coverage, by-ball, by-pattern, per-session trend, small-sample flag.
    store = get_store()
    sid1 = store.create_session('u_md', {'mode': 'practice', 'oil_pattern_id': 'oilA'})['id']
    for v in (17.0, 17.5):
        sh = store.create_shot('u_md', sid1, {'source': 'live', 'ball_configuration_id': 'ballA'})
        store.save_shot_result(sh['id'], _rec_speed(v), {'ok': True})
    sid2 = store.create_session('u_md', {'mode': 'practice', 'oil_pattern_id': 'oilB'})['id']
    sh = store.create_shot('u_md', sid2, {'source': 'live', 'ball_configuration_id': 'ballB'})
    store.save_shot_result(sh['id'], _rec_speed(16.0), {'ok': True})
    sh = store.create_shot('u_md', sid2, {'source': 'live', 'ball_configuration_id': 'ballB'})
    store.save_shot_result(sh['id'], {'metrics': {'ball_speed': {'value': None, 'status': 'unavailable'}}}, {'ok': True})
    d = client.get('/me/stats/metric/ball_speed', headers={'X-Dev-User': 'u_md'}).json()
    assert d['n'] == 3 and d['small_sample'] is True
    assert abs(d['avg'] - 16.83) < 0.05 and d['coverage'] == 0.75   # 3 measured of 4 total
    assert len(d['by_ball']) == 2 and len(d['by_pattern']) == 2 and len(d['trend']) == 2


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
