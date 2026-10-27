# Analysis attempt log + structured failures (DEC-086)
Version: 1.0
Last Updated: 2026-10-27
Status: CANONICAL for the failure-tracking surface. Migration `019_analysis_attempts.sql`.
Owner: Shayne

Every run of the CV/pose pipeline — on an upload or a live shot — is an **attempt**. An attempt either produces
a result (`analyzed`) or raises a structured `AnalysisFailure` (`failed`). This doc is the contract for how a
failure is represented, surfaced to the user, and recorded for triage.

## 1. Structured failures (`lanesight_core/failures.py`)
`AnalysisFailure(RuntimeError)` — subclasses `RuntimeError` so existing `pytest.raises(RuntimeError, …)` and
broad excepts keep working.
- `code` — stable UPPER_SNAKE identifier (e.g. `LANE_NOT_DETECTED_NO_WOOD`, `TRACK_TOO_SPARSE_FOR_SPEED`).
- `stage` — one of `decode · stabilize · lane · track · impact · metrics · sanity · form_pose · storage · internal`
  (an unknown stage falls back to `internal`).
- `message` — developer-facing detail (goes to `job.reason` as `"CODE: message"`; never shown to the user).
- `diagnostics` — the numbers behind the decision (point counts, windows, pixel fractions). Stored, not shown.
- `as_dict()` → `{code, stage, user_title, user_message, tip}` — the block the API returns and the app renders.

`FAILURE_COPY` maps each `code` → user `title` / `message` / `tip`. `failure_block(code, stage)` returns the
block, falling back to `INTERNAL_ERROR`'s generic copy for an unknown code. **The raw code/trace never reaches
the user** — the app shows the copy only. A test (`test_every_raised_code_has_user_copy`) scans the source for
raised codes and fails if any lacks a `FAILURE_COPY` entry, so a new raise can't ship without copy.

Anything unexpected (a bare `ValueError`, etc.) is wrapped by the job runner as `INTERNAL_ERROR` with the
exception type + a trace tail in `diagnostics` — still a clean, coded, user-safe failure.

## 2. `shots` columns (first-class failure state)
`analysis_status` `pending | running | analyzed | failed`, plus `failure_code`, `failure_stage`, `analyzed_at`.
`algorithm_version` (pre-existing) is filled on every analysis. Lab › Uploads reads `analysis_status` to show
Analyzing / Analyzed / Couldn't-analyze. Backfill: a non-empty record → `analyzed`; an empty/null record →
`failed` / `UNKNOWN_LEGACY`.

## 3. `analysis_attempt` (retained log — one row per attempt)
Successes are logged too: failure **rates** need a denominator. Modeled on `feedback` (DEC-059): **no FK
cascade** — `user_id` / `shot_id` are plain uuids, so a row outlives shot deletion, account deletion and the
score reset. It is the long-term record of what LaneSight could and couldn't analyze.

| column | meaning |
|---|---|
| `id`, `created_at` | row identity / time |
| `user_id`, `shot_id`, `session_id` | plain uuids (not FKs) |
| `source` | `upload` \| `live` |
| `capture_mode` | `shot` \| `form` |
| `status` | `analyzed` \| `failed` |
| `failure_code`, `failure_stage` | set when `failed` |
| `diagnostics` (jsonb) | the numbers behind a failure |
| `algorithm_version`, `api_revision`, `env` | engine version, Cloud Run revision (`K_REVISION`), `dev`/`beta`/`live` |
| `duration_ms`, `step_timings` (jsonb) | timing |
| `content_hash` | groups repeat uploads of the same clip |
| `clip` (jsonb) | `{fps,width,height,duration_s,codec,hdr,bytes}` |

RLS: owner-only `select` (`user_id = auth.uid()`); all writes via the service role (the API). Logging is
**best-effort** — a logging failure never breaks an analysis (`store.log_analysis_attempt` swallows errors).

`analysis_failure_rates` view: `day × algorithm_version × capture_mode × failure_code` → `attempts`,
`failures`, `failure_rate`.

## 4. Store API (`lanesight_api/store.py`, both Memory + Pg)
- `save_shot_result(shot_id, record, result, algo_version=None)` → sets `analysis_status='analyzed'`, clears
  failure fields, stamps `analyzed_at`.
- `mark_shot_failed(shot_id, code, stage)` → `analysis_status='failed'` + failure fields.
- `log_analysis_attempt(row)` → append one attempt row (best-effort).
- `list_uploads(user_id)` → both stores build the row via the shared `_upload_row` static (identical types;
  `created_at` is epoch, never an ISO string — the drift that previously broke the list), and a `failed` row
  carries `failure_title`/`failure_message`/`tip`.

## 5. Upload de-dup flag (DEC-086)
`LANESIGHT_UPLOAD_DEDUPE` gates the upload content-hash short-circuit only. **Default OFF** → re-uploading a
clip makes a new shot (re-analyze while the engine changes). Live-capture hash de-dup is independent, always
on. `GET /health` reports the current value as `config.upload_dedupe`. See `DEPLOY_CLOUDRUN.md`.

## 6. iOS contract
`JobResponse.failure` = `FailureInfo {code, stage, user_title, user_message, tip}`. On a failed job the app
shows `user_message` + `tip` — never the code/reason. `UploadRow` carries `state` + (on failure) the copy;
the Lab list decodes lossily (one bad row can't blank the list) and a decode error reads "Couldn't load your
uploads." The upload analyzing cover / result / failure are presented at the **app root** so navigating away
mid-analysis can't orphan the result; the screen stays awake throughout.
