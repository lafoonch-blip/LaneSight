#!/bin/bash
# DEC-098 §2 (M5): manage the storage-metering job as a per-user launchd agent that runs ONCE DAILY (03:30
# local) so ops.storage_latest stays current. Mirrors lanesight_api/service.sh (the API service), but this
# is a periodic job (StartCalendarInterval), not a long-running daemon — no caffeinate, no KeepAlive.
# Runs as the logged-in user so `security` can read the Supabase creds from the Keychain.
#
#   lanesight_api/ops_snapshot_service.sh install     # generate + load the LaunchAgent, run once now, status
#   lanesight_api/ops_snapshot_service.sh status      # loaded? last run exit? + last log lines
#   lanesight_api/ops_snapshot_service.sh run         # run once now (kickstart)
#   lanesight_api/ops_snapshot_service.sh logs        # tail the out/err logs
#   lanesight_api/ops_snapshot_service.sh uninstall   # stop + remove the LaunchAgent
set -euo pipefail

LABEL="com.lanesight.ops-snapshot"
HERE="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$HERE/ops_snapshot.sh"
CORE="$(cd "$HERE/.." && pwd)"
LOGDIR="$HOME/LaneSightData/logs"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI="gui/$(id -u)"

write_plist() {
  mkdir -p "$LOGDIR" "$HOME/Library/LaunchAgents"
  chmod +x "$RUNNER"
  # StartCalendarInterval = daily at 03:30. launchd runs a missed daily job at next wake if the Mac was
  # asleep. No RunAtLoad (install runs it once explicitly). PATH carries /opt/homebrew/bin for python/tooling.
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$RUNNER</string>
  </array>
  <key>WorkingDirectory</key><string>$CORE</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key><string>$HOME</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>3</integer>
    <key>Minute</key><integer>30</integer>
  </dict>
  <key>StandardOutPath</key><string>$LOGDIR/ops-snapshot.out.log</string>
  <key>StandardErrorPath</key><string>$LOGDIR/ops-snapshot.err.log</string>
  <key>ProcessType</key><string>Background</string>
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
    launchctl kickstart "$GUI/$LABEL" 2>/dev/null || true   # run once now
    echo "installed + ran once: $LABEL (daily 03:30)"
    echo "plist: $PLIST"
    echo "logs:  $LOGDIR/ops-snapshot.{out,err}.log"
    ;;
  run)
    launchctl kickstart "$GUI/$LABEL"
    echo "kickstarted $LABEL"
    ;;
  uninstall)
    launchctl bootout "$GUI/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "uninstalled $LABEL (logs kept in $LOGDIR)"
    ;;
  logs)
    exec tail -n 40 -f "$LOGDIR/ops-snapshot.out.log" "$LOGDIR/ops-snapshot.err.log"
    ;;
  status)
    if launchctl print "$GUI/$LABEL" >/tmp/.ls_snap 2>/dev/null; then
      state=$(grep -m1 'state =' /tmp/.ls_snap | sed 's/.*= //')
      last=$(grep -m1 'last exit code =' /tmp/.ls_snap | sed 's/.*= //' || true)
      echo "launchd: loaded  state=$state  last_exit=${last:-n/a}  (daily 03:30)"
    else
      echo "launchd: NOT loaded (run: lanesight_api/ops_snapshot_service.sh install)"
    fi
    rm -f /tmp/.ls_snap 2>/dev/null || true
    [ -f "$LOGDIR/ops-snapshot.out.log" ] && { echo "--- last out ---"; tail -n 4 "$LOGDIR/ops-snapshot.out.log"; }
    ;;
  *) echo "usage: $0 {install|status|run|logs|uninstall}"; exit 2;;
esac
