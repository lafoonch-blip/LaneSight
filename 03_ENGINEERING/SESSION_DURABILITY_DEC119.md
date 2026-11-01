---
title: Session durability + upload reliability (DEC-119 build)
status: scoped — backend ready, iOS app work pending
date: 2026-11-01
decision: DEC-119 (amends DEC-096, DEC-099)
---

# DEC-119 build — session lasts until the user ends it; uploads never hang silently

## Recovered: today's 13:56 shot
The 13:56 clip (signed URL issued, no upload, no analyze, no error) was **recovered intact** from the device app
container: `tmp/lanesight-shot-BF834572-57CB-4E97-9BD5-6955F30FB989.mov` (29 MB, HEVC 1440×1080 ~60 fps), saved to
`~/LaneSightData/recovered/shot_1356_BF834572.mov`. It can be re-uploaded/analyzed. Root symptom: the clip was
written to `tmp/` but the upload never started and nothing was persisted/retried — exactly what DEC-119 fixes.

## Backend status — ALREADY IN PLACE (no server change needed for the failure/durability path)
- `POST /analysis/client-failure` accepts `stage` (incl. `upload`) → logs `analysis_attempt` `CLIENT_UPLOAD`
  (`app.py:1507`). The app must CALL it on final upload failure.
- Durable jobs (DEC-110): `analysis_job` persists queued→running→done/failed; `GET /jobs/:id` resolves
  cross-instance. Server is the source of truth for job state.
- Sessions: `sessions.ended_at null` = active (server source of truth per DEC-119); mirror locally for offline.

## iOS app work remaining (the build)
1. **Session lifecycle (item 1).** AppModel: a single `activeSession` mirrored from the server
   (`ended_at null`), persisted locally (UserDefaults/file) so it survives relaunch/offline. Home + Lab show a
   "Session in progress · Return" banner → opens Active Session (all shots: analyzed/analyzing/failed+Retry).
   **Show the tab bar on the Active Session** (amends DEC-099 — remove the hide). Sessions never auto-end; only
   **End session** closes one (→ history; summary/feedback per DEC-072/053 skippable).
2. **Cold-launch / long-background resume (item 1).** On launch (post force-quit/crash) or foreground after
   **≥30 min** background with an active session → prompt "session in progress (started <time>, N shots):
   Continue / End". <30 min → straight back, no prompt. Track background enter-time; compare on foreground.
3. **Background upload (item 2).** Replace the foreground upload with a **background `URLSession`**
   (`URLSessionConfiguration.background`, `isDiscretionary=false`), resource/request timeouts, progress on the
   Analyzing screen, **retry with backoff**, and on final failure a friendly error + **Retry** + call
   `POST /analysis/client-failure` (`stage=upload`). The signed-URL PUT must be a background upload task so it
   survives app suspension.
4. **Persist-before-upload + resume (item 3).** Write a per-shot record (session id, local clip path, capture
   settings, state) to disk the moment recording finishes, BEFORE upload. On relaunch, enumerate pending shots in
   the active session and resume upload/analysis. Keep the clip in a durable dir (not `tmp/`, which the OS can
   purge) until the shot reaches a terminal state.
5. **Tests (item 4).** Airplane mode mid-upload; kill app mid-upload and mid-analysis; crash; 30+ min background;
   switch tabs mid-session. Each must end in the Active Session with the result OR a visible failure + Retry; the
   resume prompt must appear exactly per item 2. These need device/sim interaction (background transitions,
   process kill) — can't be fully headless; drive via a dev harness + manual on-device steps.

## Why this wasn't shipped in one pass
Background `URLSession` + process-death resume + the crash/airplane/kill test matrix is a multi-day iOS feature
whose correctness is only provable with on-device lifecycle testing. Shipping it unverified would risk the build
and the exact silent-failure class it's meant to remove. The backend it depends on is ready; this note is the
actionable spec.
