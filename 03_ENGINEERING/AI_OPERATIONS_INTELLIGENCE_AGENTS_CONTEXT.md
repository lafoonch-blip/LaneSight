# LaneSight — AI Operations & Intelligence Agents

Status: PROPOSED / PLANNING — pending owner approval
Version: 1.0
Last Updated: 2026-10-26
Owner: Shayne
Related: `01_PRODUCT/PRODUCTION_MONITORING_OBSERVABILITY_CONTEXT.md`, `01_PRODUCT/CONTROLLED_BETA_STRATEGY_CONTEXT.md`, `01_PRODUCT/BUILD_PLAN.md`, `00_CONTEXT/DECISIONS.md`

> Planning context, not an accepted DEC. GitHub is source of truth under AGENTS.md; DECISIONS.md and CURRENT_STATE.md govern on conflicts. This document creates no new accepted product decision. Numbers below are proposed gates or examples until instrumented and measured.

## 1. Operating model

Establish an **AI Operations Director** supervising seven specialized monitoring responsibilities. Use deterministic cloud alerts and scheduler/queue-driven diagnostics as the sensing layer; AI reads summarized evidence, investigates and prioritizes. Agents do not need dedicated always-on LLM processes. Outputs are **incident alerts when justified, a short daily digest, a weekly strategic report, and owner-approved GitHub issues**.

**Important status:** ChatGPT recurring automations are currently created:
- `LaneSight Daily Ops Watch`: approximately 8 AM America/New_York daily, task ID `6adff27d386481919f33d4472b91b96c`.
- `LaneSight Weekly Intelligence`: Sunday approximately 7 PM America/New_York, task ID `6adff285e6fc8191bcd323a925285503`.

Those scheduled checks are **not equivalent to a deployed 24/7 production monitoring system**. They may inspect only connected/accessible evidence (currently GitHub and potentially accessible Supabase data), must flag unknown/inaccessible sources, and cannot credibly assert PostHog/Sentry/GCP observations until read-only access/data delivery exists. Google Cloud's/incident management's native alerts will supply prompt notifications once configured.

## 2. Agent responsibility matrix

| Agent | Role and data | Proposed cadence | Output |
|---|---|---|---|
| Operations Director | Merge all agents, severity and duplicate grouping, customer impact, decisions | Daily + incident-triggered | Executive digest, action queue |
| Customer Intelligence | Product events, funnels, masked/consented replay references, feature adoption, friction, feedback | Daily | Cohort and UX findings |
| Video Quality Analyst | Job statuses, failure reasons, metric eligibility, calibration, confidence, locked-set accuracy, version | Hourly trend scan + daily investigation | Accuracy/drift alerts, CV issue |
| Production Reliability | Cloud Run, API, queues, Supabase, Sentry client crashes, deployments | Native metric checks every ~5–15 min; AI review hourly | Service incident, root-cause leads |
| Financial Controller | GCP/Supabase/object storage/AI invoices & metered usage, unit cost, forecast | Daily; native budget triggers as available | Cost anomalies, optimization |
| Security & Compliance | Auth/permission failures, unusual quotas, security audit changes, retention/deletion exceptions | Native security alerts + hourly AI triage | Restricted security incident |
| Product Optimization | Feature ROI, retention, conversion, price surveys, release experiments | Weekly | Ranked roadmap proposals |
| **Director coordination** | Provenance, deduplication, prioritization, gaps | On every report | One coherent customer-impact narrative |

Frequency is a target operating cadence, **not proof agents are deployed**. ChatGPT automations support at most hourly scheduled checks; more frequent monitoring must be implemented in infrastructure.

## 3. Data access and evidence contract

Create **read-only scoped connectors** or a small telemetry aggregator API covering: PostHog cohorts/events, Sentry issues/traces, Cloud Run monitoring/logs, Supabase metrics/storage, billing and billing exports, GitHub release/CI/issue status, and first-party CV evaluation events. Avoid broad direct credentials in prompts or messages. Normalize observations to `metric`, `window_start/end`, `value`, `unit`, `baseline`, `source`, `access_status`, `ingested_at`, `trace/correlation_ids`, `confidence`.

Mandatory reporting states: **HEALTHY WITH VERIFIED DATA**, **DEGRADED**, **NO DATA**, **STALE DATA**, **SOURCE NOT CONNECTED**, **INSUFFICIENT EVIDENCE**. Never equate a missing source or silent agent run with good health.

Privacy: use pseudonymous customer IDs and aggregate events by default; privileged ticket drill-down only as needed; no raw private recording, bystander footage, credentials, unmasked replay screenshots, or unrestricted customer profiles in LLM prompts.

## 4. Incident reasoning workflow

1. Deterministic detector receives a threshold breach, deployment regression, cost anomaly or high-signal user feedback.
2. Relevant specialist gathers time-windowed, verified data and comparable baseline; checks seasonality/sample size and telemetry freshness.
3. Correlate `trace_id`, `analysis_id`, `algorithm_version`, `release_id`, feature flags, camera/FPS and provider costs.
4. Director deduplicates related symptoms, identifies blast radius (affected users/jobs), and assigns severity.
5. Produce **facts / hypothesis / confidence / customer impact / cost impact / recommended next action / owner / evidence links**. No ungrounded numerical claims.
6. If approved by established workflow, propose or create a labeled GitHub issue with reproduction and rollback guidance.
7. Track acknowledgment/resolution and measure post-fix error, accuracy, latency, customer impact and cost.

