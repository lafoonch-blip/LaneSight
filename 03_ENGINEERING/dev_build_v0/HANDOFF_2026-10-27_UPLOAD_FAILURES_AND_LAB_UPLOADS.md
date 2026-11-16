# Handoff — Upload failures, failure-reason tracking, Lab › Uploads, analyze-screen navigation
**Date:** 2026-10-27 · **Repo:** `~/Developer/LaneSight`, branch `dev-build-v0` · **Next DEC:** DEC-084 · **Next migration:** `019_…`

Run this end to end without stopping between steps. Make all code + test changes, verify locally, record decisions, then report once. The only things that need Shayne's explicit go-ahead are the irreversible ones — applying migration 019 to the **live** Supabase project, redeploying Cloud Run, and pushing to GitHub. Prepare all three fully and list them in the final report; don't hold up the rest of the work waiting for them.

Before relying on any spec, check the latest DEC in `00_CONTEXT/DECISIONS.md` and use the repo if it's newer than anything below.

---

## What happened (observed 2026-10-27, test account `vipergt777@gmail.com`, user `4806c8bc-78ae-49c7-8deb-cb8ce5a3522a`)

1. **Upload analysis failed** — shot `267020af-20d2-4083-90f7-348771057666` (upload, Shot mode, 17:23 UTC). The app showed: `Analysis failed: RuntimeError: ball not tracked enough to measure speed (the rolling track is too short or sparse)`. Raised at `lanesight_core/cv/metrics.py:80` — after lane detection and impact detection succeeded, no window between 2 and ~32 ft had ≥5 on-lane ball points spanning ≥0.08 s. The shot row was left with `record = {}`, no status, no reason. The reason existed only in the in-memory `jobs.py` job object on Cloud Run (lost on scale-to-zero).
2. **Lab › Uploads shows "Couldn't reach the analysis host"** with a raw JSON dump — it's a decode failure, not a network failure. Supabase `list_uploads` (`lanesight_api/store.py:~1250`) returns `created_at` as an ISO string; `UploadRow.created_at` (`ios/.../API/Models.swift:620`) is `Double?`. Every other Supabase read already converts with `_ts_epoch()` (store.py:15/29/756) — this one was missed. Breaks Uploads for **every account with ≥1 upload**.
3. **Left the analyze screen mid-analysis → result lost.** Shot `9f7c2415-bb72-4a95-a404-2887f89cd669` (17:36 UTC) actually finished fine (19 measurements), but: `UploadView` starts analysis with an unstructured `Task` (continues, state lives in `AppModel.pipeline`), yet the result sheet is bound only on `UploadView` (`.sheet(isPresented: $model.showResult)`, UploadView.swift:57). After navigating away nothing presents it; `showResult` stays true and can pop up stale later. The upload screen uses an inline progress card, so the bottom nav stays tappable and the idle timer isn't disabled — violates the existing rule that a blocking analyzing modal + kept-awake screen are required while a shot analyzes (live `CaptureView` already does this).
4. Related gaps found: Supabase `list_uploads` never returns `failed` (only `analyzed`/`pending`), so failed uploads show "pending" forever. `shots.algorithm_version` is NULL on all 3,804 shots.

---

## Decisions (Shayne, 2026-10-27) — record as DEC-084 (partially supersedes the dedupe clause of DEC-055)

- **Pause upload de-duplication** so the same clip can be uploaded and analyzed repeatedly for testing. Put it behind a config flag (`LANESIGHT_UPLOAD_DEDUPE`, default **off**) rather than deleting it. Live-shot retry idempotency (`find_shot_by_hash`) stays on — it's a dropped-connection guard, not upload dedupe.
- **Failures must fail gracefully** with a user-friendly message explaining why, never raw exception text.
- **Every failure must be tracked with its exact reason** (stable code + stage + diagnostic numbers) so failure reasons can be counted and LaneSight's analysis capability improvement tracked over time.
- Failed uploads **are listed** in Lab › Uploads as "Couldn't analyze" with the reason and a Retry.
- Uploads get the same blocking analyzing modal + kept-awake screen as live capture; a finished result is never lost by navigating.

---

## Work

### A. Pause upload dedupe (backend)
- `lanesight_api/app.py`: gate the `find_upload_by_hash` short-circuits in `POST /uploads` and `POST /shots/analyze` (upload path only) on `LANESIGHT_UPLOAD_DEDUPE == '1'`. Default off. Keep computing/storing `content_hash` (useful for grouping repeat uploads of the same clip in failure analysis).
- Leave `find_shot_by_hash` (live retries) unchanged.
- Add `LANESIGHT_UPLOAD_DEDUPE` to config/health output and to `03_ENGINEERING/DEPLOY_CLOUDRUN.md`.
- Tests: same bytes uploaded twice → two shots, two analyses when flag off; one shot when flag on; live retry still dedupes.

