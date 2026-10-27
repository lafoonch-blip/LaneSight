# LaneSight — Production Monitoring & Observability Strategy

Status: PROPOSED / PLANNING — pending owner approval
Version: 1.0
Last Updated: 2026-10-26
Owner: Shayne
Related: `00_CONTEXT/DECISIONS.md`, `01_PRODUCT/BUILD_PLAN.md`, `01_PRODUCT/COST_PLAN.md`, `01_PRODUCT/ROLLOUT_STRATEGY.md`, `03_ENGINEERING/PERFORMANCE_RELIABILITY_SLO_PROPOSAL.md`

> Planning context, not an accepted DEC. GitHub is source of truth under AGENTS.md; DECISIONS.md and CURRENT_STATE.md govern on conflicts. This document creates no new accepted product decision. Numbers below are proposed gates or examples until instrumented and measured.

## 1. Operational mandate

Every production feature must be **observable, attributable, supportable, and controllable**: who used it (pseudonymously), what happened, whether it succeeded, why it failed, its latency, its costs, and which release/algorithm was involved. Distinguish **end-user product events**, **diagnostic traces/logs**, **video quality evidence**, **provider billing records**, and **security audit events**; never ship raw sensitive content indiscriminately to analytics.

Adopt enterprise-grade **coverage and incident response**, but minimize monthly service overhead at 60–75 beta users. Monitoring provider choices below are **proposals to validate against current SDK capabilities, pricing, residency, retention and privacy** before implementation. The canonical cost/rollout plans mention R2/Modal while the active cloud direction includes Google Cloud Run; instrument through provider-neutral OpenTelemetry and cost adapters rather than falsely presuming a single deployed provider.

## 2. Eight coverage domains and source mapping

| Domain | Signals and drilldowns | Primary candidate |
|---|---|---|
| Customer experience | Screen flows, conversion, navigation, rage taps, consented masked replay, feedback | PostHog iOS / mobile analytics |
| Product intelligence | Activation, DAU/WAU, sessions, funnels, cohorts, retention, segment adoption, experiments | PostHog + product events |
| Video/CV quality | Capture tier, calibration, ball/pin/pose success, per-metric coverage, MAE/bias/p90, algorithm drift | First-party FastAPI pipeline metrics + validation data |
| Client/API reliability | iOS crash-free sessions, startup/freeze/battery, uploads, API error/latency p50/p95/p99 | Sentry + OTel |
| Compute/platform | Cloud Run instances, CPU/memory, cold starts, requests, timeout, queues, retries, deployment outcomes | GCP Cloud Monitoring/Logging |
| DB/storage | Supabase size, slow queries, connections/RLS failures, per-bucket bytes, orphan media, transfer, retention backlog | Supabase metrics + object-store inventory |
| FinOps | Cloud/storage/AI spend, cost per successful shot, budgets, forecast, allocated/unallocated charges | Billing exports + first-party metering |
| Security/controls | Auth anomalies, rate limiting, quotas, privileges, role changes, admin access, deletions, audit trail | Supabase/auth + application audit logs |

Add release-health/CI evidence (GitHub) across every domain.

## 3. Proposed instrumentation stack

- **PostHog:** consent-aware events, funnels/cohorts, mobile replay if compatibility and masking pass security review. Disable replay on media/camera views or other high-risk content until verified; iOS support differs from web and must be tested in native SwiftUI.
- **Sentry:** crashes, application exceptions, mobile performance and symbolication; avoid collecting video, credentials or unrestricted user attributes.
- **OpenTelemetry:** service traces/metrics, propagating correlation context through iOS uploads → FastAPI → asynchronous video job → Cloud Run → storage/DB.
- **GCP Cloud Monitoring/Logging:** runtime, queue, alerts and budget feeds; **Supabase** built-in monitoring for DB/auth/usage; native storage-provider telemetry for object data.
- **Grafana / consolidated command center:** use when native dashboards become fragmented. Start with curated deep links and operational aggregate tables rather than prematurely building a custom BI front-end.
- **GitHub Actions:** instrument deployment metadata, regression and evaluation reports with app/build/algorithm versions.

No invented assumption that all products are already installed or connected. Confirm account plan, SDK capacity, and retention at implementation.

