"""Offline tests for the DV-03 engine wiring + new endpoints (MemoryStore + dev auth).

Uses synthetic ShotRecords and a stored validation ShotRecord as analyzed results, then exercises score
recompute, the achievement engine (progress/unlocks/activity/notifications), session-end tiers, benchmarks,
stats, and every new endpoint. No live project is touched (LANESIGHT_FORCE_MEMORY=1)."""
import os, json, pathlib, tempfile

os.environ['LANESIGHT_API_DEV'] = '1'
os.environ['LANESIGHT_FORCE_MEMORY'] = '1'
os.environ['LANESIGHT_DATA'] = tempfile.mkdtemp()

from fastapi.testclient import TestClient
from lanesight_api.app import app
from lanesight_api.store import get_store
from lanesight_api import engines

client = TestClient(app)
_VAL = pathlib.Path(__file__).resolve().parents[1] / 'validation' / 'IMG_8751_shot.json'


def H(u):
    return {'X-Dev-User': u}


def _m(value, status='ok', unc=None):
    d = {'value': value, 'status': status}
    if unc is not None:
        d['uncertainty'] = unc
    return d


def _rec(shot_id, entry_board=17, entry_angle=5.0, speed=16.0, rev=410.0, rev_unc=15.0,
         arrows=15.0, bp=10.0):
    metrics = {'entry_board': _m(entry_board), 'entry_angle': _m(entry_angle),
               'ball_speed': _m(speed), 'speed_late': _m(speed),
               'rev_rate': _m(rev, 'calibrated_estimate', unc=rev_unc),
               'arrows_board': _m(arrows), 'breakpoint_board': _m(bp)}
    return {'shot_id': shot_id, 'metrics': metrics, 'insights': {'classification': 'EXECUTED', 'recommendations': []}}


def _seed_shots(user, n, session_id, **kw):
    """Inject n analyzed shots (with intent) straight into the store, as the CV job would."""
    store = get_store()
    for i in range(n):
        sh = store.create_shot(user, session_id, {'intent': {'arrows_board': 15.0, 'breakpoint_board': 10.0},
                                                  'handed': 'R'})
        store.save_shot_result(sh['id'], _rec(sh['id'], **kw), {'ok': True})


# --------------------------------------------------------------------------- stats
def test_stats_honest_empty_then_populated():
    u = 'stats1'
    empty = client.get('/me/stats?view=throw', headers=H(u)).json()
    assert empty['empty'] is True and empty['n_shots'] == 0
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    _seed_shots(u, 5, sid)
    t = client.get('/me/stats?view=throw', headers=H(u)).json()
    assert t['empty'] is False and t['n_shots'] == 5
    assert t['averages']['ball_speed']['n'] == 5 and t['metric_coverage']['ball_speed']['pct'] == 100


def test_stats_coverage_and_failure_reasons_from_real_record():
    u = 'stats2'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    store = get_store()
    rec = json.loads(_VAL.read_text())
    sh = store.create_shot(u, sid, {'handed': 'R'})
    rec['shot_id'] = sh['id']
    store.save_shot_result(sh['id'], rec, {'ok': True})
    t = client.get('/me/stats?view=throw', headers=H(u)).json()
    # axis_rotation/axis_tilt are 'unavailable' in the validation record -> coverage 0, a failure reason
    assert t['metric_coverage']['axis_rotation']['pct'] == 0
    reasons = {r['metric'] for r in t['top_failure_reasons']}
    assert 'axis_rotation' in reasons or 'axis_tilt' in reasons


def test_stats_score_and_form_views():
    u = 'stats3'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    _seed_shots(u, 3, sid)
    client.get('/me/score', headers=H(u))                  # force a snapshot
    s = client.get('/me/stats?view=score', headers=H(u)).json()
    assert s['view'] == 'score' and 'components' in s
    f = client.get('/me/stats?view=form', headers=H(u)).json()
    assert f['view'] == 'form' and f['empty'] is True      # no form metrics measured -> honest empty


