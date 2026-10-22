# Decisions to add — Dev Build v0 (2026-10-21/22)
Status: APPROVED BY SHAYNE in the claude.ai session; record these in `00_CONTEXT/DECISIONS.md`.
Version: 1.0
Last Updated: 2026-10-22

Claude Code: append the entries below as DEC-045…053 in the house format (**Decision / Why / Date / Status / Supersedes**). Keep the wording, and fix only the numbering if DECISIONS.md has moved on since DEC-044.

### DEC-045 — Dev Build v0 on Shayne's iPhone; free-framing capture
**Decision:**
- The first iOS build is a developer build for Shayne only. It runs against the real pipeline on his Mac, reached over Tailscale, with Supabase for auth and data.
- Its purpose:
  - test all core functionality and workflows
  - collect feasibility data on every core metric
  - capture session feedback
- Distribution: Xcode, then TestFlight internal. Bundle id `com.lanesight.app`.
- Capture is **never blocked by framing**. Bowlers record from any spot. An advisory spot check suggests a better camera position, and failed or degraded shots return the same tip.
- UI is the approved Claude Design set `02_DESIGN/dev_build_v0/`. Figma is reserved for finalized user designs.

**Why:** Test live at the lanes quickly and at ~$0 infrastructure, with honest data on what works.
**Date:** 2026-10-22 · **Status:** ACCEPTED · **Supersedes:** framing-gate behavior in DEC-033/035 for the dev build (the advisory replaces the gate).

### DEC-046 — Benchmarks and form recommendations
**Decision:**
- Four benchmark layers: L0 sourced reference → L1 delivery-style template → L2 personal baseline → L3 coach profile. Resolution order: L3 → L2 → L1 → L0.
- Delivery styles: one-handed with thumb / one-handed no thumb / two-handed. The bowler picks at setup.
- Personal baseline: 10 qualifying shots per view. For form-only clips, all Measured shots qualify.
- Self-coached target editing is not in MVP; it comes with the Coaching tab.
- Drills and cues are written by LaneSight from cited sources and reviewed by the owner.
- Elite research numbers are owner-only.
- **All rules, references, templates and thresholds are owner-only.** They are visible and editable only by Shayne, in a Rules admin with draft → tested → published → retired states and versions. They never ship to clients.
- Rules make every call; an LLM may only phrase output later. In MVP, feedback uses templates.

**Why:** Personalized, explainable advice without grading bowlers against invented ideals; the owner keeps control of the fundamentals.
**Date:** 2026-10-22 · **Status:** ACCEPTED · **Spec:** `01_PRODUCT/BENCHMARKS_AND_RECOMMENDATIONS_SPEC.md`

### DEC-047 — MVP scope answers and exit
**Decision:**
- Form Analysis P1 metrics are in MVP, labeled Best effort.
- Tripod + handheld capture in MVP; smart glasses are best effort in Beta.
- Coaching text comes from templates.
- The LaneSight Score ships provisional and labeled Beta.
- Axis tilt/rotation and PAP stay in MVP. They are populated only when calculable, otherwise blank with a reason, and their accuracy is tracked against sensor data.
- Oil patterns: a published-pattern library with scheduled refresh (see DEC-052).
- League capture: tap to record per shot.
- **MVP exit is Shayne's call.** He tests the MVP indefinitely and decides when it's ready for the friends Beta. The Stage 1–8 gates are readiness evidence, not automatic exit criteria.

**Date:** 2026-10-22 · **Status:** ACCEPTED · **Supersedes:** BUILD_PLAN "MVP exit" (private beta of 10–25 league bowlers).

### DEC-048 — Dev score formula `L-dev-0` (no pinfall)
**Decision:** For the dev build and Beta testing, `L = round(10 × (0.40·S' + 0.25·A + 0.25·C + 0.10·P'))`, where:
- S' = 0.6 × pocket% (entry board in the pocket range, 16–19 right-handed, mirrored for left) + 0.4 × the share of shots with entry angle in 4–6°
- A = DEC-031
- C = DEC-032
- P' = power from ball data: entry speed, rev rate (only when its band is within target), entry angle and ball weight, each normalized against owner-editable reference ranges and averaged. Carry is excluded.

