# LaneSight Decision Log
Status: CANONICAL  
Version: 1.1  
Last Updated: 2026-09-27  
Owner: Shayne  
Supersedes: v1.0

Format: Decision / Why / Date / Status / Supersedes. To change a decision, add a new DEC and mark the old one `SUPERSEDED by DEC-0xx` — never edit history.

## Accepted decisions

### DEC-001 — Fixed camera before POV
**Decision:** Prove reliable measurement from stable tripod/rear video before handheld, POV or smart glasses.  
**Why:** Removes camera-motion complexity and creates a trusted reference pipeline.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
**Supersedes:** POV/smart-glasses-first MVP (archived Master Build Context v2, POV Video MVP Build Spec)

### DEC-002 — Sensor-enhanced, not sensor-dependent
**Decision:** Integrate sensor data early, but LaneSight Vision must remain useful without a sensor.  
**Why:** Broad accessibility plus better release telemetry/validation when available.  
**Date:** 2026-09-27 (recorded)  
**Status:** ACCEPTED  
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
**Status:** ACCEPTED  
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

## Superseded decisions
Record superseded DEC entries here with a pointer to their replacement.

