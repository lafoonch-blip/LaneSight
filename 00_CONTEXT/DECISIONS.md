# LaneSight Decision Log
Status: CANONICAL  
Version: 1.16  
Last Updated: 2026-10-19  
Owner: Shayne  
Supersedes: v1.15

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
**Status:** PROPOSED. The default frame rate is SUPERSEDED by DEC-028 (highest supported, targeting 120 fps). The 30 fps / 720p minimum and the moving-camera ≥60 fps rule remain proposed.  
**Supersedes:** UI Spec v1 §7 implicit single-tier assumption

### DEC-025 — GitHub repo is the source of truth for context docs
**Decision:** The LaneSight context and product docs live in GitHub `lafoonch-blip/LaneSight` (`main`), at the same paths as before (`00_CONTEXT/`, `01_PRODUCT/`, `02_RESEARCH/`, `03_ENGINEERING/`). All edits happen there. The Google Drive LaneSight folder and the claude.ai LaneSight Project are read-only mirrors, re-synced after each change. `AGENTS.md` at the repo root tells any AI assistant how to read and update the docs.  
**Why:** Claude and ChatGPT both need the same context. One editable copy prevents the two tools from drifting apart.  
**Date:** 2026-10-14  
**Status:** ACCEPTED  
**Supersedes:** The claude.ai Project as the only home of the docs

### DEC-026 — Pin results are read from video, never guessed
**Decision:** The pin leave / strike comes only from reading the settled deck in the video. When the deck cannot be read — the bowler steps into frame and blocks it, or the clip ends before the pins settle — the result is reported **unreadable** (with the reason), not a strike or an inferred leave. Occlusion is detected by comparing the static masking unit above the pins before vs after impact (a blocked deck drops the correlation far below a clean one). Unreadable shots are excluded from strike %, open %, carry % and the game sheet, and the bowler can record the real result with Fix pins. No recommendation or stat is ever built on a guessed pin result.  
**Why:** A confident wrong result is worse than "couldn't read it." LaneSight's value is trustworthy numbers; a light/flat shot that reads as a strike because the pins were hidden would mislead the bowler and corrupt the session stats.  
**Date:** 2026-10-15  
**Status:** ACCEPTED  
**Supersedes:** —

### DEC-027 — Rev rate is reported unavailable when the spin period can't be read
**Decision:** The video rev rate comes only from a clear surface-pattern periodicity inside the 4–10 Hz search band. When no period is found, the search's best match slides to the edge of the band and `60 ÷ period` returns the band's ceiling (600 lane-rpm → ~672 sensor-equivalent) or floor — a wall value, not a measurement. Those are detected (the peak lands on the search rail) and reported **unavailable** with a reason, never the rail value. Confidence alone does not gate this: a correct 448-rpm read scored lower confidence than a failed 672, so the rail position is the signal.  
**Why:** Same principle as DEC-026 for pins — a confident wrong number is worse than "couldn't read it." Three live-session shots (IMG_8810/8812/8817) all reported exactly ~672 vs Ruby's ~400; shipping that as a reading would corrupt rev consistency and any advice built on it.  
**Date:** 2026-10-15  
**Status:** ACCEPTED  
**Supersedes:** —

### DEC-028 — In-app capture defaults to the highest supported frame rate; metrics report capture-adaptive precision
**Decision:** When the live app records a throw, it captures at the highest frame rate the phone supports, targeting 120 fps (falling back to 60, then the DEC-023 minimum of 30). Every metric's reported precision is **derived from the actual capture** — frame rate, camera motion, how much of the shot was tracked — not a fixed figure. Rev rate is the first instance: its uncertainty band is the frame-lag quantum `rev² / (60·fps)`, so it reports ~±40 rpm at 60 fps, ~±20 at 120, ~±10 at 240, automatically tightening on better video. The same principle extends to axis/PAP (≥120 fps) and to moving-camera/glasses capture (precision widens with camera motion and partial framing).
**Why:** Users bring varying phones and film from varying positions; the engine must adapt to the video it's given rather than assume one tier. Honest, capture-aware precision keeps a sensor-less reading trustworthy (DEC-002, DEC-026/027) and makes the accuracy of resolution-limited metrics (rev now, axis later) a function of capture quality we can improve by defaulting to slo-mo.
**Date:** 2026-10-16
**Status:** ACCEPTED (extends DEC-023 capture tiers)
**Supersedes:** —

