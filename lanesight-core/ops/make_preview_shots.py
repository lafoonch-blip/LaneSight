#!/usr/bin/env python3
"""Create preview shots on the staged ls_smoke account via /shots/metrics, so the DEBUG PreviewHarness
(LS_PREVIEW=shotcard, LS_PREVIEW_ID=<id>) can render the real result card for a screenshot. Prints the shot ids.

Usage:  python3 ops/make_preview_shots.py --api <url>
Prints: MEASURED <shot_id>   and   FARLANE <shot_id>
"""
import json, os, subprocess, sys, urllib.request, urllib.error

EMAIL = 'ls_smoke@lanesight.test'
PW = os.environ.get('LANESIGHT_SMOKE_PW') or 'Sm0ke-deploy!2026'


def keychain(s):
    return subprocess.run(['security', 'find-generic-password', '-a', 'lanesight', '-s', s, '-w'],
                          capture_output=True, text=True).stdout.strip()


def http(method, url, headers=None, data=None, timeout=60):
    req = urllib.request.Request(url, method=method, data=data, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def smoothed_path():
    """A realistic curved ball path (board vs ft), sampled smoothly — like the design good-throw line."""
    anchors = [(0, 16.5), (7, 15.1), (15, 12.0), (30, 8.2), (43, 5.6), (52, 7.0), (59, 13.5)]
    pts = []
    for i in range(len(anchors) - 1):
        (z0, b0), (z1, b1) = anchors[i], anchors[i + 1]
        for k in range(6):
            t = k / 6.0
            pts.append({'z_ft': round(z0 + t * (z1 - z0), 2), 'board': round(b0 + t * (b1 - b0), 2)})
    pts.append({'z_ft': 59.0, 'board': 13.5})
    return pts


def main():
    api = (sys.argv[sys.argv.index('--api') + 1] if '--api' in sys.argv else os.environ.get('LANESIGHT_SMOKE_API')).rstrip('/')
    base = keychain('lanesight.supabase.db_url').split('/rest/')[0]
    svc = keychain('lanesight.supabase.service_role')
    http('POST', f'{base}/auth/v1/admin/users',
         {'apikey': svc, 'Authorization': f'Bearer {svc}', 'Content-Type': 'application/json'},
         json.dumps({'email': EMAIL, 'password': PW, 'email_confirm': True}).encode())
    _, resp = http('POST', f'{base}/auth/v1/token?grant_type=password',
                   {'apikey': svc, 'Content-Type': 'application/json'},
                   json.dumps({'email': EMAIL, 'password': PW}).encode())
    tok = json.loads(resp)['access_token']
    jauth = {'Authorization': f'Bearer {tok}', 'Content-Type': 'application/json'}
    http('PUT', f'{api}/me/profile', jauth,
         json.dumps({'display_name': 'LS Smoke', 'handed': 'R', 'units': 'mph', 'dob': '1990-01-01'}).encode())
    _, resp = http('POST', f'{api}/sessions', jauth, b'{}')
    sid = json.loads(resp)['id']
    traj = {'smoothed': smoothed_path(), 'series': smoothed_path()}

    def make(label, metrics):
        body = {'metrics': metrics, 'session_id': sid, 'capture_mode': 'shot', 'source': 'live',
                'algorithm_version': 'ios-ondevice-preview', 'trajectory': traj,
                'metadata': {'handed': 'R', 'intent': {'arrows_board': 12.0, 'breakpoint_board': 6.0}}}
        st, r = http('POST', f'{api}/shots/metrics', jauth, json.dumps(body).encode())
        if st != 200:
            raise SystemExit(f'{label} failed ({st}): {r[:200]!r}')
        print(label, json.loads(r)['shot_id'])

    # (a) measured: speed/rev + near-lane boards present; far-lane gated server-side by policy
    make('MEASURED', {
        'ball_speed': {'value': 17.4}, 'rev_rate': {'value': 404.0},
        'speed_avg_foul_to_pins': {'value': 16.2}, 'laydown_board': {'value': 16.4},
        'board_at_7ft': {'value': 15.1}, 'arrows_board': {'value': 12.2}, 'launch_angle': {'value': 1.5},
        'entry_board': {'value': 15.3}, 'entry_angle': {'value': 3.7}, 'breakpoint_board': {'value': 5.4},
        'breakpoint_distance': {'value': 43.0}})
    # (b) far-lane / sparse: only the very near lane read (laydown), everything else unavailable
    make('FARLANE', {
        'ball_speed': {'value': 17.7}, 'rev_rate': {'value': 404.0}, 'laydown_board': {'value': 16.4},
        'arrows_board': {'value': 12.2}})


if __name__ == '__main__':
    main()
