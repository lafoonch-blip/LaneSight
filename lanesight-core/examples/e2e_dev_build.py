"""Scripted Dev Build v0 end-to-end test (HANDOFF §3 DV-03 'done when').

Drives a running lanesight_api: health -> create session -> upload a real clip -> poll the serial job ->
shot result -> end session -> feedback -> CSV export. Reports per-step timings.

Memory mode (no creds):   LANESIGHT_API_DEV=1 uvicorn lanesight_api.app:app --port 8787 &
                          python3 examples/e2e_dev_build.py --base http://127.0.0.1:8787 --dev-user u1 --clip ~/IMG_8751.MOV
Live mode (Supabase):     add the Keychain items (README), mint a Supabase JWT for a test user,
                          python3 examples/e2e_dev_build.py --base <url> --token <jwt> --clip ~/IMG_8751.MOV
"""
import argparse, json, sys, time
import httpx


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--base', required=True)
    ap.add_argument('--clip', required=True, help='a real down-lane shot clip, e.g. IMG_8751.MOV')
    ap.add_argument('--token', help='Supabase JWT (live mode)')
    ap.add_argument('--dev-user', help='X-Dev-User id (memory/dev mode)')
    ap.add_argument('--timeout', type=float, default=180)
    a = ap.parse_args()
    h = {}
    if a.token: h['Authorization'] = f'Bearer {a.token}'
    if a.dev_user: h['X-Dev-User'] = a.dev_user
    c = httpx.Client(base_url=a.base, headers=h, timeout=30)

    def step(name, fn):
        t = time.monotonic(); r = fn(); dt = time.monotonic() - t
        print(f"  {name:22} {dt*1000:7.0f} ms")
        return r

    print("health:", json.dumps(c.get('/health').json()['versions']))
    sid = step('create session', lambda: c.post('/sessions', json={'mode': 'practice'})).json()['id']
    with open(a.clip, 'rb') as f:
        up = step('upload shot', lambda: c.post(f'/sessions/{sid}/shots',
                  files={'file': ('clip.mov', f, 'video/quicktime')},
                  data={'metadata': json.dumps({'handed': 'R', 'capture_mode': 'shot',
                        'intent': {'arrows_board': 15.0, 'breakpoint_board': 8.0}})})).json()
    job_id = up['job_id']
    deadline = time.monotonic() + a.timeout
    while True:
        job = c.get(f'/jobs/{job_id}').json()
        if job['state'] in ('done', 'failed'):
            break
        if time.monotonic() > deadline:
            print("TIMEOUT waiting for job"); sys.exit(2)
        time.sleep(1)
    print("job:", job['state'], "timings:", job.get('timings'), "reason:", job.get('reason'))
    if job['state'] != 'done':
        print("FAIL: analysis job did not complete"); sys.exit(1)
    shot = c.get(f"/shots/{up['shot_id']}").json()
    print("shot metrics:", list((shot.get('record') or {}).get('metrics', {}))[:6], "...")
    print("score:", json.dumps({k: c.get('/me/score').json().get(k) for k in ('eligible', 'score', 'tier')}))
    print("end:", c.post(f'/sessions/{sid}/end').json())
    print("feedback:", c.post(f'/sessions/{sid}/feedback',
          json={'rating': 5, 'tags': ['Workflow'], 'text': 'e2e'}).status_code)
    csv = c.get(f'/sessions/{sid}/export.csv')
    print("export.csv bytes:", len(csv.text), "| has header:", 'shot_id,metric,value' in csv.text)
    print("E2E PASS")


if __name__ == '__main__':
    main()
