"""DEC-087 — profile fields (names/phone/grip/PAP), validation, the DOB 13+ gate, and the email-change flow.
In-memory + dev auth, same harness as test_api."""
import os, tempfile
from datetime import date

os.environ['LANESIGHT_API_DEV'] = '1'
os.environ['LANESIGHT_FORCE_MEMORY'] = '1'
os.environ['LANESIGHT_DATA'] = tempfile.mkdtemp()

import pytest
from fastapi.testclient import TestClient
from lanesight_api.app import app
from lanesight_api import userauth
from lanesight_api.profile_validation import validate_profile_patch, validate_dob, ProfileValidationError

client = TestClient(app)


def _h(u):
    return {'X-Dev-User': u}


def _adult_dob():
    return f'{date.today().year - 30}-06-15'


# ---------------------------------------------------------------- round-trip + partial updates

def test_profile_round_trips_every_field():
    h = _h('p_round')
    body = {'first_name': 'Shayne', 'last_name': 'Lafoon', 'phone': '+15035551234', 'dob': _adult_dob(),
            'handed': 'R', 'grip_middle_pitch_in': 0.25, 'grip_span_in': 4.5,
            'pap_over_in': 5.0, 'pap_up_in': 0.5}
    assert client.put('/me/profile', json=body, headers=h).status_code == 200
    p = client.get('/me/profile', headers=h).json()
    assert p['first_name'] == 'Shayne' and p['last_name'] == 'Lafoon'
    assert p['display_name'] == 'Shayne Lafoon'          # maintained for existing readers
    assert p['phone'] == '+15035551234' and p['handedness'] == 'right'
    assert p['grip_middle_pitch_in'] == 0.25 and p['grip_span_in'] == 4.5
    assert p['pap_over_in'] == 5.0 and p['pap_up_in'] == 0.5


def test_partial_update_preserves_other_fields():
    h = _h('p_partial')
    client.put('/me/profile', json={'first_name': 'Ann', 'last_name': 'Early', 'dob': _adult_dob()}, headers=h)
    # change ONLY the phone — names/dob must survive
    assert client.put('/me/profile', json={'phone': '5035559999'}, headers=h).status_code == 200
    p = client.get('/me/profile', headers=h).json()
    assert p['first_name'] == 'Ann' and p['last_name'] == 'Early' and p['dob']
    assert p['phone'] == '5035559999'
    # changing only last_name keeps first_name and recomposes display_name
    client.put('/me/profile', json={'last_name': 'Late'}, headers=h)
    p = client.get('/me/profile', headers=h).json()
    assert p['first_name'] == 'Ann' and p['last_name'] == 'Late' and p['display_name'] == 'Ann Late'


def test_clear_phone_with_empty_string():
    h = _h('p_clearphone')
    client.put('/me/profile', json={'first_name': 'Phe', 'last_name': 'None', 'dob': _adult_dob(),
                                    'phone': '+15035551234'}, headers=h)
    client.put('/me/profile', json={'phone': ''}, headers=h)
    assert client.get('/me/profile', headers=h).json().get('phone') in (None, '')


def test_legacy_display_name_splits_into_first_last_on_read():
    h = _h('p_legacy')
    client.put('/me/profile', json={'name': 'Jo Bowler', 'dob': _adult_dob()}, headers=h)
    p = client.get('/me/profile', headers=h).json()
    assert p['first_name'] == 'Jo' and p['last_name'] == 'Bowler'


# ---------------------------------------------------------------- validation (reject, never clamp)

def test_invalid_phone_rejected():
    h = _h('p_badphone')
    r = client.put('/me/profile', json={'phone': 'call-me'}, headers=h)
    assert r.status_code == 400 and r.json()['detail']['field'] == 'phone'


def test_out_of_range_measurement_rejected():
    h = _h('p_badmeas')
    r = client.put('/me/profile', json={'grip_span_in': 12.0}, headers=h)   # way beyond 3.0-6.0
    assert r.status_code == 400 and r.json()['detail']['field'] == 'grip_span_in'
    # a sane value is accepted
    assert client.put('/me/profile', json={'grip_span_in': 4.75}, headers=h).status_code == 200


def test_dob_missing_at_profile_creation_rejected():
    h = _h('p_nodob')
    r = client.put('/me/profile', json={'first_name': 'No', 'last_name': 'Dob'}, headers=h)
    assert r.status_code == 400 and r.json()['detail']['field'] == 'dob'


def test_dob_under_13_rejected_on_create_and_edit():
    h = _h('p_kid')
    young = f'{date.today().year - 8}-01-01'
    r = client.put('/me/profile', json={'first_name': 'Kid', 'last_name': 'O', 'dob': young}, headers=h)
    assert r.status_code == 400 and r.json()['detail']['field'] == 'dob'
    # a valid adult create, then editing to an under-13 DOB is also rejected
    client.put('/me/profile', json={'first_name': 'Kid', 'last_name': 'O', 'dob': _adult_dob()}, headers=h)
    r2 = client.put('/me/profile', json={'dob': young}, headers=h)
    assert r2.status_code == 400 and r2.json()['detail']['field'] == 'dob'


def test_future_dob_rejected():
    with pytest.raises(ProfileValidationError):
        validate_dob(f'{date.today().year + 1}-01-01')


def test_validate_exactly_13_allowed():
    today = date(2026, 10, 27)
    validate_dob('2013-10-27', today=today)              # turns 13 today — allowed
    with pytest.raises(ProfileValidationError):
        validate_dob('2013-10-28', today=today)          # 13 tomorrow — rejected


# ---------------------------------------------------------------- email change (mock Auth)

def test_email_change_triggers_confirmation(monkeypatch):
    sent = {}
    def fake_update_email(token, email):
        sent['token'] = token; sent['email'] = email
        return 200, {'email': 'old@x.com', 'new_email': email}
    monkeypatch.setattr(userauth, 'update_email', fake_update_email)
    r = client.put('/me/email', json={'email': 'new@x.com'},
                   headers={'X-Dev-User': 'p_email', 'Authorization': 'Bearer faketoken'})
    assert r.status_code == 200
    body = r.json()
    assert body['status'] == 'confirmation_sent' and body['email_pending'] == 'new@x.com'
    assert sent == {'token': 'faketoken', 'email': 'new@x.com'}
    # the pending email is NOT written to the profile
    assert 'email' not in (client.get('/me/profile', headers={'X-Dev-User': 'p_email'}).json() or {})


def test_email_change_rejects_garbage():
    r = client.put('/me/email', json={'email': 'not-an-email'},
                   headers={'X-Dev-User': 'p_email2', 'Authorization': 'Bearer faketoken'})
    assert r.status_code == 400 and r.json()['detail']['field'] == 'email'
