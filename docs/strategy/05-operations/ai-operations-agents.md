# AI Operations & Intelligence Agents
Status: PROPOSED — not an accepted decision  
Version: 1.1  
Last Updated: 2026-10-26  
Authority: `00_CONTEXT/DECISIONS.md` on `dev-build-v0` (v1.43, DEC-082) and current branch `CURRENT_STATE.md` (v1.37). Confirm latest local branch before adoption.  

> Strategy proposals never override accepted DEC entries. Decisions require Shayne's approval and an append-only DEC. This file is additive, not a modification of product authority.

## Principle
Agents may summarize **accessible verified data**, never hallucinate telemetry or change production state autonomously.

## Agent charter
- Reliability reviewer: analysis_jobs exceptions, DEC-061 error categories, cloud failures.
- Quality reviewer: calibration/pose coverage, confidence distribution and independent validation comparisons.
- Cost reviewer: effective Cloud Run + Supabase spend per shot, projected cap breach.
- Customer insight reviewer: non-staged retained `feedback` triage, friction and repeat use.
- Security reviewer: available RLS/security findings, unusual access where auditable.

## Scheduling state (2026-10-26)
**Daily Ops Watch is PAUSED** until telemetry is accessible. Industry opportunity watch and two weekly briefs remain active for a proposed four-week utility evaluation; this does not automatically extend monitoring coverage or schedule deletion.

## Reporting contract
Source/period/coverage, verified metrics, missing connections, change since previous period, severity, top actionable ideas, owner action and confidence. When sources are absent: NO DATA, do not pretend a check succeeded.

## Rollout
Phase 0 manual dashboards → conditional read-only agent review → eventually evidence-gated alerts. User must authorize any external writes and approve a future stack decision.
