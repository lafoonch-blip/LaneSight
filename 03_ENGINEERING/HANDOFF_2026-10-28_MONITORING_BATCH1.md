# LaneSight handoff — Monitoring Batch 1: the failure loop (2026-10-28)
Version: 1.0 · Owner: Shayne · Spec: the "LaneSight Monitoring — Target-State Requirements" registry (claude.ai doc; requirement IDs below come from it). Commit the registry to `03_ENGINEERING/MONITORING_REQUIREMENTS.md` as step 0.

## Read first
Repo `~/Developer/LaneSight`. Read `AGENTS.md`, `00_CONTEXT/CURRENT_STATE.md`, the last ~8 DECs (through DEC-101), `03_ENGINEERING/OPS_REPORTING_DEFINITIONS.md`, `ops-dashboard/README.md`, and `02_RESEARCH/ANALYSIS_FAILURE_RCA_2026-10-28.md`.

Rules:
- Work straight through and give one report.
- Backend tests must pass before every commit. The dashboard validator must pass (`ops-dashboard/validation/validate_definitions.py`).
- Swift: build for simulator **and** device in Xcode; a syntax check isn't enough.
- **Approved by Shayne for this round:** apply migration 028 to live `europwryibstnmipbvam`, then redeploy Cloud Run from `dev-build-v0`, then push. Order: migration first, then API.

## What's live right now
- **Cloud Run:** rev `lanesight-api-00037-r6s`, built from `dev-build-v0` @ `30d34f2` (DEC-099/100/101 + ops §2). Seen live 2026-10-29 02:42 UTC.
- **Flags:**
  - clip retention on (7 days, newest 40 per user)
  - precheck in shadow mode
  - upload de-dupe off
- **Migrations applied to live:** through `027_ops_instrumentation`. There are two files numbered 026: `026_intel_competitor_benchmark` and `026_arsenal_default_ball`. The next free number is **028**.
- **Live data checked 2026-10-28:**
  - `api_request`: 129 rows.
  - `storage_snapshot`: 4 rows.
  - Cost on 6 attempts.
  - 1 attempt with `clip.storage_path`.
  - 0 with snapshot frames (no failure since the deploy).
  - 0 `CLIENT_*` rows.
  - `product_event`: **0 rows**. The app emits no events yet.

## Branches (state of each)
- `dev-build-v0` @ `30d34f2`: mainline. Pushed, deployed (00037). Work from here on a new branch, `monitoring/batch1`.
- `main` @ `56d71e9`: **stale** (decision log v1.44). Don't build from it. Fast-forward it to `dev-build-v0` at the end of this round (approved).
- `integrate/dec-099-100-with-ops`, `fix/clip-retention-diagnostics`, `fix/ux-batch-2026-10-28`, `ops-instrumentation`: all merged into `dev-build-v0`. Leave them alone.

## What's done
- DEC-098: ops reporting, the owner-only RPC pattern and the dashboard tabs.
- DEC-100: clip retention, snapshot frames on failures, `/analysis/client-failure`, `ops/fetch_clip.py`.
- DEC-101: the phone trim keeps the whole shot.

## Next round of work (do this)
0. **Registry into the repo.** Commit `03_ENGINEERING/MONITORING_REQUIREMENTS.md` (Shayne exports it from the doc). Add a DEC for "the monitoring requirements registry is the single source for dashboards, instrumentation and alerts", at the next free number.

1. **WP1: usable-result views + panels** (migration `028_ops_failure_loop.sql`, additive):
   - **`ops.attempt_usable`:** one row per attempt with `tier`, worked out from the shot record:
     - **`shot_full`:** speed, entry board, entry angle measured and pins readable.
     - **`shot_near`:** speed + arrows or laydown measured, with the far lane honestly unavailable.
     - **`form_usable`:** not `FORM_DELIVERY_NOT_ISOLATED`, and ≥ 1 key frame + swing timing.
     - **`not_usable`:** anything else, including failed attempts and `CLIENT_*` rows.
     - Add `usable bool`.
     - Write the tier rules as SQL **and** as `lanesight_core/usable.py` with tests (one definition; the validator checks they agree on fixtures).
   - **Views:**
     - `ops.reliability_matrix`: day × mode × source × env with completed, usable, failed, client_failed, usable_rate (nullif), distinct_bowlers. Covers REL-01/02/05.
     - `ops.repeat_clips`: REL-09.
     - `ops.stuck_attempts`: no terminal state after 600 s (REL-16).
     - `ops.time_to_fail`: PERF-07.
     - `ops.cv_stage_time`: PERF-09.
     - `ops.shot_metric_coverage`: per metric, status share + top notes (SHOT-03/04).
     - `ops.shot_capture`: lane selection, gate trips, pins read, trim kept (SHOT-11/13/14/15).
     - `ops.form_quality`: usable rate, gate trips, events located, key frames, view, steps, metric coverage (FORM-01–08).
     - `ops.engagement`: Weekly Engaged Bowlers, mode/source mix, second-session rate, failure exposure (JRN-04/07/08/10).
     - `ops.unit_cost`: cost per attempt, per usable result and of failures, by mode × source (COST-02–05).
     - `ops.feature_use`: FEAT-01–03.
   - Every view excludes staged accounts and is read through a new owner-checked `public.ops_rpc_*` (same pattern as 025). Add them to `definitions.json` and `OPS_REPORTING_DEFINITIONS.md`; the validator must pass.
   - **Panels:**
     - Rewrite **Reliability**: headline usable rate by mode × source with counts, Pareto, stage, phone-side failures, repeat clips, stuck attempts.
     - New **Shot Trust** and **Form Trust** pages.
     - Add unit cost to **Cost** and engagement to the **Overview**.
     - Honest states only.

