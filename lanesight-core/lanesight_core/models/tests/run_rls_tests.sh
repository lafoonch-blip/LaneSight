#!/bin/sh
# Permanent RLS / migration test for Dev Build v0 (migrations 006-010).
# Spins an ephemeral Postgres 16 cluster, applies the Supabase shim + schema.sql + migrations 002-010
# from scratch, re-runs 006-010 once to prove idempotency, then runs rls_dev_build_v0.sql.
# Exits non-zero on any failure. No network, no cloud, no credentials.
#
# Usage:  PG16_BIN=/opt/homebrew/opt/postgresql@16/bin ./run_rls_tests.sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
MOD=$(cd "$HERE/.." && pwd)                 # .../models
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

echo "Applying shim + schema + migrations 002-010..."
PSQL -f "$HERE/_shim.sql" >/dev/null
PSQL -f "$MOD/schema.sql" >/dev/null
for n in 002_ball_catalog 003_ball_configuration_surface 004_rls_hardening 005_ball_catalog_refresh \
         006_rules_benchmarks 007_score_achievements 008_dev_build_fields 009_oil_patterns \
         010_achievement_view_invoker; do
  PSQL -f "$MOD/migrations/$n.sql" >/dev/null
done

echo "Idempotency: re-running 006-010..."
for n in 006_rules_benchmarks 007_score_achievements 008_dev_build_fields 009_oil_patterns 010_achievement_view_invoker; do
  PSQL -f "$MOD/migrations/$n.sql" >/dev/null
done

echo "Running RLS tests..."
PSQL -f "$HERE/rls_dev_build_v0.sql" 2>&1 | grep -E 'PASS|FAIL|PASSED'
echo "OK"
