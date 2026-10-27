# LaneSight Executive Business & Launch Strategy
Status: PROPOSED — not an accepted decision  
Version: 1.1  
Last Updated: 2026-10-26  
Authority: `00_CONTEXT/DECISIONS.md` on `dev-build-v0` (v1.43, DEC-082) and current branch `CURRENT_STATE.md` (v1.37). Confirm latest local branch before adoption.  

> Strategy proposals never override accepted DEC entries. Decisions require Shayne's approval and an append-only DEC. This file is additive, not a modification of product authority.

## Thesis
LaneSight is a video-first bowling performance intelligence and coaching platform that grows into a unified persistent bowler profile. Early differentiation must be **reliable, explainable improvement insight**, not a broad unvalidated feature catalog. Working strategic sequence: Measure → Profile → Coach → Team → Connect → Manage → Platform; later stages are directional, not commitments.

## Phase model (DEC-047)
- **Founder-only MVP:** Shayne exercises real workflows and may stay in MVP as long as he chooses; test results are evidence, never automatic exit criteria.
- **Friends Beta:** invite-only, cohort size and waves **OPEN**; optimize dependable use, privacy, support and feedback.
- **Market:** wider consumer access contingent on owner decision, appropriate legal/product preparations and demonstrated value.

## Product contract
- Shot and Form analysis are separate flows; live capture proceeds Record → blocking Analyzing → detail → close / next delivery (DEC-080/081).
- Near-field board/launch, early speed, Form and strike/not-strike are candidate customer metrics subject to evidence. Per DEC-065, entry board/angle, breakpoint and late/full-lane speed stay **UNAVAILABLE** until independent Phase-2 validation. PAP deferred.
- No customer-facing sensor experiences in MVP or Beta (DEC-070). Pairing only inside founder validation.
- Form uses key-position thumbnails, optional confidence-gated skeletal overlays; no full video playback (DEC-082).
- No automatic score/pinfall fabrication. Strike/not-strike per throw, not speculative complete game data.

## Commercial proposition
Primary initial personas: serious practice-focused league bowler, competitive amateur and coach. Sell measurable understanding of execution, reliable trends and trusted guidance; do not promise lane transition intelligence dependent on unavailable far-field metrics.

## Economics
Cloud Run us-east1 + Supabase; benchmark 191 vCPU-sec/shot ≈ $0.005 Cloud Run compute/shot at stated list-rate assumptions. Form ≈ $0.01/clip estimated; remeasure end-to-end bills. Private-beta infra cap ≤$100/month; unit-efficiency target ≤$5/1,000 shots (DEC-043). At $0.005/shot, compute **alone** reaches the unit target, so overhead requires optimization or explicit exception approved by owner. Nothing here approves one.

## Operating model
Customer support uses one retained feedback table and excludes staged accounts; maintain cost and quality review using analysis_jobs, Cloud Run/Supabase native telemetry and optionally Sentry free. Pause daily automated ops claims until telemetry is connected. Add heavier tools by measured necessity.

## Outcomes and accountability
Use verified activation (first eligible analyzed shot), weekly substantive engagement, metric coverage, correction rates, failures, cost/1,000 shots and qualitative learning. No fabricated traction baseline. Assign one owner and next checkpoint to each risk, experiment and open business question. Owner signs off phase transition.

## Decisions reserved for Shayne
Friends Beta size/waves; pricing unit, allowances and tiers; legal P0 scope; task retention at four-week review; observability additions. Proposals are reversible until approved.
