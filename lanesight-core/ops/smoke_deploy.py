#!/usr/bin/env python3
"""Mandatory post-deploy smoke test (P0 2026-10-29).

Uploads a known-good clip (IMG_8753, Ruby-validated 17.8 mph) through the REAL prod API end to end —
sign in -> create session -> create shot (multipart) -> the shot analyzes -> GET /shots/{id} — and asserts
status=analyzed with ball_speed within tolerance. Exit 0 = healthy; nonzero = the deploy is bad and the
caller (deploy_cloudrun.sh) rolls back to the previous revision.

Auth: a STAGED ls_* smoke account (DEC-063 — ls_* accounts may hold fabricated/staged data; only the owner
account stays real-only). The account is admin-created (idempotent) and a token minted, both via the Supabase
service-role key in the login keychain. Never touches the owner account.

Usage:  python3 ops/smoke_deploy.py [--api <url>]
Env:    LANESIGHT_SMOKE_API (override API), LANESIGHT_SMOKE_PW (override staged password)
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

CLIP = os.path.expanduser('~/LaneSightData/training_videos/IMG_8753.MOV')
CLIP_KEY = 'IMG_8753.MOV'
# Assert against the STORED SERVER reference within the DEC-092 don't-regress tolerance (ball_speed ±0.2 mph),
# so the smoke catches metric DRIFT revision-to-revision, not just breakage. The reference is the server's
# stable value (ops/smoke_reference.json); ball_speed is the 60 ft foul→pins average (DEC-064; metrics.py).
REFERENCE = os.path.join(os.path.dirname(__file__), 'smoke_reference.json')
SMOKE_EMAIL = 'ls_smoke@lanesight.test'
SMOKE_PW = os.environ.get('LANESIGHT_SMOKE_PW') or 'Sm0ke-deploy!2026'


def keychain(service: str) -> str:
    return subprocess.run(['security', 'find-generic-password', '-a', 'lanesight', '-s', service, '-w'],
                          capture_output=True, text=True).stdout.strip()


def supa_base() -> str:
    rest = keychain('lanesight.supabase.db_url')          # https://<ref>.supabase.co/rest/v1/
    if '/rest/' not in rest:
        raise SystemExit('db_url keychain item is not the Supabase REST base')
    return rest.split('/rest/')[0]


def http(method, url, headers=None, data=None, timeout=360):
    req = urllib.request.Request(url, method=method, data=data, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def token(base: str, svc: str) -> str:
    """Admin-create the staged smoke user (idempotent), then password sign-in for an access token."""
    http('POST', f'{base}/auth/v1/admin/users',
         {'apikey': svc, 'Authorization': f'Bearer {svc}', 'Content-Type': 'application/json'},
         json.dumps({'email': SMOKE_EMAIL, 'password': SMOKE_PW, 'email_confirm': True}).encode())
    st, resp = http('POST', f'{base}/auth/v1/token?grant_type=password',
                    {'apikey': svc, 'Content-Type': 'application/json'},
                    json.dumps({'email': SMOKE_EMAIL, 'password': SMOKE_PW}).encode())
    if st != 200:
        raise SystemExit(f'sign-in failed ({st}): {resp[:200]!r}')
    return json.loads(resp)['access_token']


def main():
    api = os.environ.get('LANESIGHT_SMOKE_API')
    if '--api' in sys.argv:
        api = sys.argv[sys.argv.index('--api') + 1]
    if not api:
        raise SystemExit('set --api <url> or LANESIGHT_SMOKE_API')
    api = api.rstrip('/')
    if not os.path.exists(CLIP):
        raise SystemExit(f'smoke clip missing: {CLIP}')

    base, svc = supa_base(), keychain('lanesight.supabase.service_role')
    if not svc:
        raise SystemExit('service_role not in keychain')
    tok = token(base, svc)
    auth = {'Authorization': f'Bearer {tok}'}

    # 0) ensure the staged account has a profile row (sessions FK to it) — idempotent onboarding
    http('PUT', f'{api}/me/profile', {**auth, 'Content-Type': 'application/json'},
         json.dumps({'display_name': 'LS Smoke', 'handed': 'R', 'units': 'mph',
                     'dob': '1990-01-01'}).encode())

    # 1) session
    st, resp = http('POST', f'{api}/sessions', {**auth, 'Content-Type': 'application/json'}, b'{}')
    if st != 200:
        raise SystemExit(f'create session failed ({st}): {resp[:200]!r}')
    sid = json.loads(resp).get('id') or json.loads(resp).get('session_id')

    # 2) multipart upload of the clip -> SYNC analysis (returns after the shot is analyzed). curl handles the
    #    multipart body robustly; the metadata marks it a shot upload on the staged account.
    meta = json.dumps({'capture_mode': 'shot', 'source': 'upload', 'handed': 'R'})
    cp = subprocess.run(['curl', '-s', '-w', '\n%{http_code}', '-X', 'POST',
                         f'{api}/sessions/{sid}/shots',
                         '-H', f'Authorization: Bearer {tok}',
                         '-F', f'file=@{CLIP};type=video/quicktime',
                         '-F', f'metadata={meta}'], capture_output=True, text=True, timeout=420)
    body, _, code = cp.stdout.rpartition('\n')
    if code.strip() != '200':
        raise SystemExit(f'create shot failed ({code.strip()}): {body[:300]}')
    shot_id = json.loads(body)['shot_id']

    # 3) read the shot back and assert
    st, resp = http('GET', f'{api}/shots/{shot_id}', auth)
    if st != 200:
        raise SystemExit(f'get shot failed ({st}): {resp[:200]!r}')
    rec = (json.loads(resp).get('record') or {})
    mets = rec.get('metrics') or {}
    bs = (mets.get('ball_speed') or {})
    val, status = bs.get('value'), bs.get('status')
    ref = json.load(open(REFERENCE))['clips'][CLIP_KEY]
    exp, tol = ref['ball_speed'], ref['tol_mph']
    print(f'smoke: shot={shot_id} ball_speed={val} status={status} (reference {exp}±{tol} mph)')
    if status != 'ok' or val is None:
        raise SystemExit(f'SMOKE FAIL: ball_speed not measured (status={status})')
    if abs(val - exp) > tol:
        raise SystemExit(f'SMOKE FAIL: ball_speed {val} drifted from reference {exp} by '
                         f'{val - exp:+.2f} (> ±{tol}). If intentional, update ops/smoke_reference.json.')
    print('SMOKE PASS')


if __name__ == '__main__':
    main()
