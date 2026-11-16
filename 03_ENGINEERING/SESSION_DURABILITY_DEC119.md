---
title: Session durability + upload reliability (DEC-119 build)
status: BUILT + ON-DEVICE VALIDATED (iPhone 17 Pro Max) — 3 bugs found & fixed during device testing
date: 2026-11-01
decision: DEC-119 (amends DEC-096, DEC-099)
---

## ON-DEVICE VALIDATION — 2026-11-01 (iPhone 17 Pro Max, via devicectl + console telemetry)
Driven on the connected device with `LS119` console telemetry at each state transition (DEBUG-gated). Confirmed:
- **Persist-before-upload** → clip written to `Application Support/LaneSightUploads/clips/` (NOT tmp/) before upload.
- **Background `URLSession` PUT** to Supabase Storage (`status=200`) → `upload finished` → `analyze start`.
- **Tab bar visible on the Active Session**; tab switching works mid-session; banner on Home + Lab.
- **Cold-launch resume prompt** fires on every launch with an active session; Continue → Active Session.
- **Active-session mirror** reconciled from the server (`ended_at` null).
- **Offline:** record stays `pending` with capped backoff, shows "Saved — we'll finish when you're online" (never a
  data-loss failure); **reconnect → auto-resume** upload → analyze.
- **Process death mid-analyze:** `.analyzing` record persists; on relaunch `recoverAnalyzing` does a shot-existence
  check (deliver if the server has it, re-run if not) — no duplicate shot.

### Bugs found on-device and fixed (this is why on-device testing was required)
1. **Offline uploads terminally failed** after ~34 s of retries and a `.failed` record won't auto-resume → the shot
   would be lost. Fix: transport/offline errors keep the record `.pending` (never `.failed`); added the
   `.offlineQueued` UI state + auto-resume on reconnect (`Connectivity.onChange`).
2. **Concurrent double-start:** the several resume triggers (scenePhase, RootTabs task, Connectivity) each
   (re)started the same record → the clip was PUT 3× and analyzed 3× (→ duplicate shots). Fix: in-flight guards
   (`inFlightUploads` / `inFlightAnalyze`) — exactly one upload + one analyze per record.
3. **Sticky Active-Session nav:** opening the Active Session from Home's stack left it pushed after switching tabs
   (Home showed the session instead of Home). Fix: the push is transient — RootTabs pops it when you leave its tab.

### Environment caveats (not app bugs)
- **Signing — must use Shayne's PAID Apple Developer team.** The build was tested on a free/personal signing cert,
  which iOS can only verify **online**: the OS refuses to *launch* the app while offline (airplane mode), so the
  **offline force-quit → relaunch → resume** test is still PENDING. It can only be run once the app is signed with
  the paid Apple Developer team (paid certs launch offline). The in-session "lose connection → reconnect → resume"
  path WAS validated (app already running when connectivity dropped); the untested gap is specifically relaunching
  the app from cold while still offline. Re-sign with the paid team and run: airplane on → record → force-quit →
  relaunch (should launch and show the resume prompt) → the pending clip uploads when back online.
- **≥30 min warm-background prompt**: the threshold logic is unit-tested (`shouldPromptResume`) and the prompt UI is
  validated via cold launch; the real-time warm 30-min trigger is a manual step (background 30 min, foreground).

## BUILT — 2026-11-01 (branch `feat/session-durability`)
All five items are implemented in `ios/LaneSight`. Builds clean for the connected device (signed) and the
simulator; 16 iOS unit tests pass (incl. 11 new DEC-119 tests). On-device lifecycle correctness (kill / crash /
airplane / ≥30 min background) is verified by the manual matrix below — it can't be driven headlessly.

- **New:** `Sources/Session/SessionDurability.swift` — `PersistedSession` (active-session mirror),
  `ShotUpload` + `ShotUploadStore` (durable per-shot record + clip in Application Support, NOT tmp/),
  `BackgroundUploadManager` (a background `URLSession`, `isDiscretionary=false`, request 90 s / resource 600 s,
  `sessionSendsLaunchEvents`), `UploadOutcome`/`UploadBackoff`. `Sources/Session/ActiveSessionBanner.swift` —
  the "Session in progress · Return" banner + the Active Session screen router.
- **`AppModel`**: persist-before-upload (`enqueueAndStart` writes the record + durable clip, then trims, then
  uploads), background PUT via the manager (progress → Analyzing screen), retry with backoff, terminal-failure
  `POST /analysis/client-failure` (`stage=upload`), analyze-on-upload-complete, `resumePendingUploads()` on
  relaunch/foreground, the active-session mirror (`activeSession`, server-reconciled), the ≥30 min / cold-launch
  resume decision (`shouldPromptResume`), and End clears the mirror.
- **`LaneSightApp`**: `AppDelegate` for `handleEventsForBackgroundURLSession`; scenePhase stamps background time,
  resumes uploads + reconciles the session on foreground; the Continue/End resume alert; routes Continue/banner
  to the Active Session (tab bar visible).
- **`SessionView`**: tab bar no longer hidden (amends DEC-099). **`HomeView`/`LabView`**: the active-session banner.

### Known limits (noted, not blockers)
- The analyze request is still a single long synchronous call; if it drops after the PUT, recovery relies on the
  existing `pendingAnalysis` + reconcile mechanism (shot is durable server-side, DEC-110). A kill *during* the
  analyze request can, in the worst case, re-POST analyze on resume (same duplicate window the pre-existing
  Retry already had). Not worse than before.
- Legacy `APIClient.putClipToStorage` (foreground PUT) is now unused but left in place (other branches may use it).

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