### DEC-029 — The app is native SwiftUI; capture via AVFoundation; backend FastAPI + Supabase
**Decision:** The LaneSight app is built **native SwiftUI in Xcode** (iOS-first). Camera capture uses **AVFoundation** with locked 60 fps, 240 fps slo-mo, and **real per-frame timestamps** (presentation timestamps, not a nominal fps tag) — the capture requirement that makes the metrics and their capture-adaptive precision (DEC-028) trustworthy. The app is first a **capture + upload client** to the **FastAPI** CV service (on the Mac at first, then cloud) and persists through **Supabase** (Swift SDK); on-device CV via **Core ML / Vision** may follow later as a latency optimization, not v1. The Xcode project lives in the repo next to `lanesight-core` (monorepo). Figma Dev Mode / connector feeds frames and tokens; colors map to the DEC-016 palette as SwiftUI color assets. Distribution: free provisioning for solo-device dev (7-day expiry) → **TestFlight** (Apple Developer Program, $99/yr) for persistent builds and beta bowlers.
**Why:** LaneSight is iOS-first and its core is precise camera capture (fps lock, slo-mo, frame timestamps); native AVFoundation gives direct control without a cross-platform bridge. The **`ShotRecord` JSON contract (schema v1, `SCHEMA_VERSION`) is the app↔service seam** and stays versioned so the app and the CV service evolve independently. The service reuses `core.analyze_clip` as its analysis entry; today's `lanesight_runner` is a dev dashboard, not the app API.
**Date:** 2026-10-16
**Status:** ACCEPTED (realizes Stage 7 UI + Stage 8 cloud; capture per DEC-028, brand per DEC-016)
**Supersedes:** —

### DEC-030 — Headline ball speed is RELEASE speed (foul→arrows); refines DEC-022
**Decision:** The headline `ball_speed` is the **release speed** — the ball's velocity over the skid (foul line → arrows, ~4–24 ft), what the bowler imparts — not the full-lane average. The 60 ft foul→pins **average** (the old DEC-022 definition) is kept as a secondary metric `speed_avg`. Release speed needs only the reliable front half of the track, so unlike a fixed 60 ft ÷ interval it is immune to back-half tracking fade (which was inflating speed up to ~12 % when the track stopped short of the pins). This matches the bowling convention (release = the number bowlers quote; average varies with ball/friction).
**Why:** Validated on the 21-clip live session vs Ruby (10–11 matched): switching to release speed moved bias +1.10 → −0.36 mph and removed the advice-flipping +2–4 mph over-reads, while needing only the front half of the track (robust for shaky/far/glasses capture, DEC-028). Source of the insight: a well-known community "Speed & Revs calculator" (Reddit) that separates release speed (15 ft, `10.22727·fps/frames`) from average (60 ft, `40.909·fps/frames`) and prefers release. A residual ~1 mph MAE + under-reads on well-tracked clips trace to a ~6 % near-field Z-scale in the lane homography — a geometry-calibration issue affecting all speed definitions, to settle against Specto.
**Date:** 2026-10-16
**Status:** ACCEPTED (refines DEC-022 Speed; revisit with Specto ground truth)
**Supersedes:** DEC-022 Speed definition (release vs average split)

