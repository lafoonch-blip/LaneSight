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


def test_upload_dedupe_flag(monkeypatch):
    # DEC-086: upload de-duplication is behind LANESIGHT_UPLOAD_DEDUPE (default OFF) so the same clip can be
    # uploaded and analyzed repeatedly for testing.
    import hashlib
    store = get_store()
    data = b'fake-clip-bytes-for-dedupe'
    h = hashlib.sha256(data).hexdigest()
    prior = store.create_shot('u1', None, {'source': 'upload'})
    store.set_content_hash(prior['id'], h)
    # Flag ON -> an identical re-upload short-circuits to the existing shot (never runs analysis).
    monkeypatch.setenv('LANESIGHT_UPLOAD_DEDUPE', '1')
    r = client.post('/uploads', files={'file': ('clip.mov', data, 'video/quicktime')},
                    data={'metadata': '{}'}, headers=H)
    assert r.status_code == 200
    body = r.json()
    assert body.get('duplicate') is True and body['shot_id'] == prior['id'] and 'job_id' not in body
    # Flag OFF (default) -> the identical clip makes a brand-new shot + runs a fresh analysis.
    monkeypatch.delenv('LANESIGHT_UPLOAD_DEDUPE', raising=False)
    r = client.post('/uploads', files={'file': ('clip.mov', data, 'video/quicktime')},
                    data={'metadata': '{}'}, headers=H)
    body = r.json()
    assert body.get('duplicate') is not True and body['shot_id'] != prior['id'] and 'job_id' in body


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


def test_next_focus_dominant_issue():
    # MVP-12: the dominant recurring recent issue becomes the Home focus; strikes don't count against it.
    store = get_store()
    def rec_state(state, reason):
        return {'metrics': {'ball_speed': {'value': 17.0, 'status': 'ok'}},
                'insights': {'state': state, 'recommendations': [{'reason': reason, 'expected': 'x'}]}}
    sid = store.create_session('u_focus', {'mode': 'practice'})['id']
    for _ in range(4):
        sh = store.create_shot('u_focus', sid, {'source': 'live'})
        store.save_shot_result(sh['id'], rec_state('execution_miss', 'Missed your mark'), {'ok': True})
    sh = store.create_shot('u_focus', sid, {'source': 'live'})
    store.save_shot_result(sh['id'], rec_state('strike_repeat', 'Strike'), {'ok': True})
    d = client.get('/me/focus', headers={'X-Dev-User': 'u_focus'}).json()
    assert d['status'] == 'ok' and d['state'] == 'execution_miss' and d['focus'] == 'Hit your mark'


def test_next_focus_building_for_new_user():
    assert client.get('/me/focus', headers={'X-Dev-User': 'u_focusnew'}).json()['status'] == 'building'


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

def test_me_score_parts_delta_30d():
    """DEC-083: /me/score reports each part's 30-day change from history; only parts present in both the
    current and the ~30-day-old reference snapshot get a delta — nothing is fabricated."""
    import time as _t
    st = get_store()
    uid = 'u_delta'
    now = _t.time()
    # a reference snapshot 40 days ago, then today's — the endpoint reads the most recent >=30-day-old one
    st.snapshots[uid] = [
        {'eligible': True, 'score': 600, 's_perf': 60, 'a_acc': 50, 'c_cons': 70, 'p_power': None,
         'computed_at': now - 40 * 86400},
        {'eligible': True, 'score': 640, 's_perf': 64, 'a_acc': 48, 'c_cons': 70, 'p_power': 71,
         'computed_at': now},
    ]
    d = client.get('/me/score', headers={'X-Dev-User': uid}).json()['parts_delta_30d']
    assert d['s_perf'] == 4.0 and d['a_acc'] == -2.0 and d['c_cons'] == 0.0
    assert 'p_power' not in d          # no reference value 40 days ago → no delta (shown as "New")


def test_me_score_parts_delta_30d_absent_for_new_account():
    st = get_store()
    uid = 'u_delta_new'
    st.snapshots[uid] = [{'eligible': True, 'score': 500, 's_perf': 50, 'a_acc': 50, 'c_cons': 50,
                          'p_power': 50, 'computed_at': __import__('time').time()}]
    assert client.get('/me/score', headers={'X-Dev-User': uid}).json()['parts_delta_30d'] == {}


