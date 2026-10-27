# LaneSight — Controlled Beta Strategy

Status: PROPOSED / PLANNING — pending owner approval
Version: 1.0
Last Updated: 2026-10-26
Owner: Shayne
Related: `00_CONTEXT/DECISIONS.md`, `00_CONTEXT/CURRENT_STATE.md`, `01_PRODUCT/BUILD_PLAN.md`, `01_PRODUCT/ROLLOUT_STRATEGY.md`, `03_ENGINEERING/PERFORMANCE_RELIABILITY_SLO_PROPOSAL.md`

> Planning context, not an accepted DEC. GitHub is source of truth under AGENTS.md; DECISIONS.md and CURRENT_STATE.md govern on conflicts. This document creates no new accepted product decision. Numbers below are proposed gates or examples until instrumented and measured.

## 1. Mission and decision framework

Run a controlled, invitation-only beta that proves three independent values: **Know Your Shot**, **Improve Your Form**, and **Track Your Progress**. The most important outcomes are **trustworthy measurement**, **reliable core flows**, **repeat usage**, and **evidence of willingness to pay**. Do not widen access while measurement results are misleading, however strong engagement may appear.

This proposes **60 participants in three waves**, expandable to 75 if gates pass, over **8 weeks after internal dogfooding**. Existing `ROLLOUT_STRATEGY.md` describes a smaller 10–25-person private beta and alternative infrastructure assumptions; reconcile via explicit owner decision before treating either size or provider choice as committed. Native iOS/TestFlight first.

## 2. Cohort design and recruitment

| Cohort | Proposed seats | Validation purpose |
|---|---:|---|
| Competitive league bowlers | 20 | Weekly bowling, serious performance use |
| Scratch/tournament bowlers | 10 | Advanced metrics and repeatability |
| Coaches | 8 | Expert assessment; AI coaching safety/utility |
| Improvement-focused recreational bowlers | 12 | Discoverability and comprehension |
| Measurement/data testers | 5 | Paired sensor/video evidence |
| Center/industry contacts | 5 | Operational practicality, partnership signals |
| **Total** | **60** | Multiple experience levels and settings |

Recruit from **5–8 varied centers** (local Richmond first, remote next), camera angles, lighting, ball styles, FPS/device configurations, and experience levels. Collect application data: bowling background and goals, device/OS, bowling location type, sensor availability, willingness to record, permission preferences, expected session cadence. Selection must not depend on willingness to share identifiable raw video. Avoid recruiting exclusively expert friends who already know the metrics.

## 3. Rollout and gated schedule

| Timing | Participants | Primary purpose | Advancement requirement |
|---|---:|---|---|
| Weeks -2–0 preparation | Internal | Regression dataset, supported-camera guide, consent, TestFlight, dashboards, incident runbooks | Telemetry and safeguards functioning; no critical blocking defects |
| Weeks 1–2, Wave 1 | First 15 | Technical/measurement quality; paired reference sessions | Acceptable validated accuracy, failure messages, processing reliability |
| Weeks 3–4, Wave 2 | Add 20 (35 total) | Onboarding, workflow comprehension, coaching usefulness | Usability and stability gates met |
| Weeks 5–6, Wave 3 | Add 25 (60 total) | Retention, cost under load, segment behavior | Quality remains stable under expanded load |
| Weeks 7–8, evaluation | Existing cohort | Follow-up, price research, exit decision | Formal green/yellow/red assessment |

If a wave fails, pause invitations and fix problems; do not silently relax the gates. Refresh the calendar after the product passes internal accuracy and reliability checks.

## 4. Proposed success scorecard

- **Accuracy:** ≥90% of *eligible reported metrics* inside separately defined, independently verified per-metric tolerances. Use existing locked-set Stage 1 gates from `BUILD_PLAN.md` (e.g., speed ±0.5 mph, path/entry ≤1 board median, rev ±30 rpm where supported, strike/non-strike ≥95%) unless superseded by a documented accepted decision. Record MAE, bias, p90, calibration rates, coverage, and reference provenance. The blanket 90% figure does *not* replace per-metric gates.
- **Reliability:** ≥95% valid supported videos processed successfully, ≥99.5% crash-free app sessions, ≥85% initial-session flow completed without support. Distinguish unsupported input, honest unavailable metric, user cancellation, technical failure, and bad numeric output.
- **Engagement:** ≥60% of activated testers finish ≥3 sessions; ≥50% of activated return at week 4; measure enrollment vs activation denominators.
- **Value:** ≥75% of surveyed participants report better understanding of their game; ≥40% would be very disappointed without the product; stratify by feature/cohort and report survey N.
- **Commercial discovery:** ≥30% express willingness to pay (directional only); separately measure credible commitment/pricing behavior.
- **Economics:** measured per-successful-video/shot cost, p50/p95 analysis latency, storage and egress; budget thresholds established and respected.

These are proposed targets, not observed results or external benchmarks.

## 5. Beta product scope

**P0 enabled (only when technically validated):** login/profile, arsenal, guided supported-camera setup, video record/import, shot and available form metrics with uncertainty/unavailable reasons, 0–1000 LaneSight Score with its existing formula and eligibility rules, shot/session stats and trends, Performance Lab flows, grounded actionable recommendations, feedback/report issue, privacy/consent and deletion controls.

