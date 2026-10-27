# Data Accuracy & Validation Strategy
Status: PROPOSED — not an accepted decision  
Version: 1.1  
Last Updated: 2026-10-26  
Authority: `00_CONTEXT/DECISIONS.md` on `dev-build-v0` (v1.43, DEC-082) and current branch `CURRENT_STATE.md` (v1.37). Confirm latest local branch before adoption.  

> Strategy proposals never override accepted DEC entries. Decisions require Shayne's approval and an append-only DEC. This file is additive, not a modification of product authority.

## Non-negotiable truthfulness
Measured means supported by evidence; best effort means visibly bounded; unavailable shows no number. Per DEC-061, map `ok/measured` to MEASURED, `best_effort/low_confidence/calibrated_estimate` to BEST EFFORT, others to UNAVAILABLE. A failed video may still yield honest near-field/Form results.

## Validation matrix (proposed acceptance evidence, not auto MVP exit)
| Metric family | MVP/early Beta state | Validation method |
|---|---|---|
| Laydown, 7ft, arrows, launch | Candidate only when near-field pose solves | Labelled ground-truth near-lane markers, board residual, view stratification |
| Early speed | Candidate after reference comparison | Time-aligned independent speed/tape benchmarks, bias/p90 |
| Strike / not-strike | Best effort when deck visible | Blinded manual pin-deck labels; unreadable properly flagged |
| Form angles/checkpoints | Best effort where visible | Manually labelled pose landmarks by side/rear and occlusion class |
| Rev/axis | Do not assume reliability | Internal paired-sensor validation only; no customer pairing |
| Entry, breakpoint, late/full-lane speed | **UNAVAILABLE** | Require full Phase-2 camera protocol + ball/reference accuracy pass (DEC-065) |
| PAP | Deferred | No launch commitment |

## Evaluation design
Locked holdout split by center, lane, bowler, camera height/angle, lighting and device. Record completion/coverage, median error, p90, bias, calibrated confidence, wrong-advice incidence, regression vs baseline and capture instruction effectiveness. Label geometry independently of algorithm training.

## Failing safely
No whole-video fail when a near-field reading is valid; disable far-lane numbers and any recommendations dependent on them. DEC-061 states include repeat after strike, repeat/hit mark, pins unknown → ask, `no_reliable_data` → camera guidance, low-confidence qualified advice with user opt-in. Never propose >2-foot/1-eye board move based on one shot.

## Release evidence
Owner-facing report per app/model/rule version; links to clips only in transient test-controlled environments with explicit retention rules, never claim production video archive. Owner determines advancement (DEC-047).