def test_attempt_clip_and_quality_capture():
    """DEC-086: the attempt log captures camera/recording facts (clip) and, on success, capture-quality +
    geometry (so framing can be correlated with outcomes), with missing fields omitted (never fabricated)."""
    from lanesight_api.app import _clip_info, _quality
    probe = {'measured_fps': 59.94, 'nominal_fps': 60, 'width': 1920, 'height': 1080, 'short_side_px': 1080,
             'rotation': 90, 'hdr': True, 'variable_frame_rate': False, 'duration_s': 7.2, 'frames': 432,
             'codec': 'hevc', 'color_transfer': 'arib-std-b67'}
    ci = _clip_info(probe)
    assert ci['width'] == 1920 and ci['rotation'] == 90 and ci['hdr'] is True and ci['fps'] == 59.94
    assert 'bytes' not in ci                                   # omitted when absent, not null/0

    q = _quality({'capture_quality': {'far_lane': 'limited', 'reason': 'camera too close'},
                  'metrics': {'ball_speed': {'value': 17.2}, 'entry_board': {'value': 18.0},
                              'rev_rate': {'value': None}}})
    assert q['far_lane'] == 'limited' and q['capture_reason'] == 'camera too close'
    assert q['ball_speed'] == 17.2 and q['entry_board'] == 18.0 and q['n_measured'] == 2
    assert 'rev_rate' not in q                                 # None metric omitted
    assert _quality(None) is None and _quality({}) is None     # nothing measured → None


def test_shot_card_enrichment_on_get_shot():
    """DEC-088/090: GET /shots/{id} enriches a ball shot with path_fit, impact_energy_j, baseline and
    insights.throw/lane/coach — the fields the redesigned shot card renders."""
    h = {'X-Dev-User': 'u_card'}
    sid = client.post('/sessions', json={'mode': 'practice'}, headers=h).json()['id']
    store = get_store()
    rec = json.loads(_VAL.read_text())
    shot = store.create_shot('u_card', sid, {'handed': 'R'})
    rec['shot_id'] = shot['id']
    store.save_shot_result(shot['id'], rec, {'ok': True})
    body = client.get(f"/shots/{shot['id']}", headers=h).json()
    r = body['record']
    assert r.get('path_fit') and r['path_fit']['points']            # the fitted lane path for the 3D view
    assert r.get('impact_energy_j') is not None                     # Power ring (DEC-024)
    ins = r.get('insights') or {}
    assert ins.get('coach', {}).get('action') in ('keep', 'lane_move', 'no_move', 'no_move_yet')
    assert ins.get('throw', {}).get('status') in ('good', 'off', 'building')
    assert ins.get('lane', {}).get('status') in ('good', 'miss', 'not_read')
    assert r.get('baseline', {}).get('n') is not None


def test_precheck_is_safe_on_a_bad_path():
    """DEC-092 P0: the framing precheck never raises — an unreadable clip yields ok=None so the caller
    falls through to the full pipeline (shadow mode must never block analysis)."""
    from lanesight_core.cv.precheck import precheck
    r = precheck('/no/such/clip.mov')
    assert r['ok'] is None and 'seconds' in r


def test_decode_stats_counts_passes():
    """DEC-092 P0 counters + P1 decode-once: the first pass decodes and populates the bounded frame cache; a
    second pass over a clip that fits the budget is served from the cache (no decode) with byte-identical frames."""
    from lanesight_core.cv import stabilize as _stab
    from lanesight_core.cv.stabilize import reset_decode_stats, decode_stats, frames
    import numpy as np, cv2, tempfile, os
    _stab._FRAME_CACHE_MB = 100          # enough for the tiny clip regardless of the prod default
    reset_decode_stats()
    s0 = decode_stats()
    assert s0['passes'] == 0 and s0['frames'] == 0 and s0['cached_passes'] == 0
    # write a tiny 6-frame clip with distinct content per frame, then decode it twice
    with tempfile.TemporaryDirectory() as td:
        p = os.path.join(td, 't.mp4')
        w = cv2.VideoWriter(p, cv2.VideoWriter_fourcc(*'mp4v'), 10, (32, 32))
        for k in range(6):
            w.write(np.full((32, 32, 3), k * 20, np.uint8))
        w.release()
        if not os.path.exists(p) or os.path.getsize(p) == 0:
            return  # no mp4 encoder available in this env; the counter contract is still covered above
        first = [f.copy() for _, f in frames(p)]      # pass 1: decodes + populates cache
        second = [f.copy() for _, f in frames(p)]      # pass 2: served from cache (fits the budget)
    s = decode_stats()
    assert s['passes'] == 1, f"second pass should be cached, not decoded: {s}"
    assert s['cached_passes'] == 1 and s['cache_complete'] is True
    assert len(first) == len(second) and len(first) >= 2
    for a, b in zip(first, second):                    # decode-once must be byte-identical (accuracy unchanged)
        assert np.array_equal(a, b)