## 4. Canonical event/trace model

Envelope for user actions and jobs: `event_name`, `occurred_at` (UTC), `environment`, `anonymous_user_id`, optional privileged-map `customer_id`, `session_id`, `app_version`, `build_number`, `device_model`, `os_version`, `feature`, `flow_step`, `status`, `error_code`, `trace_id`, `request_id`, `analysis_id`, `job_id`, `algorithm_version`, `flag_variants`, `consent_state`, `duration_ms`.

Supplement **video** events with source FPS/duration/resolution/bytes, capture pose quality (not actual frames), framing validation, calibration validity, ball track coverage, confidence/status per metric, reason codes, and named sensor reference/provenance. Supplement **cost** events with provider/product, workload, resource use, attributed cost estimate in USD, and reconciliation timestamp.

Definitions: `analysis_started` when accepted into queue; `analysis_completed` only if result delivered; `analysis_failed` categorized; `metric_unavailable` is an honest status, not always a job failure. Require schema registry/version, non-duplicative event IDs, offline buffering/retry idempotency, client/server clock handling, sample policies, and validation tests.

**Explicit exclusions:** credentials/tokens, unmasked email/phone, private form inputs, full uploaded clips, third-party bowlers' faces, unredacted session-replay frames, precise location, and raw AI prompts containing private footage or identity.

## 5. Dashboard catalogue

| Dashboard | Required widgets | Drill-down |
|---|---|---|
| 01 Executive Command Center | Live incidents, uptime, DAU/WAU, processed shots, success%, latency, spend forecast, storage, release | Link to owning specialized dashboard |
| 02 Customer Journey | Signup→first successful shot, first session, replays, abandonment, rage-tap candidates, support feedback, cohorts | Pseudonymous user timeline |
| 03 Video & AI Trust | Jobs by status/reason, coverage by metric/device/camera/FPS, calibration, track, confidence, accuracy vs reference, versions | Authorized analysis/job trace and labeled validation evidence |
| 04 App/API Performance | Crash-free sessions, client errors, upload failure, API 4xx/5xx, p50/p95/p99 latency, cold starts | Sentry trace, request logs, deployment |
| 05 Storage & DB | Volume by bucket/type/cohort, growth, orphaned files, aged media, transfer, slow queries, capacity | Bucket, query, safe retention queue |
| 06 Financial Operations | Spend provider/service/day, cost per shot/success, cost by feature/cohort, forecast vs caps, unallocated cost | Billing export ↔ workload tags |
| 07 Security & Controls | Auth failures, abuse, quota denials, feature-flag interventions, admin actions, permission failures | Restricted audit record |
| 08 Release & Regression | Version rollout and adoption, performance/error/quality/cost differences, CI eval gates | Commit, build, canary cohort |

Do not present dummy metrics as real system health. Dashboards must display last-ingested timestamp, freshness SLA, monitoring coverage, and distinct **NO DATA / NO ACCESS / HEALTHY** states.

## 6. Customer replay and support diagnostics

Glassbox-like outcome: browse pseudonymous journeys, authorized masked session replay, associated errors and successful/failed processing, version and feature flag, feedback ticket, and relevant trace. Replay must be **opt-in where appropriate**, masked by default, disabled around uploaded video and third-party capture, retention-limited, role-restricted, and auditable. Use separate explicit consent for retaining bowling-video originals for CV training/validation. `customer_id` mapping and player footage must not be exposed in broadly accessible analytics.

## 7. Video reliability and accuracy

Standardize error taxonomy: `LANE_CALIBRATION_FAILED`, `FOUL_LINE_NOT_VISIBLE`, `MULTIPLE_LANES_DETECTED`, `BALL_TRACK_LOST`, `INSUFFICIENT_FRAMES`, `PIN_DETECTION_UNREADABLE`, `BODY_KEYPOINT_CONFIDENCE_LOW`, `VIDEO_UNSUPPORTED`, `PROCESSING_TIMEOUT`, `WORKER_MEMORY_LIMIT`, `UPLOAD_FAILED`, `INTERNAL_ERROR`. Separate user-actionable guidance from internal diagnostic classification.

