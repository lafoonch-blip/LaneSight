# LaneSight Decision Log
Status: CANONICAL  
Version: 1.52  
Last Updated: 2026-10-27  
Owner: Shayne  
Supersedes: v1.51

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

### DEC-011 — Logo direction (superseded)
**Decision:** Withdrawn. An LS monogram concept was briefly recorded here; it was never adopted and has been removed from the repo, designs and Figma.  
**Date:** 2026-09-27 (recorded) · withdrawn 2026-10-25  
**Status:** SUPERSEDED by DEC-054  
**Supersedes:** —

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
**Status:** ACCEPTED PRODUCT DIRECTION; comparison post-MVP. The MVP tile is PARTIALLY SUPERSEDED by DEC-069 (hidden for now).
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

### DEC-044 — Ball catalog and configured ball reaction drive arsenal recommendations
**Decision:**
- **Shared catalog.** `ball_models` holds every ball in the major brands' current lineups (ball-catalog-1.0: 211 balls — Storm, Roto Grip, 900 Global, Brunswick, DV8, Radical, Hammer, Ebonite, Track, Motiv). Each ball has its manufacturer stock photo **linked, not hosted** (copying images needs manufacturer permission), 15 lb out-of-box specs, and the published manufacturer, bowling.com and Brunswick motion-chart ratings stored untouched with source URLs. Unpublished values are null, never guessed.
- **Normalized box reaction.** For cross-brand comparison every ball also gets `ls_hook`, `ls_length`, `ls_backend` (1–10), an oil range and a reaction shape. Each value records its basis — motion chart, in-scale retailer number, manufacturer rating, word rating, or a spec estimate (always low confidence and labeled).
- **Configured reaction.** A bowler's own ball is not the box ball. When the bowler has entered a layout (Dual Angle, VLS, or just pin up/down) and/or a surface change, its expected reaction = box reaction + one explained adjustment per recorded variable (`lanesight_core/arsenal/configured.py`). Directions come from manufacturer layout/surface guides; magnitudes are provisional (`best_effort`), scaled by differential and capped at ±2.5 per axis for layout and for surface. Recommendations rank the bowler's balls on this configured reaction.
- **Surface is history.** Re-sanding or polishing is a new append-only `surface_events` row; each shot stores the `surface_event_id` it was thrown with (DEC-007).
- **Measured beats rated.** Once a configuration + surface has enough measured shots, its observed breakpoint and entry should replace the catalog/configured estimate (not built yet).

**Why:** Ball recommendations need a per-ball expected reaction that is comparable across brands and reflects how this bowler's ball is actually drilled and surfaced. No public live ball database exists (FEATURE_REVIEW §2.4), so LaneSight curates one with provenance.
**Date:** 2026-10-21
**Status:** ACCEPTED (catalog + schema + code in `lanesight-core`); configured-reaction magnitudes and recommendation weights PROVISIONAL pending coach / pro-shop review (M4-08) and measured-shot calibration.
**Supersedes:** —

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
**Date:** 2026-10-22
**Status:** ACCEPTED
**Supersedes:** framing-gate behavior in DEC-033/035 for the dev build (the advisory replaces the gate).

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
**Date:** 2026-10-22
**Status:** ACCEPTED
**Spec:** `01_PRODUCT/BENCHMARKS_AND_RECOMMENDATIONS_SPEC.md`
**Supersedes:** —

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

**Date:** 2026-10-22
**Status:** ACCEPTED
**Supersedes:** BUILD_PLAN "MVP exit" (private beta of 10–25 league bowlers).

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
**Date:** 2026-10-22
**Status:** ACCEPTED (dev/Beta only)
**Supersedes:** nothing; DEC-038 remains the target formula.

