# Business Analytics & KPI Strategy
Status: PROPOSED
Version: 1.1
Last Updated: 2026-10-26

## Funnel
Invite/awareness → signup → first successful Shot/Form analysis → second session → weekly meaningful engagement → paid intent (future). WAIB is a *proposed engagement proxy*, not a verified measure of improvement.

## Event and metric definitions
Activation is one eligible completed analysis. Quality is eligible/partial/unavailable distributions by view and version; include manually corrected outcomes. Retention uses matured D7/D30 cohorts, never new cohorts as churn. Cost monitors all-in cost per 1000 completed shots and infra/month. No hypothetical revenue or customers portrayed as actual.

## Exclusions
No staged accounts in usage, feedback or user baselines (DEC-063). Uploaded clips must not count for score/achievements (DEC-055) and duplicate uploads must be deduplicated. Separate dev/beta/live cohorts and show all denominators.

## Source-of-truth
analysis_jobs + Cloud Run/Supabase + retained feedback; optional richer analytics tools need separate decision.