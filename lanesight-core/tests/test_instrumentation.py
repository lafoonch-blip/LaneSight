"""DEC-098 §2 — ops instrumentation (M1 cost, M2 api_request, M3 product events, M4 pseudonymisation, M5
storage snapshot). Offline: MemoryStore + dev auth, no live project."""
import os
import tempfile

os.environ['LANESIGHT_API_DEV'] = '1'
os.environ['LANESIGHT_FORCE_MEMORY'] = '1'
os.environ.setdefault('LANESIGHT_DATA', tempfile.mkdtemp())

from fastapi.testclient import TestClient
from lanesight_api.app import app, _attempt_cost, _templatize_path
from lanesight_api.store import get_store, MemoryStore, _user_ref

client = TestClient(app)
H = {'X-Dev-User': 'u1'}


# ---- M4 pseudonymisation -------------------------------------------------------------------------
def test_user_ref_is_deterministic_and_opaque():
    a, b = _user_ref('user-123'), _user_ref('user-123')
    assert a == b and a != 'user-123' and len(a) == 64          # stable hex sha256, not the raw id
    assert _user_ref('other') != a
    assert _user_ref(None) is None and _user_ref('') is None


def test_analysis_attempt_gets_user_ref():
    s = MemoryStore()
    r = s.log_analysis_attempt({'user_id': 'u9', 'status': 'analyzed'})
    assert r['user_ref'] == _user_ref('u9')


# ---- M1 cost -------------------------------------------------------------------------------------
def test_attempt_cost_measures_resource_seconds_no_dollars():
    c = _attempt_cost(2000, {'bytes': 2 * 1048576})            # 2.0s, 2 MiB
    assert c['basis'] == 'best_effort' and c['compute_s'] == 2.0
    assert c['vcpu_s'] == round(2.0 * c['vcpu'], 2) and c['gib_s'] == round(2.0 * c['gib'], 2)
    assert c['egress_mb'] == 2.0
    assert 'usd' not in json_keys(c) and 'est_usd' not in c     # no invented dollars in the row


def json_keys(d):
    return ''.join(d.keys())


def test_attempt_cost_never_raises():
    assert _attempt_cost(None, None) is not None                # degrades, doesn't crash


# ---- M2 api_request middleware -------------------------------------------------------------------
def test_health_is_not_metered_but_other_paths_are():
    store = get_store()
    client.get('/health')
    client.post('/sessions', json={}, headers={})              # 401, still metered
    reqs = getattr(store, 'api_requests', [])
    assert not any(r['path'] == '/health' for r in reqs)        # /health excluded
    sess = [r for r in reqs if r['path'] == '/sessions']
    assert sess and sess[-1]['status'] == 401 and sess[-1]['method'] == 'POST'
    assert 'duration_ms' in sess[-1] and 'user_id' not in sess[-1]   # no raw id in api_request


def test_templatize_path_collapses_ids():
    assert _templatize_path('/shots/8f3ab12cd9ef4455/pins') == '/shots/:id/pins'
    assert _templatize_path('/sessions') == '/sessions'


# ---- M3 product events ---------------------------------------------------------------------------
def test_events_ingest_validate_and_dedup():
    store = get_store()
    before = len(getattr(store, 'product_events', []))
    payload = {'events': [
        {'event_name': 'app_opened', 'client_event_id': 'e1'},
        {'event_name': 'first_shot_analyzed', 'client_event_id': 'e2', 'feature': 'shot'},
        {'event_name': 'not_a_real_event', 'client_event_id': 'e3'},     # unknown -> dropped
    ]}
    r = client.post('/events', json=payload, headers=H)
    assert r.status_code == 200
    assert r.json() == {'received': 3, 'accepted': 2}
    # idempotent: re-send e1/e2 -> 0 new
    r2 = client.post('/events', json={'events': [
        {'event_name': 'app_opened', 'client_event_id': 'e1'},
        {'event_name': 'session_started', 'client_event_id': 'e9'}]}, headers=H)
    assert r2.json()['accepted'] == 1
    evs = store.product_events[before:]
    assert all('user_id' not in e for e in evs)                 # pseudonymised
    assert any(e['user_ref'] == _user_ref('u1') for e in evs)
    assert all(e['event_name'] in {'app_opened', 'first_shot_analyzed', 'session_started'} for e in evs)


def test_events_requires_auth_and_list():
    assert client.post('/events', json={'events': []}).status_code == 401      # no auth
    assert client.post('/events', json={'nope': 1}, headers=H).status_code == 400


# ---- M5 storage snapshot writer ------------------------------------------------------------------
def test_record_storage_snapshot():
    s = MemoryStore()
    out = s.record_storage_snapshot([{'bucket': 'shot-clips', 'bytes': 123, 'objects': 2, 'aged_objects': 0},
                                     {'bucket': 'images', 'bytes': None}])   # NULL size allowed (NO DATA)
    assert len(out) == 2 and out[0]['bucket'] == 'shot-clips' and 'captured_at' in out[0]
    assert s.storage_snapshots[1]['bytes'] is None              # honest NULL, not 0