### DEC-049 — Shot card: target vs actual, form from clip, sensor question
**Decision:**
- The bowler enters intent (feet, arrows and breakpoint boards) on the capture screen. The shot card draws the target line against the actual line and shows the miss at each point plus the execution class. The "Did you hit your mark?" prompt is removed.
- When the bowler is in view in a Shot clip, the card shows the Form metrics that angle supports, below the ball metrics. The rest are Unavailable with a reason.
- After each shot the app asks "Was a sensor in the ball?" (No / Yes plus one of the user's own sensors) and stores it on the shot for later comparison. No sensor brand names are built into the UI.

**Date:** 2026-10-22
**Status:** ACCEPTED; the "form from clip" bullet is SUPERSEDED by DEC-056
**Supersedes:** —

### DEC-050 — No pinfall in the dev build
**Decision:**
- No pin, strike, spare, leave or game-score features or metrics in this build.
- Pocket reads use entry board and entry angle only.
- Video pin reading stays in `lanesight-core` but isn't surfaced.

**Why:** No center score data; pinfall isn't a focus for this pass.
**Date:** 2026-10-22
**Status:** PARTIALLY SUPERSEDED by DEC-066 (strike / not-strike per throw is in scope)
**Supersedes:** —

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

**Date:** 2026-10-22
**Status:** ACCEPTED
**Spec:** `01_PRODUCT/SCORE_TIERS_ACHIEVEMENTS_SPEC.md`
**Supersedes:** —

### DEC-052 — Oil pattern library
**Decision:**
- Build an oil pattern library like the ball catalog: pull an initial list of published patterns (name, length, volume, ratio, source) and refresh it on a schedule.
- Keep "House shot", "Unknown" and user-entered patterns.
- Check each source's terms before import.

**Date:** 2026-10-22
**Status:** ACCEPTED
**Supersedes:** —

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
**Date:** 2026-10-22
**Status:** ACCEPTED
**Supersedes:** —

### DEC-054 — Official LaneSight logo is the Figma brand-standards logo
**Decision:** The only LaneSight logo is the official logo component in Figma (Design Components › "Brand standards / Official LaneSight identity", component `LaneSight / Brand / Official logo and wordmark`): the lane-and-arc mark with the "LaneSight" wordmark. App and web icons use that arc mark (`02_DESIGN/brand/`, Figma "Brand standards / App & web icons"). The LS monogram concept is not a LaneSight mark and must not be used.  
**Why:** It is the approved Home-header logo; the monogram was an unadopted concept that caused wrong assets.  
**Date:** 2026-10-25  
**Status:** ACCEPTED  
**Supersedes:** DEC-011

### DEC-055 — Uploads are standalone analyses; Home activity scope; disabled tabs
**Decision:**
- **Upload Video to Analyze is not a session.** An uploaded clip is analyzed on its own. It is never added to a live or practice session, and it never appears in Recent sessions or Home Recent activity.
- **Uploads don't count.** Uploaded shots never feed Stats, the LaneSight Score, tiers or achievements.
- **Where uploads live:** a separate **Uploads** list on the Lab tab, below Sessions. Each opens its shot result.
- **Home Recent activity** shows only: completed practice sessions, achievement unlocks, and LaneSight tier (rank) changes. No other event types.
- **Leagues and Tourneys tabs** are shown disabled (dimmed, not tappable) with no "Soon" / "Coming soon" label.
- **Live session setup:** the bottom button on session setup reads "Start session" and opens the camera.

**Why:** Keeps session history and activity limited to real practice and meaningful milestones.
**Date:** 2026-10-25
**Status:** ACCEPTED (Dev Build v0 designs 3.1)
**Supersedes:** the "Add to session" option on the Upload screen (designs ≤3.0) and the "Soon" / "Coming soon" label on the Leagues and Tournaments tabs.

### DEC-056 — Shot and Form metrics are split by analysis mode (for now)
**Decision:**
- **Shot Analysis** results show only shot metrics: next-shot advice, target vs actual, ball metrics, the sensor question and score/achievement nudges. No form metrics, even when the bowler is in view.
- **Form Analysis** results show only form metrics. No ball or lane metrics.
- The Shot session summary shows shot results only (no form focus or form deliveries).
- Later, results will combine naturally based on what is detected in the video. That needs a new DEC.

**Why:** Keeps each mode simple and its numbers trustworthy while bowler-in-view detection and cross-mode metrics are unproven.
**Date:** 2026-10-25
**Status:** ACCEPTED (Dev Build v0 designs 3.2)
**Supersedes:** DEC-049 "form from clip" bullet; SCORE_TIERS_ACHIEVEMENTS_SPEC "Form on shot clips"; HANDOFF Phase 2 "Bowler-in-view on shot clips" (deferred).

### DEC-057 — Shayne's form fundamentals v1 drive form findings and feedback
**Decision:**
- Shayne's fundamentals (`01_PRODUCT/FORM_BENCHMARKS.md` §0) are the default L0 owner rules for form findings, feedback and drills.
- **Timing checkpoints with early / on time / late verdicts:**
  - pushaway: ball beside the ball-side leg when the foot after the pushaway step lands
  - ball-start step: step 1 of a 4-step approach, step 2 of a 5-step approach
  - backswing apex at slide start
  - release after the slide foot stops (leverage window)
  - Every verdict is shown with its measured offset.
- **New measured metrics:** foul-line distance when the slide stops; spine tilt and its consistency; balance arm; shoulder tilt; follow-through height.
- **Hand and wrist rules** (behind and under, inside-out, finger exit, suitcasing, broken wrist) are coaching cues only, not measured, until a validated method exists.
- **Swing-timing baseline:** the bowler can set a baseline in **Profile › Form baseline** (entered, or "use my average"). Form results compare each delivery to it phase by phase.

**Why:** Gives form feedback concrete, coach-standard checkpoints while keeping unmeasurable advice clearly separate from measured results.
**Date:** 2026-10-25
**Status:** ACCEPTED (Dev Build v0 designs 3.4). On-time windows and thresholds are provisional owner settings until validated on real clips.
**Supersedes:** FORM_ANALYSIS_SPEC §2 honesty note ("never as a grade") for these owner-defined checkpoints; DEC-046 in part (a bowler may set a swing-timing baseline in Profile; other self-set targets still wait for the Coaching tab).

### DEC-058 — Bowler notes on every shot, stored for comparison
**Decision:**
- Every shot card ends with **Your notes on this shot**: free text plus optional quick tags (Hit my target, Missed left, Missed right, Pocket, Light, High, Felt good, Pulled it). Notes autosave.
- Notes are stored with the shot (`shot_note`: text, tags, timestamps), visible only to the bowler and the owner, and deleted with the shot or account. *(Storage superseded by DEC-059.)*
- Notes and tags are included in the session CSV export and are available for owner analysis: compare what the bowler saw (e.g. "light", "missed right") with the measured metrics to find metric errors and tune rules.
- Notes never change any measured value, the LaneSight Score or achievements.

**Why:** The bowler's own observation at the lane is the fastest check on whether a measurement or recommendation was right.
**Date:** 2026-10-25
**Status:** ACCEPTED (Dev Build v0 designs 3.6); storage/retention SUPERSEDED by DEC-059
**Supersedes:** —

### DEC-059 — One retained feedback store for dev, beta and live
**Decision:**
- All bowler feedback goes into one `feedback` table, tagged with app phase (`dev` / `beta` / `live`) and versions. That covers shot notes and tags, session-end feedback, advice 👍/👎, and future form notes and general feedback.
- Spec: `03_ENGINEERING/FEEDBACK_STORE_SPEC.md`.
- **Retention:** feedback is kept when its shot or session is deleted (links set to null; a snapshot of the measured results is stored with each row).
- **Account deletion:** the account is deleted and its feedback is **anonymized**, not deleted. De-identified retention is disclosed in the privacy policy, as App Store rules require.
- **Access:** bowlers add and edit their own feedback; only the owner reads everything and triages it (new / reviewed / actioned / dismissed). No client delete.
- **No live effect:** feedback is for offline analysis and owner-driven changes only. Nothing in the app reads it to change measurements, rules, scores or advice.

**Why:** Collect, analyze and act on feedback across every phase, whenever Shayne chooses, without losing it to shot or account cleanup.
**Date:** 2026-10-25
**Status:** ACCEPTED; implementation not started
**Supersedes:** storage parts of DEC-053 (`session_feedback` table) and DEC-058 (`shot_note`, delete with shot/account)

### DEC-060 — MVP+: Multi-Bowler Session Tracking on the roadmap
**Decision:**
- Add an MVP+ feature in which:
  - at session start the user selects who to track (self plus optional friends or guests)
  - each tracked bowler is enrolled with front and back photos, handedness and ball
  - the phone records the full session
  - LaneSight attributes each delivery to an enrolled bowler, analyzes only those, ignores everyone else
  - after the session, LaneSight offers a bowler-vs-bowler comparison
- It builds on DEC-014 (continuous capture, rolling buffer, discard non-user footage) and DEC-015 (session-scoped multi-signal recognition; face supports but never drives).
- Uncertain deliveries are confirmed by the user at session end, never guessed.
- Friends and guests consent before tracking. Enrollment data is session-scoped unless the bowler opts in.
- Plan and tasks: BUILD_PLAN "MVP+ — Multi-Bowler Session Tracking" (MB-01…MB-08).

**Why:** Hands-free tracking for a whole session, and friend comparisons, are strong reasons to come back and to invite others (growth loop, Master Context §16).
**Date:** 2026-10-25
**Status:** ACCEPTED FOR ROADMAP (MVP+); not in MVP or the dev build; biometric-privacy legal review required before launch
**Supersedes:** —

### DEC-061 — Recommendation guardrails and one metric-status rule
**Decision:**
- A next-shot move is given only when the shot is trustworthy. Otherwise the Shot card shows one of the 3.7 states (`NextShotStates.dc.html`): strike → repeat; missed target → repeat and hit your mark; pins not read → ask the bowler for the leave, then advise; not enough reliable data → no move plus a camera tip; low confidence → "Maybe…" with a secondary "Apply anyway".
- Moves are in boards, at most 2 (feet) and 1 (eyes) per shot; bigger moves need 2+ agreeing shots. All boards clamp to 1–39.
- A plausibility gate runs before insights: if speed rises downlane, the far-lane track jumps, or calibration residuals are high, far-lane metrics (breakpoint, entry board/angle, late speed) drop to best effort or unavailable and no move is given.
- Metric status chips: `ok`/`measured` → MEASURED; `best_effort`/`low_confidence`/`calibrated_estimate` → BEST EFFORT; anything else → UNAVAILABLE, which never shows a number.
- Uploaded clips are de-duplicated by content hash and never show score or achievement blocks (DEC-055).

**Why:** Shot 14b234c8 (2026-10-25) was a strike, but a far-lane calibration error made it read 7 boards light, and the engine told Shayne to move 8 boards right with breakpoint 0 (`02_RESEARCH/SHOT_REVIEW_2026-10-25_14b234c8.md`). Wrong confident advice is worse than no advice.
**Date:** 2026-10-25
**Status:** ACCEPTED (dev build onward)
**Supersedes:** —

### DEC-062 — Geometry-first CV re-architecture (staged, ablation-gated)
**Decision:**
- Adopt the outside CV review's spine (`03_ENGINEERING/CV_REARCHITECTURE_RESPONSE_2026-10-25.md`, responding to the ChatGPT handoff): **geometry-first camera calibration decoupled from the ball**, metric-level (not shot-level) gating with propagated uncertainty, learned detection/calibration only where justified, and known geometry + physics for physical quantities.
- The far-lane calibration no longer anchors to the ball's extrapolated impact position (today's synthetic far line in `cv/metrics.lane_homography`); it will solve from real, stationary downlane fiducials (foul line, arrows, dots, pin spots, gutters). This subsumes and supersedes the old GUARDRAILS workstream **A** (far-lane calibration).
- **Mandatory Phase-1 gate before any ML investment:** the A/B/C/D ablation on the 17-clip benchmark. If Run C (manual geometry + manual ball centers) can't reach the accuracy target on near-level clips, the limit is resolution/identifiability — change capture guidance / metric eligibility, not models.
- The production CV path is **frozen** until the ablation reports; `accuracy over coverage` stays the tie-breaker. All Phase-1 harness code (`cv/calib/`) is additive and off the production path.
- Canonical lane geometry lives in one cited module (`cv/calib/lane_geometry.py`); no nominal sports-geometry magic constants in algorithm code, and any coordinate we don't actually know is `unavailable` with a reason, never fabricated.

