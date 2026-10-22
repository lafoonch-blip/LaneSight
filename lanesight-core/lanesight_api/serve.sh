#!/bin/bash
# Start the LaneSight Mac API for on-device app testing and print the Tailscale URL to use in the app.
# The API binds to the Mac's TAILSCALE IP, so it is reachable only by your tailnet peers (your phone),
# not the public internet or the local LAN. Traffic is WireGuard-encrypted peer-to-peer, so plain HTTP
# over the tailnet is fine for this owner-only dev build (this account can't get HTTPS certs for serve).
# Usage:  lanesight_api/serve.sh            # live mode (writes to Supabase; needs auth users)
#         lanesight_api/serve.sh --memory   # in-memory (first phone test; no Supabase users needed)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="$(cd "$HERE/.." && pwd)"
cd "$CORE"
# shellcheck disable=SC1091
source .venv/bin/activate

export LANESIGHT_API_DEV=1
[ "${1:-}" = "--memory" ] && export LANESIGHT_FORCE_MEMORY=1 && echo "mode: MEMORY (no Supabase writes)"

PORT=8787
TS_IP="$(/opt/homebrew/bin/tailscale ip -4 2>/dev/null | head -1 || true)"
DNS="$(/opt/homebrew/bin/tailscale status --json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)"
BIND="${TS_IP:-127.0.0.1}"
echo
[ -n "$DNS" ] && echo "App Settings -> API URL:  http://$DNS:$PORT"
[ -n "$TS_IP" ] && echo "            (or by IP:  http://$TS_IP:$PORT )"
echo "Keep the Mac awake while bowling:  caffeinate -s"
echo
echo "Starting API on $BIND:$PORT  (tailnet-only; Ctrl-C to stop)…"
exec uvicorn lanesight_api.app:app --host "$BIND" --port "$PORT"