def test_coaching_notify_flag():
    """DEC-084: PUT /me/notify records the coaching-launch interest flag; GET reads it back."""
    h = {'X-Dev-User': 'u_notify'}
    assert client.get('/me/notify', headers=h).json()['coaching_launch'] is False
    assert client.put('/me/notify', json={'coaching_launch': True}, headers=h).json()['coaching_launch'] is True
    assert client.get('/me/notify', headers=h).json()['coaching_launch'] is True


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


def test_score_breakdown_shape_building():
    """/me/score/breakdown returns the 4 part blocks for a brand-new user, all null (building) — never a
    fabricated number and never a 500."""
    H = {'X-Dev-User': 'uScoreBreakdown'}
    r = client.get('/me/score/breakdown', headers=H)
    assert r.status_code == 200
    b = r.json()
    for k in ('performance', 'accuracy', 'consistency', 'power'):
        assert k in b, f'missing part {k}'
    assert b['performance']['value'] is None
    assert b['accuracy']['n_total'] == 0
    assert b['accuracy']['avg_arrow_miss'] is None
    assert b['consistency']['spreads'] == {}


# --- DEC-097: ball + oil locked per shot at record time; mid-session changes affect only later shots ---

def test_oil_backfills_from_session_and_locks_on_the_shot():
    store = get_store()
    sid = store.create_session('u_oilA', {'mode': 'practice', 'oil_pattern_id': 'oilA'})['id']
    s1 = store.create_shot('u_oilA', sid, {'source': 'live', 'user_ball_id': 'ballA'})
    assert s1['oil_pattern_id'] == 'oilA'                       # backfilled from the session at record time


def test_explicit_per_shot_oil_wins_over_session():
    store = get_store()
    sid = store.create_session('u_oilB', {'mode': 'practice', 'oil_pattern_id': 'oilSession'})['id']
    sh = store.create_shot('u_oilB', sid, {'source': 'live', 'oil_pattern_id': 'oilExplicit'})
    assert sh['oil_pattern_id'] == 'oilExplicit'


def test_mid_session_oil_change_affects_only_later_shots():
    store = get_store()
    sid = store.create_session('u_oilC', {'mode': 'practice', 'oil_pattern_id': 'oil1'})['id']
    s1 = store.create_shot('u_oilC', sid, {'source': 'live', 'user_ball_id': 'ball1'})
    store.sessions[sid]['oil_pattern_id'] = 'oil2'              # bowler switches oil mid-session
    s2 = store.create_shot('u_oilC', sid, {'source': 'live', 'user_ball_id': 'ball2', 'oil_pattern_id': 'oil2'})
    assert store.shots[s1['id']]['oil_pattern_id'] == 'oil1'   # earlier shot keeps what it was thrown with
    assert store.shots[s2['id']]['oil_pattern_id'] == 'oil2'
    assert store.shots[s1['id']]['user_ball_id'] == 'ball1' and store.shots[s2['id']]['user_ball_id'] == 'ball2'


def test_last_setup_reads_per_shot_oil_not_session_current():
    # DEC-097/044: recommendations/ball-reaction read the oil ON the shot, never the session's current value.
    store = get_store()
    sid = store.create_session('u_oilD', {'mode': 'practice', 'oil_pattern_id': 'oilThrown'})['id']
    store.create_shot('u_oilD', sid, {'source': 'live', 'user_ball_id': 'ballThrown'})
    store.sessions[sid]['oil_pattern_id'] = 'oilLater'         # session changes AFTER the shot was thrown
    ctx = store.last_setup('u_oilD')
    assert ctx['oil_pattern_id'] == 'oilThrown' and ctx['user_ball_id'] == 'ballThrown'


