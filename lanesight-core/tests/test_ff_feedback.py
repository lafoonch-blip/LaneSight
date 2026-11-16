"""F&F cohort + feedback app_phase (DEC-123 / DEC-124).

The stored feedback app_phase is authoritative from the author's account cohort, so a client can never spoof
the phase and Shayne's real account and staged test accounts never mix into the F&F / beta / live data.
"""
import os
import tempfile

os.environ['LANESIGHT_API_DEV'] = '1'          # dev auth via X-Dev-User
os.environ['LANESIGHT_FORCE_MEMORY'] = '1'     # never touch live Supabase
os.environ['LANESIGHT_DATA'] = tempfile.mkdtemp()

from fastapi.testclient import TestClient            # noqa: E402
from lanesight_api.app import app                    # noqa: E402
from lanesight_core.owner import OWNER_USER_ID       # noqa: E402

client = TestClient(app)


def _h(user):
    return {'X-Dev-User': user}


def test_general_feedback_defaults_phase_dev_when_no_cohort():
    # No profile cohort and the client sent none -> defaults to 'dev' (DEC-124 "defaults to dev only when absent").
    r = client.post('/feedback', json={'source': 'general', 'tags': ['Bug'], 'text': 'crashed on upload'},
                    headers=_h('ff_nocohort'))
    assert r.status_code == 200, r.text
    row = r.json()
    assert row['source'] == 'general'
    assert row['app_phase'] == 'dev'
    assert row['tags'][0] == 'Bug'          # category rides in tags[0] (DEC-124)


def test_general_feedback_phase_from_ff_cohort_overrides_client():
    # An F&F account's feedback is 'ff' from its cohort, even though the client sent app_phase='dev' (anti-spoof).
    u = 'ff_tester'
    pr = client.put('/me/profile', json={'name': 'FF Tester', 'dob': '2000-01-01', 'cohort': 'ff',
                                         'ff_consent_version': 'ff-consent-1',
                                         'ff_consent_at': '2026-11-02T12:00:00Z'},
                    headers=_h(u))
    assert pr.status_code == 200, pr.text
    assert pr.json().get('cohort') == 'ff'
    assert pr.json().get('ff_consent_version') == 'ff-consent-1'

    r = client.post('/feedback',
                    json={'source': 'general', 'tags': ['Idea'], 'text': 'great', 'app_phase': 'dev'},
                    headers=_h(u))
    assert r.status_code == 200, r.text
    assert r.json()['app_phase'] == 'ff'    # cohort wins over the client-sent phase


def test_owner_cohort_forced_dev():
    # Shayne's real account stays 'dev' whatever the client requests (DEC-123 guard).
    pr = client.put('/me/profile', json={'name': 'Shayne', 'dob': '1990-01-01', 'cohort': 'ff'},
                    headers=_h(OWNER_USER_ID))
    assert pr.status_code == 200, pr.text
    assert pr.json().get('cohort') == 'dev'

    r = client.post('/feedback', json={'source': 'general', 'tags': ['Other'], 'text': 'owner note'},
                    headers=_h(OWNER_USER_ID))
    assert r.json()['app_phase'] == 'dev'


def test_staged_account_cohort_forced_dev():
    # Staged test accounts are 'dev' (DEC-063/076) so they never contaminate F&F data.
    u = 'ff_staged'
    pr = client.put('/me/profile',
                    json={'name': 'Staged', 'dob': '1995-01-01', 'is_staged': True,
                          'staged_kind': 'active', 'cohort': 'ff'},
                    headers=_h(u))
    assert pr.status_code == 200, pr.text
    assert pr.json().get('cohort') == 'dev'
