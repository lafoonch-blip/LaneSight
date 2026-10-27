# lanesight_api — Mac service (Dev Build v0)

FastAPI over the real `lanesight_core` pipeline + engines. Binds to **localhost only** and is exposed to
the iPhone solely through **Tailscale serve** (HTTPS → localhost). Verifies the Supabase JWT on every
request (except `/health`). Analysis runs **one shot at a time** (serial queue, DEC-043). Video stays on
the Mac under `~/LaneSightData`; the Supabase service key lives only in the **macOS Keychain**.

## Install
```
cd lanesight-core && source .venv/bin/activate
pip install -e ".[api]"        # fastapi, uvicorn, python-multipart, pyjwt[crypto]
```

## Secrets (macOS Keychain — never in the repo or a log)
Two items on the `lanesight` account. `db_url` is the **PostgREST base** (the service writes via PostgREST
with the service_role key — no direct Postgres password needed):
```
security add-generic-password -a lanesight -s lanesight.supabase.db_url       -w 'https://<ref>.supabase.co/rest/v1/'
security add-generic-password -a lanesight -s lanesight.supabase.service_role -w '<service_role key>'
```
User JWTs are verified with the project's **public JWKS (ES256)** derived from `db_url` — there is no HS256
shared secret to store. With both items present the service runs in **live** mode (writes to Supabase);
with neither, **memory** mode for local testing (`LANESIGHT_FORCE_MEMORY=1` forces memory even if creds
exist). `GET /health` reports which (presence booleans only, never values).

## Run
```
lanesight_api/serve.sh            # live mode; binds to the tailnet IP, prints the app URL
lanesight_api/serve.sh --memory   # in-memory (first phone test; no Supabase users needed)
```
`serve.sh` binds uvicorn to the Mac's **Tailscale IP** so it's reachable by your phone (a tailnet peer)
but not the public internet or the LAN. This account can't issue HTTPS certs for `tailscale serve`, so the
app connects over plain **HTTP on the tailnet** (`http://<mac>.<tailnet>.ts.net:8787`) — WireGuard encrypts
it peer-to-peer. If you enable HTTPS Certificates + MagicDNS in the Tailscale admin console, switch back to
`tailscale serve --bg --https=443 http://127.0.0.1:8787` and bind uvicorn to 127.0.0.1.
Keep the Mac awake (`caffeinate -s`). `launchd` plist to start on login: `com.lanesight.api.plist` → copy
to `~/Library/LaunchAgents/`, then `launchctl load` it.

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