**Why:** The 17 pale-lane training clips (3/17 analysable) exposed that metrics are only reliable from a narrow framing. Root cause is a 4-point homography whose far anchor is the ball itself (circular), zero real downlane depth anchors, and difference-based detection that loses the back-half ball — not a tuning problem. An honest geometry-proof ablation is the cheapest way to know whether correct geometry alone fixes it before spending on annotation/training.
**Date:** 2026-10-25
**Status:** ACCEPTED (supersedes GUARDRAILS workstream A). Phase-1 harness + ablation done. **Phase-1 outcome amended by DEC-065** (pose-based geometry: near recoverable, far re-opened as unvalidated) — the spine (geometry-first, decoupled from the ball, solve from real fiducials) stands.
**Supersedes:** GUARDRAILS 3.7 workstream A (far-lane calibration)

### DEC-063 — Staged test accounts for dev build and testing
**Decision:**
- Shayne's real account stays real-only (practice/validation data). Full-experience testing uses **separate staged accounts**, never staged data in a real account.
- Seven kinds: `new_user`, `active` (main showcase), `improving`, `struggling`, `edge_cases`, `heavy`, `under_13` (`03_ENGINEERING/dev_build_v0/HANDOFF_2026-10-26_STAGED_TEST_ACCOUNTS.md`).
- Staged accounts are flagged (`profiles.is_staged`); their feedback is flagged too and excluded from feedback review, analytics and cross-user baselines. Uploads still never count (DEC-055).
- Staged history is generated from real analyzed shots and run through the real score, tier, achievement and recommendation engines; a re-runnable seed tool resets any staged account to its known state and refuses to touch non-staged accounts.

**Why:** Staging data inside the real account would contaminate Stats, LaneSight Score, achievements and the retained feedback store (a contaminated session already needed a reset script on 2026-10-25). Known-state accounts also give repeatable regression testing and carry forward into Beta.
**Date:** 2026-10-26
**Status:** ACCEPTED (dev build onward)
**Supersedes:** —

### DEC-064 — Canonical metric reference definitions (entry board / entry angle / speed)
**Decision:** (resolves D-1/D-2/D-3 in `03_ENGINEERING/CV_MEASUREMENT_DEFINITIONS.md`)
- **Entry board (D-1):** the canonical metric is read at a **fixed 60.0 ft plane** (foul line → head-pin spot), named `entry_board@60ft`. The other positions are kept as **separately named secondary** metrics — `entry_board@59.44ft` (ball centre at first contact, the current production value) and `entry_board@55ft` (sensor-style). Every entry-board metric name carries its reference plane; no bare "entry_board".
- **Entry angle (D-2):** canonical is `entry_angle@52–55ft` — a **fixed window**, `atan(dX/dZ)` in degrees, sign positive = toward the pocket. The dynamic last-1.5-ft version is demoted to an internal diagnostic.
- **Speed (D-3):** keep four **separately named** speeds — `ball_speed` (60 ft foul→pins average, canonical headline), `speed_release`, `speed_early`, `speed_late`. Speeds are **planar** unless suffixed `_dz` (downlane dZ/dt).
- (D-4 Ruby speed definition remains OPEN — treat Ruby as a secondary reference and flag the mismatch; D-5 USBC ranges already implemented.)
- The canonical constants live in `cv/calib/lane_geometry` (`ENTRY_REFERENCE_FT`, `ENTRY_ANGLE_WINDOW_FT`, `ENTRY_SECONDARY_FT`). Applying them to the production `cv/metrics` outputs is a small, mechanical follow-up, **deferred while production CV is frozen (DEC-062)**.

**Why:** Production shipped two different "entry" references (board @ 59.44 ft contact vs angle @ 52–55 ft) and a floating entry-angle window — the exact ambiguity the CV review (§4) warned makes a *perfectly calibrated* clip disagree with ground truth. Fixing the definitions now lets Phase-2 accuracy be scored against a stable reference.
**Date:** 2026-10-26
**Status:** ACCEPTED (definitions; production implementation deferred under DEC-062 freeze)
**Supersedes:** refines DEC-036 (speed) and the entry-metric conventions; no decision withdrawn

### DEC-065 — Pose-based, self-calibrating lane geometry; near-field partial results, far-lane gated
**Decision (Shayne, 2026-10-26):** adopt a **3D camera pose (solvePnP from foul + pin spots)** as the lane
geometry solver, replacing the degenerate single-plane homography the Phase-1 verdict tested. It is
**self-calibrating**: the focal length is fit from the lane labels (no mandatory user/checkerboard
calibration), with the focal source pluggable (explicit > EXIF > fitted) and its sensitivity always reported.
- **Goal preserved:** accurate analysis from **ordinary phone videos without mandatory calibration**. The
  fitted focal is validated as a usable lens constant per clip/session, not assumed.
- **Near-field partial results are ON now** where the geometry validates: laydown board, board @ 7 ft, arrows
  board, launch angle (+ all form). These are the 🟡 path — never reject a whole video.
- **Far-lane metrics stay `unavailable`** (entry board/angle, breakpoint, late/full-lane speed) — *not*
  estimated — **until BOTH the new geometry AND real ball measurements pass a reference test** (Phase-2
  mid-lane tape / cross-camera reference; `CV_PHASE2_CAMERA_VALIDATION_PROTOCOL`). No far-lane promise ships
  before that.
- **Validation status (independent, on the 17-clip cohort, `cv/calib/validate_pose.py`):** self-cal focal is
  consistent (median 1640 px, std 45, n=12 — calibratable); the pose reprojects foul+pins < 1.8 px; the
  **held-out arrows land in their USBC 12–16 ft band on 12/12 clips** (an independent check — arrows are not
  used in the solve); a ±10 % focal error moves a near **board** reading by ≤ 0.2 board (so near lateral-board
  metrics need no mandatory calibration). Near **speed** depends on the depth scale and carries focal
  uncertainty — use EXIF/known focal or report the band. Far lane: UNVALIDATED (no held-out fiducial past
  16 ft). Evidence: `CV_PHASE1_VALIDATION_REPORT` §3.6 + §5.
- **Still not ML; production CV still frozen (DEC-062).** This is geometry-first, exactly DEC-062's spine; the
  Phase-1 "physical limit" sub-conclusion (report §3.4/§4) is **amended** — the near-to-mid lane is
  recoverable with the correct model + intrinsics; the far-lane limit is re-opened as "unvalidated", pending
  the Phase-2 reference, not asserted as physical.

