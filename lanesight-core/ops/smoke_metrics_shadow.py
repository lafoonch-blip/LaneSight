#!/usr/bin/env python3
"""DEC-127 live check — the on-device-first path produces BOTH engines' rows for one shot, with matching status.

Through the REAL prod API on the staged ls_smoke account (never the owner): POST /shots/metrics (an 'ios'
metrics record, no video) → upload the IMG_8753 clip to Storage → POST /shots/{id}/shadow_video (the server
VIDEO shadow). Then reads analysis_attempt + analysis_metric_outcome via the Supabase REST service role and
asserts the one shot has BOTH an 'ios' and a 'server' attempt, and that the per-metric STATUS agrees across
engines (ball_speed=best_effort, rev_rate=calibrated_estimate, entry_board=unavailable [DEC-065 gate],
arrows_board=measured) — i.e. no metric is 'measured' on one engine and best_effort/unavailable on the other.
Exit 0 = both-engine + parity confirmed.

Usage:  python3 ops/smoke_metrics_shadow.py --api <url>
"""
import json, os, subprocess, sys, urllib.error, urllib.request

CLIP = os.path.expanduser('~/LaneSightData/training_videos/IMG_8753.MOV')
SMOKE_EMAIL = 'ls_smoke@lanesight.test'
SMOKE_PW = os.environ.get('LANESIGHT_SMOKE_PW') or 'Sm0ke-deploy!2026'
# the metric statuses we expect BOTH engines to assign (the parity contract)
EXPECT = {'ball_speed': 'best_effort', 'rev_rate': 'calibrated_estimate',
          'arrows_board': 'measured', 'entry_board': 'unavailable', 'breakpoint_board': 'unavailable'}


def keychain(service):
    return subprocess.run(['security', 'find-generic-password', '-a', 'lanesight', '-s', service, '-w'],
                          capture_output=True, text=True).stdout.strip()


def http(method, url, headers=None, data=None, timeout=600):
    req = urllib.request.Request(url, method=method, data=data, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def main():
    api = sys.argv[sys.argv.index('--api') + 1] if '--api' in sys.argv else os.environ.get('LANESIGHT_SMOKE_API')
    if not api:
        raise SystemExit('set --api <url>')
    api = api.rstrip('/')
    if not os.path.exists(CLIP):
        raise SystemExit(f'clip missing: {CLIP}')
    rest = keychain('lanesight.supabase.db_url')
    base = rest.split('/rest/')[0]
    svc = keychain('lanesight.supabase.service_role')
    if not svc:
        raise SystemExit('service_role not in keychain')
    # staged account token
    http('POST', f'{base}/auth/v1/admin/users',
         {'apikey': svc, 'Authorization': f'Bearer {svc}', 'Content-Type': 'application/json'},
         json.dumps({'email': SMOKE_EMAIL, 'password': SMOKE_PW, 'email_confirm': True}).encode())
    st, resp = http('POST', f'{base}/auth/v1/token?grant_type=password',
                    {'apikey': svc, 'Content-Type': 'application/json'},
                    json.dumps({'email': SMOKE_EMAIL, 'password': SMOKE_PW}).encode())
    if st != 200:
        raise SystemExit(f'sign-in failed ({st}): {resp[:200]!r}')
    tok = json.loads(resp)['access_token']
    auth = {'Authorization': f'Bearer {tok}'}
    jauth = {**auth, 'Content-Type': 'application/json'}

    http('PUT', f'{api}/me/profile', jauth,
         json.dumps({'display_name': 'LS Smoke', 'handed': 'R', 'units': 'mph', 'dob': '1990-01-01'}).encode())
    st, resp = http('POST', f'{api}/sessions', jauth, b'{}')
    sid = json.loads(resp).get('id')

    # 1) on-device metrics record → 'ios' shot (server stamps canonical status)
    metrics = {k: {'value': v, 'status': 'ok'} for k, v in {
        'ball_speed': 16.8, 'rev_rate': 410.0, 'arrows_board': 13.5, 'laydown_board': 17.7,
        'board_at_7ft': 15.2, 'entry_board': 18.9, 'entry_angle': 5.2, 'breakpoint_board': 9.9,
        'breakpoint_distance': 36.5, 'launch_angle': 1.7}.items()}
    metrics['speed_avg_foul_to_pins'] = {'value': 15.2, 'status': 'best_effort'}
    body = {'metrics': metrics, 'session_id': sid, 'capture_mode': 'shot', 'source': 'live',
            'algorithm_version': 'ios-ondevice-smoke', 'metadata': {'handed': 'R',
            'intent': {'arrows_board': 13.0, 'breakpoint_board': 10.0}}}
    st, resp = http('POST', f'{api}/shots/metrics', jauth, json.dumps(body).encode())
    if st != 200:
        raise SystemExit(f'/shots/metrics failed ({st}): {resp[:300]!r}')
    shot_id = json.loads(resp)['shot_id']
    print(f'metrics: shot={shot_id} (ios)')

    # 2) upload the clip to Storage, then 3) fire the server VIDEO shadow for the SAME shot
    st, resp = http('POST', f'{api}/uploads/signed-url', jauth, b'{}')
    tgt = json.loads(resp)
    with open(CLIP, 'rb') as f:
        up_st, _ = http('PUT', tgt['upload_url'], {'Content-Type': 'video/quicktime'}, f.read())
    if up_st not in (200, 201):
        raise SystemExit(f'storage upload failed ({up_st})')
    st, resp = http('POST', f'{api}/shots/{shot_id}/shadow_video', jauth,
                    json.dumps({'storage_path': tgt['path']}).encode())
    print(f'shadow_video: {st} {resp[:120]!r}')
    if st != 200:
        raise SystemExit(f'shadow_video failed ({st}): {resp[:300]!r}')

    # 4) read attempts + outcomes via the Supabase REST service role
    sr = {'apikey': svc, 'Authorization': f'Bearer {svc}'}
    st, resp = http('GET', f'{base}/rest/v1/analysis_attempt?shot_id=eq.{shot_id}&select=id,platform,status,duration_ms', sr)
    attempts = json.loads(resp)
    plats = {a['platform']: a for a in attempts}
    print(f'attempts for shot: {[(a["platform"], a["status"], a.get("duration_ms")) for a in attempts]}')
    if 'ios' not in plats or 'server' not in plats:
        raise SystemExit(f'FAIL: expected BOTH ios + server attempts, got {sorted(plats)}')
    ids = ','.join(a['id'] for a in attempts)
    st, resp = http('GET', f'{base}/rest/v1/analysis_metric_outcome?attempt_id=in.({ids})'
                           f'&select=engine,metric_key,status,value', sr)
    rows = json.loads(resp)
    by = {}
    for r in rows:
        by.setdefault(r['metric_key'], {})[r['engine']] = r['status']
    print('\n  metric                 iphone        server')
    bad = []
    for k in EXPECT:
        i, s = by.get(k, {}).get('iphone'), by.get(k, {}).get('server')
        flag = '' if (i == s == EXPECT[k]) else '  <-- MISMATCH'
        if flag:
            bad.append((k, i, s))
        print(f'  {k:<20} {str(i):<12} {str(s):<12}{flag}')
    if bad:
        raise SystemExit(f'FAIL: cross-engine status disagreement: {bad}')
    print('\nPASS: one shot, BOTH engines, per-metric status agrees (DEC-127 parity + engine_metric_agreement).')


if __name__ == '__main__':
    main()
