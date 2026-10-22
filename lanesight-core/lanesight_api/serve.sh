#!/bin/bash
# Start the LaneSight Mac API for on-device app testing and print the Tailscale URL to use in the app.
# Usage:  lanesight_api/serve.sh            # live mode (writes to Supabase; needs auth users)
#         lanesight_api/serve.sh --memory   # in-memory (first phone test; no Supabase users needed)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="$(cd "$HERE/.." && pwd)"          # .../lanesight-core
cd "$CORE"
# shellcheck disable=SC1091
source .venv/bin/activate

export LANESIGHT_API_DEV=1              # dev auth: the app sends X-Dev-User instead of a Supabase JWT
[ "${1:-}" = "--memory" ] && export LANESIGHT_FORCE_MEMORY=1 && echo "mode: MEMORY (no Supabase writes)"

PORT=8787
DNS="$(/opt/homebrew/bin/tailscale status --json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)"
echo
echo "1) In another terminal, expose this over Tailscale (once):"
echo "     tailscale serve --bg --https=443 http://127.0.0.1:$PORT"
[ -n "$DNS" ] && echo "2) Set the app's API URL (Settings) to:  https://$DNS"
echo "3) Keep the Mac awake:  caffeinate -s   (or Energy Saver)"
echo
echo "Starting API on 127.0.0.1:$PORT  (Ctrl-C to stop)…"
exec uvicorn lanesight_api.app:app --host 127.0.0.1 --port "$PORT"