**Why:** the fixed near-field run showed the §3.5 near-homography fails on real labels (0/17, reproj
16–2,600 boards), while the calibrated-focal pose recovers the near-to-mid lane and cross-validates against
held-out arrows. Accuracy-over-coverage: ship the validated near set, gate the unproven far set.
**Date:** 2026-10-26
**Status:** ACCEPTED (near path validated on cohort; far path gated pending Phase-2 reference + ball test)
**Supersedes:** amends DEC-062's Phase-1 outcome (near recoverable; far re-opened as unvalidated). Consistent
with DEC-062's geometry-first spine; no decision withdrawn.

### DEC-066 — Strike / not-strike per throw; no game scores
**Decision (Shayne, 2026-10-26):**
- Each recorded throw records whether it was a **strike or not**, read from video **when the pins are visible**.
- No game scores, frames, series, spares, leaves or pin-by-pin results are tracked.
- When the pins aren't visible or can't be read, the result is "not read" — never guessed (DEC-026). The DEC-061 next-shot states still apply.
- Applies to the dev build and the target-state (Figma) designs.

**Why:** A strike is the clearest outcome of a throw and is useful without center score data; full pinfall and game scoring aren't needed yet.
**Date:** 2026-10-26
**Status:** ACCEPTED (dev build and target state)
**Supersedes:** DEC-050 in part (strike result per throw is now in scope; the rest of DEC-050 stands). Target-state Figma pinfall screens (Spares stats, pin-leave entry) are out of MVP.

### DEC-067 — Live session setup: practice only, no lane picker, no target for Form Analysis
**Decision (Shayne, 2026-10-26):**
- **No session-type choice.** MVP Lab sessions are practice only, so Setup doesn't ask for Practice / League / Tournament.
- **No lane picker** anywhere (Setup, Active Session, Shot card, summaries).
- **Form Analysis has no target line.** The optional target (feet / arrows / breakpoint) shows only for Shot Analysis.
- The **Leagues and Tournaments tabs** stay in the bottom nav, disabled (dimmed, not tappable, no label), per DEC-055.
- Applies to the dev build and the target-state (Figma) designs.

**Why:** Only practice exists in MVP; the lane number added a step with no metric value; a target line means nothing for a form clip.
**Date:** 2026-10-26
**Status:** ACCEPTED (dev build and target state)
**Supersedes:** the Figma Setup Session type chips and "Lane" row; the dev build 2.0 lane-picker removal is now recorded as a decision.

### DEC-068 — Analysis is a blocking modal and keeps the screen awake
**Decision (Shayne, 2026-10-26):**
- While a clip is trimming, uploading or analyzing, the app shows a **modal overlay with the analyzing animation and progress** that **blocks all input** behind it. Nothing can be changed during analysis (for example the analysis type, target, ball or oil pattern).
- While analysis is running, the **phone does not sleep and the screen stays on** (idle timer disabled for the duration; restored when it finishes, fails or is cancelled).
- The modal's failure state offers the existing next steps (4c), and closes only on result, failure or an explicit cancel.
- Applies to the dev build and the target-state (Figma) designs.

**Why:** In the dev build the analysis type could be changed while a video was analyzing, which can corrupt or mislabel the result; sleep during analysis interrupts the job.
**Date:** 2026-10-26
**Status:** ACCEPTED (dev build and target state). Briefly superseded by DEC-078, reinstated by DEC-080.
**Supersedes:** the non-blocking Analyzing screen (4b) behavior.

### DEC-069 — Lab starts with the analysis mode, then live or upload; PBA compare hidden for now
**Decision (Shayne, 2026-10-26):**
- The Lab tab starts with the **analysis mode**: the bowler picks **Shot Analysis** or **Form Analysis**.
- A sheet then asks **Live session** or **Upload video**.
  - Live session → session setup → camera. Setup no longer has a mode toggle (the mode was already chosen).
  - Upload video → pick a clip → analysis; still a standalone upload under Lab › Uploads (DEC-055).
- The separate **Upload Video** and **Compare to a PBA Pro** tiles are removed from Lab. Pro comparison is hidden entirely for now (not shown as a disabled tile) and can return later.
- Applies to the dev build and the target-state (Figma) designs.

**Why:** One clear starting choice (what to analyze), then how to capture it, instead of three parallel entry points.
**Date:** 2026-10-26
**Status:** ACCEPTED (dev build and target state)
**Supersedes:** DEC-042 in part (the disabled "Compare to a PBA Pro" tile is no longer shown in MVP; post-MVP direction unchanged); the Lab entry tiles in Dev Build v0 designs ≤3.7.

### DEC-070 — No sensor features in MVP; sensor designs parked for a future partnership
**Decision (Shayne, 2026-10-26):**
- The MVP app has **no sensor references**: no per-shot "Was a sensor in the ball?" question, no sensor picker, no sensor list in Profile or Settings, and no sensor-vs-video variance.
- The **dev build keeps** the per-shot sensor question. It exists only so Shayne can compare video metrics with his own sensor; it is not a user feature.
- The sensor designs are **parked** in Figma (section "Parked · Sensor partnership (post-MVP)") for a possible sensor partnership later. Bringing them back needs a new DEC.
- Applies to the target-state (MVP) designs.

**Why:** Sensor references were a validation aid for the owner, not something MVP bowlers need.
**Date:** 2026-10-26
**Status:** ACCEPTED (MVP / target state; dev build unchanged)
**Supersedes:** DEC-021 and DEC-049's sensor question for MVP (both remain valid for the dev build and as post-MVP direction); memory/scope note "optional sensor pairing in MVP".

### DEC-071 — The target line is edited only at session setup and on the session screen
**Decision (Shayne, 2026-10-26):**
- The bowler sets the target line (feet / arrows / breakpoint) at **session setup** and can change it on the **Active Session** screen.
- The **camera (Record) screen has no target controls**: no target chip and no "Edit target" sheet. It keeps the current-ball chip and the advisory spot-check tip.
- Applies to the target-state (MVP) designs. The dev build follows when its designs are next updated.

**Why:** Fewer controls on the camera screen; the target rarely changes between shots and the session screen is one tap away.
**Date:** 2026-10-26
**Status:** ACCEPTED (target state)
**Supersedes:** the capture-screen target chip and Edit-target sheet (Dev Build v0 designs 2.0 / 4a) for target state.

### DEC-072 — Session end: score popup, then a session-focused summary (also used for past sessions)
**Decision (Shayne, 2026-10-26):**
- **On End session**, a temporary popup shows the LaneSight Score and tier progress plus the change in the score parts and core metrics (up / down / no change). It closes on its own after a few seconds or with "See session summary".
- The **Session summary** is about the session, not the score:
  - a compact score row (score, change, tier) that opens the same popup;
  - all core stats from the in-session view;
  - **early vs late trends** per metric (first vs last shots of the session, with a per-shot sparkline), so the bowler sees warm-up and fatigue effects (e.g. speed up after warm-up, revs down late);
  - lane transition, the bowler's rating, and **all shots listed at the bottom** as on the Active Session screen.
- The **same screen opens for a past session** from history. There is no separate past-session view.
- The session feedback sheet still appears after the session ends (DEC-053).
- Applies to the target-state (MVP) designs. The dev build follows when its designs are next updated.

**Why:** Keep the summary focused on what happened in this session and how it changed; score and tier progress get their own moment at the end.
**Date:** 2026-10-26
**Status:** ACCEPTED (target state)
**Supersedes:** the separate Session summary (13) and Past session (6a) layouts in Dev Build v0 designs 3.7 for target state; DEC-035's "No Session Summary screen" (already superseded in practice by the dev build).

