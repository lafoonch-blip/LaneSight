#!/usr/bin/env bash
# Deploy the LaneSight API to Cloud Run WITH a mandatory post-deploy smoke test + auto-rollback (P0 2026-10-29).
#
# Why the config: --concurrency 8 lets the light API (home/score/sessions) be served ALONGSIDE a running
# analysis instead of queued behind it; --max-instances 3 means a deploy's new revision can start next to a
# busy old one (no more rollover 5xx) and a burst of users gets its own instance. Scale-to-zero stays
# (min-instances unset) for the cost cap. A per-INSTANCE guard in jobs.py caps one analysis per instance, so
# concurrency 8 can't put two multi-GB analyses on one 4 GiB instance (DEC-043 one-at-a-time is per session).
#
# If the smoke test fails, traffic is rolled back to the previous revision and the script exits nonzero.
set -euo pipefail
REGION=us-east1
SERVICE=lanesight-api
cd "$(dirname "$0")/.."     # -> lanesight-core (has the Dockerfile)

# --- Single-deployer lock (2026-10-29): only this session deploys to prod. Guards against a concurrent deploy
# (e.g. another agent/session) racing us or moving traffic out from under us (the 00050/00051/00052 mess).
LOCK="ops/.deploy_lock"; EXPECTED="ops/.expected_rev"
if [ -f "$LOCK" ]; then echo "ABORT: a deploy is already in progress ($(cat "$LOCK")). Remove $LOCK if stale."; exit 1; fi
echo "pid=$$ started=$(date -u +%FT%TZ)" > "$LOCK"; trap 'rm -f "$LOCK"' EXIT

SERVING=$(gcloud run services describe "$SERVICE" --region "$REGION" --format="value(status.traffic[0].revisionName)")
if [ -f "$EXPECTED" ] && [ "$(cat "$EXPECTED")" != "$SERVING" ]; then
  echo "ABORT: traffic is on '$SERVING' but this session last deployed '$(cat "$EXPECTED")' — another session deployed."
  echo "       Reconcile first (verify which revision is correct, update $EXPECTED), then re-run."
  exit 1
fi
PREV="$SERVING"
echo "== current (serving) revision: $PREV =="

# Build EXPLICITLY, tagged by the git commit (2026-10-29): `gcloud run deploy --source` reused stale cached
# images more than once (the 00050 reuse; a dep pin that resolved to the wrong opencv). The default Cloud Build
# docker builder (Kaniko off) builds FRESH from the source tar every time — no layer cache — so a per-commit
# tag + the digest verify below provably tie the deployed artifact to this commit. (--no-cache is a Kaniko-only
# flag and is unnecessary here.)
REPO="us-east1-docker.pkg.dev/project-fd28bc3f-a844-43c2-a1c/cloud-run-source-deploy/$SERVICE"
SHA=$(git rev-parse --short HEAD)
echo "== building $REPO:$SHA (fresh, non-kaniko) =="
gcloud builds submit --tag "$REPO:$SHA" --quiet .
DIGEST=$(gcloud artifacts docker images describe "$REPO:$SHA" --format="value(image_summary.digest)" 2>/dev/null)
echo "== built digest: $DIGEST =="

gcloud run deploy "$SERVICE" \
  --image "$REPO:$SHA" --region "$REGION" --allow-unauthenticated \
  --cpu 4 --memory 4Gi --timeout 600 --concurrency 8 --max-instances 3 \
  --set-env-vars LANESIGHT_SYNC_JOBS=1,LANESIGHT_DATA=/tmp/lanesight,MPLBACKEND=Agg,LANESIGHT_PRECHECK_ENFORCE=1 \
  --set-secrets LANESIGHT_DB_URL=LANESIGHT_DB_URL:latest,LANESIGHT_SERVICE_ROLE=LANESIGHT_SERVICE_ROLE:latest,LANESIGHT_JWT_SECRET=LANESIGHT_JWT_SECRET:latest \
  --quiet

# The revision now SERVING traffic (not latestReadyRevisionName — a concurrent build can advance that without
# routing). If it's unchanged, another deploy intervened: fail loudly.
NEW=$(gcloud run services describe "$SERVICE" --region "$REGION" --format="value(status.traffic[0].revisionName)")
URL=$(gcloud run services describe "$SERVICE" --region "$REGION" --format="value(status.url)")
if [ "$NEW" = "$PREV" ]; then
  echo "ABORT: traffic is still on $PREV — deploy did not route a new revision (concurrent deploy)."
  exit 1
fi
# Verify the deployed image digest matches the digest we just built from this commit (item 3).
SERVED_IMG=$(gcloud run revisions describe "$NEW" --region "$REGION" --format="value(spec.containers[0].image)" 2>/dev/null)
if [ -n "$DIGEST" ] && ! printf '%s' "$SERVED_IMG" | grep -q "$DIGEST"; then
  echo "ABORT: serving image ($SERVED_IMG) != built digest ($DIGEST) — stale/cached image. Rolling back."
  gcloud run services update-traffic "$SERVICE" --region "$REGION" --to-revisions "$PREV=100" --quiet
  exit 1
fi
echo "== deployed: $NEW — running mandatory smoke test against $URL =="

if python3 ops/smoke_deploy.py --api "$URL"; then
  echo "== SMOKE PASS — $NEW is live =="
  echo "$NEW" > "$EXPECTED"
else
  echo "== SMOKE FAIL — rolling traffic back to $PREV =="
  gcloud run services update-traffic "$SERVICE" --region "$REGION" --to-revisions "$PREV=100" --quiet
  echo "$PREV" > "$EXPECTED"
  echo "== rolled back to $PREV =="
  exit 1
fi