# --------------------------------------------------------------------------- achievements
def test_achievements_onboarding_and_cumulative_unlock():
    u = 'ach1'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    _seed_shots(u, 1, sid)
    client.put('/me/profile', json={'handed': 'R', 'delivery_style': 'one_handed_thumb'}, headers=H(u))
    client.post('/me/arsenal', json={'nickname': 'Phaze', 'weight_lb': 15}, headers=H(u))
    a = client.get('/me/achievements', headers=H(u)).json()
    flat = {x['id']: x for cat in a['categories'].values() for x in cat}
    assert flat['ACH-050']['unlocked'] is True             # profile complete
    assert flat['ACH-051']['unlocked'] is True             # first valid shot
    assert flat['ACH-053']['progress_status'] == 'in_progress' and flat['ACH-053']['current_value'] == 1
    # coming_later rows are present and flagged
    assert flat['ACH-005']['status'] == 'coming_later' and flat['ACH-005']['inactive_reason']
    assert a['unlocked_count'] >= 2


def test_achievement_detail_has_evidence_and_count_qualifying_unlock():
    u = 'ach2'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    _seed_shots(u, 10, sid)                                # 10 intent shots within 1 board -> ACH-010
    d = client.get('/me/achievements/ACH-010', headers=H(u)).json()
    assert d['unlocked'] is True and len(d['evidence_shot_ids']) == 10
    # a notification + activity item were emitted exactly once
    acts = client.get('/me/activity', headers=H(u)).json()
    assert sum(1 for x in acts if x['ref_id'] == 'ACH-010:1') == 1
    notes = client.get('/me/notifications?undelivered=1', headers=H(u)).json()
    assert any(n['ref_id'] == 'ACH-010:1' and n['kind'] == 'achievement_popup' for n in notes)


def test_achievement_idempotent_no_duplicate_unlocks():
    u = 'ach3'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    _seed_shots(u, 10, sid)
    for _ in range(3):
        client.get('/me/achievements', headers=H(u))       # re-run engine repeatedly
    store = get_store()
    unlocks = [x for x in store.list_ach_unlocks(u) if x['achievement_id'] == 'ACH-010']
    assert len(unlocks) == 1
    acts = [x for x in store.list_activity(u) if x['ref_id'] == 'ACH-010:1']
    assert len(acts) == 1


def test_not_trackable_window_ratio_honest():
    u = 'ach4'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    _seed_shots(u, 5, sid)                                 # under the 30-sample floor
    d = client.get('/me/achievements/ACH-011', headers=H(u)).json()
    assert d['progress']['status'] == 'not_trackable' and d['progress']['unavailable_reason']


def test_pins_roundtrip():
    u = 'ach5'
    client.put('/me/achievements/pins',
               json={'pins': [{'achievement_id': 'ACH-051', 'kind': 'showcase', 'position': 1}]}, headers=H(u))
    a = client.get('/me/achievements', headers=H(u)).json()
    assert a['pins'] == [{'achievement_id': 'ACH-051', 'kind': 'showcase', 'position': 1}]


# --------------------------------------------------------------------------- score + tiers (session end)
def test_session_end_scores_and_promotes_tier():
    u = 'tier1'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    # 25 clean shots (S'=100,A=100,C=100) + power ranges seeded -> eligible, high score -> onyx first-time
    _seed_shots(u, 25, sid)
    end = client.post(f'/sessions/{sid}/end', headers=H(u)).json()
    assert end['score']['eligible'] is True and end['score']['score'] is not None
    assert end['tier_event'] and end['tier_event']['kind'] == 'promotion'
    assert end['tier_event']['first_time'] is True
    # the first-time tier celebration notification exists and outranks achievement popups
    notes = client.get('/me/notifications?undelivered=1', headers=H(u)).json()
    cele = [n for n in notes if n['kind'] == 'tier_celebration']
    assert cele and cele[0]['priority'] == 100
    # Status achievement (first_tier) unlocked too
    det = client.get('/me/achievements/ACH-059', headers=H(u)).json()
    assert det['unlocked'] is True


def test_notifications_deliver_and_dismiss():
    u = 'tier2'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    _seed_shots(u, 10, sid)
    client.get('/me/achievements', headers=H(u))
    notes = client.get('/me/notifications?undelivered=1', headers=H(u)).json()
    assert notes
    nid = notes[0]['id']
    assert client.post(f'/me/notifications/{nid}/delivered', headers=H(u)).status_code == 200
    assert nid not in [n['id'] for n in client.get('/me/notifications?undelivered=1', headers=H(u)).json()]
    assert client.post(f'/me/notifications/{nid}/dismiss', headers=H(u)).status_code == 200
    assert nid not in [n['id'] for n in client.get('/me/notifications', headers=H(u)).json()]


