# Product Roadmap & Release Strategy
Status: PROPOSED — not an accepted decision  
Version: 1.1  
Last Updated: 2026-10-26  
Authority: `00_CONTEXT/DECISIONS.md` on `dev-build-v0` (v1.43, DEC-082) and current branch `CURRENT_STATE.md` (v1.37). Confirm latest local branch before adoption.  

> Strategy proposals never override accepted DEC entries. Decisions require Shayne's approval and an append-only DEC. This file is additive, not a modification of product authority.

## Canonical dependency
Engineering task identifiers and completed statuses remain in `01_PRODUCT/BUILD_PLAN.md` on active branch, not in this strategy. The latter can be older/internally inconsistent; latest numbered DEC wins. Never assign tasks to Claude's active branch from this proposal.

## Founder-only MVP — owner-controlled (DEC-047)
- Capture Shot or Form, Analyzing screen, result/detail, next shot, usable sessions/profile/arsenal where implemented.
- Provenance, confidence and explicit unavailable reasons required; DEC-061 no invented metrics/advice.
- Eligible **near-field** shot readings: laydown/7ft/arrows, launch and early speed, subject to real validation. Form candidate measures and strike/not-strike per throw.
- **Unavailable until Phase-2 reference validation:** entry board/angle, breakpoint, late and whole-lane speed (DEC-065). PAP deferred. No customer-facing sensor features (DEC-070).
- Form results use key frames + conditional skeletal overlays, not full playback (DEC-082). Capture can be side or rear (DEC-081).

## Friends Beta
Founder chooses start and population. Proposed emphasis: capture usability, telemetry completeness, correctness under real lighting/views, support turnaround, retention and economics. No default 60-person / three-wave plan and no auto advancement.

## Market
Consider wider onboarding, transparent commercial plans, permissioned partnerships and accessibility improvements after owner reviews evidence; no launch date asserted.

## Feature control
Every new feature proposal records user need, DEC linkage, dependencies, scope, measurable acceptance observations and rollback behavior. Do not quietly reintroduce sensor picker, entire-game scoring, background analysis or Form video player.

## Design handoff
Dev build screens live under `02_DESIGN/dev_build_v0/`; target-state UI in Figma; brand icons from approved Figma brand export, not deprecated LS monogram. Refer to latest branch AGENTS.md.