### DEC-073 — Metric hierarchy per moment; Form session summary; Stats tabs Score · Shot · Form · Equipment
**Decision (Shayne, 2026-10-26):**
- Each screen shows the metrics that matter at that moment, per `01_PRODUCT/METRIC_TO_SCREEN_SPEC.md`. Rules: show a metric only where it explains performance or drives a decision; show spread next to averages; end every summary with one takeaway; no invented composites (no Session Score, Form score or carry).
- **Shot card:** result, lane picture and next move first; top rings are Speed, Rev rate and Accuracy; entry angle, breakpoint, laydown, loft and impact energy sit in the expanded metrics.
- **Shot session summary** (DEC-072) adds a one-line takeaway at the top, averages with spread (e.g. 17.8 ± 0.4 mph), and a by-ball split when 2+ balls were used.
- **New Form session summary:** repeatability across deliveries (approach time, release timing, ball start, swing time, spine tilt) against the Profile baseline, early vs late trends, one focus and drill, and all deliveries. It does not change the LaneSight Score, so there is no score popup for form sessions.
- **Stats tabs:** Score · Shot (was "Throw") · Form · **Equipment** (by ball, by oil pattern). Filters: period (30 / 90 days / all time), ball and oil pattern. No session-type filter (practice only).
- Not adopted: carry metrics, knee flexion, and drift as a primary form metric; the shot↔form "intelligence layer" is post-MVP and must be worded as association, not cause.
- Applies to the target-state (MVP) designs. The dev build follows when its designs are next updated.

**Why:** ChatGPT's metric-hierarchy review (2026-10-26), adjusted to existing decisions; keeps each screen focused while the stored data stays complete.
**Date:** 2026-10-26
**Status:** ACCEPTED (target state); spec approved as v1.0 on 2026-10-26
**Supersedes:** the Score / Throw / Form tab set (Dev Build v0 designs 3.7) for target state.

### DEC-074 — Grip (pitch, span) and PAP belong to the bowler profile, not the ball
**Decision (Shayne, 2026-10-26):**
- Middle pitch, span and PAP (over / up) are **bowler** measurements. They are set once in **Profile › Advanced** and used for every ball.
- **Ball setup** (add from catalog and view / edit) has no pitch, span or PAP fields. Its drilling section is layout, surface (finish) and weight.
- Applies to the target-state (MVP) designs. The dev build follows when its designs are next updated.

**Why:** These values describe the bowler's hand and axis, not a ball; entering them per ball duplicates data and invites mismatches.
**Date:** 2026-10-26
**Status:** ACCEPTED (target state); **MVP + dev build scope per DEC-087** (grip/PAP are now built in Profile › Advanced, stored per bowler).
**Supersedes:** the "Pitch / span · From profile" row on Ball setup (Figma, Dev Build v0 designs 20).

### DEC-075 — Form key-position thumbnails and upload thumbnails come from the bowler's own clip
**Decision (Shayne, 2026-10-26):**
- The Key positions row on Form results (ball start, end of pushaway, top of swing, release) shows **frames taken from that delivery's video** at the detected event times. Tapping one opens that frame. No stock or illustrated poses.
- Upload clip thumbnails are a frame from the uploaded clip.
- Design detail (approved by Shayne 2026-10-26): if an event isn't detected, its tile shows the event name with "Not detected" instead of a frame.
- Marketing imagery stays separate: the Shot and Form Analysis card images are LaneSight-generated and kept; the Welcome hero keeps its composition and will be replaced with an AI-generated image of Shayne (asset to come).

**Why:** The thumbnails are evidence for the timing call; they must show the bowler's actual body position in that delivery.
**Date:** 2026-10-26
**Status:** ACCEPTED (target state)

### DEC-076 — Form Analysis detects the camera view; thumbnails and metrics follow it
**Decision (Shayne, 2026-10-26):**
- The app detects the camera view of each Form clip (side, rear/behind, or front) from the video itself; the bowler does not pick it.
- Form results show the detected view in the header (e.g. "rear view (detected)").
- The Key positions thumbnails (DEC-075) are frames from that clip, so they show the bowler from the detected view.
- The metric set follows the view (FORM_ANALYSIS_SPEC §5.1). Metrics the view can't see show UNAVAILABLE with the view they need (e.g. "Side view"), never a number.
- Design details (approved by Shayne 2026-10-26): if detection is unsure, the result shows the best guess and the bowler can correct the view on the results screen; the rear-view example screen measures drift and balance arm (best effort) and marks spine tilt and foul-line distance as needing a side view, with steps best effort.

**Why:** One recording supports one view (DEC-040). Showing the wrong pose angle or a metric the camera can't see would undermine trust in the timing call.
**Date:** 2026-10-26
**Status:** ACCEPTED (target state)
**Extends:** DEC-075.

### DEC-077 — MVP LaneSight Score uses the DEC-048 formula (provisional)
**Decision (Shayne, 2026-10-26):**
- The MVP (target-state) LaneSight Score is **DEC-048's formula**: `L = round(10 × (0.40·S' + 0.25·A + 0.25·C + 0.10·P'))`, with S' = 0.6 × pocket% + 0.4 × entry-angle-in-4–6° share, A = DEC-031, C = DEC-032, P' = power from ball data (entry speed, rev rate when its band is in target, entry angle, ball weight; no carry).
- Same eligibility floors (20 / 20 / 10 / 10 shots), 90-day window, snapshot per recompute, and no silent reweighting.
- In MVP it is labeled **provisional** (not "Beta · dev formula"). Tiers use DEC-038's working thresholds.
- Strike % is shown in Stats but is **not** part of S'.
- DEC-038's full formula (game score, spare conversion, Power & Carry) stays the long-term target and needs pinfall data first.

**Why:** DEC-066 removes game scores and spares from MVP, so DEC-038's S can't be computed; Home still needs a real, computed score.
**Date:** 2026-10-26
**Status:** ACCEPTED (target state)
**Extends:** DEC-048 from dev/Beta to MVP. DEC-038 remains the post-MVP target.

### DEC-078 — Analysis runs in the background with the clip's settings locked
**Decision (Shayne, 2026-10-26):**
- After a shot is recorded, the app confirms it ("Shot 14 received · analyzing") and the bowler can keep using the session and record the next shot. No blocking modal.
- The clip's analysis type, target, ball and oil are **locked to that clip** when it is recorded; later changes apply only to new shots.
- The shot row and latest-shot card show **Analyzing…** until results arrive, then update in place. Failures show on that shot with Retry (no re-recording).
- The screen stays awake while any analysis is running (kept from DEC-068).

**Why:** Analysis can take 1–2 minutes (longer after a cold start); blocking between shots stalls a session. Locking per clip keeps DEC-068's protection against mislabeled results.
**Date:** 2026-10-26
**Status:** WITHDRAWN 2026-10-26 — superseded by DEC-080.
**Supersedes:** DEC-068's blocking modal. DEC-068's keep-awake rule stays.

### DEC-079 — v3.7 design review changes (ChatGPT review, 2026-10-26)
**Decision (Shayne, 2026-10-26):** Apply to the target-state designs:
- **Active Session** leads with the latest shot (result, lane picture, next move, Record), then a compact 4-metric row (Speed, Rev rate, Accuracy, Consistency), with shot history and lane transition collapsed below.
- **Recommendations** follow move → evidence → expected effect. Pin result, target execution, pocket entry and lane reaction are labeled separately.
- **Home** adds a "Your next focus" card below a more compact score breakdown.
- **Session summary** leads with What went well / What to improve / Next focus and a "vs your typical" comparison, shown only with enough comparable shots.
- **Setup** defaults to the last-used ball, oil and target, and shows one "Ready to bowl" line above the detailed checks; the service check does not imply a warm worker.
- **Lab** explains uploads vs sessions in plain language.
- **Form results** lets the bowler tap a key position or checkpoint to play the video from that frame (playback superseded by DEC-082: thumbnails with a skeleton overlay instead); Early / On time / Late are judged against the bowler's own baseline.
- **Stats** metric tiles open a detail view; Shot stats add an Accuracy trend; Impact Energy is labeled as not a carry prediction (DEC-024).
- **States** added: resume an interrupted session, retry an upload without re-recording, first-use baseline explainer, small-sample labels.
- Not adopted: Practice / League / Tournament filters in Lab (DEC-067).