def test_old_shot_without_per_shot_oil_falls_back_to_session():
    store = get_store()
    sid = store.create_session('u_oilE', {'mode': 'practice', 'oil_pattern_id': 'oilSess'})['id']
    sh = store.create_shot('u_oilE', sid, {'source': 'live', 'user_ball_id': 'ballE'})
    store.shots[sh['id']]['oil_pattern_id'] = None             # simulate a pre-DEC-097 row
    ctx = store.last_setup('u_oilE')
    assert ctx['oil_pattern_id'] == 'oilSess'                  # read-time fallback to the session's oil


def test_session_shots_carry_per_shot_ball_and_oil():
    # DEC-097 follow-up: each shot row carries the ball + oil it was thrown with (for the list + dividers).
    store = get_store()
    sid = store.create_session('u_rows', {'mode': 'practice', 'oil_pattern_id': 'oilR1'})['id']
    a = store.create_shot('u_rows', sid, {'source': 'live', 'user_ball_id': 'ballR1'})
    store.shots[a['id']]['record'] = {'metrics': {'ball_speed': {'value': 17.0, 'status': 'ok'}}}
    store.sessions[sid]['oil_pattern_id'] = 'oilR2'              # switch oil mid-session
    b = store.create_shot('u_rows', sid, {'source': 'live', 'user_ball_id': 'ballR2', 'oil_pattern_id': 'oilR2'})
    store.shots[b['id']]['record'] = {'metrics': {'ball_speed': {'value': 16.0, 'status': 'ok'}}}
    rows = store.session_shots('u_rows', sid)
    assert [r['user_ball_id'] for r in rows] == ['ballR1', 'ballR2']
    assert [r['oil_pattern_id'] for r in rows] == ['oilR1', 'oilR2']   # first backfilled to the session oil at record
    assert all('ball_name' in r and 'oil_name' in r for r in rows)     # name fields present (None offline)


def test_arsenal_default_ball_is_separate_from_current():
    # DEC-099: one default ball per bowler (what a new session starts with), independent of is_current.
    hh = {'X-Dev-User': 'ars_def'}
    a = client.post('/me/arsenal', json={'name': 'Phaze II', 'make_current': True, 'make_default': True},
                    headers=hh).json()
    assert a['is_default'] is True and a['is_current'] is True
    b = client.post('/me/arsenal', json={'name': 'Spare Ball'}, headers=hh).json()
    assert b['is_default'] is False
    # picking another ball for the session moves CURRENT, never the default
    client.patch(f"/me/arsenal/{b['id']}", json={'is_current': True}, headers=hh)
    by_id = {x['id']: x for x in client.get('/me/arsenal', headers=hh).json()}
    assert by_id[b['id']]['is_current'] and by_id[a['id']]['is_default'] and not by_id[b['id']]['is_default']
    # setting a new default unsets the old one
    client.patch(f"/me/arsenal/{b['id']}", json={'is_default': True}, headers=hh)
    lst = client.get('/me/arsenal', headers=hh).json()
    assert [x['id'] for x in lst if x['is_default']] == [b['id']]
    # clearing / retiring removes the default
    client.patch(f"/me/arsenal/{b['id']}", json={'is_default': False}, headers=hh)
    assert not any(x['is_default'] for x in client.get('/me/arsenal', headers=hh).json())
    client.patch(f"/me/arsenal/{a['id']}", json={'is_default': True}, headers=hh)
    client.patch(f"/me/arsenal/{a['id']}", json={'retired': True}, headers=hh)
    assert not any(x['is_default'] for x in client.get('/me/arsenal', headers=hh).json())


