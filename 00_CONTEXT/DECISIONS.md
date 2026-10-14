# LaneSight Decision Log
Status: CANONICAL  
Version: 1.3  
Last Updated: 2026-10-14  
Owner: Shayne  
Supersedes: v1.2

Format: Decision / Why / Date / Status / Supersedes. To change a decision, add a new DEC and mark the old one `SUPERSEDED by DEC-0xx` — never edit history.

## Accepted decisions

### DEC-001 — Fixed camera before POV
**Decision:** Prove reliable measurement from stable tripod/rear video before handheld, POV or smart glasses.  
**Why:** Removes camera-motion complexity and creates a trusted reference pipeline.  
**Date:** 2026-09-27 (recorded)  
**Status:** PARTIALLY SUPERSEDED by DEC-018. Fixed camera remains the reference and validation baseline; moving-camera measurement is no longer deferred past MVP.  
**Supersedes:** POV/smart-glasses-first MVP (archived Master Build Context v2, POV Video MVP Build Spec)

### DEC-002 — Sensor-enhanced, not sensor-dependent
**Decision:** Integrate sensor data early, but LaneSight Vision must remain useful without a sensor.  
**Why:** Broad accessibility plus better release telemetry/validation when available.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED (extended by DEC-021)  
**Supersedes:** Sensor fusion as a late, partnership-only feature

### DEC-003 — Bowler Profile is the persistent core
**Decision:** All product areas attach to one durable bowler identity/profile.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** Shot/session as the top-level product object

### DEC-004 — League Mode precedes league management
**Decision:** Build recurring bowler utility during league nights before attempting secretary/center administration.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** —

### DEC-005 — Separate Execution Coach and Lane Coach
**Decision:** Execution misses and lane-reaction changes use different evidence paths.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** Single combined lane-transition recommendation (UI Spec v1)

### DEC-006 — A user “No” does not discard the shot
**Decision:** If the bowler says they missed the intended line, exclude the shot from lane-transition evidence but retain it for execution learning.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** —

### DEC-007 — Arsenal uses physical UserBall + configuration history
**Decision:** Do not treat commercial ball model as sufficient. Track drilling/layout, PAP, surface and maintenance over time.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** —

### DEC-008 — Team Lane Management is a strategic network feature
**Decision:** Permissioned teammate shots can contribute to shared lane state and team strategy.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** —

### DEC-009 — External records retain provenance
**Decision:** USBC/league/scoring metrics remain source-, season- and context-aware and are never silently blended.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** —

### DEC-010 — LaneSight remains master brand
**Decision:** Keep LaneSight for the broader platform.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** —

### DEC-011 — LS Monogram is preferred logo direction
**Decision:** Evolve away from an eye-led master mark to the LS lane/trajectory monogram.  
**Why:** Better represents a platform spanning performance, coaching, teams, leagues and centers.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** Eye-shaped logo (UI Spec v1 §2.1)

### DEC-012 — Smart glasses are a capture adapter, not the product
**Decision:** Meta/other glasses may reduce capture friction later but are not a dependency or primary identity.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED (still true under DEC-018: glasses are one input to the moving-camera pipeline)  
**Supersedes:** "Meta smart glasses may be the first capture device" (Master Build Context v2)

### DEC-013 — Bowler-first market entry
**Decision:** Win individual bowlers, deepen profiles, create weekly league utility and team network effects before selling replacement league software.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** —

### DEC-014 — Continuous tripod capture with rolling buffer in Session/League Mode
**Decision:** Session and League Mode record continuously from a fixed tripod, segment deliveries automatically, keep only the enrolled user's clips and discard other footage quickly.  
**Why:** Weekly league-night habit requires hands-free capture; intentional per-shot capture doesn't scale to a full league night.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** "Intentional shot capture only, no continuous recording" (Master Build Context v2 privacy stance)

### DEC-015 — Session-scoped multi-signal user recognition
**Decision:** Recognize the enrolled bowler per session using appearance, pose/motion, approach, handedness and ball appearance; a face signal may support but not drive matching, and identity expires unless the user opts in.  
**Why:** Needed for League Mode on a shared pair while keeping privacy defensible.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** "No facial recognition" (Master Build Context v2)

### DEC-016 — Brand palette replaces UI Spec v1 tokens
**Decision:** Midnight Navy #0B1320, Lane Blue #007BFF, Electric Blue #00D2FF, Cool Gray #A7B0BE, Ice White #F7F9FC are the working palette. UI Spec v1's dark-first layout principles (8px grid, tabular numerals, one dominant visual per screen) remain useful guidance.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** UI Spec v1 color tokens