# --------------------------------------------------------------------------- benchmarks / findings
def test_findings_and_baselines_from_session_end():
    u = 'bench1'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    # 15 shots with varied speed so a personal baseline establishes and spread can be classified
    store = get_store()
    import random
    random.seed(1)
    for i in range(15):
        sh = store.create_shot(u, sid, {'intent': {'arrows_board': 15.0, 'breakpoint_board': 10.0}, 'handed': 'R'})
        store.save_shot_result(sh['id'], _rec(sh['id'], speed=16.0 + random.uniform(-1.5, 1.5)), {'ok': True})
    client.post(f'/sessions/{sid}/end', headers=H(u))
    bases = {b['metric']: b for b in store.list_baselines(u)}
    assert 'ball_speed' in bases and bases['ball_speed']['n'] == 15 and bases['ball_speed']['established'] is True


# --------------------------------------------------------------------------- session screen / surface / upload / delete
def test_session_shots_listing():
    u = 'sess1'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    _seed_shots(u, 2, sid)
    rows = client.get(f'/sessions/{sid}/shots', headers=H(u)).json()
    assert len(rows) == 2 and all(r['state'] == 'analyzed' for r in rows)
    assert rows[0]['metrics']['ball_speed'] == 16.0


def test_surface_event():
    u = 'sess2'
    b = client.post('/me/arsenal', json={'nickname': 'Phaze'}, headers=H(u)).json()
    r = client.post(f"/me/arsenal/{b['id']}/surface", json={'grit': '2000', 'notes': 'fresh'}, headers=H(u))
    assert r.status_code == 200 and r.json()['grit'] == '2000'
    assert client.post('/me/arsenal/does-not-exist/surface', json={}, headers=H(u)).status_code == 404


def test_upload_uses_serial_path_with_source_upload():
    u = 'sess3'
    # Standalone upload (DEC-055): no session needed; the endpoint no longer takes a sid.
    r = client.post('/uploads', headers=H(u),
                    files={'file': ('clip.mov', b'not-a-video', 'video/quicktime')},
                    data={'metadata': json.dumps({'handed': 'R'})})
    assert r.status_code == 200 and r.json()['source'] == 'upload' and r.json()['job_id']
    # The upload shot is standalone (no session) and listed under Lab › Uploads.
    store = get_store()
    sh = store.get_shot(u, r.json()['shot_id'])
    assert sh['session_id'] is None and sh['source'] == 'upload'
    assert client.get('/sessions', headers=H(u)).json() == []            # never a session
    ups = client.get('/me/uploads', headers=H(u)).json()
    assert len(ups) == 1 and ups[0]['id'] == r.json()['shot_id'] and ups[0]['source'] == 'upload'


def test_uploads_excluded_from_score_stats_and_activity():
    u = 'sess3b'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    _seed_shots(u, 3, sid)                                               # 3 real practice shots
    store = get_store()
    # inject a standalone analyzed upload (source='upload', no session) as the CV job would
    up = store.create_shot(u, None, {'source': 'upload', 'handed': 'R'})
    store.save_shot_result(up['id'], _rec(up['id'], speed=25.0), {'ok': True})
    # score/stats read-back excludes the upload: still exactly the 3 practice shots
    recs, _i, _h = store.read_shot_records(u)
    assert len(recs) == 3 and all(r['shot_id'] != up['id'] for r in recs)
    assert client.get('/me/stats?view=throw', headers=H(u)).json()['n_shots'] == 3
    # the upload is listed under Lab › Uploads but never in Recent activity
    assert any(x['id'] == up['id'] for x in client.get('/me/uploads', headers=H(u)).json())
    assert all(x.get('ref_id') != up['id'] for x in client.get('/me/activity', headers=H(u)).json())


def test_delete_me_clears_user_data():
    u = 'del1'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    _seed_shots(u, 2, sid)
    client.get('/me/score', headers=H(u))
    assert client.delete('/me', headers=H(u)).json()['deleted'] is True
    store = get_store()
    assert store.user_shots(u) == [] and store.list_sessions(u) == []
    assert store.latest_score(u) is None
