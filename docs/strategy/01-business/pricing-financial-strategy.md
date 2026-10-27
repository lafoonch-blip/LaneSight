# Pricing & Financial Strategy
Status: PROPOSED — not an accepted decision  
Version: 1.1  
Last Updated: 2026-10-26  
Authority: `00_CONTEXT/DECISIONS.md` on `dev-build-v0` (v1.43, DEC-082) and current branch `CURRENT_STATE.md` (v1.37). Confirm latest local branch before adoption.  

> Strategy proposals never override accepted DEC entries. Decisions require Shayne's approval and an append-only DEC. This file is additive, not a modification of product authority.

## Decision state
**OPEN:** billable unit; prices; allowance basis; tier names; coach pricing; upgrades. Do not show customer-facing price sheets until approved. Every pricing and coaching proposal must import the same single pricing decision record.

## Measured / estimated unit economics
- Shot compute: **191 vCPU-seconds/shot measured**, ≈ **$0.005/shot** Cloud Run at current modeled list-rate basis. Measurement is CPU, estimate is price; reconcile actual effective billing, memory, requests, egress and storage before claiming all-in cost.
- Form: **≈$0.01/clip estimated**, not a validated unit cost.
- Sessions commonly contain **20–40+ shots**. The previous 2/15/40 analyses-per-month model is not appropriate and is withdrawn as a proposal.
- DEC-043 private-beta cap **≤$100 infrastructure/month** and **≤$5/1,000 analyzed shots** unit-efficiency target; watch threshold $25/1,000. Baseline Cloud Run CPU alone is ~$5/1,000, leaving no budget for ancillary costs at that target.

## Scenario arithmetic (illustrative; not prices)
| Shots per active user/month | Cloud Run CPU at $0.005/shot | Form work excluded |
|---:|---:|---|
| 100 | $0.50 | Additional |
| 250 | $1.25 | Additional |
| 500 | $2.50 | Additional |
| 1000 | $5.00 | Additional |

At $100/mo, purely theoretical CPU-only capacity is 20,000 shots; **do not** market this as actual supported capacity because storage/DB/egress/observability and Form eat the same budget.

## Proposed experiment design
Compare a monthly **shot allowance**, pooled **session-equivalent allowance** (with disclosed shot cap), and usage-based pricing. Define consumption carefully: charge once for completed accepted shot analysis, not failed uploads/retries or duplicate deduplicated jobs; handling Form independently remains open. Document grace limits and abuse protections before billing implementation.

## Single future tier matrix (template, deliberately unnamed)
| Tier ID | Display name | Monthly shot allowance | Form allowance | Monthly price | Coach seat | Status |
|---|---|---|---|---|---|---|
| T0 | OPEN | OPEN | OPEN | OPEN | OPEN | PROPOSED |
| T1 | OPEN | OPEN | OPEN | OPEN | OPEN | PROPOSED |
| T2 | OPEN | OPEN | OPEN | OPEN | OPEN | PROPOSED |

Coaching doc must reference T0/T1/T2, not invent its own tier schedule.

## Forecast and checkpoints
Model active users × shots/user × measured all-in shot cost + Form clips + DB/storage + support/vendor fees; separate paid conversion assumptions and attach ranges. Review 30/60/90-day usage cohorts and actual invoice export. No automatic spend increase over DEC-043.
