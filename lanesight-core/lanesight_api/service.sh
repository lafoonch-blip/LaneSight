#!/bin/bash
# DV-03: manage the LaneSight Mac API as a per-user launchd service so it starts at login, restarts if it
# dies (KeepAlive), keeps the Mac awake while running (caffeinate -s), and logs to ~/LaneSightData/logs.
# It runs lanesight_api/serve.sh in its DEFAULT (LIVE Supabase) mode — never memory. No Terminal window
# to babysit.
#
#   lanesight_api/service.sh install     # generate + load the LaunchAgent, start it now, print status
#   lanesight_api/service.sh status      # loaded? running? pid? + /health probe
#   lanesight_api/service.sh restart      # kickstart -k (reload code)
#   lanesight_api/service.sh logs         # tail the out/err logs
#   lanesight_api/service.sh uninstall    # stop + remove the LaunchAgent
set -euo pipefail

LABEL="com.lanesight.api"
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="$(cd "$HERE/.." && pwd)"
SERVE="$HERE/serve.sh"
LOGDIR="$HOME/LaneSightData/logs"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI="gui/$(id -u)"
CAFFEINATE="/usr/bin/caffeinate"

write_plist() {
  mkdir -p "$LOGDIR" "$HOME/Library/LaunchAgents"
  chmod +x "$SERVE"
  # caffeinate -s <serve.sh>: -s asserts the system stays awake for the lifetime of the wrapped process.
  # KeepAlive restarts the API if it ever exits; RunAtLoad starts it at login. Live mode = no env overrides
  # (serve.sh default). PATH carries /opt/homebrew/bin so serve.sh can find `tailscale`.
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$CAFFEINATE</string>
    <string>-s</string>
    <string>$SERVE</string>
  </array>
  <key>WorkingDirectory</key><string>$CORE</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key><string>$HOME</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOGDIR/api.out.log</string>
  <key>StandardErrorPath</key><string>$LOGDIR/api.err.log</string>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST
}

case "${1:-status}" in
  install)
    write_plist
    launchctl bootout "$GUI/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$GUI" "$PLIST"
    launchctl enable "$GUI/$LABEL" 2>/dev/null || true
    launchctl kickstart -k "$GUI/$LABEL" 2>/dev/null || true
    echo "installed + started: $LABEL"
    echo "plist: $PLIST"
    echo "logs:  $LOGDIR/api.{out,err}.log"
    sleep 2
    exec "$0" status
    ;;
  restart)
    launchctl kickstart -k "$GUI/$LABEL"
    echo "restarted $LABEL"; sleep 2; exec "$0" status
    ;;
  uninstall)
    launchctl bootout "$GUI/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "uninstalled $LABEL (logs kept in $LOGDIR)"
    ;;
  logs)
    exec tail -n 40 -f "$LOGDIR/api.out.log" "$LOGDIR/api.err.log"
    ;;
  status)
    if launchctl print "$GUI/$LABEL" >/tmp/.ls_svc 2>/dev/null; then
      state=$(grep -m1 'state =' /tmp/.ls_svc | sed 's/.*= //')
      pid=$(grep -m1 'pid =' /tmp/.ls_svc | sed 's/.*= //' || true)
      echo "launchd: loaded  state=$state  pid=${pid:-none}"
    else
      echo "launchd: NOT loaded (run: lanesight_api/service.sh install)"
    fi
    IP="$(/opt/homebrew/bin/tailscale ip -4 2>/dev/null | head -1 || true)"
    DNS="$(/opt/homebrew/bin/tailscale status --json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)"
    for host in "${IP:-}" 127.0.0.1; do
      [ -z "$host" ] && continue
      if curl -s --max-time 4 "http://$host:8787/health" >/tmp/.ls_health 2>/dev/null; then
        python3 -c 'import sys,json;d=json.load(open("/tmp/.ls_health"));print(f"health:  {d[\"status\"]}  supabase_reachable={d[\"supabase_reachable\"]}  mode={d[\"config\"][\"mode\"]}")' 2>/dev/null \
          && { [ -n "$DNS" ] && echo "app URL: http://$DNS:8787"; rm -f /tmp/.ls_svc /tmp/.ls_health; exit 0; }
      fi
    done
    echo "health:  UNREACHABLE (check $LOGDIR/api.err.log)"
    rm -f /tmp/.ls_svc /tmp/.ls_health 2>/dev/null || true
    ;;
  *) echo "usage: $0 {install|status|restart|logs|uninstall}"; exit 2;;
esac