def test_clips_are_retained_and_linked_to_the_attempt(monkeypatch):
    # DEC-100: an analyzed clip stays in Storage for the diagnostic window and its path is on the attempt row.
    from lanesight_api.store import get_store
    store = get_store()
    hh = {'X-Dev-User': 'keep1'}
    up = client.post('/uploads/signed-url', headers=hh).json()
    with open(up['upload_url'][len('file://'):], 'wb') as f:
        f.write(b'not-a-video')                            # the job fails; retention must still hold
    r = client.post('/shots/analyze', headers=hh,
                    json={'storage_path': up['path'], 'metadata': {'capture_mode': 'shot'}})
    assert r.status_code == 200
    assert store.storage_download('shot-clips', up['path']) == b'not-a-video'      # NOT deleted
    import time as _t
    for _ in range(100):                                    # the job may run on the serial worker
        if client.get(f"/jobs/{r.json()['job_id']}", headers=hh).json().get('state') in ('done', 'failed'):
            break
        _t.sleep(0.1)
    att = [a for a in getattr(store, 'analysis_attempts', []) if a.get('user_id') == 'keep1']
    assert att and att[-1]['clip']['storage_path'] == up['path']


def test_clip_retention_zero_deletes(monkeypatch):
    monkeypatch.setenv('LANESIGHT_CLIP_RETENTION_DAYS', '0')
    from lanesight_api.store import get_store
    import os as _os
    hh = {'X-Dev-User': 'keep0'}
    up = client.post('/uploads/signed-url', headers=hh).json()
    p = up['upload_url'][len('file://'):]
    with open(p, 'wb') as f:
        f.write(b'x')
    client.post('/shots/analyze', headers=hh, json={'storage_path': up['path'], 'metadata': {}})
    assert not _os.path.exists(p)


def test_purge_keeps_only_newest(tmp_path):
    from lanesight_api.store import MemoryStore
    import os as _os, time as _t
    s = MemoryStore()
    for i in range(5):
        s.storage_upload('shot-clips', f'purge_u/{i}.mov', b'x')
        p = s._local_storage_path('shot-clips', f'purge_u/{i}.mov')
        _os.utime(p, (_t.time() - (100 - i), _t.time() - (100 - i)))
    assert s.purge_old_clips('shot-clips', 'purge_u', days=7, keep_max=2) == 3
    left = sorted(_os.listdir(_os.path.dirname(s._local_storage_path('shot-clips', 'purge_u/x'))))
    assert left == ['3.mov', '4.mov']


def test_client_failure_is_logged():
    from lanesight_api.store import get_store
    r = client.post('/analysis/client-failure', headers={'X-Dev-User': 'cf1'},
                    json={'stage': 'upload', 'error': 'The request timed out.', 'source': 'upload',
                          'capture_mode': 'shot', 'clip_bytes': 51000000})
    assert r.status_code == 200
    att = [a for a in getattr(get_store(), 'analysis_attempts', []) if a.get('user_id') == 'cf1']
    assert att[-1]['failure_code'] == 'CLIENT_UPLOAD' and att[-1]['failure_stage'] == 'client'


def test_form_record_with_every_event_gated_is_a_failure():
    # DEC-100: tonight's form uploads came back "analyzed" with every swing event dropped (empty card).
    from lanesight_api.app import _form_not_isolated
    gated = {'events': {'E2': None, 'E4': None, 'E5': 4.1, 'E7': None, 'E8': 5.3}, 'key_frames': [],
             'metrics': {'swing_time': {'value': 1.135}, 'step_count': {'value': 3}}, 'view': 'down_lane'}
    d = _form_not_isolated(gated)
    assert d and d['swing_time_s'] == 1.135 and d['step_count'] == 3
    ok = {'events': {'E2': 1.0, 'E4': 1.6, 'E7': 2.6}, 'key_frames': ['release']}
    assert _form_not_isolated(ok) is None


def test_snapshot_frames_from_a_real_video(tmp_path):
    import cv2, numpy as np
    from lanesight_api.app import _snapshot_frames
    p = str(tmp_path / 'c.mp4')
    w = cv2.VideoWriter(p, cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 360))
    for i in range(60):
        w.write(np.full((360, 640, 3), i * 4, np.uint8))
    w.release()
    fr = _snapshot_frames(p, n=4)
    assert len(fr) == 4 and all(f.get('jpg_b64') for f in fr)
    assert _snapshot_frames(str(tmp_path / 'missing.mp4')) == []