Example hypothetical: failed video jobs go 3%→11% after a release; video specialist isolates low-rear-view calibration cases; customer specialist counts affected bowlers; cost specialist calculates wasted processing; director issues one SEV2 report with evidence and suggested rollback. Example is **not observed production data**.

## 5. Communication contract

**Critical/severe:** Cloud-native immediate notification first (approved email/push/on-call); AI can provide context afterward. A scheduled chat report is never the sole critical alert path.

**Daily ~8 AM ET:** max one-screen executive overview: service health and coverage; new incidents (severity/impacted cohort); CV quality; product friction; spend/forecast and storage; deployments; 1–3 prioritized fixes; unconnected/stale sources. Routine no-change status may be short.

**Weekly Sunday evening:** verified week-over-week active users, retention, feature usage, completion/success/error rates, accuracy/coverage by capture tier, performance, storage, budget/unit economics, security/control events, regressions, top 3–5 opportunities ranked by user trust/impact × effort × cost. Always show N/baselines/observation windows and uncertainty.

**Incident report format:** title/severity/start time, detector/source, measurable deviation, customer impact, version scope, suspected root cause vs confirmed facts, financial exposure, remediation/owner, next check, direct evidence links.

Suppress duplicates and non-actionable churn. Separate warnings from recommendations; no automatic assertion that user sentiment implies accuracy or willingness to pay.

## 6. Permissions and autonomous action policy

**Level 1 (pre-beta): Observe** telemetry and report. Read-only credentials.
**Level 2 (beta): Recommend** issue drafting/prioritization; issue creation allowed only under scoped policy and audit logging. No arbitrary repo changes.
**Level 3 (post-validation): Act** via deterministic, tested rule-based controls for quota rejection, queue pauses, retry limits, spend soft caps, and targeted feature kill switches. Require explicit owner approval for deployments, broad rollbacks, material entitlement changes, destructive file deletion, or access permission changes. Security incident response may use separately approved narrowly scoped fail-safe actions.

Agent statements must name what was **measured**, what was **inferred**, and what is **unavailable**. Evaluate prompts/actions against injection, malicious free text, false alarms, and confidential-data leakage.

## 7. Reliability of the monitoring system itself

Monitor agent jobs: schedule adherence, last-success timestamp, source freshness, API failure, token/cost consumption, retries, duplicate incidents, resolution precision, false-positive rate, and quality of human decisions. Alerts must still work when LLM provider or agent infrastructure is down.

Maintain an audit log of source queries, evidence IDs, classification, output, issue mutations, and approvals. Set limited retention on agent intermediate data and anonymize before LLM inference.

## 8. Architecture and operational cost

**Sources → telemetry/metrics + secure rollups → deterministic alert engine + scheduler → scoped specialist analysis → Director deduplication/synthesis → dashboards, notifications, GitHub.** Prefer smaller time-window summaries over feeding every event to an LLM. Event-triggered deep-dive only on anomalies; cap agent runs/tokens and report marginal AI-monitoring cost separately. Use provider-managed alerts rather than a continuously polling LLM where possible.

## 9. Staged implementation and acceptance

**Phase A, prior to beta:** finalize metrics and error taxonomy, instrument correlation IDs, wire cloud and Sentry alerting, read-only metric gateway/credentials, daily consolidated report, cost/storage coverage, secured evidence store, run simulated outages and billing spikes.

**Phase B, beta:** validate hourly CV scans, customer funnel analysis and feedback correlation, AI incident summaries, controlled GitHub issue generation, weekly business report, anomaly precision and digest quality.

**Phase C, post-beta:** anomaly baselines calibrated to larger datasets, model/version risk forecasting, richer cost projections, policy-constrained automated remediation.

**Acceptance tests:** detect genuine synthetic regressions; no alert for missing-data-as-healthy; evidence-linked summary; emergency alert works without agents; duplicate signals unify; permissions prevent changes; downstream test failures open remediation backlog; total monitoring cost stays within approved limit.

## 10. Build tasks

`AIOPS-01` read-only telemetry adapter + schema; `AIOPS-02` Director report formatter; `AIOPS-03` CV hourly scan; `AIOPS-04` service reliability integration; `AIOPS-05` daily cost/storage model; `AIOPS-06` customer intelligence aggregates; `AIOPS-07` security review and audit events; `AIOPS-08` weekly product analysis; `AIOPS-09` severity, dedup, runbook and on-call wiring; `AIOPS-10` safe GitHub ticket workflow; `AIOPS-11` agent coverage/accuracy/cost dashboard; `AIOPS-12` replayable synthetic-incident test suite.

**Source of truth:** do not overwrite accepted decisions or change historical DEC entries. Add proposed implementation items to Build Plan in a separate, version-bumped update after owner approval.
