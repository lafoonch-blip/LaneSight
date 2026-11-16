# Deploy the LaneSight backend to Google Cloud Run (remove the Mac dependency)
Version: 1.2
Last Updated: 2026-10-27
Status: DEPLOYED. Phase 1 synchronous service LIVE at `https://lanesight-api-665597641318.us-east1.run.app`
(rev 00003, `--cpu 4 --memory 4Gi --timeout 600 --concurrency 1 --max-instances 1`, scale-to-zero). Storage
upload path + iOS repoint done 2026-10-26. Phase 2 = Cloud Run Jobs (async, same OpenCV engine), later.

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
- **Free-tier fit (MEASURED 2026-10-26, full pipeline on IMG_8902):** peak RAM **~1.8 GB** (→ use **4 GiB**;
  2 GiB is too tight), total CPU work **~191 vCPU-sec/analysis** (26 s wall on an 8-core Mac; ≈ **90 s wall on
  `--cpu 2`**). Cloud Run free tier (180k vCPU-sec, 360k GiB-sec, 2M req/mo) → **~900 analyses/month free** →
  effectively **$0** for a few testers.

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
  --cpu 4 --memory 4Gi \                    # deployed config: 4 vCPU (a full 26 s clip is ~328 s wall)
  --timeout 600 \                           # 10-min request cap (full synchronous analysis fits w/ margin)
  --concurrency 1 --max-instances 1 \       # one analysis at a time; scales to zero (min-instances 0 default)
  --set-env-vars LANESIGHT_SYNC_JOBS=1,LANESIGHT_DATA=/tmp/lanesight,MPLBACKEND=Agg \
  --set-secrets LANESIGHT_DB_URL=LANESIGHT_DB_URL:latest,LANESIGHT_SERVICE_ROLE=LANESIGHT_SERVICE_ROLE:latest,LANESIGHT_JWT_SECRET=LANESIGHT_JWT_SECRET:latest
```
Output is the service URL, e.g. `https://lanesight-api-xxxxx-uc.a.run.app`.

### Env flags
- `LANESIGHT_SYNC_JOBS=1` — run the CV inline in the request (required on Cloud Run; see Architecture).
- `LANESIGHT_UPLOAD_DEDUPE` — **leave UNSET (default off, DEC-086).** When off, re-uploading the same clip
  makes a **new** shot so a bowler can re-analyze while the engine is changing. Set to `1` only to restore
  the old DEC-055 "same clip → same shot" short-circuit. Live-capture content-hash de-dup is independent and
  always on. `GET /health` echoes the current value as `config.upload_dedupe`.

## Verify
```
curl https://<service-url>/health          # status ok, mode live, supabase_reachable true
```
From the phone (OFF the tailnet): Settings → API URL → the Cloud Run URL → Check connection → upload a clip →
real Shot card. (First request after idle: ~15–30 s cold start, then ~1–2 min analysis.)

## Storage upload path (DONE 2026-10-26 — bypasses Cloud Run's ~32 MiB request cap)
A raw multipart upload of a full clip 413'd at Cloud Run's request-size limit. Clips now go through Supabase
Storage instead (bucket `shot-clips`, private, 512 MB limit):
```
app --POST /uploads/signed-url--> API (returns {path, upload_url})
app --PUT clip bytes--> Supabase Storage (direct; no API size cap)
app --POST /shots/analyze {storage_path, session_id?, metadata}--> API
      API downloads the clip, runs the SAME serial/sync analyze path, writes the shot, DELETES the clip.
```
- `session_id` present → a shot in that live session; absent → standalone upload. The upload content-hash
  dedupe is now behind `LANESIGHT_UPLOAD_DEDUPE` (**default off, DEC-086**): off → a re-sent clip makes a new
  shot; on → it returns the existing shot and deletes the Storage object (old DEC-055 behavior).
- The clip is never retained server-side (download → analyze → delete, and deleted on dedupe hit).
- **Verified end-to-end on Cloud Run (rev 00003):** full 43 MB IMG_8902 → signed URL → PUT (HTTP 200) →
  `/shots/analyze` (HTTP 200, 328 s synchronous) → 19 real metrics. The 32 MiB cap no longer applies.
- Backend: `store.storage_signed_upload_url / storage_download / storage_delete` (PgStore → real Supabase
  Storage via service role; MemoryStore → local-dir sim), endpoints in `app.py`. Commit `0d5e6ed`.

## Repoint the app (DONE 2026-10-26 — iOS code written; Shayne builds in Xcode)
- `ios/LaneSight/Sources/AppModel.swift`: default API URL → the Cloud Run HTTPS URL **+ auto-migrates** an
  existing install still pinned to the old tailnet / `:8787` / plain-HTTP dev URL (ATS now blocks HTTP).
- `ios/LaneSight/Info.plist`: plain-HTTP ATS exception removed (HTTPS needs none).
- `APIClient`: `signedUploadURL()`, `putClipToStorage()`, `analyzeFromStorage()` + `UploadTarget` model;
  `AppModel.runPipeline` now uses the Storage flow with a 600 s client timeout on the PUT + analyze calls.
- **iOS contract (kept):** analysis is treated as ASYNC in the UI (processing state) even though Phase-1's
  backend blocks in one request; the 600 s client timeout covers a full synchronous analysis. Full async
  recovery of a dropped connection is the durable-jobs follow-up below.
- **Needs Shayne:** build/install from Xcode. An already-installed app auto-migrates its saved URL on next
  launch; no manual Dev-Panel change needed.

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
