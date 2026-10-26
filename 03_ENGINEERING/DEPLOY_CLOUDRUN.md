# Deploy the LaneSight backend to Google Cloud Run (remove the Mac dependency)
Version: 1.0
Last Updated: 2026-10-26
Status: Runbook. Phase 1 = synchronous Cloud Run service (get it public + validate processing, fewest
changes). Phase 2 = Cloud Run Jobs (async, same OpenCV engine). Decision: Shayne, 2026-10-26.

Goal: the app works from anywhere (bowling center, friends) with no Mac tethered. Supabase stays as-is
(auth + DB + results). Artifacts: `lanesight-core/Dockerfile` (shared), this runbook.

## Architecture (Phase 1)
```
iOS app --upload--> Cloud Run service (FastAPI) --runs CV INLINE in the request (LANESIGHT_SYNC_JOBS=1)-->
         <--result/poll--                          --writes shot record + metrics--> Supabase (durable)
```
- **Synchronous execution** (`LANESIGHT_SYNC_JOBS=1`, jobs.py): the analysis runs inside the HTTP request so
  Cloud Run keeps CPU allocated (request-scoped CPU would throttle a background thread). The instance scales
  to **zero** when idle → ~$0.
- **One at a time:** `--concurrency 1 --max-instances 1` (matches DEC-043; keeps the in-memory job state on
  one instance). A 2nd simultaneous upload waits. Fine for a few testers; raise later.
- **Durable result:** the shot record + measurements are written to Supabase by the analysis, so a dropped
  connection can still recover the result (see "iOS contract" + the durable-jobs follow-up).
- **Free-tier fit:** ~2 min/analysis ≈ 120 vCPU-sec; the Cloud Run free tier (180k vCPU-sec, 360k GiB-sec,
  2M req/mo) covers ~1,000+ analyses/month — effectively $0 for this phase. (Benchmark real CPU/RAM to confirm.)

## One-time setup (Shayne — interactive)
1. Install the CLI: `brew install --cask google-cloud-sdk` (or https://cloud.google.com/sdk/docs/install).
2. Log in + pick/create a project + enable billing (billing is required even to use the free tier):
   ```
   ! gcloud auth login
   ! gcloud projects create lanesight-<something>   # or use an existing project
   gcloud config set project lanesight-<something>
   # link a billing account in the console, then:
   gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com
   ```
Then tell Claude Code to continue — the rest is scripted.

## Deploy (Claude Code runs these once you're logged in)
From `lanesight-core/`. Secrets go into Secret Manager (pulled from the Mac Keychain, never printed/committed):
```
for s in db_url service_role jwt_secret; do
  NAME=$(echo "LANESIGHT_${s}" | tr '[:lower:]' '[:upper:]')
  printf '%s' "$(security find-generic-password -s lanesight.supabase.${s} -w)" \
    | gcloud secrets create "$NAME" --data-file=- 2>/dev/null \
    || printf '%s' "$(security find-generic-password -s lanesight.supabase.${s} -w)" \
    | gcloud secrets versions add "$NAME" --data-file=-
done

gcloud run deploy lanesight-api \
  --source . \                              # Cloud Build builds the Dockerfile remotely (no local Docker)
  --region <near-supabase> \                # match the Supabase project region (many DB round-trips)
  --allow-unauthenticated \                 # app does its own Supabase JWT auth; Cloud Run IAM stays open
  --cpu 2 --memory 4Gi \                    # Shayne's initial spec; benchmark then trim
  --timeout 300 \                           # 5-min request cap (a 2-min analysis fits)
  --concurrency 1 --max-instances 1 \       # one analysis at a time; scales to zero (min-instances 0 default)
  --set-env-vars LANESIGHT_SYNC_JOBS=1,LANESIGHT_DATA=/tmp/lanesight,MPLBACKEND=Agg \
  --set-secrets LANESIGHT_DB_URL=LANESIGHT_DB_URL:latest,LANESIGHT_SERVICE_ROLE=LANESIGHT_SERVICE_ROLE:latest,LANESIGHT_JWT_SECRET=LANESIGHT_JWT_SECRET:latest
```
Output is the service URL, e.g. `https://lanesight-api-xxxxx-uc.a.run.app`.

## Verify
```
curl https://<service-url>/health          # status ok, mode live, supabase_reachable true
```
From the phone (OFF the tailnet): Settings → API URL → the Cloud Run URL → Check connection → upload a clip →
real Shot card. (First request after idle: ~15–30 s cold start, then ~1–2 min analysis.)

## Repoint the app (when the new designs land — iOS is on hold)
- `ios/LaneSight/Sources/AppModel.swift`: default API URL → the Cloud Run HTTPS URL.
- `ios/LaneSight/Info.plist`: drop the plain-HTTP ATS exception (HTTPS needs none).
- **iOS contract (keep from day one):** treat analysis as ASYNC — show a processing state, let the user leave,
  and recover the result by polling the durable record — even though Phase-1's backend blocks in one request.
  Set the upload request's client timeout ≥ 5 min so a synchronous analysis doesn't time out. This keeps the
  UX independent of Phase 1 vs Phase 2.

## Follow-ups (not needed to validate processing)
- **Avatars → Supabase Storage.** Cloud Run has no persistent disk (`/tmp` is ephemeral), so disk-based
  avatars (`DATA_ROOT/avatars`) are lost on scale-down. Move avatar read/write to a Supabase Storage bucket
  (migration 017 anticipates this). Shot analysis doesn't need disk. HEIC still needs `pillow-heif` (no `sips`).
- **Durable job status table.** For robust cross-instance polling + drop recovery, persist job state to a
  Supabase `analysis_jobs` table (keyed by a client idempotency key the app sends) and have `GET /jobs/{id}`
  fall back to it. Phase-1 synchronous returns the result inline, so this is an enhancement, not a blocker.
- **Phase 2 — Cloud Run Jobs.** Move execution to a Cloud Run **Job** (its own free compute pool), API stays
  light, app polls Supabase. The OpenCV engine is unchanged — only the execution wrapper. Lets a user record
  the next shot while the previous one analyzes.
- **Form analysis.** Add `.[api,form]` + the 29 MB pose model (on a bucket/baked in) when enabling form.

## Note
`fly.toml` is kept as an alternative host config, but Cloud Run is the chosen path (Shayne, 2026-10-26).
Secrets live only in Secret Manager + the Mac Keychain — never commit them.
