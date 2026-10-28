# LaneSight — Ops Reporting Definitions (§3)

Status: DRAFT (worktree `ops-dashboard`) — relocate to `03_ENGINEERING/` at merge
Version: 1.0
Last Updated: 2026-10-28
Owner: Shayne
Related: `01_PRODUCT/PRODUCTION_MONITORING_OBSERVABILITY_CONTEXT.md` (§4 event model, §5 dashboard catalogue), `DEC-086` (analysis_attempt), `DEC-092` (latency P0), `DEC-063` (staged accounts), migration `0XX_ops_reporting.sql`, `definitions.json`.

> This is the canonical, human-readable definition of every metric the owner ops dashboard reports. The machine-readable twin is `definitions.json`; the SQL that produces the numbers is `0XX_ops_reporting.sql`; `validation/validate_definitions.py` keeps the three in sync. **No metric here is a mock number** — each names its real source column and its honesty rule.

## 1. Scope today vs pending §2

LaneSight already records one rich production signal: the retained **`analysis_attempt`** log (one row per analysis, success + failure, DEC-086/092) plus **`feedback`**, **`shots`**, **`sessions`**, **`profiles`**. That is enough to report, honestly, on three of the strategy's eight observability domains and partially on three more. The remaining two have **no instrumentation yet** and are reported as NO DATA, never faked:

| Domain (strategy §5) | Availability | Real source today | Backing view |
|---|---|---|---|
| 03 Video & AI Trust | **available** | `analysis_attempt` | `ops_cv_coverage`, `ops_analysis_daily` |
| 08 Release & Regression | **available** | `analysis_attempt` version/revision | `ops_release_health` |
| 04 App/API Performance | partial | `analysis_attempt.step_timings` | `ops_latency_stages` |
| 02 Customer Journey | partial | `shots`/`sessions` counts | `ops_usage_daily` |
| 07 Security & Controls | partial | `feedback` triage (no auth-event log yet) | `ops_feedback_summary` |
| 01 Executive | partial | derived from the real sources above | overview |
| 05 Storage & DB | **no_data** | not instrumented | — (pending §2) |
| 06 Financial Operations | **no_data** | no cost metering | — (pending §2) |

`ops_coverage_status` encodes this table in SQL so the dashboard renders HEALTHY vs NO DATA by domain.

## 2. Honesty states

- **HEALTHY** — a real measured value is present.
- **NO DATA** — the source is empty in scope, or a rate's denominator is 0 (the SQL returns `NULL` via `nullif`). Rendered as "NO DATA", never 0.
- **NO ACCESS** — the dashboard could not reach the DB (missing/invalid `service_role` env, or a query error). Rendered as "NO ACCESS", never a guess.

## 3. Universal filters

- **Real accounts only.** Every canonical view excludes `profiles.is_staged = true` (DEC-063 — staged `ls_*` accounts MAY hold fabricated data). Only `ops_freshness` and `ops_coverage_status` are not row-level real-only (they are metadata). Deleted accounts (no `profiles` row) are treated as real, since staged status is then unknowable; staged accounts are long-lived, so this is a safe, documented edge.
- **Environment.** `env ∈ {dev, beta, live}` is a selectable dimension, not a hidden filter. Production scope is **live + beta**; `dev` is local test traffic and is shown only when explicitly selected.

## 4. Metric glossary

Each metric: **source view.column** — definition — honesty rule.

### Analysis reliability (`ops_analysis_daily`, day × env × capture_mode)
- **attempts** `.attempts` — count of analysis attempts. A real 0 is 0; an empty window is NO DATA.
- **analyzed / failures** `.analyzed`/`.failures` — attempts by terminal `status`.
- **failure_rate** `.failure_rate` — `failures / nullif(attempts,0)`. NULL (NO DATA) when there were no attempts — never 0%.
- **distinct_users** `.distinct_users` — distinct `user_id` with an attempt.
- **p50/p90/p95_attempt_seconds** — percentiles of end-to-end attempt seconds (`duration_ms/1000`).

### Video & CV trust (`ops_cv_coverage`, day × env, ball/shot attempts)
- **far_lane_read_rate** `.far_lane_read_rate` — share of shot attempts whose far lane was read = `far_lane_read / nullif(attempts where far_lane recorded, 0)`. Denominator is attempts that recorded a `far_lane` verdict; NULL → NO DATA. This is LaneSight's hardest CV frontier (back-half ball read), so it is the headline trust number.
- **avg_metrics_measured** `.avg_metrics_measured` — mean `n_measured` per attempt.
- **hdr_clips / vfr_clips / cold_start_attempts** — capture-fact counts (HDR, variable frame rate, cold-start job).
- **precheck_rejects / precheck_evaluated** — DEC-092 shadow framing-precheck verdicts (shadow = recorded, never blocking until validated).
- **probe_errors** — attempts whose clip probe errored.

### Latency by stage (`ops_latency_stages`, day × env, analyzed attempts)
- **p50_total_s / p90_total_s** — end-to-end seconds.
- **p50_server_analyze_s, p50_decode_s, p50_hdr_convert_s** — server stages (DEC-092 P0 timings).
- **p50_phone_trim_s, p50_phone_upload_s, p50_phone_pre_analyze_s** — phone-side stages (`step_timings.client`, DEC-092 P0 M1).
- **cold_start_rate** — `cold_start / nullif(analyzed,0)`. NULL → NO DATA. A stage percentile is NULL when that stage was never timed in the window (NO DATA, not 0) — e.g. HDR convert on an all-SDR day.

### Release & regression (`ops_release_health`, algorithm_version × api_revision × env)
- **attempts, failure_rate, p50_attempt_seconds, avg_metrics_measured, distinct_users, first_seen, last_seen** — per release, for regression comparison (DEC-092 promotion discipline: accuracy/coverage/runtime compared separately; this view is the runtime/failure side).

### Feedback & support (`ops_feedback_summary`, day × app_phase × source)
- **total, thumbs_up, thumbs_down, untriaged, avg_rating** — real feedback only (staged excluded, mirrors `feedback_review`, DEC-063). `untriaged` = `triage_status='new'`.

### Product usage (`ops_usage_daily`, day)
- **shots, active_users_shots, sessions_started** — real-account production counts.

### Freshness (`ops_freshness`, per source)
- **source, last_ingested, rows** — drives the dashboard's last-updated clock and per-source NO DATA.

## 5. Change control

A view column cannot change in only one place. If you add/rename a column in `0XX_ops_reporting.sql`, update `definitions.json` (and this doc). `validation/validate_definitions.py` fails CI on any drift between them. The dashboard reads only columns named here.
