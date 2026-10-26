# Deploy the LaneSight backend to Fly.io (remove the Mac dependency)
Version: 1.0
Last Updated: 2026-10-26
Status: Runbook. Goal: the app works from anywhere (bowling center, friends' phones) with no Mac tethered.

Moves the FastAPI + CV pipeline off the Mac to a cloud container with public HTTPS. Supabase (DB + auth)
is unchanged. Artifacts: `lanesight-core/Dockerfile`, `.dockerignore`, `fly.toml`. Ball (shot) analysis
first; Form is a follow-up (see the Dockerfile note).

## What's where after this
- **Supabase** — DB + auth (already cloud; unchanged).
- **Fly.io machine** — runs `uvicorn lanesight_api.app:app`; processes CV jobs in-process (one at a time,
  DEC-043); serves `https://<app>.fly.dev`. One always-on machine (the job queue is in-memory).
- **Fly volume `/data`** — persistent `DATA_ROOT`: profile avatars + any retained output survive redeploys.
  CV temp clips are ephemeral (fine).
- **The Mac** — no longer in the path. (Keep the launchd service if you still want a local dev backend.)

## One-time setup (Shayne — interactive)
1. Install the CLI: `brew install flyctl` (or `curl -L https://fly.io/install.sh | sh`).
2. Create an account + log in (opens a browser):  type in this session:  `! fly auth login`
3. (Billing) add a card — a shared-cpu-2x/4 GB always-on machine is ~\$10–20/mo.

Then tell Claude Code to continue — the rest is scripted below.

## Deploy (Claude Code runs these once you're logged in)
From `lanesight-core/`:
```
fly launch --no-deploy --copy-config --name lanesight-api --region <near-supabase>   # reuses fly.toml
fly volumes create lanesight_data --size 3 --region <same>                            # 3 GB persistent disk
# secrets (pulled from the Mac Keychain — same values the live service uses):
fly secrets set \
  LANESIGHT_DB_URL="$(security find-generic-password -s lanesight.supabase.db_url -w)" \
  LANESIGHT_SERVICE_ROLE="$(security find-generic-password -s lanesight.supabase.service_role -w)" \
  LANESIGHT_JWT_SECRET="$(security find-generic-password -s lanesight.supabase.jwt_secret -w)"
fly deploy                           # remote build (no local Docker needed) -> HTTPS URL
fly logs                             # watch startup; expect "Application startup complete", /health ok, mode=live
```
Pick `<near-supabase>` as the Fly region closest to the Supabase project (minimizes DB round-trip latency —
the analyze path makes many PostgREST calls). Confirm the Supabase project region in the dashboard.

## Verify
```
curl https://lanesight-api.fly.dev/health        # status ok, mode live, supabase_reachable true
```
Then from the phone (OFF the tailnet, e.g. on cellular): Settings → API URL → `https://lanesight-api.fly.dev`
→ Check connection → record/upload a shot → Shot card with real metrics.

## Repoint the app
- Change the default API URL in `ios/LaneSight/Sources/AppModel.swift` (currently the tailnet URL) to the Fly
  HTTPS URL, and remove the now-unneeded HTTP ATS exception in `ios/LaneSight/Info.plist` (HTTPS needs none).
- Rebuild/install (or ship via TestFlight — see below).

## Share with friends (TestFlight — Apple side, Shayne)
Separate from the backend; works once the Fly URL is live.
1. Xcode → Product → Archive → Distribute App → App Store Connect (uses team GK3N928748).
2. App Store Connect → TestFlight → add the build → invite friends by email (external testing needs a short
   Beta App Review; internal testers are instant).
3. Friends install **TestFlight** + the invite → the app talks to the Fly backend → they sign up
   (email/password, real Supabase auth). Consider a beta-invite gate later if you want to limit signups.

## Known limits / follow-ups
- **One machine, in-memory job queue:** a restart mid-analysis loses that job (the app re-uploads). Fine for
  a few testers; a durable queue is a later step if load grows.
- **Form analysis** is off in v1 (ball only). To enable: `.[api,form]` in the Dockerfile + put
  `pose_landmarker_heavy.task` on the volume at `/data/models/`.
- **Avatars** persist on the volume. If you later want multi-machine, move them to a Supabase Storage bucket
  (migration 017 already anticipates this).
- **HEIC profile photos** won't convert in the container: `app.py` falls back to macOS `sips` for HEIC/HEIF,
  which isn't on Linux (JPEG/PNG avatars work fine via Pillow). Fix when wanted: add `pillow-heif` to the
  image + register its opener, or convert client-side. Not on the shot-analysis path — safe to defer.
- Shot analysis itself has **no macOS dependency** (OpenCV/numpy; config reads env secrets, so the Keychain
  `security` call is never hit in the container).
- **Secrets** are only in Fly + the Mac Keychain — never commit them.
