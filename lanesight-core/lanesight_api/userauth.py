"""Email/password auth for the dev build. The Mac service mediates Supabase GoTrue so the iOS app only
ever sends email/password to the Mac (every Supabase key stays server-side). It returns the Supabase
session JWT (ES256); the app sends that as `Authorization: Bearer` and the API verifies it via JWKS.

Signup admin-creates a CONFIRMED user (so there's no email-confirmation round-trip for the owner dev
build), then password-grants a session. No fabricated success: any GoTrue error is surfaced.
"""
from __future__ import annotations
import json
import urllib.request
import urllib.error
from .config import settings


class AuthError(Exception):
    def __init__(self, status: int, body):
        self.status = status
        self.body = body
        super().__init__(f'{status}: {str(body)[:200]}')


def _post(path: str, body: dict, service_bearer: bool = False):
    s = settings()
    if not s.supabase_base:
        raise AuthError(503, 'live auth not configured (no Supabase db_url) — this build is misconfigured')
    headers = {'apikey': s.service_role or '', 'Content-Type': 'application/json'}
    if service_bearer:
        headers['Authorization'] = f'Bearer {s.service_role or ""}'
    req = urllib.request.Request(s.supabase_base + path, data=json.dumps(body).encode(),
                                 method='POST', headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, json.loads(r.read().decode() or '{}')
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode() or '{}')
        except Exception:
            return e.code, {}


def _session(tok: dict) -> dict:
    if not tok.get('access_token'):
        raise AuthError(401, tok or {'error': 'no session returned'})
    user = tok.get('user') or {}
    return {'access_token': tok['access_token'], 'refresh_token': tok.get('refresh_token'),
            'expires_in': tok.get('expires_in'), 'user_id': user.get('id')}


def signup(email: str, password: str) -> dict:
    # admin-create a confirmed user; tolerate "already registered" then fall through to sign in.
    st, body = _post('/auth/v1/admin/users',
                     {'email': email, 'password': password, 'email_confirm': True}, service_bearer=True)
    if st >= 400 and 'already' not in json.dumps(body).lower() and 'registered' not in json.dumps(body).lower():
        raise AuthError(st, body)
    return signin(email, password)


def signin(email: str, password: str) -> dict:
    st, tok = _post('/auth/v1/token?grant_type=password', {'email': email, 'password': password})
    if st >= 400:
        raise AuthError(401, tok)
    return _session(tok)


def refresh(refresh_token: str) -> dict:
    st, tok = _post('/auth/v1/token?grant_type=refresh_token', {'refresh_token': refresh_token})
    if st >= 400:
        raise AuthError(401, tok)
    return _session(tok)