### DEC-031 — Accuracy = execution against intent at the arrows and breakpoint
**Decision:** Accuracy measures how closely the actual shot follows the bowler's intended line. It never uses pinfall or strike results.
- Arrow error = |actual arrow board − intended arrow board|. Breakpoint error = |actual breakpoint board − intended breakpoint board| (geometric breakpoint, DEC-022).
- Arrow score = 100 × max(0, 1 − min(arrow error ÷ 5, 1)). Breakpoint score = 100 × max(0, 1 − min(breakpoint error ÷ 8, 1)).
- **Accuracy = round(0.60 × arrow score + 0.40 × breakpoint score).** Arrows weigh more because breakpoint also depends on lane reaction.
- On-target indicator: arrows within 1 board, breakpoint within 2 boards. The continuous score still reflects the size of the miss.
- No intended line recorded → show "—" with "Set a target line to measure accuracy". Never show 0, which would imply a measured, completely inaccurate shot.
- Low confidence on either input → "Low confidence" or "Unavailable" with the reason; the shot is excluded from the session average.
- A session average uses only valid, measured shots with known intent.

**Why:** Accuracy is now a primary metric (DEC-035) and needs a reproducible definition that separates execution from lane reaction (DEC-005).  
**Date:** 2026-10-16  
**Status:** ACCEPTED. The 5- and 8-board scales and the 60/40 weights are starting parameters, to be validated against annotated shots before release. Display is gated by DEC-034.  
**Supersedes:** —

### DEC-032 — Consistency = robust spread of repeated shots, independent of intent
**Decision:** Consistency measures how repeatable the bowler's shots are around their own center, not their distance from the target. A bowler can be very consistent while repeatedly missing.
- Components and target spread: speed ≤0.5 mph, rev rate ≤30 rpm, actual arrow board ≤1 board, actual breakpoint board ≤2 boards.
- Spread = robust standard deviation = 1.4826 × median absolute deviation, so one outlier has little effect.
- Component score = 100 × max(0, 1 − spread ÷ (3 × target)). Overall = equal-weight average of the available components. An unavailable or too-imprecise component is excluded (never treated as zero spread) and the reduced coverage is shown.
- Window: the 10 most recent comparable shots (same ball configuration and same intended line). Changing ball or intentionally moving the target starts a new segment.
- Fewer than 5 valid shots → "Building consistency". 5–9 shots → provisional. 10 → normal rolling score.
- Rev rate is excluded when its capture-adaptive uncertainty (DEC-028) exceeds the 30 rpm target (e.g. ~±40 rpm at 60 fps).

**Why:** Consistency is a primary metric (DEC-035) and must stay independent of Accuracy (DEC-031) so the two tell the bowler different things.  
**Date:** 2026-10-16  
**Status:** ACCEPTED (target spreads and weights provisional until validated). Display gated by DEC-034.  
**Supersedes:** —

### DEC-033 — MVP analysis runs server-side, staged and asynchronous
**Decision:** Extends DEC-029.
- **iPhone:** captures with AVFoundation and real frame timestamps (DEC-028), checks framing and capture quality, uploads the shot to the active session, and shows processing status and results as they arrive.
- **Server:** runs the full CV pipeline via FastAPI (`core.analyze_clip`): tracking, trajectory, metrics, pin reading. Results are stored with source, confidence and algorithm version.
- **Persistence:** Supabase for auth and structured data; object storage for video; analysis as asynchronous jobs, not one long request.
- **Staged results:** a fast pass returns the first reliable results, target ≤30 s; deeper metrics (rev rate, loft) follow in the background. The 30 s target is an engineering requirement, not yet demonstrated (the pipeline takes minutes per clip today). Nothing is fabricated to meet it; a metric that isn't ready or can't be measured says so.
- **Hosting:** the Mac service during development; cloud with queued jobs and controlled scaling for external beta. Benchmark CPU hosting (processing time, upload size, storage) on the validation set before committing to GPU.

**Why:** Keeps the phone a capture client while the CV pipeline is still changing, and makes cost and latency decisions on measured evidence.  
**Date:** 2026-10-16  
**Status:** ACCEPTED  
**Supersedes:** —

### DEC-034 — Metric launch bar
**Decision:** No public beta advertises a core metric as validated until it passes on the locked validation set (Seed Dataset + Specto where appropriate):

| Requirement | Gate |
|---|---|
| Ball speed | ±0.5 mph |
| Trajectory / board positions | median ≤1 board |
| Entry board | median ≤1 board |
| Strike / non-strike | ≥95% on readable decks |
| Supported clips processed | ≥90% without manual repair |
| Failures | every unsupported or failed measurement shows an explicit failure or unavailable state |

