# LaneSight — Ops Reporting Definitions (§3)

Status: CANONICAL (DEC-098; migration 025 applied live 2026-10-28)
Version: 1.4
Last Updated: 2026-10-29
Owner: Shayne
Related: `01_PRODUCT/PRODUCTION_MONITORING_OBSERVABILITY_CONTEXT.md` (§4 event model, §5 dashboard catalogue), `DEC-086` (analysis_attempt), `DEC-092` (latency P0), `DEC-063` (staged accounts), migration `025_ops_reporting.sql`, `definitions.json`.

> This is the canonical, human-readable definition of every metric the owner ops dashboard reports. The machine-readable twin is `definitions.json`; the SQL that produces the numbers is `025_ops_reporting.sql`; `validation/validate_definitions.py` keeps the three in sync. **No metric here is a mock number** — each names its real source column and its honesty rule.

## 1. Scope today vs pending §2

LaneSight already records one rich production signal: the retained **`analysis_attempt`** log (one row per analysis, success + failure, DEC-086/092) plus **`feedback`**, **`shots`**, **`sessions`**, **`profiles`**. That is enough to report, honestly, on three of the strategy's eight observability domains and partially on three more. The remaining two have **no instrumentation yet** and are reported as NO DATA, never faked:

| Domain (strategy §5) | Availability | Real source today | Backing view |
|---|---|---|---|
| 03 Video & AI Trust | **available** | `analysis_attempt` | `ops.cv_coverage`, `ops.analysis_daily` |
| 08 Release & Regression | **available** | `analysis_attempt` version/revision | `ops.release_health` |
| 04 App/API Performance | partial | `analysis_attempt.step_timings` | `ops.latency_stages` |
| 02 Customer Journey | partial | `shots`/`sessions` counts | `ops.usage_daily` |
| 07 Security & Controls | partial | `feedback` triage (no auth-event log yet) | `ops.feedback_summary` |
| 01 Executive | partial | derived from the real sources above | overview |
| 05 Storage & DB | **no_data** | not instrumented | — (pending §2) |
| 06 Financial Operations | **no_data** | no cost metering | — (pending §2) |

`ops.coverage_status` encodes this table in SQL so the dashboard renders HEALTHY vs NO DATA by domain.

## 2. Honesty states

- **HEALTHY** — a real measured value is present.
- **NO DATA** — the source is empty in scope, or a rate's denominator is 0 (the SQL returns `NULL` via `nullif`). Rendered as "NO DATA", never 0.
- **NO ACCESS** — the owner RPC returned an error (not signed in as the owner, or a transport error). Rendered as "NO ACCESS", never a guess.

**Access model.** The views live in a private `ops` schema PostgREST does not expose (usage revoked from anon/authenticated). The dashboard signs the owner in with Supabase Auth and reads data only through SECURITY DEFINER RPCs `public.ops_rpc_*`, each of which raises `42501` unless `ops.is_owner()` (auth.uid() == the id in `ops.app_owner` == `owner.py OWNER_USER_ID`). No service_role / JWT secret / DB password is used. The Next.js server additionally gates on `OPS_OWNER_ID` (non-owner → 403).

## 3. Universal filters

- **Real accounts only.** Every canonical view excludes `profiles.is_staged = true` (DEC-063 — staged `ls_*` accounts MAY hold fabricated data). Only `ops.freshness` and `ops.coverage_status` are not row-level real-only (they are metadata). Deleted accounts (no `profiles` row) are treated as real, since staged status is then unknowable; staged accounts are long-lived, so this is a safe, documented edge.
- **Environment.** `env ∈ {dev, beta, live}` is a selectable dimension, not a hidden filter. Production scope is **live + beta**; `dev` is local test traffic and is shown only when explicitly selected.

## 4. Metric glossary

Each metric: **source view.column** — definition — honesty rule.

### Analysis reliability (`ops.analysis_daily`, day × env × capture_mode)
- **attempts** `.attempts` — count of analysis attempts. A real 0 is 0; an empty window is NO DATA.
- **analyzed / failures** `.analyzed`/`.failures` — attempts by terminal `status`.
- **failure_rate** `.failure_rate` — `failures / nullif(attempts,0)`. NULL (NO DATA) when there were no attempts — never 0%.
- **distinct_users** `.distinct_users` — distinct `user_id` with an attempt.
- **p50/p90/p95_attempt_seconds** — percentiles of end-to-end attempt seconds (`duration_ms/1000`).

### Video & CV trust (`ops.cv_coverage`, day × env, ball/shot attempts)
- **far_lane_read_rate** `.far_lane_read_rate` — share of shot attempts whose far lane was read = `far_lane_read / nullif(attempts where far_lane recorded, 0)`. Denominator is attempts that recorded a `far_lane` verdict; NULL → NO DATA. This is LaneSight's hardest CV frontier (back-half ball read), so it is the headline trust number.
- **avg_metrics_measured** `.avg_metrics_measured` — mean `n_measured` per attempt.
- **hdr_clips / vfr_clips / cold_start_attempts** — capture-fact counts (HDR, variable frame rate, cold-start job).
- **precheck_rejects / precheck_evaluated** — DEC-092 shadow framing-precheck verdicts (shadow = recorded, never blocking until validated).
- **probe_errors** — attempts whose clip probe errored.