### B. Structured analysis failures (core)
- Add `AnalysisFailure(RuntimeError)` in `lanesight_core` with: `code` (stable SCREAMING_SNAKE), `stage` (`decode | stabilize | lane | track | impact | metrics | sanity | form_pose | storage | internal`), `message` (technical), `diagnostics: dict` (numbers that explain it). Subclassing `RuntimeError` keeps existing `pytest.raises(RuntimeError, match=…)` tests and `examples/eval_session.py` string checks working — update them to assert codes where cheap.
- Convert every raise site. Minimum mapping (verify against the code; add any I missed):

| Site | Code | Stage | Diagnostics to capture |
|---|---|---|---|
| `cv/lanes.py:89` no wood | `LANE_NOT_DETECTED_NO_WOOD` | lane | % pixels matched, s_min used, HDR flag |
| `cv/lanes.py:92` no straight edges | `LANE_NOT_DETECTED_NO_EDGES` | lane | wood regions found |
| `cv/lanes.py:224` foul line off frame | `FOUL_LINE_NOT_IN_VIEW` | lane | points found |
| `cv/pipeline.py:120` | `LANE_NOT_DETECTED` | lane | candidates tried |
| `cv/track.py:28` empty ROI | `LANE_GEOMETRY_UNUSABLE` | track | vp, foul y |
| `cv/pipeline.py:123` | `BALL_TRACK_NOT_FOUND` | track | track points (vs 10 needed) |
| `cv/pipeline.py:129` | `PIN_IMPACT_NOT_DETECTED` | impact | track last ft, last t |
| `cv/metrics.py:80` **(today's failure)** | `TRACK_TOO_SPARSE_FOR_SPEED` | metrics | on-lane pts total, pts + time span in each tried window (4–24, 4–30, 2–max), track_first_ft, track_last_ft, n dropped as off-lane |
| `cv/pipeline.py:145` >30 mph | `IMPOSSIBLE_SPEED_SCALE` | sanity | measured mph, track_last_ft |
| `cv/stabilize.py:53` | `TIMING_FRAME_MISMATCH` | stabilize | timing frames, video frames |
| `form/pose.py` PoseBackendError (4 sites) | `FORM_POSE_BACKEND_UNAVAILABLE`, `VIDEO_DECODE_FAILED`, `VIDEO_NO_FRAMES` | form_pose / decode | path ext, codec if known |
| anything else in the job | `INTERNAL_ERROR` | internal | exception type + first 500 chars + traceback tail (server log only) |

- `jobs.py`: on `AnalysisFailure`, set `job.reason` to the code + message and attach `failure_code`, `failure_stage`, `diagnostics` to the job dict; wrap unknown exceptions as `INTERNAL_ERROR`. Job JSON keeps `reason` for back-compat and adds `failure: {code, stage, user_title, user_message, tip}`.

### C. User-friendly copy
- Add one server-side table (e.g. `lanesight_core/failures.py`) mapping each code → `user_title`, `user_message`, `tip` (camera/capture advice). The server owns the copy so it can change without an app release; the app falls back to a generic message for unknown codes. Examples:
  - `TRACK_TOO_SPARSE_FOR_SPEED` → "We lost the ball early" / "We couldn't follow the ball through the first 30 feet, so speed can't be measured." / "Keep the foul line through the arrows in clear view, with nothing crossing in front of the camera."
  - `FOUL_LINE_NOT_IN_VIEW` → "The foul line isn't in the shot" / … / "Raise or pull the camera back so the foul line is visible."
  - `INTERNAL_ERROR` → "Something went wrong on our side" / "This one's on us — try again." / —
- Never surface the exception class name or raw message in the app.

### D. Persist + track every attempt (DB, migration 019)
- `shots`: add `analysis_status text` (`pending | running | analyzed | failed`), `failure_code text`, `failure_stage text`, `analyzed_at timestamptz`. Backfill: rows with metrics → `analyzed`; the 8 rows with empty record → `failed` / `failure_code = 'UNKNOWN_LEGACY'`.
- **Fill `shots.algorithm_version`** on every analysis (core version + git short SHA, or whatever `/health` already reports as `core`).
- New retained table **`analysis_attempt`** — one row per analysis attempt, successes included (rates need a denominator). Retained like `feedback`: **no FK cascade from shots or users** (store `shot_id`/`user_id` as plain uuids), not deleted by shot/account deletion or the score reset. Columns (suggested): `id, created_at, user_id, shot_id, session_id, source (upload|live), capture_mode (shot|form), status (analyzed|failed), failure_code, failure_stage, diagnostics jsonb, algorithm_version, api_revision (Cloud Run revision from K_REVISION), duration_ms, step_timings jsonb, content_hash, clip jsonb (fps, width, height, duration_s, codec, hdr, bytes), env (dev|beta|live)`. RLS: owner-only read; writes via service role.
- Write the attempt row in the job runner for both success and failure (best-effort — a logging failure must never fail the analysis).
- Add a simple view for trend analysis, e.g. `analysis_failure_rates` grouped by day × algorithm_version × capture_mode × failure_code with attempts / failures / rate.
- Add the migration to `lanesight_core/models/migrations/019_analysis_attempts.sql`; apply to a local/branch DB and run tests. **Do not apply to live** — prepare and list it for Shayne.

### E. Fix Lab › Uploads (backend + app)
- `store.py` Supabase `list_uploads`: `created_at=_ts_epoch(sh.get('created_at'))`; select and return `analysis_status`, `failure_code`, and the failure copy (`user_title`, `user_message`) so the row can render. `state` = `analysis_status` (fallback to the old metrics heuristic for legacy rows). Mirror in the in-memory store.
- Add a contract test that the Supabase-store and memory-store `list_uploads` rows have identical types (this exact drift caused the bug). Worth a quick sweep of other Supabase list endpoints for raw ISO timestamps vs `Double` fields in `Models.swift`.
- App `UploadRow`: add `failure_code`, `failure_title`, `failure_message`. Row states: **Analyzing…** (spinner, not tappable until done), **Analyzed** (opens result), **Couldn't analyze** (reason + Retry that re-picks/re-uploads — dedupe is off, so a fresh attempt runs).
- App error handling: `APIError.decoding` must not render as "Couldn't reach the analysis host". Show "Couldn't load your uploads" + Retry; log the detail (dev panel / console), never dump JSON on screen. Make the list decode lossy (skip a bad row, keep the rest) so one malformed row can't blank the section.

### F. Upload analyze flow (app)
- `UploadView` uses the same full-screen blocking analyzing modal as `CaptureView` (`.fullScreenCover`, analyzing animation, `interactiveDismissDisabled`) and sets `UIApplication.shared.isIdleTimerDisabled = true` for the duration; restore on completion/failure.
- On failure, the modal is replaced by the friendly failure (title, message, tip, Retry / Done) using the server `failure` object — not `"Analysis failed: \(reason)"` (`AppModel.swift:498`).
- Move result presentation off `UploadView`: present from the app root (or a global "Your upload finished — View" banner) so a result is never orphaned. Clear `showResult`/`result` once consumed so a stale sheet never re-pops when the upload screen is reopened.
- If the app is backgrounded mid-request and the request dies, the shot row's `analysis_status` is the source of truth: Lab › Uploads shows it Analyzing/Analyzed/Failed from the server, so the user can always get back to it. (A durable `analysis_jobs` table / Cloud Run Jobs stays a separate follow-up.)

### G. Docs
- DEC-084 in `00_CONTEXT/DECISIONS.md` (decisions above; note it supersedes DEC-055's "uploads are de-duplicated by content hash" line while the flag is off).
- Update `00_CONTEXT/CURRENT_STATE.md`, `03_ENGINEERING/FEEDBACK_STORE_SPEC.md` (or a new `ANALYSIS_ATTEMPT_LOG_SPEC.md`) describing the attempt log as short-term failure tracking + long-term capability trend data, and `DEPLOY_CLOUDRUN.md` (new env flag).
- Re-sync the changed docs to the claude.ai LaneSight Project after committing.

---

## Verify before reporting
- Unit tests: every raise site → expected `code`/`stage` with non-empty diagnostics; copy table has an entry for every code; dedupe flag on/off; live-retry dedupe intact; `list_uploads` type parity between stores.
- End to end against the local runner (and Cloud Run only after authorization): a clip that triggers `TRACK_TOO_SPARSE_FOR_SPEED` → shot `failed` with code, one `analysis_attempt` row with diagnostics, friendly message in app; a good clip → `analyzed`, attempt row, `algorithm_version` set; the same good clip uploaded twice → two shots.
- iOS: Lab › Uploads loads for an account with uploads (including the legacy empty row); leaving the upload screen is blocked during analysis; a finished result is presented/reachable; no stale sheet on reopen. Build in Xcode is Shayne's step — state clearly what to test on the phone.

## Final report (one message)
What changed (files), test results, anything not done and why, and the pending go-aheads: (1) apply migration 019 to live Supabase `europwryibstnmipbvam`, (2) redeploy Cloud Run with `LANESIGHT_UPLOAD_DEDUPE` unset/0, (3) push `dev-build-v0`.