Track processing duration by pipeline stage; metric yield vs supported capture tier; measured errors against locked reference set and paired Ruby/Specto where present; honest unavailable-rate; false-confidence and silent-regression incidents. Release comparisons must include **accuracy and coverage**, not just uptime and speed. Sampling/ground-truth coverage and reference uncertainty prominently shown.

## 8. Storage, cost, and operational controls

Monitor bytes and transfer by user/cohort/object type; days until expiry; deletion job success; residual or orphan objects; database and object store separately. Suggested baseline policy (requires privacy/legal approval): originals deleted at 30 days unless customer explicitly opts into supported retention or validation corpus; remove derived temporary artifacts after narrower TTL; keep minimal permitted metrics independently. Verify lifecycle jobs and deletion audit trail.

FinOps: per completed video and **per successful shot** with CPU-sec/GiB-sec/GPU-sec (if applicable), egress, inference, storage and retries; distinguish estimated marginal workload cost from invoiced shared overhead. Forecast 30/60/90 days and flag sampling bias.

**Deterministic guardrails:** upload byte/duration ceilings; per-user and per-tenant daily job allowances; queue concurrency and backpressure; per-job deadline; bounded retries + dead-letter queue; rate limiting; spend soft thresholds; hard entitlement enforcement; emergency feature kill switch. Budget alerts **are not themselves spending caps**; provider-level hard caps may affect service availability. Proposed illustrative warning/action thresholds $50/$100/$150/$200/$250 month only after validating real provider economics.

## 9. Alerting, incidents and SLOs

Use `03_ENGINEERING/PERFORMANCE_RELIABILITY_SLO_PROPOSAL.md` for governing latency/availability proposals; do not silently invent competing SLOs. Alert on real user-impact symptoms first, then saturation/trend. Classify:
- **SEV1:** outage, data exposure/corruption, catastrophic billing/processing runaway → immediate push/on-call; restrict dangerous activity using preapproved fail-safe.
- **SEV2:** sustained processing/accuracy regression, widespread upload failure, rapid unexplained spend → prompt operator attention.
- **SEV3:** growing storage, localized device issues, moderate error drift → daily digest.
- **SEV4:** optimization ideas, minor friction → weekly review.

Every page requires owner, runbook, deduplication, correlation evidence, suppression for planned maintenance, escalation, and incident/postmortem links. Smoke-test both alerts and recovery.

## 10. Production readiness contract for **every** feature

No feature launches without: (1) named customer success/failure events, (2) structured error codes, (3) duration/throughput, (4) usage and cost attribution or documented N/A, (5) controlled feature flag/kill switch where relevant, (6) safe auditability and least privilege, (7) retention and privacy review, (8) dashboard owners and alerts, (9) SLO/eval regression tests, (10) rollback and customer support traceability. CI should enforce schema/tests where automated.

## 11. Delivery sequence and acceptance

**Pre-beta P0:** event taxonomy, trace IDs, Sentry, PostHog core journeys, Cloud Run/Supabase health metrics, job-level CV observability, billing exports/usage estimates, storage age inventory, caps and alerts, error taxonomy, private operational dashboard. Run fault-injection tests for invalid video, queue timeout, runaway retries, full capacity, and unauthenticated requests.

**Beta early:** richer conversion and replay (only after masking review), account-specific support timeline, per-version regression/accuracy dashboards, spend reconciliation.

**Later:** Grafana single pane if useful, anomaly detection, richer revenue economics, cross-provider chargeback, advanced automated ops recommendations.

## 12. Required implementation artifacts

`OBS-01` event contract + versioned taxonomy; `OBS-02` tracing SDK and end-to-end IDs; `OBS-03` Sentry configuration; `OBS-04` Cloud/Supabase collectors; `OBS-05` video diagnostics and ground-truth evaluation dashboard; `OBS-06` storage/billing metering; `OBS-07` caps/quota enforcement; `OBS-08` alert runbooks; `OBS-09` secure support drill-down; `OBS-10` privacy/consent/redaction tests; `OBS-11` CI feature-readiness checklist.

Integrates with `01_PRODUCT/CONTROLLED_BETA_STRATEGY_CONTEXT.md` and `03_ENGINEERING/AI_OPERATIONS_INTELLIGENCE_AGENTS_CONTEXT.md`.