**P0 operational scope:** usage/event telemetry, error and performance tracking, pipeline health, per-video job diagnostics, feature flags/kill switches, storage/compute budgets, quotas, admin access/audit logs, raw-video retention jobs, consent-aware validation-data intake.

**Constrained in beta:** start with validated camera positions rather than arbitrary angles; label experimental measurements visibly; AI coaching cannot recommend precise adjustments from uncertain evidence; coach participation uses basic permissioned report review and comments rather than a full professional product.

**Defer unless already stable and explicitly approved:** PBA comparison (disabled preview tile may remain), center/scoring feeds, broad sensor marketplace, smart-glasses rollout, social competitions, complex coach management, subscriptions. Existing accepted moving-camera back-end MVP scope remains in force; deferral here refers to **beta enrollment exposure**, not rewriting DEC-018.

## 6. Data collection and experiment design

**Measurement & ML validation:** raw original (opt-in), capture configuration, frame timestamps and encoding, supported-view quality checks, lane calibration landmarks and reprojection residuals, track coverage, event timing, detection confidence, per-metric value/status/precision/provenance, reference Ruby/Specto/etc. with matching confidence, algorithm version and feature flags, reviewer annotations and known failure classes. Create a permissioned, curated locked dataset representing success and edge cases. Provide separate opt-in for long-term model-validation retention.

**Product events:** `signup_completed`, `onboarding_completed`, `ball_added`, `capture_setup_started`, `capture_quality_failed`, `recording_started`, `upload_started/completed/failed`, `analysis_requested/completed/failed`, `shot_viewed`, `form_viewed`, `recommendation_viewed/applied/rejected`, `session_completed`, `stats_viewed`, `feedback_submitted`, `return_session_started`, `account_data_deleted`. Use common pseudonymous IDs, timestamps, device/app version, and correlation IDs as defined in the observability doc. Avoid sensitive free-text/video/frame content in analytics.

**Feedback:** one-tap in shot, form, session, and settings; ask accuracy, comprehensibility, usefulness, missing capability; short post-session prompt; 3-session evaluation; final value/pricing survey; 10–15 targeted qualitative interviews. Never infer numerical accuracy solely from subjective feedback.

**Technical & commercial:** errors and crash trails, time-to-result p50/p95, memory/battery/upload reliability by iOS device and recording settings, cloud compute seconds, storage retained, provider charges, price sensitivity, coach utility, and replacement-product usage.

## 7. Beta-specific UX requirements

- Founding Beta onboarding: supported recording modes, experimental features, expectations, privacy choices, reporting, and incentives.
- Small BETA badge; clearly defined validated / estimated / unavailable result states (not uncalibrated green confidence labels).
- Guided camera positioning, lane and foul-line visibility, video quality preflight, explain unsupported inputs before paid analysis.
- Contextual report-issue action captures authorized diagnostics and analysis correlation ID.
- Optional beta progress badge: sessions, shots, issues, milestones; never reward excessive uploads or submission of personal media.

## 8. Founding member rewards and coach advisory track

Beta access free. Proposed milestones for **3 months future premium access**: ≥4 sessions, ≥30 shots, ≥2 substantive reports, final survey. Extra 6 months for strong contributors; 12 months for top 5–10; terms start when premium launches and must be disclosed. Founding badge and early access; optional affordable bowling-specific giveaway. No general lifetime-free promise or incentives for positive feedback.

Coach subgroup (5–8): validate measurements versus live observation; assess approach/form analysis, recommendation appropriateness, benchmark needs, shareable summaries, comment workflow, and customer willingness to share with a coach. Require explicit permissioned sharing and revocation; do not treat coach findings as reference sensor truth.

## 9. Beta operations and decision rights

TestFlight invitation and build expiry management; admin roster in Supabase (least privilege); in-app feedback to triaged GitHub issue; private opt-in community; weekly concise release notes, biweekly feedback pulse, final cohort assessment. Daily production health and weekly intelligence report via the AI Operations plan, with clear data-access caveats.

A launch review must approve: measurement gate, security/privacy, support readiness, cost/quotas, retention/deletion proof, minimum core journey, and economics. Exit categories: **GREEN** public-launch readiness, **YELLOW** extend limited beta with specific remediation, **RED** rework trust or experience fundamentals. No public launch when numerically misleading metrics remain unresolved.

## 10. Workstream backlog / owners

- BETA-01 accuracy spec and locked reference dataset (CV).
- BETA-02 capture guidance/preflight and trust/error states (iOS/CV).
- BETA-03 instrument funnel, session, metric coverage, cost telemetry (iOS/backend).
- BETA-04 opt-in, privacy policy, recording/third-party safeguards, deletion verification (product/legal).
- BETA-05 flags, job quotas, budget alarms, incident runbooks (backend/ops).
- BETA-06 TestFlight, applications, wave-selection rubric, onboarding (product).
- BETA-07 in-app feedback, survey, coach reviews (product).
- BETA-08 pre/post metrics, pricing evidence, exit report (product/ops).

Dependencies: `01_PRODUCT/PRODUCTION_MONITORING_OBSERVABILITY_CONTEXT.md` and `03_ENGINEERING/AI_OPERATIONS_INTELLIGENCE_AGENTS_CONTEXT.md`.