### Latency by stage (`ops.latency_stages`, day × env, analyzed attempts)
- **p50_total_s / p90_total_s** — end-to-end seconds.
- **p50_server_analyze_s, p50_decode_s, p50_hdr_convert_s** — server stages (DEC-092 P0 timings).
- **p50_phone_trim_s, p50_phone_upload_s, p50_phone_pre_analyze_s** — phone-side stages (`step_timings.client`, DEC-092 P0 M1).
- **cold_start_rate** — `cold_start / nullif(analyzed,0)`. NULL → NO DATA. A stage percentile is NULL when that stage was never timed in the window (NO DATA, not 0) — e.g. HDR convert on an all-SDR day.
- **decode_cache_engaged_rate** (DEC-092 P1, migration 029) — share of attempts where the decode-once frame cache held the whole clip and every later pass was served from cache: `count(decode_cache_complete) / nullif(count(attempts that recorded the field),0)`. Denominator excludes attempts analysed before the cache shipped (field absent) → NULL → NO DATA until real post-deploy traffic. Tells us whether the cache ever fires in production (it only fits short/lower-fps/lower-res windows; see `DECODE_ONCE_FINDINGS.md`). Per-attempt detail: `ops.attempt.decode_cache_complete` / `decode_cached_passes`.

### Release & regression (`ops.release_health`, algorithm_version × api_revision × env)
- **attempts, failure_rate, p50_attempt_seconds, avg_metrics_measured, distinct_users, first_seen, last_seen** — per release, for regression comparison (DEC-092 promotion discipline: accuracy/coverage/runtime compared separately; this view is the runtime/failure side).

### Feedback & support (`ops.feedback_summary`, day × app_phase × source)
- **total, thumbs_up, thumbs_down, untriaged, avg_rating** — real feedback only (staged excluded, mirrors `feedback_review`, DEC-063). `untriaged` = `triage_status='new'`.

### Product usage (`ops.usage_daily`, day)
- **shots, active_users_shots, sessions_started** — real-account production counts.

### Freshness (`ops.freshness`, per source)
- **source, last_ingested, rows** — drives the dashboard's last-updated clock and per-source NO DATA.

### Engine comparison — server vs on-device (`ops.platform_daily`, day × env × platform × capture_mode)
Migration 028 (DEC-103). Same volume/latency/failure metrics as `analysis_daily` but **split by `platform`**
(`server` = authoritative Python/Cloud Run; `ios` = native on-device **shadow**, DEC-106). Columns: **attempts,
analyzed, failures, failure_rate, distinct_users, p50/p90/p95_attempt_seconds, avg_analyze_s**. Rendered on the
dashboard **Engine A/B** page. On-device rows come from `POST /analysis/shadow` (recorded, never shown/scored).
This panel is **volume/latency/failure only — NOT an accuracy verdict**: DEC-106 Gate A is accuracy vs **ground
truth**, not vs the server, so accuracy/bias/plausible-but-wrong + the per-metric flip live with the DEC-094
harness (`ops/cv_eval.py`), not here.

## 4b. Partially built / future panels

- **Engine accuracy comparison vs ground truth** (DEC-106 Gate A). The per-metric accuracy/bias/unavailable-rate
  comparison (server vs on-device vs **ground truth**, by `algorithm_version`) is **not a dashboard view yet** —
  it is produced today by `ops/cv_eval.py` against the **DEC-094** labeled set (file-based, not in the DB). Surface
  it on the dashboard once the DEC-094 eval set is complete (labels for all manifest clips + Specto lateral truth);
  the server-vs-on-device *latency/volume* half already ships as `ops.platform_daily` (above). This is the runtime
  face of the DEC-106 promotion gates (A accuracy / B integrity / C performance) — no metric flips to on-device
  until it passes A/B/C vs ground truth.

## 5. Change control

A view column cannot change in only one place. If you add/rename a column in `025_ops_reporting.sql`, update `definitions.json` (and this doc). `validation/validate_definitions.py` fails CI on any drift between them. The dashboard reads only columns named here.

## 6. Known advisor warnings (intentional)

Supabase's security advisor flags the **9 `public.ops_rpc_*` functions** under `authenticated_security_definer_function_executable` — "signed-in users can execute a SECURITY DEFINER function via `/rest/v1/rpc/…`" (lint `0029`). **This is intentional and safe:**

- Each RPC's first statement is `if not ops.is_owner() then raise 42501 ('not authorized')`, so a signed-in **non-owner** gets permission-denied, not data. Proven on live 2026-10-28: non-owner call → `42501: not authorized`; owner call → correct rows.
- SECURITY DEFINER is **required**, not optional: the underlying views live in the private `ops` schema (usage revoked from anon/authenticated), so a SECURITY INVOKER function would fail even for the owner. The definer + in-function `ops.is_owner()` check is the sanctioned owner-only RPC pattern.
- `EXECUTE` is granted only to `authenticated` (revoked from `anon`/`public`); the owner must be signed in.

No action needed. If Supabase adds a lint-suppression comment mechanism, annotate there; until then this note is the record. (The advisor's other findings — `rls_enabled_no_policy` on `intel.*`/rule tables, leaked-password protection, unindexed-FK/unused-index performance lints — are pre-existing and unrelated to DEC-098.)