Report bias and error distributions, not only averages.

**Accuracy and Consistency** are shown as validated only after their inputs pass these gates and the derived score is itself validated. Until then they carry a provisional / Best effort label.

**May ship as Best effort** (always with source, confidence and an honest unavailable state): rev rate with its uncertainty band (validate against Ruby); Power as a labeled estimate (definition pending DEC-024); loft and launch angle where the capture supports them; axis tilt, rotation and PAP from a sensor, video values unavailable until validated. Pin leave only when the deck is readable (DEC-026).

**Current status:** gate not yet passed. The live-session evaluation in CURRENT_STATE reported 57% clip completion and rev rate resolution-limited at 60 fps; speed bias improved after DEC-030 but still needs Specto ground truth.  
**Why:** The metrics are the product's credibility (DEC-017).  
**Date:** 2026-10-16  
**Status:** ACCEPTED  
**Supersedes:** —

### DEC-035 — MVP app scope and screen set (Figma, 2026-10-16)
**Decision:**
- **Practice is the only session type in MVP.** League and Tournament session types, leagues, tournaments, coaching and USBC are hidden (not shown as disabled controls).
- **Primary metric hierarchy everywhere:** Rev Rate · Speed · Accuracy · Consistency. Active Session's second row: Breakpoint · Strike % · Power · Entry Angle. Game stats (spare %, pocket %, first-ball average…) are secondary.
- **Per-shot capture:** the bowler taps to record and stop each shot. Continuous capture / League Mode (DEC-014) stays post-MVP.
- **No Session Summary screen.** Ending a session saves it and returns to the Sessions tab; a completed session opens read-only.
- **Post-MVP:** shot replay video ("Play Shot Replay") and importing clips from Photos. The static shot view (simulated lane with target vs actual path, key points and the selected oil pattern as a reference) stays in MVP.
- **Screen inventory:** Figma file "Lanesight – Product UX – Design", page "01 — Home & Foundation": original session screens, MVP · Profile management (P1–P10), MVP · Stats (S1–S4), MVP · Sessions (X1–X2), MVP · Session flow & states (F1–F8), MVP · Empty states & permissions (E1–E5).

**Why:** Locks the reduced MVP agreed during the Figma pass so development and the docs match the screens.  
**Date:** 2026-10-16  
**Status:** ACCEPTED; Photos import partially SUPERSEDED by DEC-043 (upload is MVP)  
**Supersedes:** DEC-019 in part (video replay deferred; session types reduced to Practice); FEATURE_REVIEW §2.7 session types

### DEC-036 — Far-lane track recovery; headline speed reverts to the 60 ft average (supersedes DEC-030)
**Decision:** The tracker now recovers the back half of the ball path (`extend_forward`): the ball stays detected near the pins (blobs exist to ~61 ft), but on trim-degraded stabilisation the small far ball jitters and the RANSAC refine / trailing-segment trim dropped it, stopping the track ~6 ft short. `extend_forward` walks forward through those dropped far candidates along the fitted trajectory. With the ball reaching the pins, the impact anchor sits at the true 59.44 ft (not mid-lane), so the **60 ft foul→pins average is accurate again and is the headline `ball_speed`** — reverting DEC-030's release-speed workaround. The skid/front-half speed stays as a secondary `speed_release`.
**Why:** DEC-030 switched the headline to release speed because a short back-half track inflated the 60 ft average; `extend_forward` fixes that at the source. Validated vs Ruby (live session): `ball_speed` MAE 0.83 (≈0.35 excluding the corrupted IMG_8815 and geometry-outlier IMG_8819), **entry board recovered** (was unavailable) and **entry angle corrected** (implausible ~1.4° → realistic 3.8–5.6°) — directly required for the new primary Accuracy metric (DEC-031, arrow + breakpoint) and the DEC-034 entry-board gate. `speed_release` reads ~9 % low from a near-field homography Z-scale residual; which definition is ultimately "correct" is settled against Specto. On capture where the back half can't be recovered, the >30 mph scale-sanity guard still fails the shot honestly rather than emitting an inflated speed.
**Date:** 2026-10-16
**Status:** ACCEPTED (headline revisited with Specto ground truth, alongside the near-field Z-scale)
**Supersedes:** DEC-030 (release-speed headline; release is now the secondary `speed_release`)

