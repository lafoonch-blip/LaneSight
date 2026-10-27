# Lean Production Monitoring & Observability Strategy
Status: PROPOSED — not an accepted decision  
Version: 1.1  
Last Updated: 2026-10-26  
Authority: `00_CONTEXT/DECISIONS.md` on `dev-build-v0` (v1.43, DEC-082) and current branch `CURRENT_STATE.md` (v1.37). Confirm latest local branch before adoption.  

> Strategy proposals never override accepted DEC entries. Decisions require Shayne's approval and an append-only DEC. This file is additive, not a modification of product authority.

## MVP / friends Beta stack
- Google Cloud Run native logs/metrics, budget alarms and per-service utilization.
- Supabase built-in DB/Auth/storage health, RLS/security audit and usage.
- `analysis_jobs` as per-shot ledger (MVP-10/11): id, owner, shot vs Form, status, version, validated/error reason, duration, CPU/memory when available, cost estimate, retry/dedup, outcome. Minimize personal fields.
- Sentry **free tier proposed**, only if SDK/error integration and data policy are acceptable.

## Do not adopt by default
PostHog, OpenTelemetry, Grafana and session-replay vendors are conditional Phase-2 upgrades when Beta population, incident volume and cost justify them. Do not install invasive recordings or capture raw video in telemetry.

## Failure taxonomy
Normalize to existing DEC-061 user-visible states (`no_reliable_data`, `pins_unknown`, low confidence, etc.) plus capture-view/quality reasons. Never confuse genuine partial results with total failures, and never label data absence healthy.

## Operating dashboard
Shot analysis attempts/completed/partial/unavailable; near-field/Form coverage; CV metric validation regressions; p50/p95 end-to-end elapsed; job errors and crash rate; Supabase errors/RLS violations; estimated vs invoiced costs/1,000 shots; active infra spend vs $100 private-beta cap.

## Alerts and incident ownership
Owner-directed alerts for cross-user data exposure, sustained analyze failure, excessive cost, stuck jobs or privacy deletion problems. Early stage: manual daily/weekly checks with real accessible telemetry; no agent claims without connection.

## Data handling
Log non-identifying IDs and reason codes; do not archive customer videos, Form frame image contents, or secret tokens inside observability.
