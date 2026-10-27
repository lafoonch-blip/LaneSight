# AI Model & Recommendation Governance Strategy
Status: PROPOSED — not an accepted decision  
Version: 1.1  
Last Updated: 2026-10-26  
Authority: `00_CONTEXT/DECISIONS.md` on `dev-build-v0` (v1.43, DEC-082) and current branch `CURRENT_STATE.md` (v1.37). Confirm latest local branch before adoption.  

> Strategy proposals never override accepted DEC entries. Decisions require Shayne's approval and an append-only DEC. This file is additive, not a modification of product authority.

## Current state
Coaching is template-driven in MVP (DEC-047). Do not represent generated text as verified facts or assume autonomous agents can modify models, scoring, recommendations or customer accounts.

## Policy
Version each rule, formula and model; store input metric statuses, provenance and confidence. If required inputs are unavailable or unreliable, return `no_reliable_data` with concrete capture tip; no fabricated far-lane lane-move intelligence.

## Evaluation
Offline replay/labelled test suites across capture views and versions; monitor recommendation appropriateness, user correction, hallucinated precision, false confident moves and accessibility. Require human review of significant rule changes and an accepted DEC where product meaning changes.

## AI operations boundary
Reporting agents may summarize accessible telemetry only. No direct operational writes, cost changes, destructive data management or production deployments without explicit separate authorization.

## Risk handling
Maintain rollback of rules/service versions, auditing, version-specific defect queues and incident escalation for incorrect advice impacting trust.