### DEC-024 — "Power" becomes Impact Energy: translational kinetic energy at lane entry
**Decision:** The metric shown as "Power" is renamed **Impact Energy** (unit: joules), because power is energy per unit time (watts) and that is not what is measured.
- **E = ½ · m · v²**, where m = ball mass in kg from the user's selected ball weight (lb × 0.45359), and v = measured **entry speed** in m/s (mph × 0.44704) — the late/pocket speed, not the headline ball speed (the 60 ft average, DEC-036).
- Example: a 15 lb ball (6.80 kg) entering at 15.4 mph (6.88 m/s) → ~161 J. At 17.5 mph it would be ~208 J; using the slower entry speed is what makes it an impact value.
- Calculated only when the ball weight is known and entry speed is measured with sufficient confidence; otherwise **unavailable** with the reason. Shown as Best effort until entry speed passes validation (DEC-034).
- Info text: translational kinetic energy only. It ignores rotational energy and is not a prediction of strikes or carry.

**Why:** A simple, physically defensible number that helps compare balls and speeds, built from inputs LaneSight already has.  
**Date:** 2026-10-16  
**Status:** ACCEPTED  
**Supersedes:** "Power" as proposed in `01_PRODUCT/FEATURE_REVIEW.md`

### DEC-037 — LaneSight Score: 0–1,000 personal performance index
**Decision:** Home's LaneSight Score is computed, never assigned.
- **Scoring Performance index S** = 0.50 × (average game ÷ 300 × 100) + 0.25 × strike % + 0.25 × spare conversion % (percentages as points, e.g. 62).
- **LaneSight Score L = 10 × (0.50·S + 0.25·A + 0.25·C)**, where A = Accuracy (DEC-031) and C = Consistency (DEC-032), each 0–100. L ranges 0–1,000.
- Worked example: average 200, strike 40 %, spare conversion 70 %, A = 85, C = 80 → S = 60.83, **L = 717**. (The draft example's 697 was an arithmetic slip.)
- Shown only with at least 10 completed games with readable or corrected results, 30 valid shots with recorded intent (for A), 10 comparable shots (for C), and sufficient measurement confidence. Until then: "Building your LaneSight Score".
- If any component is unavailable the whole score is unavailable; weights are never silently re-balanced, so scores stay comparable over time.
- Trend: rolling 90-day score vs the preceding 90 days; the Home delta is that calculated change.
- It is a personal index, not a percentile or ranking against other bowlers.

**Why:** A summary number that rewards scoring, execution and repeatability together and gives bowlers a reason to come back, without fabricated values.  
**Date:** 2026-10-16  
**Status:** SUPERSEDED by DEC-038 for the overall composite formula and eligibility. Historical 50/25/25 formula retained here; never use it for the new four-pillar score. DEC-031 and DEC-032 component definitions remain current.  
**Supersedes:** —

### DEC-038 — LaneSight Score four-pillar model and tier presentation
**Decision:** Replace DEC-037's three-pillar composite with the agreed four-pillar design: **L = 10 × (0.40·S + 0.25·A + 0.25·C + 0.10·P)**, where S = Scoring Performance, A = intent-based Accuracy (DEC-031), C = delivery Consistency (DEC-032), and P = **Power & Carry composite**, each normalized to 0–100. L is rounded to an integer in [0, 1000]. Keep the DEC-037 Performance *subformula* as the provisional S definition until separately superseded: `S = 0.50·(average_game/300×100) + 0.25·strike% + 0.25·spare_conversion%`. Preserve DEC-031/032 component formulas, limitations and confidence gating.

**Critical distinction:** The user-facing `Power & Carry` pillar **is not** DEC-024 `Impact Energy` (joules). Impact Energy is a physical input/diagnostic, not a normalized 0–100 skill score. The exact P normalization (effective energy, pocket/carry behavior, and difficulty adjustments) is **not yet defined or validated**. Do not normalize joules ad hoc or silently set P=0 or redistribute its 10%; **the new full L is SPEC-ONLY / unavailable until P is defined, calibrated and all four pillars are available and validated**. Component scores may be displayed individually with proper provisional status. Existing DEC-037 worked example L=717 is historical, not valid under this four-pillar formula.

**Eligibility & time:** rolling 90-day scoring history; compare with previous 90 days only where both complete windows meet eligibility; start with DEC-037 floors (≥10 completed games, ≥30 intent-labeled valid shots, ≥10 comparable shots), plus sufficient qualifying data for P once established. Never fabricate values for missing game/shot data; no silent reweighting. Standard (score-result-based) vs Advanced (shot-telemetry-enhanced) **are product goals, not currently calibrated interchangeable formulas**; do not issue comparable numeric L from the Standard-only subset until an evidence-based calibration is separately approved. Show Provisional / Building / Unavailable with reason; distinguish measured, estimated and verified.

**Tiers (working thresholds; not validated against populations):** Bronze 0–399, Silver 400–549, Gold 550–699, Platinum 700–849, Onyx 850–1000. Tiers apply to the **overall** eligible L, not a session result. Session Score may use 0–1000 and the same pillar intent but requires its own approved aggregation/gates; no tier promotion from one session. Tiers reflect an absolute scale; peer percentiles are separate and must never be invented. Home hero shows numeric L, badge/tier, 90-day delta, and next-tier progression. Directly underneath, show four component tiles: Performance (40%), Accuracy (25%), Consistency (25%), Power & Carry (10%), with individual values or explicit unavailable states.

**Why:** A recognizable score and tier provide long-term identity; execution and effective delivery augment conventional scoring. Incomplete inputs must not cause higher scores for owners of better sensors.
**Date:** 2026-10-18
**Status:** ACCEPTED PRODUCT SPEC; all composite scores SPEC-ONLY, weights and tier cutoffs provisional pending real-world validation and P-definition DEC.
**Supersedes:** DEC-037 overall weighting (50/25/25), not DEC-037 S subformula, minimum baseline guidance or the DEC-031/032 component definitions.

### DEC-039 — Achievements independent of LaneSight Score
**Decision:** Achievements award permanent, non-scoring accomplishments. Unlocking or progressing an achievement must **never** affect LaneSight Score, individual score pillars or tiers. Track structured definitions, progress, unlock history, source evidence, quality/verification and notifications. Display in Profile → Achievements: earned showcase (up to 3 pinned earned badges), up to 3 pinned goals, In Progress (nearest relevant goals), categorized Collection, and individual detail/progress. First verified unlock per achievement **level** creates exactly one celebratory in-app pop-up and exactly one Recent Activity record; subsequent repeats may increase a separate occurrence count but do not replay first-unlock celebration. Larger events (300, 800) may use elevated treatment. Defer notification until results are finalized; deduplicate by user + achievement + level and source event; handle corrected scores with transparent revocation/reconciliation policy. Historical imports require provenance and eligibility.

**Achievement rule types:** single-game high; three-game-series high; consecutive strikes/spares/frames; cumulative shot/session counters; rolling-period improvement vs qualifying baseline; intent-qualified accuracy; comparable-shot spread; competition-result verified milestones; LaneSight tier first reached. Show best-to-date vs live streak separately; never treat a series best as additive progress. An achievement that lacks qualified data is **unavailable / not trackable**, not 0% or failed. Define a meaningful minimum sample and quality gate per rule. Tier badges belong to LaneSight Score; achievements use separate collection/level visual language.

**Launch:** activate only rules fed by supported, sufficiently verified inputs. Scoring/core streak/onboarding milestones first; advanced accuracy/consistency next; league/tournament achievements when official/verified event records exist (DEC-035 Practice-only MVP). Full proposed catalog and exact draft criteria live in `01_PRODUCT/ACHIEVEMENTS.md`; these thresholds are **product proposals** until validation, not measured or code-implemented.

**Why:** Celebrate measurable milestones and encourage engagement without distorting the skill index or rewarding missing data.
**Date:** 2026-10-18
**Status:** ACCEPTED FEATURE SPEC; implementation NOT STARTED; individual achievement thresholds/provisional gates require validation.
**Supersedes:** —


### DEC-040 — Performance Lab, dual capture modes and coaching
**Decision:** LaneSight is a serious-bowler performance metrics and statistics platform focused on understanding the entire game and improving performance. Performance Lab is the core analytical experience, with **Shot Analysis** (lane/ball/pin-facing video) and **Form Analysis** (bowler/approach-facing video) as distinct selectable capture modes. **One camera/recording perspective per analysis at a time**; do not require simultaneous dual-camera capture. Users may record or upload existing video. Practice/League/Tournament is a session *activity type*, independent of analysis mode; preserve existing Sessions UX and allow separate analyses under one activity when supported.

Form Analysis roadmap: approach duration/step count/cadence, footwork/drift/slide, timing/pushaway/swing, posture/balance, release and follow-through, only where angle/frame rate/validation support reliable measurement. Start with a small validated subset; no fabricated pose metrics. Support baseline-vs-current comparison and side-by-side annotated video. Coaching workflow: user-approved share of original/annotated video and measurements, coach timestamped comments/drawings, coach validation/correction, assigned drills, follow-up comparison. Consent and privacy controls govern coach access and use of feedback for model improvement. Unified Shot/Delivery records retain modality, source, timestamp, confidence, model version and sensor data when available. Sensor integrations (Ruby first for feasibility, Storm F5 and others exploratory) are optional, vendor-neutral, subject to API/export rights and validation. Manufacturer scoring partnerships and tournament tools remain strategic parallel/later tracks; do not block Shot MVP for Form or integrations.
**Why:** A differentiated, credible, unified measurement and coach-feedback system without requiring bowlers to use two cameras.
**Date:** 2026-10-18
**Status:** ACCEPTED PRODUCT DIRECTION; Form CV, coaching collaboration and partner APIs NOT IMPLEMENTED.
**Supersedes:** earlier dual-camera-as-default proposals; any description of form metrics as categorically out of scope. Does not override DEC-035 MVP capture constraints.

### DEC-041 — Single evolving LaneSight Score; no Improvement Score
**Decision:** Retain **one** overall LaneSight Score (0–1,000) and existing four pillars: Performance 40%, Accuracy 25%, Consistency 25%, Power & Carry 10% (DEC-038). No independent Improvement Score. Improved demonstrated ability appears as gradual change in this same score over time, shown with historical trend (30d, 90d, 6mo, 1y, all-time when qualified), deltas and personal best. Score measures current demonstrated ability, not recording frequency, sensor ownership, achievements or a universal ideal form. Use a stable recency-weighted history and minimum sample/quality gates; exact smoothing and baseline rules remain **TBD and require validation/decision before implementation**. Missing data reduces coverage/confidence and must not automatically lower ability; preserve DEC-038's no-silent-reweighting/no-fabrication requirement. Form metrics remain diagnostic and baseline-relative; do not add Form as a fifth pillar without a later DEC. Tiers and achievement system remain, with achievements independent of score (DEC-039). Provisional tier thresholds follow DEC-038 (Onyx 850–1000); Legend is an **unapproved concept**, not a live sixth tier. Prioritize performance/development milestones over engagement badges; existing provisional catalog remains subject to review. A tier is earned through qualifying score, not number of uploads.
**Why:** One understandable, trustworthy measure of skill and longitudinal improvement; avoids duplicative score systems and gamified inflation.
**Date:** 2026-10-18
**Status:** ACCEPTED PRODUCT DIRECTION; score and smoothing SPEC-ONLY; no formula implementation claimed.
**Supersedes:** proposed separate Improvement Score and any proposal to incorporate Form directly into overall L at this stage; retains DEC-038 formula/gating and DEC-039 separation.

### DEC-042 — Pro comparison discovery tile now, feature after MVP
**Decision:** Performance Lab offers three top-level paths: Start Live Session, Upload Video to Analyze, and Compare to a PBA Pro. The third tile is visible but **disabled / Coming Soon during MVP**. No PBA comparison engine, catalog, video reuse license, or pro stats are required for MVP. After MVP, enable comparison only with authorized pro footage/data, validated camera-angle-sensitive form metrics, metric provenance/quality, and explicit non-comparable/unavailable states. Show side-by-side synchronized video and approach/timing differences when validated; speed/revs optional where comparable data exists. A pro profile is a reference, not a universal ideal, performance baseline, coach-prescribed target, or LaneSight Score input. **Do not edit Figma now**; review standalone image mockups first.
**Why:** Demonstrates the future product story without delaying validated core shot and form analysis or promising rights we don't own.
**Date:** 2026-10-19
**Status:** ACCEPTED PRODUCT DIRECTION; MVP tile only, comparison post-MVP.
**Supersedes:** any prior implication that full pro comparison is MVP.

### DEC-043 — Performance/reliability SLOs are target state; upload is MVP; one analysis at a time; cost caps bound performance work
**Decision:**
- **Target state, not a beta gate.** The latency, availability and reliability targets in `03_ENGINEERING/PERFORMANCE_RELIABILITY_SLO_PROPOSAL.md`, together with BUILD_PLAN C-03 (≤10 s cloud / ≤5 s edge) and DEC-033's ≤30 s fast pass, are **target-state requirements for public launch and scale**. They do **not** gate development, testing or private beta. During those phases they are measured and reported (OPS-01), not enforced.
- **Binding in every phase:** honesty rules (no placeholder or fabricated metric to meet a time; explicit unavailable with reason, DEC-026/027), no silent loss of an accepted shot, zero cross-user video/metric access, and the Stage 1 / DEC-034 accuracy gates, which are unchanged.
- **Upload Video to Analyze is MVP** (confirms DEC-042). Until M1-13 delivery segmentation exists, an uploaded clip is analyzed as one shot; multi-shot uploads depend on M1-13.
- **One analysis at a time per session.** The next shot's analysis starts only when the current one has finished. MVP needs no in-session concurrency or backlog SLO.
- **Cost caps bound performance work.** Private-beta infrastructure stays **≤$100/month**, and unit cost targets **≤$5 per 1,000 analyzed shots** (COST_PLAN target efficiency; alert at $25 per 1,000, the unoptimized case). Every latency or throughput improvement (GPU hosting, higher capture fps, more workers, on-device CV) is checked against these caps with measured cost before adoption. If a speed-up breaks a cap, the cap wins unless a later DEC changes it.

**Why:** Keeps real targets on record without blocking testing on numbers the pipeline can't reach yet (35–80 s per clip today). Upload is part of the Performance Lab MVP. Serial analysis matches how a bowler uses one shot's feedback before the next. Cost per clip is the variable that decides whether LaneSight can launch cheaply (COST_PLAN §1).
**Date:** 2026-10-19
**Status:** ACCEPTED
**Supersedes:** DEC-035 in part (importing clips from Photos moves into MVP as Upload Video to Analyze). Recasts the C-03 and DEC-033 latency targets as target state; the targets themselves are unchanged.

## Superseded decisions
- DEC-037 — composite weighting superseded by DEC-038; S subformula and historical definition retained.
- DEC-001 — partially superseded by DEC-018 (see entry above).
- DEC-019 — partially superseded by DEC-035 (video replay deferred; Practice-only sessions).
- DEC-022 — Speed definition refined by DEC-030, then DEC-036.
- DEC-023 — default frame rate superseded by DEC-028.
- FEATURE_REVIEW "Power" — replaced by DEC-024 Impact Energy.
- DEC-030 — release-speed headline superseded by DEC-036 (60 ft average, after far-lane track recovery); release kept as the secondary `speed_release`.
- DEC-035 — "importing clips from Photos is post-MVP" superseded by DEC-043 (Upload Video to Analyze is MVP).
