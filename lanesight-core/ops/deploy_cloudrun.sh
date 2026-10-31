#!/usr/bin/env bash
# Deploy the LaneSight API to Cloud Run WITH a mandatory post-deploy smoke test + auto-rollback (P0 2026-10-29).
#
# Why the config: --concurrency 8 lets the light API (home/score/sessions) be served ALONGSIDE a running
# analysis instead of queued behind it; --max-instances 3 means a deploy's new revision can start next to a
# busy old one (no more rollover 5xx) and a burst of users gets its own instance. Scale-to-zero stays
# (min-instances unset) for the cost cap. A per-INSTANCE guard in jobs.py caps one analysis per instance, so
# concurrency 8 can't put two multi-GB analyses on one instance (DEC-043 one-at-a-time is per session).
# --memory 8Gi (was 4Gi): DEC-113 canonical SDR decode is ~11 s/pass in pure numpy, so it is run ONCE per clip
# and the decoded frames are cached (LANESIGHT_FRAME_CACHE_MB=5500); the remaining ~8 passes serve from RAM
# (decode-once). A full untrimmed 14.75 s 1080p clip caches ~5.25 GB, which needs the larger instance; working
# set + cache stays ~7.3 GB < 8 GiB. Clips longer than ~5.5 GB fall back to per-pass decode (slower, still right).
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

# --- DEC-113 tiered benchmark (pick by diff path; log the tier). Quick = the post-deploy smoke below (always).
# Standard = CV/decode/metric/score code changed vs the serving revision's commit -> run the IMG_8751-54
# regression as a HARD pre-build gate. A breach auto-escalates to Full (regression_tier.py prints the ESCALATE
# line); Full itself is nightly / pre-prod-promote and is never auto-run from a deploy.
SERVING_IMG=$(gcloud run revisions describe "$PREV" --region "$REGION" --format="value(spec.containers[0].image)" 2>/dev/null || true)
SERVING_SHA="${SERVING_IMG##*:}"
if git rev-parse --verify -q "$SERVING_SHA" >/dev/null 2>&1; then
  TIER=$(ops/tier_for_diff.sh "$SERVING_SHA" HEAD 2>/dev/null || echo standard)
else
  echo "== serving commit '$SERVING_SHA' not resolvable locally — running Standard to be safe =="
  TIER=standard
fi
echo "== DEC-113 benchmark tier: $TIER (diff $SERVING_SHA..$(git rev-parse --short HEAD)) =="
if [ "$TIER" = "standard" ]; then
  echo "== Standard tier: IMG_8751-54 regression (hard gate, before build) =="
  if ! LANESIGHT_FFMPEG_DECODE=1 LANESIGHT_FRAME_CACHE_MB=5500 python3 ops/regression_tier.py; then
    echo "ABORT: Standard regression failed — not deploying (see the ESCALATE note; run the Full benchmark)."
    exit 1
  fi
fi

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
  --revision-suffix "${REV_SUFFIX:-$SHA}" \
  --cpu 8 --memory 8Gi --timeout 600 --concurrency 8 --max-instances 3 \
  --set-env-vars LANESIGHT_SYNC_JOBS=1,LANESIGHT_DATA=/tmp/lanesight,MPLBACKEND=Agg,LANESIGHT_PRECHECK_ENFORCE=1,LANESIGHT_FFMPEG_DECODE=1,LANESIGHT_FRAME_CACHE_MB=5500,LANESIGHT_VCPU=8,LANESIGHT_GIB=8 \
  --set-secrets LANESIGHT_DB_URL=LANESIGHT_DB_URL:latest,LANESIGHT_SERVICE_ROLE=LANESIGHT_SERVICE_ROLE:latest,LANESIGHT_JWT_SECRET=LANESIGHT_JWT_SECRET:latest \
  --quiet

# The NEW revision is latestReadyRevisionName (the one just built). Traffic may be PINNED to an older revision
# (a prior update-traffic), so `gcloud run deploy` does NOT auto-route — we route EXPLICITLY below. That pinning
# is exactly why earlier deploys "served 00052" while new revisions sat at 0%.
# When --revision-suffix is set the revision name is KNOWN ($SERVICE-$suffix); use it directly. Otherwise read
# latestReadyRevisionName, but POLL for it — `gcloud run deploy` can return before Cloud Run flips
# latestReadyRevisionName off the old one (the race that aborted the dec109 deploy at 0% traffic).
URL=$(gcloud run services describe "$SERVICE" --region "$REGION" --format="value(status.url)")
if [ -n "${REV_SUFFIX:-}" ]; then
  NEW="$SERVICE-$REV_SUFFIX"
else
  NEW="$PREV"
  for _ in $(seq 1 30); do
    NEW=$(gcloud run services describe "$SERVICE" --region "$REGION" --format="value(status.latestReadyRevisionName)")
    [ "$NEW" != "$PREV" ] && break
    sleep 2
  done
fi
if [ "$NEW" = "$PREV" ]; then
  echo "ABORT: no new revision was created (latest == serving $PREV) — build/deploy did not take."
  exit 1
fi
# Wait for the new revision to be Ready before routing/smoking it.
for _ in $(seq 1 30); do
  R=$(gcloud run revisions describe "$NEW" --region "$REGION" --format="value(status.conditions[0].status)" 2>/dev/null || true)
  [ "$R" = "True" ] && break
  sleep 2
done
# Verify the new revision's image digest matches the digest we just built from this commit (item 3).
SERVED_IMG=$(gcloud run revisions describe "$NEW" --region "$REGION" --format="value(spec.containers[0].image)" 2>/dev/null)
if [ -n "$DIGEST" ] && ! printf '%s' "$SERVED_IMG" | grep -q "$DIGEST"; then
  echo "ABORT: new revision image ($SERVED_IMG) != built digest ($DIGEST) — stale/cached image."
  exit 1
fi
# Route 100% traffic to the new revision (handles pinned traffic).
gcloud run services update-traffic "$SERVICE" --region "$REGION" --to-revisions "$NEW=100" --quiet
echo "== deployed + routed: $NEW — running mandatory smoke test against $URL =="

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