**Date:** 2026-10-26
**Status:** ACCEPTED (target state)

### DEC-080 — Shot flow: Analyzing screen, then shot details (DEC-078 withdrawn)
**Decision (Shayne, 2026-10-26):**
- After the bowler stops recording, the app shows the **Analyzing screen** (DEC-068: blocking, controls locked, screen stays awake) until results are ready.
- It then opens the **shot details** (Shot card) automatically. The bowler always sees the result and analysis before moving on.
- From shot details the bowler can **close** (back to the Active Session) or **record the next shot** directly.
- The bowler stops each recording by tapping (DEC-035). Stop timing isn't critical: the pins have settled by the time the bowler walks back, and analysis trims the clip to the shot window.
- Upload or analysis failures are shown on the Analyzing screen with Retry; a failed upload stays saved on the phone (DEC-079 states).

**Why:** Seeing each shot's result and next move before the next shot is the core practice loop; a background flow let bowlers skip it.
**Date:** 2026-10-26
**Status:** ACCEPTED (target state and dev build)
**Supersedes:** DEC-078 (withdrawn). Reinstates DEC-068.

### DEC-081 — Form Analysis live flow; no ball or oil for Form; first-use and detail screens
**Decision (Shayne, 2026-10-26):**
- **Ball and oil pattern are not used for Form Analysis**, live or upload. Form setup shows camera-view guidance instead.
- **Form recording works from the side or from behind**; the view is detected automatically (DEC-076), and the record screen's spot check says which view it sees.
- **Live Form flow** (mirrors DEC-080): Setup → Record delivery → Analyzing screen → Form results → **Record next delivery** or **close** to the Form session → End session → Form session summary.
- **Metric detail screens** follow the Speed template: average, spread, range, coverage, trend by session, by ball and by oil pattern, with small samples labeled.
- **First-use and permission screens** are part of the MVP designs.
- Design details (approved by Shayne 2026-10-26): camera access is explained before the iOS prompt, with a denied state that offers Open Settings or uploading a video; there is no Photos permission screen because the iOS video picker needs none; new users see "Building your LaneSight Score" on Home and Stats and empty Lab lists.

**Why:** Ball and oil don't affect body mechanics; the live Form loop should match the Shot loop so bowlers see each delivery's result before the next.
**Date:** 2026-10-26
**Status:** ACCEPTED (target state)

### DEC-082 — Form: no video playback in MVP; key-position thumbnails with a measured skeleton overlay
**Decision (Shayne, 2026-10-26):**
- **No full video playback** on Form results in MVP.
- During analysis the app **captures a thumbnail at each key moment** (ball start, end of pushaway, top of swing, release) from the bowler's clip (DEC-075), in the detected view (DEC-076).
- Each thumbnail can carry a **line-skeleton overlay** showing the pose, plus the one measurement or angle that matters at that moment (e.g. spine tilt at release from the side, shoulder tilt at release from behind).
- Design details (approved by Shayne 2026-10-26): tapping a thumbnail opens the full frame with the skeleton, the measured angle drawn against a vertical reference, and the measurements available at that position; only joints detected with confidence are drawn; when pose confidence is too low the thumbnail shows no overlay and says so; overlays are drawn by the app from stored landmarks, not burned into the image.

**Why:** Thumbnails plus measured angles give the coaching value of playback at much lower cost and scope (DEC-035 kept replay post-MVP).
**Date:** 2026-10-26
**Status:** ACCEPTED (target state)
**Supersedes:** the Form results video player added under DEC-079.

### DEC-083 — Home while the LaneSight Score is building; score-part tiles show 30-day change
**Decision (Shayne, 2026-10-27):**
- **Building state (Option A):** Home keeps the real score card. The tier badge is greyed and slightly blurred (no tier name shown). The score shows "—" with "BUILDING", a hint ("About 12 more shots, with a target set") and a **"Score unlocks · N%"** progress bar in place of the next-tier bar. "View Details" reads "How it works".
- The hint shows the largest number of shots any part still needs; when that part is Accuracy it says to set a target (kept for now).
- **Score-part tiles (Performance, Accuracy, Consistency, Power):** show the part's score and its **change over the last 30 days** (e.g. "▲ 2 · 30 days"). The weight ("40% of score") is removed from the tiles and shown only in the LaneSight Score details.
- While building, a part that isn't ready shows a dimmed tile with its shot progress (e.g. "12/20 shots"); a ready part shows its score with "Ready ✓" (DEC-038 allows parts individually; the overall score stays unavailable until all four are ready).

**Why:** The building state should look like the real Home so the switch to a real score feels natural, and the tiles should show what changed, not how the formula is weighted.
**Date:** 2026-10-27
**Status:** ACCEPTED (target state)
**Supersedes:** the "Building your LaneSight Score" card on the first-use Home (DEC-081 first-use design) and the "% of score" line on the Home tiles (DEC-038 presentation; weights stay in the score details).

