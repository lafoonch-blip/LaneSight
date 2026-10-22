# lanesight_api — Mac service (Dev Build v0)

FastAPI over the real `lanesight_core` pipeline + engines. Binds to **localhost only** and is exposed to
the iPhone solely through **Tailscale serve** (HTTPS → localhost). Verifies the Supabase JWT on every
request (except `/health`). Analysis runs **one shot at a time** (serial queue, DEC-043). Video stays on
the Mac under `~/LaneSightData`; the Supabase service key lives only in the **macOS Keychain**.

## Install
```
cd lanesight-core && source .venv/bin/activate
pip install -e ".[api]"        # fastapi, uvicorn, python-multipart, pyjwt, psycopg
```

## Secrets (macOS Keychain — never in the repo or a log)
The service reads three items on the `lanesight` account:
```
security add-generic-password -a lanesight -s lanesight.supabase.db_url       -w '<postgres connection string>'
security add-generic-password -a lanesight -s lanesight.supabase.service_role -w '<service_role key>'
security add-generic-password -a lanesight -s lanesight.supabase.jwt_secret   -w '<project JWT secret (HS256)>'
```
With `db_url` present the service runs in **live** mode (writes to Supabase). With none present it runs in
**memory** mode for local testing. `GET /health` reports which (presence booleans only, never values).

## Run
```
uvicorn lanesight_api.app:app --host 127.0.0.1 --port 8787
# expose to your iPhone over Tailscale (HTTPS -> localhost):
tailscale serve --bg --https=443 http://127.0.0.1:8787
# the app points at https://<this-mac>.<tailnet>.ts.net
tailscale serve status      # verify
```
Keep the Mac awake while serving (`caffeinate -s` or Energy Saver). `launchd` plist to start on login:
`com.lanesight.api.plist` → copy to `~/Library/LaunchAgents/`, then `launchctl load` it.

## Health check
```
curl -s http://127.0.0.1:8787/health | python3 -m json.tool
```

## End-to-end test
```
# memory mode (no creds), any real down-lane shot clip:
LANESIGHT_API_DEV=1 uvicorn lanesight_api.app:app --port 8787 &
python3 examples/e2e_dev_build.py --base http://127.0.0.1:8787 --dev-user u1 --clip ~/path/IMG_8751.MOV
# live mode: add the Keychain items above, mint a Supabase JWT for a test user, pass --token <jwt>.
```

## Security invariants
- Bind localhost; reach only via `tailscale serve`.
- Secrets read from Keychain at runtime; never written to disk or logs (`Settings.redacted()` is the only
  thing logged).
- Service role bypasses RLS, so every per-user read is scoped by `user_id` in code.