Other rules:
- Eligibility floors: 20 / 20 / 10 / 10 shots.
- 90-day window.
- A snapshot is stored on every recompute, with the formula version and inputs.
- Labeled "Beta · dev formula".
- Weights are never silently re-balanced.

**Why:** DEC-038's S and P need pinfall and game scores, which the dev build doesn't have.
**Date:** 2026-10-22 · **Status:** ACCEPTED (dev/Beta only) · **Supersedes:** nothing; DEC-038 remains the target formula.

### DEC-049 — Shot card: target vs actual, form from clip, sensor question
**Decision:**
- The bowler enters intent (feet, arrows and breakpoint boards) on the capture screen. The shot card draws the target line against the actual line and shows the miss at each point plus the execution class. The "Did you hit your mark?" prompt is removed.
- When the bowler is in view in a Shot clip, the card shows the Form metrics that angle supports, below the ball metrics. The rest are Unavailable with a reason.
- After each shot the app asks "Was a sensor in the ball?" (No / Yes plus one of the user's own sensors) and stores it on the shot for later comparison. No sensor brand names are built into the UI.

**Date:** 2026-10-22 · **Status:** ACCEPTED

### DEC-050 — No pinfall in the dev build
**Decision:**
- No pin, strike, spare, leave or game-score features or metrics in this build.
- Pocket reads use entry board and entry angle only.
- Video pin reading stays in `lanesight-core` but isn't surfaced.

**Why:** No center score data; pinfall isn't a focus for this pass.
**Date:** 2026-10-22 · **Status:** ACCEPTED (dev build)

### DEC-051 — Score tiers, achievements and display
**Decision:**
- **Tiers:** Bronze / Silver / Gold / Platinum / Onyx (DEC-038 ranges), evaluated at session end only.
  - Demotion needs more than 15 points below the floor on 2 consecutive sessions.
  - First-time promotion: a full-screen celebration plus the Status achievement.
  - Regaining a tier: a banner.
  - Demotion: a quiet activity line.
- **Achievements:** the full engine. Launch catalog = the no-pinfall subset in SCORE_TIERS_ACHIEVEMENTS_SPEC §4, including:
  - redefined Efficiency Expert (entry angle in range)
  - new **FORM-001 Post It** and **FORM-002 Metronome**
  - score-improvement achievements
  All go live now. The rest show as "Coming later".
- **Popups:** never during recording; at most one per shot; priority tier > achievement; extras are batched into the session summary.
- **Reset:** score, tier and achievement data can be reset by the owner any time before Beta. Data is archived, then cleared.
- Achievements never affect the score (DEC-039).

**Date:** 2026-10-22 · **Status:** ACCEPTED · **Spec:** `01_PRODUCT/SCORE_TIERS_ACHIEVEMENTS_SPEC.md`

### DEC-052 — Oil pattern library
**Decision:**
- Build an oil pattern library like the ball catalog: pull an initial list of published patterns (name, length, volume, ratio, source) and refresh it on a schedule.
- Keep "House shot", "Unknown" and user-entered patterns.
- Check each source's terms before import.

**Date:** 2026-10-22 · **Status:** ACCEPTED

### DEC-053 — Session feedback after every session
**Decision:**
- Every time a session ends, a sheet asks for:
  - a 1–5 rating of the session in the app
  - optional tags: Bug, Metric looked wrong, Advice, Camera/upload, Workflow, Idea
  - free text
  - "attach diagnostics" (on by default: timings, errors, versions, shot ids)
- Skip is allowed.
- Responses are stored in `session_feedback`, included in the CSV export, and listed for owner review.

**Why:** Capture bugs and observations at the moment they happen, to drive adjustments.
**Date:** 2026-10-22 · **Status:** ACCEPTED