### DEC-084 — Coaching tab replaces Leagues and Tournaments; opens a "coming soon" screen
**Decision (Shayne, 2026-10-27):**
- The bottom nav has **four tabs: Home · Stats · Lab · Coaching**. The disabled Leagues and Tournaments tabs are removed.
- **Coaching is tappable** (Claude's call, delegated by Shayne) and opens a "Coaching is on the way" screen: what's coming (share with your coach, notes and drills on shots, see what helped), an "Until then" pointer to the next-shot advice and Home's next focus, and a **Notify me when it's ready** button (one notification at launch; tapped state "✓ We'll let you know").
- The screen promises coach features only: no AI chat, consistent with DEC-046/047 and the 2026-10-27 coaching review (Coaching tab is post-MVP).

**Why:** A dimmed tab reads as broken; a short screen sets expectations and measures interest. Coaching is the next planned area, while leagues and tournaments are further out.
**Date:** 2026-10-27
**Status:** ACCEPTED + **BUILT in the dev build iOS (2026-10-27):** four-tab nav Home·Stats·Lab·Coaching (graduation-cap), the "Coaching is on the way" screen, and `GET/PUT /me/notify` for the launch-notify flag (migration 021).
**Supersedes:** the disabled Leagues / Tournaments tabs (DEC-055 for the dev build designs, DEC-067 for the target state).

### DEC-085 — Stats tab order Shot · Form · Score · Arsenal; Stats building states mirror the real screens
**Decision (Shayne, 2026-10-27):**
- **Stats tabs, in order: Shot · Form · Score · Arsenal.** "Equipment" is renamed **Arsenal**. The Stats nav button opens the **Shot** tab.
- **Score tab while the score is building** uses the real Score screen, matching Home (DEC-083): greyed, blurred badge, "—" + BUILDING, the shots-needed hint and a "Score unlocks · N%" bar; the trend chart is dimmed with "Your trend starts with your first score"; each part shows its shot progress (e.g. 12/20) with a progress bar and "—" for inputs, and a ready part shows its value with "Ready ✓". Part weights stay on this screen (the details view).
- **Shot and Arsenal tabs for a new bowler** show real values from the shots so far with a **small-sample** label ("Based on 12 shots from your first session…"); 30-day changes read "new" and by-session trend charts say "Trend starts at session 2". Arsenal shows the one ball and pattern used, marked as a small sample. Form keeps its empty state until the first Form delivery.

**Why:** A new bowler should see the real screens filling in, not a different layout; Shot is the most-used view, so it comes first.
**Date:** 2026-10-27
**Status:** ACCEPTED (target state)
**Supersedes:** DEC-073's Stats tab order (Score · Shot · Form · Equipment) and the first-use Stats cards from DEC-081.

### DEC-086 — Analysis failures are first-class: structured codes, friendly copy, a retained attempt log; upload de-dup paused
**Decision (Shayne, 2026-10-27):** When the CV/pose pipeline can't produce a result, that is a first-class, user-facing outcome — not a 500 or a silent empty row.
- **Structured failures.** Every pipeline raise is an `AnalysisFailure` with a stable `code`, a `stage` (decode · stabilize · lane · track · impact · metrics · sanity · form_pose · storage · internal), a developer `message`, and `diagnostics` (the numbers behind the decision). Anything unexpected is wrapped as `INTERNAL_ERROR` — the raw trace never reaches the user.
- **Server-owned copy.** `lanesight_core/failures.py` maps each code to a user `title` / `message` / `tip`. The API returns this block on the job and on the failed shot row; the app shows the copy, never the code.
- **Shots carry analysis state.** `shots.analysis_status` (pending · running · analyzed · failed) with `failure_code` / `failure_stage` / `analyzed_at`. Lab › Uploads reads this to show Analyzing / Analyzed / Couldn't-analyze + Retry.
- **Retained attempt log.** A new `analysis_attempt` table records one row per attempt — successes included (rates need a denominator) — with code/stage/diagnostics, `algorithm_version`, `api_revision`, `capture_mode`, `source`, `content_hash`, clip facts and `env`. Like `feedback` (DEC-059) it carries **no FK cascade** (plain uuids), so it outlives shot/account deletion and the score reset. An `analysis_failure_rates` view aggregates by day × engine version × capture mode × failure code. Owner-only read; service-role write.
- **Upload de-duplication paused.** The DEC-055/DEC-043 "same clip → same shot" short-circuit is now behind `LANESIGHT_UPLOAD_DEDUPE` (**default OFF**) so a bowler can re-analyze the same clip while the engine is changing. Live-capture content-hash de-dup is unchanged.
- **Upload analysis is presented at the app root.** The analyzing cover, the result and any failure are shown from the root (not the Upload screen), so navigating away mid-analysis can never orphan the result. The screen stays awake throughout (reaffirms DEC-068).

**Why:** During active engine development most "bugs" are really unhandled failure modes. Making failures explicit, measurable and non-scary turns them into triage data instead of lost shots and opaque errors.
**Date:** 2026-10-27
**Status:** ACCEPTED (Dev Build v0). Migration `019_analysis_attempts.sql`.
**Supersedes:** the upload de-duplication clause of DEC-055 / DEC-043 **while `LANESIGHT_UPLOAD_DEDUPE` is unset or 0** (the rest of DEC-055 — uploads are standalone, don't count, live under Lab — is unchanged).

### DEC-087 — Profile: separate editable First/Last/Email/Phone/DOB, autosave, no-default DOB, grip + PAP in MVP
**Decision (Shayne, 2026-10-27):**
- **Contact fields are separate and editable:** First name, Last name, Email, Phone (optional), Date of birth. `profiles` stores `first_name`/`last_name` (display_name kept as "First Last" for existing readers) + `phone`.
- **Date of birth has no default anywhere.** Onboarding and Profile start empty ("Select date"); onboarding can't continue until the user explicitly enters a date, and no date the user didn't pick is ever saved. The server enforces a real past date **and** the 13+ gate on **create and edit** (missing DOB at profile creation is rejected).
- **Profile autosaves; the Save button is removed.** Toggles/pickers save on change; text/number fields save when editing ends (focus leaves / Return), with a brief inline "Saved" and the server's validation error shown inline on the field, keeping the user's input (never reverted).
- **Email changes go through Supabase Auth** (`updateUser({email})` → confirmation link). The app shows "Check your new email to confirm," keeps showing the current email until confirmed, and never writes email into `profiles`.
- **Grip (middle pitch, span) and PAP (over, up) are MVP + dev-build scope** (amends DEC-074 from target-state), stored per bowler in Profile › Advanced, in inches, optional. Values validated against cited sane ranges (reject, never clamp). They flow into the configured-reaction code (`bowler` arg) but apply **no** reaction change yet — PAP is already baked into a recorded layout, and there is no sourced pitch/span→reaction model, so they're stored and surfaced, with the plug-in point documented (`configured.py` `# PAP-DERIVE`).

**Why:** Editable, separate fields match how people think of their details; a defaulted DOB silently (and wrongly) satisfies the age gate and pollutes data; autosave stops edits being lost; grip/PAP are needed for layout-aware ball stats and belong to the bowler.
**Date:** 2026-10-27
**Status:** ACCEPTED (Dev Build v0). Migration `020_profile_fields.sql`.
**Supersedes:** the combined "Name" field and read-only Email/Phone/DOB rows on Profile; the "Coming later" grip/PAP rows; the Save-profile button; and advances DEC-074 from target-state to MVP/dev-build.

### DEC-088 — Shot card: 3D lane view; core metrics split into "Your throw" and "Lane & pins"; one coach takeaway from both
**Decision (Shayne, 2026-10-27):**
- **Lane picture = a 3D down-the-lane view rendered live from the shot's measured data** (not a photo, not AI art): true-scale lane, arrows and pins; the ball path is a **smooth curve fitted through the tracked points** (never drawn point-to-point); the **target line is always shown** as a blue band; Entry and Breakpoint labels are pinned to their spots; result chip and legend on the image. Replaces the flat perspective lane recreation.
- **Core metrics as rings, in two groups inside one "Shot read" card:**
  - **Your throw (execution):** Speed, Rev rate, Target (board at the arrows vs the target). Each is compared with the bowler's **normal throw** (personal baseline median, "= your avg", "↑0.9 vs avg"; "Building your normal (n/10)" until the baseline exists). Badge + one-line verdict, e.g. "Good · your normal throw", "Off · faster than usual".
  - **Lane & pins (reaction):** Breakpoint (board @ distance), Entry board, Entry angle, each vs the target line. Badge + one-line explanation, e.g. "Lane held it · light", "Went long · light".
  - **Coach takeaway (one action) decided by both groups:** good throw + good reaction → keep the line; good throw + miss → lane move (feet/eyes; a ball change only if it keeps happening after moves); off throw + a miss the throw explains → **no move, repeat your normal throw** (never change balls or lines for a bad throw); off throw + good result → don't build on it. Implements the execution classification in BUILD_PLAN M4-02 (EXECUTED / EXECUTION_MISS / REACTION_CHANGE).
- **Far lane not read:** the path is drawn only where measured, the far lane is dimmed and labeled "Not visible from this camera spot"; Lane & pins rings show "—" / Not read; the coach says "No move yet" with a camera-setup link (DEC-065 fallback).
- Everything else (laydown, launch, loft, pocket, impact energy, axis metrics) moves behind **All metrics**; notes behind **Your notes**. Axis tilt/rotation are not shown until video measures them.
- Primary button **"Record next shot"** (was "Record shot N+1"). Upload results use the same layout with "Uploaded clip · Shot Analysis", a not-counted note and **Done**.

**Why:** The old card opened with warnings and a long metric list, so the bowler couldn't tell in a second what was good or bad or what to do. Whether a shot strikes depends on two separate things: the throw (speed, revs, accuracy vs the bowler's normal) and how the lane and pins reacted. Keeping them apart stops wrong advice, e.g. moving or changing balls after a throw that was simply faster than usual.
**Date:** 2026-10-27
**Status:** ACCEPTED (target state). Figma › Target state – v3.7: "Shot card · Shot Analysis · v3.7", states "off throw → no move" and "far lane not read", "Upload result · Shot Analysis · v3.7". Old card, options A–D drafts → page "archived".
**Supersedes:** in part DEC-073 / METRIC_TO_SCREEN_SPEC v1.0 Shot-card column (lane picture form, ring set, next-move card → coach takeaway) and the DEC-080 button label.

### DEC-089 — One app, one design set: the "dev build vs target state" split is retired
**Decision (Shayne, 2026-10-27):** There is a **single LaneSight app**, built to the v3.7 screen designs in `02_DESIGN/dev_build_v0/`. The two-tier model — a limited "Dev Build v0 (now)" versus a fuller "target state (later)" — is **removed**. The dev build *is* the target-state design.
- Every accepted decision that was scoped **"(target state)"** or **"the dev build follows when its designs are next updated"** now applies to the one build, in effect immediately. This resolves the scoping clauses in DEC-055/DEC-067 (disabled tabs), DEC-073 and DEC-085 (Stats), DEC-074 (grip/PAP), DEC-083 (Home building), DEC-084 (Coaching) and DEC-088 (Shot card): no "later version" gate remains on any of them.
- When a new design lands in `02_DESIGN/dev_build_v0/`, build it into the app directly — there is no separate target-state backlog to defer it to.
- **Naming:** the design folder keeps the name `02_DESIGN/dev_build_v0/` for now (renaming it is an optional design-side cleanup); treat it simply as "the LaneSight screen designs." The `target_state/` folder holds forward design-system notes + `lane_render`, not a second app.

**Why:** The app has caught up to the designs, so maintaining two tiers only created confusion — decisions kept getting parked as "target state, dev build later" when the intent was to build them now (e.g. the Coaching tab Shayne expected to see). One app, one design set.
**Date:** 2026-10-27
**Status:** ACCEPTED.
**Supersedes:** the target-state-vs-dev-build scoping language across DEC-055, DEC-067, DEC-073, DEC-074, DEC-083, DEC-084, DEC-085, DEC-088 and in CLAUDE.md / AGENTS.md / CURRENT_STATE.md / MVP_HANDOFF.md.

### DEC-090 — Shot card adjustments: data labels on the lane view; Accuracy ring; Lane & pins = Entry point, Entry angle, Power
**Decision (Shayne, 2026-10-27):**
- The lane view carries three pinned data labels, each with a dot on the ball path: **Entry point** (board + angle), **Breakpoint** (board + distance) and **Arrows** (board + target board). Path markers are drawn on top of the path and pins so the entry point stays visible; pin glow is reduced.
- The "Target" ring in Your throw is renamed **Accuracy** (DEC-031 score, 0–100) with the arrows board vs target underneath.
- **Lane & pins rings = Entry point, Entry angle, Power.** Power is Impact Energy (DEC-024, joules at entry, best effort) compared with the bowler's normal. Breakpoint stays on the lane view and in All metrics. Carry (pin action) is not measured by video and is not shown.
- Far lane not read: all three Lane & pins rings show "—" / Not read (Power needs entry speed).

**Why:** The entry point was hard to see on the image; entry, angle and the energy the ball carries into the pins are what explain the pin reaction.
**Date:** 2026-10-27
**Status:** ACCEPTED (target state). Figma frames updated in place.
**Supersedes:** in part DEC-088 (ring set and Target label).

### DEC-091 — The app's design source is Figma "Target state – v3.7"; every design change becomes a build item in APP_DESIGN_CHANGES.md
**Decision (Shayne, 2026-10-27):**
- The app is built to the **Figma target-state designs**: "Lanesight - Product UX - Design" (`k6F8iHTtl2ZHvnXlHmYPnd`), page "01 — Home & Foundation", section **Target state – v3.7** (guide: `02_DESIGN/target_state/README.md`). This corrects DEC-089, which pointed the one app at `02_DESIGN/dev_build_v0/`. That Claude Design canvas was last synced on 2026-10-26 (v3.8) and has none of the later Figma changes.
- `02_DESIGN/dev_build_v0/` is **frozen** (historical reference); it is not updated again. Where it disagrees with Figma, Figma wins.
- **Every design change is incremental build work.** In the same session that Figma changes, Claude (claude.ai) adds an entry to `03_ENGINEERING/APP_DESIGN_CHANGES.md`. Each entry has: what changed, Figma node, PNG export in `02_DESIGN/target_state/screens/<date>/`, exact spec, data/API, done-when, and status NOT BUILT.
- Claude Code builds every NOT BUILT entry, marks it BUILT (commit), and records any deliberate difference as DIFFERS.
- DEC-089's "one app, no target/dev split" stands; only its design-folder pointer is replaced.

**Why:** Today's Shot card changes (DEC-088, DEC-090) lived only in Figma and in notes Claude Code was told not to build from, so they never reached the app. One design source plus an explicit build queue makes every change visible and trackable.
**Date:** 2026-10-27
**Status:** ACCEPTED.
**Supersedes:** in part DEC-089 (the `02_DESIGN/dev_build_v0/` design-source pointer) and the matching lines in CLAUDE.md, AGENTS.md, CURRENT_STATE.md and `02_DESIGN/dev_build_v0/README.md`.

## Superseded decisions
- DEC-078 — background analysis withdrawn by DEC-080; DEC-068 (blocking Analyzing screen) reinstated.
- DEC-053 / DEC-058 — feedback storage and retention superseded by DEC-059 (one retained `feedback` table).
- DEC-049 — "form from clip" on the Shot card superseded by DEC-056 (shot/form split by mode).
- DEC-011 — withdrawn; replaced by DEC-054 (official Figma logo).
- DEC-037 — composite weighting superseded by DEC-038; S subformula and historical definition retained.
- DEC-001 — partially superseded by DEC-018 (see entry above).
- DEC-019 — partially superseded by DEC-035 (video replay deferred; Practice-only sessions).
- DEC-022 — Speed definition refined by DEC-030, then DEC-036.
- DEC-023 — default frame rate superseded by DEC-028.
- FEATURE_REVIEW "Power" — replaced by DEC-024 Impact Energy.
- DEC-030 — release-speed headline superseded by DEC-036 (60 ft average, after far-lane track recovery); release kept as the secondary `speed_release`.
- DEC-035 — "importing clips from Photos is post-MVP" superseded by DEC-043 (Upload Video to Analyze is MVP).
- DEC-033 / DEC-035 — the capture framing gate is superseded **for the dev build** by DEC-045 (an advisory spot check replaces the blocking gate); the gate remains the plan for later builds unless a further DEC changes it.
- DEC-050 — "no strike" superseded by DEC-066 (strike / not-strike per throw); no game scores, spares or leaves still stands.
- DEC-042 — the disabled MVP "Compare to a PBA Pro" tile superseded by DEC-069 (hidden for now; post-MVP direction unchanged).
- DEC-021 / DEC-049 — sensor pairing and the per-shot sensor question removed from MVP by DEC-070 (kept in the dev build; parked for a future partnership).
- DEC-035 — "No Session Summary screen" superseded by DEC-072 (score popup on end, session summary also used for past sessions).
- DEC-089 — design-source folder (`02_DESIGN/dev_build_v0/`) superseded by DEC-091 (Figma Target state – v3.7 + `03_ENGINEERING/APP_DESIGN_CHANGES.md`).
- DEC-088 — ring set and "Target" label partly superseded by DEC-090 (Accuracy; Entry point, Entry angle, Power).
- DEC-073 (Shot-card column) / DEC-080 (button label) — partly superseded by DEC-088 (3D lane, throw vs lane groups, coach takeaway, "Record next shot").
- DEC-055 / DEC-043 — the upload de-duplication clause is superseded by DEC-086 while `LANESIGHT_UPLOAD_DEDUPE` is off (default); the rest of DEC-055 stands.
