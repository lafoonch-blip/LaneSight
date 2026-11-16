#!/bin/bash
# DEC-098 §2 (M5): one storage/DB metering run. Activates the core venv and runs the snapshot module in
# LIVE mode (reads creds from the Keychain, same as the API). Best-effort — a signal it can't measure is
# left NULL, never invented. Called by the com.lanesight.ops-snapshot LaunchAgent (see ops_snapshot_service.sh),
# or directly: lanesight_api/ops_snapshot.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="$(cd "$HERE/.." && pwd)"
cd "$CORE"
# shellcheck disable=SC1091
source .venv/bin/activate
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ops storage snapshot: start"
python -m lanesight_api.ops_storage_snapshot
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ops storage snapshot: done"
