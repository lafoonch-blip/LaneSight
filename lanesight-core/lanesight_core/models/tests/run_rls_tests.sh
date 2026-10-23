#!/bin/sh
# Permanent RLS / migration test for Dev Build v0 (migrations 006-011).
# Spins an ephemeral Postgres 16 cluster, applies the Supabase shim + schema.sql + migrations 002-011
# from scratch, re-runs 006-011 once to prove idempotency, then runs rls_dev_build_v0.sql + the 011
# seed-presence check, and confirms the L-dev-0 formula reads the seeded power ranges end-to-end
# (DB -> lanesight_core.score). Exits non-zero on any failure. No network, no cloud, no credentials.
#
# Usage:  PG16_BIN=/opt/homebrew/opt/postgresql@16/bin ./run_rls_tests.sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
MOD=$(cd "$HERE/.." && pwd)                 # .../models
REPO=$(cd "$MOD/../.." && pwd)              # repo root (lanesight-core)
PGBIN=${PG16_BIN:-/opt/homebrew/opt/postgresql@16/bin}
PORT=${PGPORT:-5440}
WORK=$(mktemp -d)
PGDATA="$WORK/pgdata"
trap '"$PGBIN/pg_ctl" -D "$PGDATA" stop -m immediate >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

"$PGBIN/initdb" -D "$PGDATA" -U postgres --auth=trust >/dev/null
"$PGBIN/pg_ctl" -D "$PGDATA" -l "$WORK/pg.log" -o "-p $PORT -k /tmp -c listen_addresses=''" start >/dev/null
sleep 1
"$PGBIN/createdb" -h /tmp -p "$PORT" -U postgres rls_test
PSQL() { "$PGBIN/psql" -h /tmp -p "$PORT" -U postgres -d rls_test -v ON_ERROR_STOP=1 -q "$@"; }

echo "Applying shim + schema + migrations 002-011..."
PSQL -f "$HERE/_shim.sql" >/dev/null
PSQL -f "$MOD/schema.sql" >/dev/null
for n in 002_ball_catalog 003_ball_configuration_surface 004_rls_hardening 005_ball_catalog_refresh \
         006_rules_benchmarks 007_score_achievements 008_dev_build_fields 009_oil_patterns \
         010_achievement_view_invoker 011_seed_dev_build 012_arsenal_current_surface; do
  PSQL -f "$MOD/migrations/$n.sql" >/dev/null
done

echo "Idempotency: re-running 006-012..."
for n in 006_rules_benchmarks 007_score_achievements 008_dev_build_fields 009_oil_patterns \
         010_achievement_view_invoker 011_seed_dev_build 012_arsenal_current_surface; do
  PSQL -f "$MOD/migrations/$n.sql" >/dev/null
done

echo "Running RLS tests..."
PSQL -f "$HERE/rls_dev_build_v0.sql" 2>&1 | grep -E 'PASS|FAIL|PASSED'

echo "Running 011 seed-presence checks..."
PSQL -f "$HERE/seed_check_011.sql" 2>&1 | grep -E 'PASS|FAIL|PASSED'

echo "Confirming the L-dev-0 formula reads the seeded power ranges (DB -> score engine)..."
RANGES=$("$PGBIN/psql" -h /tmp -p "$PORT" -U postgres -d rls_test -t -A \
  -c "select params->'power_ref_ranges' from score_formula_version where id='L-dev-0';")
PYBIN=${PYBIN:-python3}
RANGES="$RANGES" "$PYBIN" - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ.get('LANESIGHT_REPO', '.'))
from lanesight_core.score import DEFAULT_LDEV0_PARAMS, power_component
ranges = json.loads(os.environ['RANGES'])
params = dict(DEFAULT_LDEV0_PARAMS, power_ref_ranges=ranges)
# a measured shot at Shayne's validation values; weight = 15 lb -> normalizes mid-scale.
shot = {'metrics': {'speed_late': {'value': 16.5, 'status': 'ok'},
                    'rev_rate': {'value': 410, 'status': 'ok'},
                    'entry_angle': {'value': 4.5, 'status': 'ok'}}}
p = power_component([shot], params, weight_lb=15.0)
assert p['status'] == 'ok' and p['value'] is not None, p
assert abs(p['components']['weight'] - 0.5) < 1e-9, p   # 15 lb in [14,16] -> 0.5
print(f"PASS: L-dev-0 P' from DB ranges = {p['value']} (components {p['components']})")
PY
echo "OK"