2. **WP2: attempt drill-down.** `ops-dashboard/app/attempt/[id]/page.tsx`, linked from every attempt row and count:
   - timeline (phone stages → server stages)
   - status, tier, failure code, stage, diagnostics
   - **snapshot frames** rendered from `clip.frames[*].jpg_b64`
   - phone trim (original vs uploaded seconds)
   - the clip facts
   - **clip link**: a new owner-checked RPC or API endpoint returns a 10-minute signed URL for `clip.storage_path` and writes a `clip_access_audit` row (attempt, owner, issued_at). Covers REL-14, SEC-06.
   - Add `ops.retention_compliance`: clips older than 7 days (target 0, SEC-07).

3. **WP3: root-cause workflow.**
   - Table `attempt_rca` (attempt_id, cause enum `framing|phone_trim|detector|pose|infra|client|user_error|unknown`, status `proposed|confirmed|rejected`, evidence text, fix_release, proposed_by, confirmed_at).
   - `ops/propose_rca.py`: for each not-usable attempt with no RCA row, propose a cause from code + diagnostics + trim numbers + frames, with the evidence written out. Example: PIN_IMPACT_NOT_DETECTED where the track ends within 0.3 s of clip end + an upload shorter than 4 s → `phone_trim`. Rules only; mark `unknown` when unsure. Never auto-confirm.
   - Dashboard queue on Reliability: confirm or reject with a note (an owner-checked RPC write).
   - Views: `ops.rca_mix` and `ops.fix_verification` (rate per cause before vs after `fix_release`). Covers REL-11/12/13, SUP-08.
   - Run `propose_rca.py` over all existing attempts and report the proposed mix.

4. **WP8: coaching capture.**
   - At analysis time, store the coach output on the shot record (`record.coach = {throw, lane, action, state, evidence: [metric keys + status used], suppressed_reason}`). Use the same function `_shot_card_enrich` uses, called once and saved, so the card and the store can't disagree.
   - `ops.coaching_integrity`:
     - grounding: an action citing a metric whose status is unavailable → count
     - withholding: a move suggested while measurement uncertainty exceeds its tolerance → count
     - execution vs lane: a lane/ball move after an execution miss → count
   - Covers COACH-01–05. Tests for each check.

5. **WP4, script part: safe deploy.** `ops/deploy.sh` wraps the existing `gcloud run deploy` from `DEPLOY_CLOUDRUN.md`. It:
   - refuses unless the branch is `dev-build-v0`, the tree is clean, it matches `origin`, and pytest passed
   - sets `LANESIGHT_GIT_SHA` / `LANESIGHT_GIT_BRANCH` env on the revision
   - writes a `deploy_log` row (revision, sha, branch, deployer, time, result)
   - runs a post-deploy smoke test that re-analyzes a stored known-good clip (`shot-clips/_smoke/known_good.mov`) through the live API and records pass/fail and seconds
   - **Deployed-line check:** `/health` returns the git sha; `ops.deploy_drift` compares it with the latest `dev-build-v0` sha recorded at deploy time.
   - Use this script for this round's redeploy. Covers CHG-02/03/09.

6. **Apply 028 live → deploy with `ops/deploy.sh` → verify:**
   - Every new RPC returns rows for the owner and `42501` for a non-owner.
   - The Reliability, Shot Trust and Form Trust panels render real numbers.
   - One drill-down shows frames (trigger a failure with a known-bad clip if none exist).
   - The RCA queue lists proposals.
   - Then push `monitoring/batch1`, merge into `dev-build-v0`, and fast-forward `main`.

## Deferred / gated (don't start)
- CI auto-deploy (needs a GCP key in GitHub secrets).
- Billing export (WP13).
- MetricKit (WP10).
- App events (WP7: needs an on-device build pass, next round).
- Full alerting (WP5).
- Accuracy gates (WP6).
- Score integrity (WP9).
- Security audit (WP12).
- Revenue, acquisition, integrations.
- Interim alerts run as a claude.ai scheduled task, not in code.

## Watch out for
- Other sessions commit to `dev-build-v0`. Rebase before merging, and re-check that 028 is still free.
- `clip.frames` is a list of base64 JPEGs only on failed attempts. The older `clip.frames` on some rows is the probe's **frame count** (a number). Handle both; render images only when it's an array.
- `capture_mode` / `source` can be null on old rows; bucket them as `unknown`, never drop them.
- The usable-tier rules must match `lanesight_core/usable.py`; one definition only.
- Don't add PII to any new table: `user_ref` (pseudonymous) in views, `user_id` only in base tables.

## Done-when
- Done when all of these hold:
  - Tests and the validator are green, and the iOS app builds if touched.
  - 028 is applied live and the revision deployed via `ops/deploy.sh` is live, with a smoke-test pass.
  - Panels show real data and the drill-down shows frames.
  - The RCA queue is populated.
  - `main` is fast-forwarded.
- The report includes:
  - the revision and sha
  - the usable rate by mode × source for all attempts to date
  - the proposed root-cause mix
  - each requirement ID moved to "Panel live"
  - anything that differs from the registry