### DEC-017 — Backend first, then UI, then cloud
**Decision:** Build the full back end (CV metrics, algorithms, scoring/stats, insights/adjustments, data model) and validate it before any UI. Then put a UI on top. Then move to cloud storage and processing so users can analyze shots instantly at the lanes.  
**Why:** The metrics are the product's credibility. A UI on top of unverified numbers creates rework and erodes trust.  
**Date:** 2026-10-14  
**Status:** ACCEPTED  
**Supersedes:** Build Plan v1.0 phase ordering, which put the iOS Shot Analyzer shell before the profile, arsenal and coaching back ends

### DEC-018 — Moving-camera measurement is MVP back-end scope
**Decision:** The same metrics must be derivable from moving video (handheld phone, head-mounted, smart glasses) by stabilizing every frame onto the lane plane. Fixed-camera video remains the reference and validation baseline.  
**Why:** Smart-glasses users never see themselves bowl. Per-frame lane-plane registration was proven on a handheld clip (380 px of camera motion, clean registration).  
**Date:** 2026-10-14  
**Status:** ACCEPTED  
**Supersedes:** DEC-001 sequencing (POV after fixed camera, post-MVP); Build Plan v1.0 P8-03/P8-04 as post-MVP items

### DEC-019 — Expanded MVP scope
**Decision:** MVP includes:
- shot metrics (speed, rev rate, loft, laydown, arrows, breakpoint board and distance, entry board and angle, pin leave)
- a virtual shot replay: trajectory, heatmap and key points
- insights and next-shot adjustments from the shot plus the pin leave
- LaneTalk-parity game stats: strike %, spare %, spare conversion by leave, opens, first-ball average, pocket % and carry
- bowler profile with ball inventory and drilling/layout
- ball selection per shot or session
- session and all-time trends
- an oil pattern library selectable at session start

Post-MVP: league integration and registration, league management, and USBC membership connection.  
**Why:** This is the minimum set that makes a shot reading actionable at the lanes and keeps the bowler's whole practice history in one place.  
**Date:** 2026-10-14  
**Status:** ACCEPTED  
**Supersedes:** The CURRENT_STATE v1.0 MVP list; Build Plan v1.0 placement of Phase 2 (profile/arsenal) and Phase 4 (coaching) after the Shot Analyzer launch

### DEC-020 — Center integrations fill gaps, but are never required
**Decision:** Assume future bowling-center and scoring-system integrations for data video cannot supply (official frame scores, pin counts, lane assignments). These go through a `ScoringAdapter`. MVP must work without them by using video pin reading plus quick manual entry.  
**Date:** 2026-10-14  
**Status:** ACCEPTED  
**Supersedes:** —

### DEC-021 — Sensor is an optional partner feed with visible variance
**Decision:** Users may pair a sensor (Ruby or others via `SensorAdapter`) to add metrics video cannot measure. Wherever both sources measure the same metric, show LaneSight vs sensor variance per shot and as a running summary.  
**Date:** 2026-10-14  
**Status:** ACCEPTED  
**Supersedes:** —

### DEC-022 — Metric definitions (from Ruby validation, 4 shots)
**Decision:**
- **Speed** = 60 ft ÷ (release → first pin impact). This matched Ruby within 0.5% on 3 of 4 shots. A speed profile along the lane is reported separately.
- **Breakpoint** = geometric: the farthest board reached by the smoothed path, plus its distance. This differs from a sensor's rotational skid → hook breakpoint, and the two are never presented as the same metric.
- **Rev rate** = lane rev rate from the ball's surface-pattern periodicity. Any sensor-equivalent factor (currently ~1.12 vs Ruby) is shown as a calibrated estimate until blind-validated.
- **Loft** = early speed × (touchdown − release).

**Why:** Each definition is reproducible from video and documented in `02_RESEARCH/VIDEO_VS_RUBY_VALIDATION.md`.  
**Date:** 2026-10-14  
**Status:** ACCEPTED (revisit after 30+ validation shots)  
**Supersedes:** —

### DEC-023 — Capture tiers and minimum recording requirements
**Decision (proposed):**
- **Hard minimum: 30 fps, 720p**, with the full lane + pins in frame. Below that, LaneSight refuses with a clear message.
- **Recommended and default: 1080p at 60 fps.**
- **≥120 fps slo-mo** is reserved for axis/PAP "deep analysis".
- **Moving-camera capture** (handheld/glasses) needs ≥60 fps for any guaranteed metric.
- Each metric's status per tier (Guaranteed / Best effort / Sensor / Unavailable) is defined in `01_PRODUCT/METRIC_CAPABILITIES.md` and enforced by `lanesight_core/capabilities.py`.

**Why:** In a degradation test (4 shots × 60/720, 30/1080, 30/720), timing-based metrics (speed, impact, pins) held at every tier. Far-end geometry (entry, late speed) and loft need 60 fps. A handheld 30 fps clip failed lane detection.  
**Date:** 2026-10-14  
**Status:** PROPOSED (awaiting Shayne's decision)  
**Supersedes:** UI Spec v1 §7 implicit single-tier assumption

## Superseded decisions
- DEC-001 — partially superseded by DEC-018 (see entry above).
