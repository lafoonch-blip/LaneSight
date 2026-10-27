# Customer Research & Product Validation Strategy
Status: PROPOSED — not an accepted decision  
Version: 1.1  
Last Updated: 2026-10-26  
Authority: `00_CONTEXT/DECISIONS.md` on `dev-build-v0` (v1.43, DEC-082) and current branch `CURRENT_STATE.md` (v1.37). Confirm latest local branch before adoption.  

> Strategy proposals never override accepted DEC entries. Decisions require Shayne's approval and an append-only DEC. This file is additive, not a modification of product authority.

## Research questions
What makes a bowler record 20–40+ practice shots? Which partial metrics are most believable/actionable? Can Form capture fit real lanes? Is the improvement narrative clearer than one-off numbers? What would coaches actually pay for?

## Founder → friends research
Observe multiple real founder sessions, invite a founder-selected number of friends, and include varied camera views, lane finishes, phones and skill levels. Proposed research mix, not Beta cohort size. Compare usability errors to algorithm failures and advice dissatisfaction.

## Instruments
Consent-based onboarding interview; first successful shot timing; 1–5 session utility rating; structured `feedback` source/tags per DEC-059; owner triage. Exclude `is_staged` accounts and uploaded duplicates from live behavior metrics per DEC-063/055.

## Decision packet
Weekly: evidence strength, verbatim anonymized themes, cohort denominator, reproducible faults, recommendation for keep/change/drop; no customer-facing runtime learning directly from feedback.

## Safeguards
Only gather information needed for hypotheses; do not retain raw bowling video and do not contact uninvolved bowlers without appropriate consent.
