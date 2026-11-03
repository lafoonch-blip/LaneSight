# LaneSight Decision Log
Status: CANONICAL  
Version: 1.84  
Last Updated: 2026-11-03  
Owner: Shayne  
Supersedes: v1.82 (feat/ff-feedback DEC-123/124/125 + DEC-122) merged with feat/ios-lane-parity (DEC-126/127); + DEC-128 on-device Form

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
**Status:** ACCEPTED (Dev Build v0 designs 3.4), **measured-metric list AMENDED by DEC-118** (MVP Form metrics = step count, approach duration, swing timing events + release-vs-slide, tempo consistency; drift/spine tilt/knee bend → post-MVP). On-time windows and thresholds are provisional owner settings until validated on real clips.
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

### DEC-092 — Analysis latency: optimize the existing pipeline first; measure before changing the CV
**Decision (Shayne, 2026-10-27):**
- Optimize the current server pipeline before moving more CV onto the iPhone. The phone handles framing, warm-up, trimming and hints; all metric math stays on the server (one validated implementation, DEC-062/065).
- Order: **P0** persist per-stage timings (phone + server), ~2 s precheck, wake Cloud Run when Record opens, verify SDR capture · **P1** decode once, pass the phone's trim window · **P2** low-res detection + full-res measurement · **P3** timestamped observation interface. Plan: `03_ENGINEERING/ANALYSIS_LATENCY_SPLIT_PROPOSAL.md` §6.
- Every optimization runs the same reproducible clip benchmark and passes a regression gate: less time, metrics within tolerance of the reference run, no new failures, cost per shot not up out of line with the gain.
- Report analysis time (server CPU per successful shot) separately from user-perceived latency (tap-stop to shot card, successful vs failed).
- No new speed requirement; DEC-043 unchanged. Measured results inform that later.

**Why:** A phone-trimmed shot still took ~280 s of server analysis on 2026-10-27, and a framing failure took 140 s to fail. The pipeline decodes the clip ~9 times, but per-stage timings aren't persisted, so the biggest cost must be measured before the CV changes.
**Date:** 2026-10-27 · **Status:** ACCEPTED · **Supersedes:** none

### DEC-093 — CV robustness from the IMG_8929/8930 review: honesty gates, crash guard; the mounted down-lane POV stays an honest failure
**Decision (2026-10-28, gated by DEC-092 benchmark; CV change under the DEC-062 ablation discipline):**
- **Speed honesty gate (shipped):** the ball-speed sanity check was upper-bound only (>30 mph). It now rejects the full implausible range — outside **8–30 mph**, negative, or non-finite → coded `IMPOSSIBLE_SPEED_SCALE`, never surfaced as `ok`. Per-segment speeds (`speed_early/late/release`) that come out ≤0 become `unavailable` with a reason. (The IMG_8929 pre-fix "6.1 mph ok / STRIKE" can no longer happen; that symptom was already gone once the trim fix picked the right window — this closes the gap for good.)
- **Least-squares/SVD crash guard (shipped):** a degenerate low-angle/off-axis geometry (IMG_8930) could raise an uncaught `LinAlgError: SVD did not converge`. The vanishing-point solve is validated (`_vp_solve`) and raises the coded `LANE_GEOMETRY_UNUSABLE`; `core.py` converts any pipeline `LinAlgError` into that coded failure as a backstop. No analysis can crash the job now.
- **Record the chosen lane (shipped):** `capture_quality.lane = {center_x_px, lanes_detected}` so a review can see which lane was measured.
- **Mounted down-lane POV (IMG_8929) stays an honest failure — accepted, not a regression.** Investigated end-to-end: the bowler's lane (lane 9) is paler than the return-side lane (lane 10), so `find_lanes` — which stops at the first saturation floor that yields a lane — detects only lane 10; the ball on lane 9 is never in lane 10's search region. Even when lane 9 is forced to be detected (multi-floor scan), its foul-line fit is numerically degenerate (the SVD failure above) and the ball is untrackable through the mid/back lane. A multi-floor detection change was built and reverted: it helped no clip in the test set (lane 9 remains unmeasurable) and added risk to the frozen core for zero demonstrated benefit. So IMG_8929 meets its acceptance via "**unavailable with a reason**" — and the reason is now accurate, never a fabricated number or a crash.
- **The real unlock is the frontier, deferred:** detecting a paler non-primary lane AND dense back-half ball tracking on a far/foreshortened lane. High-regression-risk CV work; not attempted now beyond the gated experiment above.

**Why:** Accuracy over coverage (DEC-026/027/061): an impossible number must fail honestly, and no clip may crash the job. The down-lane POV is Shayne's intended capture (see memory `lanesight-8929-capture-style`), but it isn't measurable with the current detector/tracker; the honest failure is the correct behaviour until the frontier work lands.
**Date:** 2026-10-28 · **Status:** ACCEPTED · **Supersedes:** none · **Gate:** full manifest PASS (validation clips byte-identical, no new failures); 303 tests green.

### DEC-094 — CV accuracy architecture: detection first, shadow tracking, uncertainty contract
**Decision (Shayne, 2026-10-28):** the program for making the CV accurate (not just non-crashing). Full handoff: `03_ENGINEERING/CV_ACCURACY_ARCHITECTURE_HANDOFF.md`.

**1. Development order**
1. **Done — DEC-093:** speed honesty gate, SVD / least-squares crash guard, chosen lane recorded on the shot.
2. **Phase-2 camera validation** (`CV_PHASE2_CAMERA_VALIDATION_PROTOCOL`) + a labeled test set covering more camera positions, lighting and lanes.
3. **Correct-lane detection and density.**
   - **3a. Correct-lane detection + stable foul-line geometry in multi-lane views.** On IMG_8929, `find_lanes` stops at the first saturation floor and finds only the lane by the ball return; the bowler's lane 9 is never detected, and its foul-line fit is numerically degenerate even when forced. Density work can't help until this is solved.
   - **3b. Detection density:** detect more real ball positions, especially from 40 to 60 ft.
4. **Physics-constrained tracking,** as a shadow experiment on top of the better detection.
5. **Isolate the release-speed bias** (see item 4).
6. **DEC-092 latency work,** in its existing order.

Steps 3–5 are gated behind Phase-2. The dataset, labels, evaluation harness and the coaching uncertainty contract (item 5) can start now: Phase-2 needs the first three, and item 5 needs no new CV.

**2. Detection is evaluated independently of tracking.** Every detector reports ball-detection recall, positional error, false positives, and observations per lane region (**0–15 / 15–40 / 40–60 ft**). A predicted/interpolated position never counts as a detection or a measured position. **`observed_fraction` does not exist yet** — it is a **new, additive** per-metric field (the share of the metric's span observed rather than predicted). Until it exists the rule binds to what does: `Measurement.status`/`confidence` + the far-lane plausibility gate.

**3. Promotion rule — accuracy, coverage and runtime measured separately.** A candidate runs in **shadow** against the current engine on a locked test split, promoted only when ALL hold: metric accuracy no worse on any metric beyond tolerance; coverage no worse (better where claimed); the **plausible-but-wrong rate** (a metric shown measured/ok whose error exceeds tolerance vs ground truth) does not rise; runtime/cost within DEC-043 caps. Finding more points is not enough — if extra detections make the trajectory worse, it's rejected. **Partial promotion is allowed** per lane region or per metric (e.g. the new detector 40–60 ft, baseline elsewhere), provided: the routing is fixed by region/metric (not chosen per shot); each promoted region/metric meets every condition on its own; the plausible-but-wrong rate does not rise in ANY region. Two tolerance sets stay separate: accuracy-vs-ground-truth (this DEC's harness, `validation/cv_eval/tolerances.json`) and don't-regress-the-current-engine (DEC-092 `ops/perf_benchmark.py`).

**4. No unvalidated correction factors.** The ~9%-low release-speed bias is isolated one cause at a time against the same reference (contact-point vs visible-center · longitudinal calibration · event-timing definitions). No universal multiplier. The existing ×1.12 rev factor (`REV_SENSOR_FACTOR`) gets blind validation against independent reference data, or it's removed and rev reported unavailable where unsupported.

**5. Uncertainty is a shared contract between measurement and coaching.** Each metric's `status`/`source`/`uncertainty` drives Score inputs, insights, recommendations and the coach takeaway. Each coaching adjustment declares the tolerance it needs (e.g. a 1-board move needs arrows-board uncertainty ≤0.5 board); if the measurement falls short the adjustment is suppressed and the shot card says why. Statuses map to Measured / Estimated (only where approved + labeled) / Unavailable-with-a-reason. Sensor source parked under DEC-070. Additive schema only.

**6. ML models must be license-safe.** Only Apache-2.0 / MIT / BSD code AND weights, verified from the actual LICENSE + weights. AGPL excluded (e.g. Ultralytics YOLO, **including Ultralytics' RT-DETR port**) unless a later DEC approves a commercial license. Apache-2.0 implementations (e.g. RT-DETR from lyuwenyu/PaddleDetection or HF-transformers) are eligible after their LICENSE files are checked.

**Preserved:** DEC-062/065 (geometry first; far-lane unavailable until Phase-2 passes) · DEC-070 (Ruby validation-only) · DEC-092 (latency order) · DEC-043 (cost caps) · DEC-093 (lane selection recorded on the shot) · existing measurement schema (changes additive only; `observed_fraction` is one such addition).

**Why:** Far-lane failures are a detection problem first — on IMG_8929 the bowler's lane isn't detected at all, and the ball gets only 3–11 observations on the lane that is; a tracker can bridge a few misses but can't rebuild a path from that few observations without large uncertainty. A believable wrong number hurts coaching more than an honest "unavailable." Correction factors hide calibration errors that vary by camera setup.
**Date:** 2026-10-28 · **Status:** ACCEPTED · **Supersedes:** none

### DEC-095 — Form: physiological event sanity gates; the display follows only trustworthy events
**Decision (2026-10-28):** located swing events are gated before anything is shown. **Release** must sit within −0.10…+0.15 s of the slide stop (E8) — it's the anchor the delivery is timed from, so if it's off, the whole delivery was mis-isolated and **every** display event is dropped. **Ball-start→release** must be 1.3–2.5 s. Events must be in chronological order. A gated-out event is nulled at the source (`pose.extras['events']`), so it produces **no thumbnail, no time, no Early/Late checkpoint, and no fundamentals position** — the entire display chain (key frames, `timing_checkpoints`, `measured_positions`) reads the gated events. Honest "unavailable with a reason" instead of a confident-wrong key position. Also: a key-frame crop requires the torso (both shoulders + both hips) visible, else the uncropped frame is shown (no thighs crop on a blurred slide/release frame).

**Naming note (not a bug):** the FORM pipeline's view `down_lane` means a **side/profile** view (`classify_view_from_pose`: bowler moves across the frame), so the app's `down_lane → "Side view"` label is correct — an overloaded name vs the CV pipeline's literal down-lane. A future rename (form `down_lane` → `side`) is advisable but deferred (touches stored records + DEC-076).

**Why:** Form shot c9df6ca0 displayed key positions that didn't match their labels — release read 0.57 s before the slide stopped and ball-start→release was 1.08 s (the delivery window was mis-isolated, ~1 s late). A believable-but-wrong frame/timing misleads more than an honest gap (consistent with DEC-026/061). Full root-cause of the mis-isolation needs the clip in the form eval set with hand-marked frames (pending Shayne).
**Date:** 2026-10-28 · **Status:** ACCEPTED · **Supersedes:** none

### DEC-096 — Live sessions stay in the session until the bowler ends them (Shot AND Form)
**Decision (Shayne, 2026-10-28):** a live session is the landing point after every analysis until the bowler ends it. Applies to live **Shot** analysis and live **Form** analysis. Uploads are unchanged (standalone, DEC-055).
- Starting a live session lands on the **Active Session** screen. From then on, the Active Session is the landing point after every analysis, until the bowler taps **End session** there.
- **Success →** shot/form details → Done/close returns to the Active Session. "Record next shot" from details goes straight to recording (DEC-080).
- **Failure →** the Analyzing/failure screen shows the friendly reason (DEC-086) with **Retry** (no re-recording) and **Back to session** (returns to the Active Session). The failed shot appears in the session's shot list as **Couldn't analyze**, with Retry.
- **Nothing in the session returns to Session Setup.** Setup is reached only when starting a NEW session. Target line and ball/oil stay editable on the Active Session (DEC-071).
- Leaving the Lab tab or backgrounding the app does **not** end the session. Returning to Lab shows the Active Session. After an app relaunch, offer **Resume session** (DEC-079 resume state).
- **Ending is only from the Active Session** → session-end popup + summary (DEC-072).

**Why:** a live practice session is a continuous loop (record → review → record next); bouncing back to Setup or out of the session after each shot breaks the rhythm and risks losing the session. One clear landing point (the Active Session) with one explicit exit (End session) makes the loop predictable and the session durable across failures, tab changes and relaunches.
**Date:** 2026-10-28 · **Status:** ACCEPTED, **AMENDED by DEC-119** (session stays active until the user ends it; survives navigation/background/crash). · **Supersedes:** nothing — clarifies DEC-080/081 and extends them to failures and Form.

### DEC-097 — Ball and oil pattern are editable on the Active Session (live Shot sessions)
**Decision (Shayne, 2026-10-28):** the Active Session shows the current **Ball** and **Oil pattern**, each with a Change control, next to the target line (DEC-071). Live Shot sessions only — Form sessions have no ball/oil (DEC-081).
- **Defaults:** the values chosen at Setup, which default to last used ("From your last session", DEC-079). Changing them does **not** require returning to Setup.
- **Ball picker:** the bowler's arsenal (same list + card style as Setup), current ball marked; "Add a ball" opens the existing add-from-catalog flow and returns to the Active Session with the new ball selected.
- **Oil picker:** the oil-pattern library (DEC-052), same search/list as Setup, current pattern marked.
- **A change applies to the NEXT shot only.** Ball and oil are **locked per clip at record time**, so a shot already recorded or analyzing keeps the ball/oil it was thrown with.
- **Per-shot provenance:** each shot row and shot card shows the ball used. When ball or oil changes mid-session, the shot list shows a small divider ("Switched to <ball>", "Oil: <pattern>").
- **Recommendations + ball-reaction (DEC-044) use the ball/oil stored on that shot**, never the session's current value.

**Backend:** ball and oil are stored **per shot**. Oil was per-session; a per-shot `oil_pattern_id` is added (additive migration, pending apply) and new shots backfill it from the session value at record time. "From your last session" returns the last values actually used, including mid-session changes.
**Date:** 2026-10-28 · **Status:** ACCEPTED · **Supersedes:** nothing — extends DEC-071/079/052/044 and DEC-096.

### DEC-098 — Owner-only ops reporting: honest views in a private schema, read via owner-checked RPCs, with a Supabase-Auth dashboard; instrumentation held
**Decision (2026-10-28):** build production ops reporting as a thin, honest layer over the signals LaneSight already records — the retained `analysis_attempt` log (DEC-086/092) plus `feedback`/`shots`/`sessions`/`profiles` — a concrete first slice of `01_PRODUCT/PRODUCTION_MONITORING_OBSERVABILITY_CONTEXT.md`. Four parts shipped; §2 instrumentation held.
- **Definitions (§3):** `ops-dashboard/definitions.json` (machine-readable single source of truth) + `03_ENGINEERING/OPS_REPORTING_DEFINITIONS.md` (human). Every metric names its real source column, formula, denominator, honesty rule, and observability domain.
- **Owner-only views + RPCs (§4):** migration `025_ops_reporting.sql` — ten aggregate views in a **private `ops` schema** (not exposed by PostgREST; `usage` revoked from anon/authenticated), read **only** through SECURITY DEFINER RPCs `public.ops_rpc_*` that raise `42501` unless `ops.is_owner()` (auth.uid() == the id in `ops.app_owner`). No service_role, no per-user RLS trickery — the owner's own JWT is the sole key.
- **Dashboard (§5):** Next.js app `ops-dashboard/` (Vercel project `lanesight-ops`) that signs the owner in with **Supabase Auth** and calls the RPCs with their JWT. Two-layer owner gate: Next middleware (`user.id === OPS_OWNER_ID`, else 403) + the DB RPC check. Renders `HEALTHY / NO DATA / NO ACCESS` per tile; env is non-secret only (URL + publishable key + owner id).
- **Validation (§1):** `validation/validate_definitions.py` (static defs↔SQL + honesty + owner-RPC security invariants) + `validation/assertions.sql` (post-apply DB checks).
- **Owner identity** single-sourced as `owner.py OWNER_USER_ID = 551bc775-dee4-41bd-a19c-116e8691d053` (lafoonch@gmail.com), mirrored by `ops.app_owner` and the dashboard's `OPS_OWNER_ID`.
- **Honesty:** staged `ls_*` accounts (DEC-063) excluded from every canonical view; `nullif` denominators (empty window → NULL → NO DATA, never 0); the two uninstrumented domains (Storage, FinOps) are NO DATA via `ops.coverage_status`, never faked.
- **§2 held** (`ops-dashboard/SECTION2_INSTRUMENTATION_PATCH_PLAN.md`, M1–M5): product events, cost metering, API middleware, user_ref pseudonymisation, storage snapshot — edits `app.py`/`store.py`/iOS; build after this merge settles.
- **Advisor note:** the 9 `ops_rpc_*` definer functions trip lint `0029` (authenticated-executable definer) — intentional and safe (each checks `ops.is_owner()`); see `03_ENGINEERING/OPS_REPORTING_DEFINITIONS.md` §6.

**Date:** 2026-10-28 · **Status:** ACCEPTED (migration 025 applied live `europwryibstnmipbvam`; security proven: anon/authenticated denied on `ops`, non-owner RPC → 42501, owner RPC → correct KPIs) · **Supersedes:** nothing — additive to DEC-086/092.

### DEC-099 — App usability batch: seamless tab loading, tab bar only on the 4 primary tabs, save-to-phone instead of retention, default ball, editable names, settable Form baseline, no Shot/Form re-ask on Upload
**Decision (Shayne, 2026-10-28):**
1. **Tabs load seamlessly.** A tab's page appears all at once, not section by section. Home, Stats (all four views) and Lab (sessions, uploads and each card's rings) fetch every section in parallel and publish together; a revisit keeps what's on screen and refreshes silently (a failed refresh never replaces good data with an error); Stats and Lab are prefetched in the background once Home is up. Implementation: `ios/…/Common/TabDataStore.swift`.
2. **The bottom tab bar shows only on Home · Stats · Lab · Coaching.** Every screen pushed on top of a tab (Profile, Settings, Setup, Active Session, Upload, metric detail, achievements, ball setup, Form baseline, summaries…) hides it, so a pushed screen can't stay open underneath another tab. **Supersedes in part DEC-096**'s "leaving the Lab tab doesn't end the session": with the tab bar hidden on the Active Session, the way out is End session (backgrounding the app still keeps the session).
3. **Video storage: the bowler chooses only "Save recordings to my phone"** (Settings › Videos, default OFF; adds each live recording to Photos with add-only access, saved before analysis so a failed analysis still keeps the clip). **How long video stays on LaneSight's servers is set by LaneSight, not the user, and will be plan/subscription-based** (policy TBD). The "Raw video retention · 30 days" row is removed. The Privacy Policy must describe server retention when it's defined.
4. **Default ball.** A bowler can mark one arsenal ball as their **default** — a checkbox on Add ball (on by default when they have no default yet) and on the ball's setup/edit screen; shown as a "Default" tag in Profile › Arsenal and the ball picker. The default is separate from the **current** ball (which moves whenever a ball is picked, DEC-097). **A new session starts with the default ball**; "From your last session" still overrides it. Storage: `user_balls.is_default` (migration 026, one per user by partial unique index); API `make_default` on POST, `is_default` on PATCH; retiring a ball clears its default.
5. **First and last name are editable from Profile for every account.** Root cause: the DEC-087 "DOB required" gate fired on every name edit for a profile created before the DOB gate, so the save always failed. The gate now applies only when the profile is first created. Phone (optional) stays editable; editable rows now show a pencil so they don't read as static labels.
6. **The Form baseline is defined and settable** (Profile › Form baseline). The values are the engine's measured swing phases, in seconds: **Pushaway** (ball starts moving → ball at hip, E2→E3), **Backswing** (hip → top of backswing, E3→E4), **Downswing** (top → bottom of the swing, E4→E6), **Release** (bottom of the swing → release, E6→E7); **Total swing** = their sum (= `swing_time`, ball start → release). Modes: **Use my average** (median of the bowler's measured form deliveries once established), **Enter my timing**, or **No baseline**. Plus **"Use this delivery as my baseline"** on a Form result (saves only that delivery's measured phases). Server validates: mode `entered`|`average`, each value 0 < t ≤ 3 s (sanity bound, not a target — DEC-095 puts the whole swing at 1.3–2.5 s), at least one phase when entered; `null` clears it.
7. **Once the bowler picks Shot or Form Analysis, nothing asks again.** The Upload screen no longer shows "What's in this clip? Shot / Form" — the mode comes from the Shot/Form card (Form uploads also drop the target fields). The Lab header's upload shortcut (an entry with no Shot/Form choice) is removed; the flow is Shot/Form → Live session or Upload video (per the Lab flow decision).
**Why:** Shayne's 2026-10-28 test pass: tabs filled in piece by piece; pushed screens stayed open under other tabs; the retention row was unclear (server vs phone) and isn't the user's call; no way to set a default ball; names couldn't be saved; the Form card compared against a baseline that couldn't be set; Upload re-asked Shot vs Form.
**Date:** 2026-10-28 · **Status:** ACCEPTED, **AMENDED by DEC-119** (tab bar is NO LONGER hidden on the Active Session). · **Supersedes:** in part DEC-096 (tab-switch-away bullet); the "Raw video retention" Settings row (v3.7 Figma 434:6174); in part DEC-087 (DOB gate scope — create only).
**Deploy order:** apply migration `026_arsenal_default_ball.sql` to live Supabase BEFORE deploying the API (the arsenal select now reads `is_default`).

### DEC-100 — Every analysis is reproducible: clips retained 7 days for diagnostics, phone-side failures logged, failures get a root cause
**Decision (Shayne, 2026-10-28):**
- **Retain every analyzed clip for 7 days** (private `shot-clips` bucket, newest 40 per user; `LANESIGHT_CLIP_RETENTION_DAYS` / `LANESIGHT_CLIP_KEEP_MAX` override; 0 = delete). The path is recorded on the attempt (`analysis_attempt.clip.storage_path`). Old clips are purged on each analysis. Owner-only access via the service role (`ops/fetch_clip.py` downloads and re-runs). This is LaneSight's diagnostic retention under DEC-099 (LaneSight sets server retention); the Privacy Policy must state it before Beta.
- **Phone-side failures are logged** (`POST /analysis/client-failure` → `analysis_attempt`, code `CLIENT_<STAGE>`, stage `client`), so no attempt is invisible.
- **Every failed attempt stores 4 snapshot frames** (small JPEGs in `analysis_attempt.clip.frames`) so the framing can be inspected straight from the database, and the phone records what its trim kept (`orig_duration_s` / `upload_duration_s` / `orig_bytes` in the client timings).
- **A Form delivery whose swing events all fail the DEC-095 gates is a coded failure** (`FORM_DELIVERY_NOT_ISOLATED`, with the gate numbers and a "keep your whole approach in frame" tip), not an "analyzed" empty card. **Form clips are no longer motion-trimmed on the phone** (that trim is tuned to the ball and can cut the start of the approach); they're only size-fitted.
- **Every failure gets a root-cause pass**, tracked in `02_RESEARCH/ANALYSIS_FAILURE_RCA_<date>.md`, with experiments on the retained clip and a validated fix (DEC-062/094 gates apply to CV changes).
**Why:** Tonight's 4–5 failed uploads couldn't be diagnosed. The clip was deleted on analysis and phone-side failures left no trace. Uploaded Shot clips have never produced a result (0/6), Form uploads return empty cards, and the same failing clips were being re-run with no way to find out why.
**Date:** 2026-10-28 · **Status:** ACCEPTED · **Supersedes:** "clips are not retained" (the storage-upload path comment of 2026-10-26; `LANESIGHT_KEEP_CLIPS` debug flag).

### DEC-101 — Phone trim keeps the whole shot; one deploy line
**Decision (2026-10-28, from the DEC-100 evidence):**
- **Shot uploads/captures: the phone trim only cuts the dead time BEFORE motion** (keeps 1 s before onset and at least 10 s after onset). The old motion window ended when the bowler stopped moving, before the ball reached the pins. Evidence: a 17.1 s clip was cut to 2.85 s, the ball track ended at 2.74 s and the result was PIN_IMPACT_NOT_DETECTED; a 19.3 s clip was cut to 3.3 s and the far lane was "limited". **Form clips are never window-trimmed.** Re-encode-to-fit (bitrate only, fps and resolution kept) is unchanged.
- **Deploy only from a line that holds every accepted server change.** Rev 00036 was deployed from `dev-build-v0` without DEC-099/DEC-100, which silently dropped clip retention. `integrate/dec-099-100-with-ops` is that line until it's merged into `dev-build-v0`.
**Date:** 2026-10-28 · **Status:** ACCEPTED · **Supersedes:** the `VideoTrimmer` motion-window end (capture spec step 2: "pads ~0.4 s on each side").

### DEC-102 — Offline-first, hybrid measurement architecture
**Decision (2026-10-28; from `ON_DEVICE_ANALYSIS_PROPOSAL.md` v0.3 §12 DEC-A):**
- LaneSight adopts an **offline-first** app architecture: losing the connection never blocks the rest of the app.
- It targets **on-device Shot and Form measurement** where validated device capability permits. The cloud engine stays as the **fallback** (older/unsupported phones) and the **reference** engine for validation and reprocessing.
- **Coaching intelligence stays server-authoritative and needs a connection:** next-shot moves, insights, form findings and drills, the LaneSight Score, tiers and achievements.
- **Measurement-validity checks may run on the device; owner-only coaching policy stays on the server** (DEC-046 intact; boundary per proposal §6.3 — e.g. owner-editable form timing windows stay server-side, the device reports raw timings).
- The app picks its mode from **measured device capability**, not the model name. An older phone never produces lower-quality or estimated metrics just to keep the offline promise.
- Keeps DEC-055 (uploads never count), DEC-068/080 (blocking Analyzing screen then shot details), and all honesty/accuracy rules.
**Why:** independence from connectivity (value even at 20–30 s), potential speed (only if measured), and near-zero per-shot server compute (DEC-043). Competitive context: Bowlin ships on-device analysis; LaneSight's moat is trusted, validated measurement + coaching, not the raw metric.
**Date:** 2026-10-28 · **Status:** ACCEPTED · **Supersedes:** amends DEC-029 and DEC-033 (server-side-only analysis) and the **long-term scope** of DEC-092. DEC-092's near-term order and its "metric math stays on the server" rule **stay in force until the DEC-103 gates pass**; on-device metric math is the target architecture, not yet an active path. DEC-062 (production CV freeze) is lifted for this work's **shadow/validation** track; production CV behavior is unchanged until the gates pass.

### DEC-103 — Measurement provenance, validation and sync
**Decision (2026-10-28; proposal §12 DEC-B):**
- Every measurement carries **engine provenance** (`engine.platform` = `ios` | `server`, `engine.version`, `engine.build`), versioned **`MeasurementEvidence`** (observations layer; observed vs predicted kept separate), and status/uncertainty/calibration info.
- **Two separate gates** before device results become authoritative: (1) **ground truth** — the device engine meets the applicable DEC-034 accuracy gates vs Specto where available, with the server as the reference engine (DEC-105: Ruby removed from the validation process); (2) **parity** — device vs server stay within metric-specific tolerances, with status/unavailable disagreements reviewed and reason codes semantically equivalent. Both must pass.
- **Offline records sync idempotently** (client UUID + idempotency key, account-scoped, retry with backoff, survive force-quit, no duplicates). Sessions/measurements are immutable or revisioned; arsenal is revisioned (DEC-007/044); last-write-wins only for simple profile fields.
- **The server validates every device submission** (auth, ownership, schema, plausibility, accepted engine version) before it feeds Stats or the Score. A client-reported engine id is for tracing, not proof.
- An **engine-version compatibility policy** governs supported versions, deprecated metrics, recalculation where evidence/clips were retained, and quarantine of outdated/rejected engines so stats never quietly mix incompatible measurements.
**Why:** device-submitted results can't be blindly trusted (risk #5); mixed engine versions would corrupt long-term stats (risk #7); honesty requires measurement validity be separable from coaching policy.
**Date:** 2026-10-28 · **Status:** ACCEPTED · **Supersedes:** extends DEC-086 (`analysis_attempt`: device attempts sync with `env`/`source` marking the device), DEC-092 P3 (the "timestamped observation interface" **is** `MeasurementEvidence`, combined with DEC-094 §5's uncertainty contract — one interface, not a second), DEC-093/094 gates (reused on the device), DEC-095 (form event gates), DEC-065 (calibration provenance). No AGPL models (DEC-094 §6) on device or server.

### DEC-104 — Video transmission, contribution and retention
**Decision (2026-10-28; proposal §12 DEC-C):**
- Video is **not required** for measurement on a supported device.
- **Server-fallback** analysis may need an upload; the upload is **disclosed before processing**.
- **Server retention is set by LaneSight** and will be plan-based (DEC-099/DEC-100: clips retained in the private `shot-clips` bucket for a diagnostic window, default 7 days, then purged). The bowler controls **only** "Save recordings to my phone".
- Using retained clips for **validation and model improvement** is a **separately disclosed consent** in the Privacy Policy — never silent. Default and opt-in/opt-out wording need a **legal/privacy review before Beta**.
- Deletion schedules are defined with the retention policy.
**Why:** on-device measurement removes the need to ship video for supported phones; validation data must not be collected silently; retention is a LaneSight/plan decision, not a per-user toggle.
**Date:** 2026-10-28 · **Status:** ACCEPTED · **Supersedes:** builds on DEC-099/DEC-100 (now implemented: 7-day clip retention + `clip.storage_path`, verified live on rev `lanesight-api-00037-r6s`). Clarifies DEC-055 (uploads standalone) for the server-fallback path.

### DEC-105 — Ruby removed from the validation process
**Decision (2026-10-29, Shayne):**
- **Ruby is no longer a validation ground-truth / accuracy reference.** Accuracy of CV changes and of the
  on-device engine is checked against **Specto where available**, with the **server as the reference engine**
  for on-device parity (DEC-103). The `validation/` Ruby values and any "compare against Ruby before committing"
  step are retired from the process.
- **Unchanged:** Ruby as a *user-pairable ball sensor* (DEC-021) — that is a product feature, not a validation
  reference, and stands unless a later DEC changes it.
**Why:** owner's call to simplify the reference set to Specto + server-parity.
**Date:** 2026-10-29 · **Status:** ACCEPTED · **Supersedes:** the Ruby-as-validation clauses of DEC-022 and
DEC-034 and the CLAUDE.md "compare against Ruby values" instruction, going forward. Historical DEC-021/022/030/035
entries stand as record (never edited); their *Ruby-validation* basis is no longer the active process.

### DEC-106 — Native iOS production engine; Python stays the reference; port only after the engine stabilizes
**Decision (Shayne, 2026-10-29):**
- **Production:** the iOS measurement engine becomes native — Swift, AVFoundation, Vision, and Core ML where they help. This is **Option B** (`03_ENGINEERING/ENGINE_ARCHITECTURE_DECISION.md`).
- **Rejected:** Option A (server-only Python) as the target production architecture; Option C (shared C++/Rust core) for the current roadmap.
- **Python stays, permanently, as the non-production reference engine:** research, algorithm experiments, evaluation against ground truth, and reprocessing old shots. Results carry `engine` + `algorithm_version` provenance (DEC-103), so reprocessed results are never silently treated as equal to production results.
- **Cross-platform consistency comes from shared ARTIFACTS, not shared code:** the canonical metric definitions (`CV_MEASUREMENT_DEFINITIONS`), a versioned ShotRecord / measurement contract (`MeasurementEvidence`, DEC-103), the DEC-094 labeled dataset, and its accuracy gates. A future Android engine is native too and must pass the same gates on its own. Converted models (Core ML / TFLite) are validated separately per platform.
- **No wholesale port** of the current classical pipeline while DEC-062/065/094 work is in progress. Experimental Swift prototypes/benchmarks continue, labeled non-production (the current `feat/on-device-analysis` engine is exactly this). New detection models are built Core ML-ready.
- **Phases:** 0. Explain the Cloud Run vs Mac latency gap. · 1. Finalize detection/geometry/metric definitions in the Python reference. · 2. Labeled dataset + accuracy harness (DEC-094). · 3. Core ML models, validated. · 4. Port the stable geometry + metric layer to Swift. · 5. Full iPhone pipeline validation. · 6. Promote Swift to production after shadow comparison. (0–2 may overlap.)
- **Promotion gates for any production engine (ground truth, not Python parity):** A — Accuracy (DEC-034 + per-metric tolerances vs ground truth); B — Integrity (confidence, unavailable states, observed-vs-predicted, geometry validity, plausible-but-wrong rate, DEC-094); C — Performance (latency, battery, memory, thermals, sustained full sessions). Python/Swift agreement is diagnostic only.
- **Server stays authoritative** for the official LaneSight Score, tiers, achievements, history and sync. **Offline behavior (decided):** the phone shows measured ball/form metrics immediately; the **official Score/tiers/achievements are NOT computed on-device** — the app shows the **last synced score labeled "Updates when online"**, computes **session stats locally** (per-session averages/trends from this session's measured shots), and **queues shots for sync** so the authoritative score/tiers/achievements recompute server-side on reconnect. **Next-shot coaching advice offline remains an open question** (current lean: **show it on reconnect** rather than compute advice on-device) — **decide before Phase 6**.
**Why:** on-device is feasible and fast on iPhone 17 Pro Max (~550 fps decode, peak memory ~68 MB, no throttling over 30 shots); it enables offline, instant feedback at ~$0/shot; a portable CPU core would give up the Apple accelerators that make on-device worthwhile; porting a mid-redesign pipeline would mean porting it twice.
**Date:** 2026-10-29 · **Status:** ACCEPTED · **Supersedes:** makes decisive **DEC-102** (offline-first hybrid → the on-device engine is specifically native Swift/Vision/Core ML and is THE production target) and **DEC-103** (its two gates are the ground-truth promotion gates above); refines DEC-043 hosting assumptions for the long term; DEC-092 server work continues meanwhile.

### DEC-107 — Headline speed is the EARLY-LANE (release) speed; the 60 ft average is secondary (DRAFT)
**Decision (Shayne, 2026-10-29 — PROPOSED; provisionally shipped for league night pending formal approval):**
The headline `ball_speed` is the **early-lane / release speed** — a regression fit of velocity across all observed ball positions over the front ~4–24 ft (the skid, foul line → arrows) — **not** the 60 ft foul→pins average. The 60 ft average is kept as a **labeled secondary** (`speed_avg_60ft`) when the ball is tracked to the pins.
- **Why:** in the front ~20 ft the ball is big, sharp and seen in many frames; downlane it's 8–15 px and often lost, which drives most failures (BALL_TRACK_NOT_FOUND, TRACK_TOO_SPARSE_FOR_SPEED, PIN_IMPACT_NOT_DETECTED) and the wrong-window over-reads. Early-lane speed is **always available** (needs no pin impact) and uses the best video. Confirmed: IMG_8752 `ball_speed`=18.23 while `speed_avg_60ft`=None (no impact found). The fit is over many positions (not two timestamps), anchored to lane markings, per the risk notes.
- **Precision handling (to validate):** fit across 20+ positions; prefer 120 fps; start the window after touchdown and project the **contact point** (ball labels carry it); anchor distance to foul/dots/arrows. **No correction multipliers.**
- **Naming / comparability:** labeled **"Release speed"** in the app; the 60 ft average (what center monitors / Specto / likely Ruby show) is the secondary. Early-lane runs ~1–2 mph above the average.
- **KNOWN, separate — ROOT-CAUSED (2026-10-29):** the IMG_8753 server-vs-local gap is a **lane-geometry down-lane (Z) scale difference**, NOT a uniform speed scale and NOT a timing distortion. Comparing the two trajectories at IDENTICAL timestamps, the server reads the ball a near-constant **0.858×** as far down the lane (t=9.82: local z=13.28 ft vs server 11.40; same ratio through the skid) → early speed 18.71 × 0.858 = 16.05 ≈ the server's 16.04. `t_release` is identical; `t_impact` differs separately (frame 709 vs 693). CONFIRMED in-container (Cloud Run Job `lanesight-cv-diag`, 2026-10-29): it is **NOT frame timing** — the Linux container reports the SAME frame count (885), fps (59.97) and PTS intervals (880@16.67ms + 4@18.33ms) as the Mac. It is the **platform opencv wheel's bundled video decoder producing different PIXELS** (Linux x86_64 wheel vs macOS arm64 wheel) → different lane/ball/pin detection → a different homography down-lane scale (and opencv 4.11 on Linux even FAILS IMG_8753 with PIN_IMPACT_NOT_DETECTED, while the Mac and current prod succeed). Mechanism of the EARLY-speed sensitivity (now the headline): the production homography is a **2-point solve (foul Z=0 → impact Z=60 ft) with NO intermediate landmarks**, so the near-lane Z-scale is tied to the far impact anchor; `t_impact` differs server-vs-Mac by 16 frames → the anchor shifts → the near z-scale shifts. Sensitivity test: ±2 px on VP/foul ≈ 0%, on the impact row ≈ ±1.4% — the solve is NOT hyper-sensitive, so the fix is **more near landmarks (arrows @15 ft, dots @7 ft — DEC-065-reliable) to anchor the near-lane directly and decouple early speed from the far impact**, making it robust AND reproducible. Deps are kept as RANGES (a blind pin to 4.10/4.11 breaks analysis — validate a pin in-container via the Job first); the Debian release is pinned (bookworm). Absolute accuracy still needs Specto (Phase-2). The label-based 60 ft truth `60/(first_pin_contact_s − foul_cross_s)` is **pending — those event fields are being filled (Shayne, IMG_8753/8754); 8751/8752 clips are present**.
- **Far lane unchanged:** breakpoint / entry board/angle stay DEC-065-gated until Phase-2; this separates speed from that problem, it doesn't solve it.
- **Validation:** Phase-2 Specto exports **both** release/early and the 60 ft average (`CV_PHASE2_FIELD_CHECKLIST.md`). Preserves DEC-034 gates, DEC-065, DEC-094 promotion rules, DEC-106.
**Why provisional ship:** Shayne bowls tonight and wanted the robust front-lane measurement in prod now; the server deploy makes the value early-lane (the existing app shows it; a label build adds "Release speed"). Formalize or revise after reviewing tonight's shots + the container Gate A.
**Date:** 2026-10-29 · **Status:** PROPOSED (provisionally live, rev ≥00051) · **Supersedes (if accepted):** DEC-036 / DEC-064 headline speed choice (returns to DEC-030's release-speed headline); keeps the 60 ft average as the named secondary.

### DEC-108 — LaneSight Score unlocks after 5 eligible shots (was 20); tier provisional until 20
**Decision (Shayne, 2026-10-30):** the overall LaneSight Score and **each score part's** eligibility unlock at **5** eligible shots, not 20. Single source of truth: `lanesight_core/score/ldev0.py` `SCORE_UNLOCK_SHOTS = 5`, which sets all four `eligibility_floors` (s_perf/a_acc/c_cons/p_power); `score_formula_params()` reads the code default, so the change is live with the deploy (no DB migration — the migration-007 seed is updated for parity only). The per-part have/need the app shows ("Score unlocks · N%", "X/Y shots") derive from those floors, so they auto-read `/5` (no hardcoded constants).
- **Tier stays provisional until 20 shots** (`TIER_PROVISIONAL_UNTIL = 20`): a tier computed from a 5-shot score carries `tier_provisional=true` on `/me/score` so an early tier isn't read as settled. The score itself is live once eligible. The DEC-077 "Provisional · Beta formula" label was ALREADY shown on every score/tier, so the early tier was already not-misleading; `tier_provisional` makes the <20-shot case explicit.
- **Does NOT change:** the coach "your normal" baseline (`coach.BASELINE_MIN_N = 10`) or the plausibility-gate speed baseline (≥20 prior shots, app.py) — separate thresholds, untouched.
- Existing accounts are recomputed (the new floors apply on the next recompute). DEC-083/085 building-state copy auto-updates to the new counts (driven by eligibility).
**Date:** 2026-10-30 · **Status:** ACCEPTED · **Supersedes:** the 20-shot score-eligibility floor (DEC-048/DEC-077 eligibility threshold); keeps those decisions' formula + provisional label.

### DEC-109 — A missed pin impact is a partial result, not a failed shot
**Decision (Shayne, 2026-10-29; renumbered from the branch draft "DEC-108", which collided with the 5-shot score DEC):**
- When the pin impact isn't detected, the shot is **not failed**. Whatever doesn't depend on the impact is still reported.
- **Rev rate is reported as measured.** It reads the ball's surface-pattern periodicity from ball crops and frame timestamps only: no lane geometry, no depth scale, no pins.
- **Speed is `unavailable` with the reason** for now, along with every other metric that rides the lane depth scale (boards, angles, breakpoint, loft). The production homography's only depth anchor today is the ball's position at impact (DEC-062/107), so without it there is no trustworthy distance scale. It is never estimated or extrapolated.
- **Pin result:** not read (DEC-026/066). **No next-shot move** (`no_reliable_data`). `capture_quality.impact = 'not_detected'` so ops can count these.
- The shot fails with `PIN_IMPACT_NOT_DETECTED` only when nothing at all can be measured (rev rate unavailable too).
- **Next: decouple speed from the pins.** Anchor the near-lane depth scale to near landmarks (approach dots, arrows at 15 ft; DEC-065 near path) so early-lane speed (the DEC-107 headline) no longer depends on the impact anchor. That is a CV change under DEC-094 shadow/regression gates.

**Why:** Speed and revs are the core stats. Failing the whole shot because the pin moment wasn't seen discarded a valid rev reading. Both live shots on 2026-10-29 (18:43 and 18:56 ET) failed this way.
**Date:** 2026-10-29 · **Status:** ACCEPTED — merged to `dev-build-v0` and deployed (rev `lanesight-api-dec109`, 2026-10-30; superseded same day by `lanesight-api-durjobs` which carries it) · **Supersedes:** the shot-level `PIN_IMPACT_NOT_DETECTED` failure from DEC-086 (code kept for the nothing-measured case).

### DEC-125 — Feedback Insights: AI-consolidated actions, founder approval, approved work queue (2026-11-02)
**Decision (Shayne, 2026-11-02):**
- A **Feedback Insights** page in the owner-only ops dashboard (DEC-098) turns all feedback (every source and phase in the DEC-059 store, plus analysis-failure reason codes as supporting evidence) into a short list of **proposed actions**.
- A scheduled **Claude feedback analyst** job (daily + "Analyze now") groups new feedback into proposals: title, type (Bug · Analysis accuracy · UX/design · Feature idea · Content/copy), plain-English summary, proposed change, affected area, priority, rough effort, related DECs, and evidence (linked feedback rows, count, distinct bowlers, phases, example quotes). New feedback merges into an existing open proposal instead of duplicating it.
- Founder actions per proposal: **Approve**, **Edit then approve**, **Defer**, **Reject** (reason), **Merge**. Nothing is built without approval.
- **Approve → work queue:** creates a GitHub issue in lafoonch-blip/LaneSight (label `lanesight-queue`) containing the founder-approved spec, linked to the proposal and its feedback. The dashboard mirrors status: proposed → approved → queued → in progress → PR open → shipped. Shipping marks the linked feedback rows `actioned`.
- **Build:** a Claude Code scheduled task picks up queued issues, works each on its own new branch and opens a PR. It never merges, never touches branches it didn't create, and never pushes to main. Shayne reviews and merges. UI changes go through Figma/APP_DESIGN_CHANGES first (DEC-091); metric/algorithm changes go through the validation gates (no unvalidated correction factors).
- **Guardrails:** feedback text is untrusted user input. It is de-identified before the LLM sees it, and the build agent works only from the founder-approved spec, never raw feedback (prompt-injection defense). LLM cost for the analyst job is capped (≤$10/month) inside the DEC-043 cap. DEC-059 "no live effect" holds: approval is the only path from feedback to a change.
**Why:** feedback is only useful if it turns into decisions; one review-and-approve surface keeps Shayne in control while removing the manual work of reading, grouping and writing up every comment.
**Date:** 2026-11-02 · **Status:** ACCEPTED · **Builds on:** DEC-059, DEC-098, DEC-124. Implements the "action queue" idea in AI_OPERATIONS_INTELLIGENCE_AGENTS_CONTEXT for the feedback source. Spec/handoff: `03_ENGINEERING/HANDOFF_2026-11-02_FEEDBACK_INSIGHTS.md`.

### DEC-124 — In-app Feedback button on Home (general feedback, categorized) (2026-11-02)
**Decision (Shayne, 2026-11-02):**
- Home gets a **Feedback** button. Tapping it opens a small sheet: **category** (required, one of: Bug · Wrong/missing numbers · Confusing · Idea · Other), **text** (required), optional **screenshot**, and an "include diagnostics" toggle (default on). Submit shows a short thank-you and returns to Home.
- It writes to the one retained `feedback` store (DEC-059) as `source = 'general'` via the existing `POST /feedback`, with the category in `tags[0]` and auto-attached context: app version/build, device model, iOS version, current screen, last session/shot id when present.
- **Every row carries the real app phase**: `dev` (Shayne), `ff` (Friends & Family, DEC-123), `beta`, `live`. `ff` is added to the phase enum. Today the iOS app sends no phase and the server defaults to `dev`; that is fixed as part of this.
- Same button and flow serve F&F, Beta and live, so F&F is the first real test of the feedback system. Session-end feedback, shot notes and advice ratings stay as they are.
- Owner reads and triages all rows (new / reviewed / actioned / dismissed) through the ops dashboard / CSV export; feedback never changes the app live (DEC-059).
- Design: the button and sheet follow "01 - Design Standards"; added to APP_DESIGN_CHANGES and needs a Figma component (Feedback button + Feedback sheet).
**Why:** testers need one obvious place to report problems and ideas while they bowl, and the feedback store needs real use before Beta.
**Date:** 2026-11-02 · **Status:** ACCEPTED · **Builds on:** DEC-059, DEC-123. Fills FEEDBACK_STORE_SPEC §2 `general` ("Settings › Send feedback", reserved) — the entry point is Home, not Settings.

### DEC-123 — Friends & Family test phase via TestFlight (pre-Beta, not gated by DEC-118) (2026-11-02)
**Decision (Shayne, 2026-11-02):**
- Add a **Friends & Family (F&F) test phase** between Shayne-only MVP testing and the friends Beta. A handful of close friends and family get the app, sign up, use it when they bowl, and send feedback. Purpose: **more real-world videos and feedback for analysis**, not a Beta.
- **Not gated by DEC-118.** The app does not need to be Beta-ready; the DEC-118 accuracy, coverage and <30 s gates still apply to the friends **Beta** only. DEC-047 (Beta is Shayne's call) is unchanged.
- **Distribution: TestFlight external testing**, private invite link (iPhone only), bundle `com.lanesight.app`. Extends DEC "Xcode, then TestFlight internal" to an external F&F group.
- **Minimum for F&F:** normal in-app sign-up (13+ gate, existing account deletion); testers told plainly it is an early test build whose numbers may be wrong or missing; a short plain-English consent covering recording, 7-day server clip retention (DEC-099/104) and use of their clips/feedback to improve analysis; their data marked as F&F (cohort/app phase) so it is separable in Stats, the ops dashboard and the feedback store (DEC-059) and never mixes with Shayne's real or staged test data (DEC-076 staged accounts); owner/dev-only screens hidden from testers; a demo login for Apple's beta review.
- **Not required for F&F:** attorney-reviewed terms, entity/trademark work, the DEC-118 metric gates, performance SLOs. Those stay Beta/launch items (LEGAL_IP_LAUNCH_STRATEGY).
- Server-fallback cost stays inside the DEC-043 $100/month private cap; a few testers are well within it.
**Why:** the bottleneck right now is labeled real-world clips and observations from more bowlers, houses and phones; waiting for Beta readiness delays the data that gets LaneSight there.
**Date:** 2026-11-02 · **Status:** ACCEPTED · **Builds on:** DEC-047, DEC-059, DEC-099/104, DEC-118 (Beta gates unchanged).

### DEC-121 — Form metric tolerances + step-count honesty + Form capture defaults (amends DEC-118) (2026-11-02)
**Decision (Shayne, 2026-11-02):** per-plant form-step labels landed (`form_steps` task → `validation/form_steps_labels.json`; all approaches are 5 steps, no 6-step data; some early plants off-frame so visible-plant counts are 8824:4, others 5, IMG_8980:3). Amends DEC-118's Form gates with explicit tolerances and records an honest status for step count.
- **Form metric gates (amends DEC-118 "events within ±2 frames"):**
  - **Step COUNT — exact** (it is the MVP Form metric the user sees).
  - **Swing events** (ball start, top of backswing, release, slide stop) — **±2 frames**.
  - **Per-plant foot-strike timing — ±3 frames** (this only feeds approach duration / tempo, not a headline number, so a looser tolerance is acceptable).
- **Step count is NOT yet a validated metric — shipped `best_effort`, not `ok` (DEC-026/094 honesty).** On the labeled clips the foot-strike detector is ±1–2 off on count and within-±3f on only ~2–3/5 plants; exact count on 2/6. Root cause investigated: combined-`max(Rs,Ls)` minima are the double-support moments *between* plants (fixed the model to per-foot stance), and the dominant *structural* bug — the step window starting after ball start — was fixed (DEC-120, made 8824 exact). But the remaining error is a **signal floor**: the foot-contact instant isn't recoverable from phone-pose foot landmarks on this footage. **Crop-refine tried (option 1):** re-running pose on an upscaled person-bbox crop lifted foot-landmark confidence on every clip (e.g. side 8825 0.72→0.82, 8824 0.77→0.86, held-out 8980 0.46→0.61) **but did NOT improve count or ±3f timing** → confidence was not the bottleneck, so crop-refine is not shipped (runtime cost, no metric gain). Experiment + numbers: `examples/foot_refine.py`, `02_RESEARCH/FORM_EVENT_BASELINE_2026-11-01.md`.
- **Supported views / coverage:** step count is best_effort on both rear and side today; neither view meets the exact gate yet. Not promised as exact for Beta until it passes on independently-captured, well-framed clips. **IMG_8980 is held out** (never used for tuning) and re-scored separately; future recorded clips stay held out too.
- **Form capture defaults (iOS):** Form recording floors at **60 fps** and takes **120 fps when the device supports it at ≥1080p** (`CaptureView` passes `max(60, preferredFPS)` for form; `bestFormat` already prefers the highest fps at ≥1080p). Added an on-screen Form framing tip — "keep both feet in frame through your whole approach" — because step count + swing timing need every plant visible. iOS change needs an Xcode build + device verification.
- **Path to a real exact step count:** a dedicated foot-contact signal (not whole-frame pose landmarks) or better capture (fps + framing), validated per-plant held-out. Until then step count stays best_effort.

**Why:** the per-plant labels proved higher landmark confidence alone can't make step-count exact from phone pose on this footage, so shipping it as a confident `ok` metric would be a false number (DEC-026/094). Make the tolerances explicit, mark step count honestly, and fix capture so a future attempt has the frame rate and framing it needs.
**Date:** 2026-11-02 · **Status:** ACCEPTED — step_count→best_effort + capture defaults on `feat/form-baseline`; crop-refine kept as a documented experiment, not shipped. **Amends:** DEC-118 (Form gates). **Builds on:** DEC-120 (slide-stop + step-window fix), DEC-094 (labeled dataset).

### DEC-120 — Form event baseline on the labeled clips; slide-stop detector fixes the swing-event gate (2026-11-01)
**Decision (2026-11-01):** Shayne's form event labels landed (LaneSight Labeler task `form_events` → `validation/form_labels.json`, 6 clips: IMG_8824–26 side, IMG_8846–48 rear; IMG_8980 added to the task, pending labels). These are the DEC-094/095/118 ground truth for form timing. A baseline harness (`examples/form_baseline.py`) scores the Python form engine against them in FRAMES.
- **Baseline (production engine, before fix):** every swing event (E2 ball-start, E4 backswing-top, E7 release) was **nulled on all 6 clips**, and E8 "slide stop" was **23–86 frames late** (median 56). Root cause: E8 was reported as `hold_start` — the *posted-finish* start (both feet still ≥0.45 s), which lands 0.4–1.0 s AFTER the real slide stop because the trail leg is still swinging up. The event gate then compared release to that late E8, found a ~0.7–1.4 s false gap, and dropped the whole delivery. Step count was exact on **0/6** (systematic under-count; approach window misses early steps).
- **Fix (shipped in `lanesight_core/form/pose.py`):** (1) a **slide-stop detector** — E8 = the slide foot (opposite the bowling hand) settling at the line: its own speed falls and stays low after the slide's speed peak, anchored on the bottom of the swing arc (E6 ≈ release), ignoring the still-swinging trail leg; (2) release (E7) clamped so the on-lane ball only *confirms* the bottom of the arc, never drags it late; (3) the event gate anchors release on the corrected E8; the DEC-095 shadow flag `LANESIGHT_FORM_GATE_FIX` is **retired** (E8 is correct by construction now).
- **After fix, vs labels (±2 frames = pass):** swing events now **surface on 5/6** (was 0/6). Rear view (8846/47/48): E4, E7, E8 all **within ±2 frames**. Side (8824/8825): E4/E7/E8 surface, mostly ±1–5 f. Per event across all 6: E8 slide-stop median **2 f** (was 56), within ±2 f on **4/6**; E7 release median **1 f**, 4/5; E4 median **1 f**, 5/5 scored. IMG_8826 (side) is still fully mis-segmented (6 steps, window wrong).
- **Remaining gaps (honest, not fixed):** (a) **E2 ball-start null on all 6** — the bowling-wrist landmark does NOT move at the labeled pushaway onset (flat for 9–21 frames past it), so the wrist-Y method cannot time it; a real fix needs a ball-blob / off-hand onset cue, validated on more clips. (b) **Step count 0/6** — the approach foot-strike detector under-counts (misses early steps). Both block the Friends-Beta Form gates (steps exact ≥95%, events ±2 f) and are the next form CV work.

**Why:** the Form MVP gate (DEC-118) needs events within ±2 frames and exact step count against independent ground truth. The slide-stop error was the single biggest and most systematic, and it cascaded into nulling every swing event; fixing it is validated and un-nulls the back-half events on the supported views. E2 and step count are characterized, not papered over (DEC-026/094 honesty).
**Date:** 2026-11-01 · **Status:** ACCEPTED — slide-stop + gate fix merged on `feat/form-baseline` (403 tests pass); numbers from `examples/form_baseline.py` on the 6 labeled clips. Not yet on device (DEC-103 port). **Builds on:** DEC-094 (labeled dataset + gates), DEC-095 (form event gates), DEC-118 (Form MVP metrics + Beta gates), DEC-057 (fundamentals E1–E9).

### DEC-119 — An active session lasts until the user ends it
**Decision (Shayne, 2026-11-01):**
- A live session (Shot or Form) stays active until the user taps **End session**. Navigating away, backgrounding, app crashes, force-quit or a dead battery never end it. There is never more than one active session.
- While a session is active, Home and Lab show a **"Session in progress · Return"** banner. Tapping it opens the Active Session with all its shots/deliveries (analyzed, analyzing, failed + Retry), and the user can record more. **The tab bar is no longer hidden on the Active Session (amends DEC-099).**
- On cold launch (after force-quit or crash), or on returning after **≥30 min** in the background, with a session still active: show a prompt **"You have a session in progress (started <time>, N shots). Continue / End session"**. Continue → straight to the Active Session. End → the session is closed and becomes history (same end flow: summary/feedback per DEC-072/053 can be skipped), and the user stays on Home.
- Shorter interruptions (**<30 min** in background) return straight to where the user was, no prompt.
- Sessions never auto-end. Any shot still uploading/analyzing in the session keeps going and shows its result there.
- Source of truth for "active" is the **server (`sessions.ended_at` null)**, mirrored locally so it works offline.
**Why:** a practice session is the user's unit of work; losing it to a background/crash/navigation (as the old blocking-flow + hidden-tab-bar design allowed) throws away shots and context. Durability + a single active session + explicit end makes the session survive anything short of the user ending it.
**Date:** 2026-11-01 · **Status:** ACCEPTED · **Amends:** DEC-096 (session activeness/navigation) and DEC-099 (hides the tab bar on the Active Session — now shown). **Builds on:** DEC-110 (durable jobs), DEC-072/053 (end-session summary/feedback), DEC-080 (Analyzing flow).

### DEC-118 — MVP = Shot Analysis + Form Analysis, each with its own validated metrics and Beta gates
**Decision (Shayne, 2026-11-01):**
- **Two independent analysis products, both required:** Shot Analysis ("what your ball did") and Form Analysis ("what your body did"), on one shared platform (capture, decoding, calibration metadata, jobs, history, confidence/unavailable states, data collection). Neither analysis can fail or block the other. The user picks Shot or Form per recording (DEC-069); running both on one recording is a later option (DEC-056 stands until then).
- **Shot Analysis MVP metrics (all required, validated before Beta):** ball speed; rev rate; observed ball path (only measured, trustworthy segments); laydown + launch angle when near-lane geometry validates; strike / no strike when the pins are readable (DEC-066). Arrows board, breakpoint, entry board/angle stay gated (DEC-065) and are not MVP requirements.
- **Form Analysis MVP metrics (all required, validated before Beta):** step count; approach duration (first step → release); swing timing events (ball start, top of backswing, release, slide stop) with release timing relative to the slide; tempo consistency across deliveries. Drift, spine tilt, knee bend and other joint angles move to post-MVP (amends DEC-057's measured-metric list; hand/wrist rules stay coaching cues only).
- **Friends-Beta release gates (per product; MVP stays Shayne-tested until he calls it, DEC-047):**

  | Gate | Shot | Form |
  |---|---|---|
  | Accuracy vs independent ground truth | speed ±0.5 mph (DEC-034); revs ±25 rpm vs marked-ball truth | step count exact on ≥95% of clips; events within ±2 frames |
  | Coverage | ≤20% of supported-camera shots return any core metric as unavailable | same |
  | Analysis time (tap-stop → result, on device) | <30 s | <30 s |

**Why:** the product is two things a bowler cares about — the ball and the body — and each must stand on its own validated metrics and its own Beta gate, sharing one capture/jobs/history platform. The gates are ground-truth, not Python/Swift parity (DEC-106). Note the on-device analysis-time gate (<30 s) is well under the current ~132 s on-device latency (DEC-117) — performance work is required before Beta.
**Date:** 2026-11-01 · **Status:** ACCEPTED · **Amends:** DEC-057 (trims the Form measured-metric list to the MVP set above; drift/spine/knee → post-MVP). **Builds on:** DEC-069 (pick Shot or Form per recording), DEC-056 (both-on-one-recording later), DEC-065/066 (gated far-lane + strike), DEC-034 (±0.5 mph launch bar), DEC-047 (Shayne-tested until he calls Beta), DEC-117 (on-device engine).

### DEC-117 — iPhone is the PRIMARY engine for speed + rev now; server runs in SHADOW (2026-11-01)
**Decision (Shayne, 2026-11-01 — amends DEC-106 phases and DEC-080):** The iPhone becomes the **primary** production engine for **ball speed + rev rate** immediately; the server runs those two in **shadow**. This pulls DEC-106 Phase 6 forward for speed/rev specifically (the rest of DEC-106 — lane read, pins, coaching — stays server-authoritative and is NOT ported yet).
- **STOP all server analysis-time work.** No FLANN/LSH, no stabilize-skip, no CPU-quota request, no ephemeral Job worker. The server speed/rev path is frozen as the shadow reference; effort moves to the phone. (Supersedes the open DEC-116 "ORB registration / FLANN" follow-up — withdrawn.)
- **1. Robustness is the prerequisite:** the impact-anchor fragility (a maxdiff-2 colour change swung 18.7↔15.6) must be fixed so perturbation spread on IMG_8751–54 is **<0.2 mph**, so the iOS decode path can't recreate the platform gap. Done before the port is trusted.
- **2. Port scope (on `ios/LaneSight/Sources/OnDevice`):** stabilize (or skip when the camera is static), lane/foul line, ball track, pin-impact anchor, **60 ft average + early-lane speed**, rev rate. Same algorithms as the Python reference. **OpenCV-iOS is acceptable** if faster to port than Vision (this amends DEC-106's "Vision/Core ML" lean for the speed/rev core only). No lane read, pins or coaching on device yet.
- **3. Promotion gate (fast, not a long shadow):** on IMG_8751–54, run on a real iPhone — **speed within 0.3 mph of Shayne's labelled truth**, rev within the server's band; report on-device time/shot, memory, battery. (This is DEC-106 gates A/C applied to speed+rev; ground truth, not Python parity.)
- **4. App flow (amends DEC-080):** after recording, the Analyzing screen shows **phone speed + rev within seconds**, then the shot card. Upload + server analysis run in the **background** (background `URLSession`, durable job, DEC-110). Server-only metrics (lane read, strike, coaching) fill in on the card with an "updating…" state. **Never block the next shot on the server.**
- **5. Provenance:** every measurement tagged `engine.platform` (`ios`|`server`) + version; recomputable. Phone speed/rev feed stats/score (Shayne's call) but stay recomputable. Log phone-vs-server speed/rev per shot in `analysis_attempt`; add a parity panel to the ops dashboard.
- **6. Disagreement:** if phone and server differ beyond tolerance on a live shot, **keep the phone value primary** but flag the shot for review in ops — never silently swap.
**Why:** on-device is feasible/fast on iPhone 17 Pro Max (DEC-106 bench), gives instant offline feedback at ~$0/shot, and the server speed path hit a cost/latency wall (DEC-116: 189–223 s, ~$25/1000, ORB registration the floor). Moving speed/rev to the phone removes that wall and the cross-platform decode gap becomes a robustness property (item 1) rather than a server-tuning chase.
**CV-review folding (2026-11-01, ChatGPT review triaged by Shayne):**
- **Depth scale = ball-INDEPENDENT metric lane plane, not the impact anchor.** Camera intrinsics (AVFoundation `AVCameraCalibrationData` on device; EXIF/known on clips) + lane edges + foul line + known width (41.5 in) solve the lane plane metrically, no pin-impact. **Prototyped in the Python reference** (`ops/metric_lane_plane.py`, findings `03_ENGINEERING/METRIC_LANE_PLANE_FINDINGS.md`): solver recovers synthetic Z exactly; on IMG_8751-54 it matches truth to **MAE ~0.30 mph GIVEN an accurate focal**, BUT the mounted down-lane POV is **ill-conditioned** (foul & far cross-line near-parallel in image, cos_img 0.71-0.98) so the depth rides on the focal (±15% f → ±16% speed). ⇒ iOS must feed the **exact per-frame intrinsic matrix** and use **two cross-lines** (foul + pin-deck/arrows); never a single foul line or an assumed focal. Impact anchor stays server-shadow.
- **Reference-frame sensitivity is a BUG** (`stabilize.py` already noted "some clips' speed is sensitive to the reference choice"). Target: speed identical (±0.05 mph) across ≥3 reference frames; separate frame→reference alignment from reference→lane geometry. Test hook added (`LANESIGHT_STAB_REF`).
- **Labeler validation tasks added** (`validation/label_tasks/`): `early_lane_speed_truth` (ball shadow crossing foul/dots/arrows, Shayne's tape-measured distances for HIS lane — validation ONLY, never a runtime anchor) and `rev_truth` (marked ball at 240 fps, successive passes of one mark).
- **Perturbation-robustness gate kept** (`ops/perturb_robustness.py`, <0.2 mph spread, plausible-but-wrong the key metric). A learned ball detector is a later item (needs labelled boxes).
- **Robustness result (item 1) so far:** brightness-RELATIVE foreground threshold (gain-invariant) shipped in `track.py` + the iOS tracker. Spread: 8751 0.40→**0.167**, 8753 **0.061**, 8754 **0.176** (pass); **8752 0.675 FAILS** — its `t_impact` is bimodal (6.40↔6.74 s, ~20 frames) and its detections are perturbation-sensitive. The metric geometry also stays >0.2 on 8752 (0.613), so the bottleneck is 8752's underlying track/detection stability, not the anchor alone — deeper detection-stability work (or the learned detector) is required to clear 8752. Not curable by thresholding; does NOT contradict the server-freeze (threshold fix is the iOS-decode guard).
**Date:** 2026-11-01 · **Status:** ACCEPTED · **Amends:** DEC-106 (pulls Phase 6 forward for speed/rev; OpenCV-iOS allowed for that core; depth scale = metric plane not impact anchor), DEC-080 (on-device results precede the card; server fills in behind). **Withdraws:** the DEC-116 FLANN/quota/Job-worker follow-ups.

### DEC-116 — Analysis-time investigation: stabilize profiled, Cloud Run CPU variance is the real blocker (2026-10-31)
**Decision/finding:** Attacked the ~190 s/shot analysis time. Per-stage breakdown via a CONTROLLED in-container A/B (both configs in one container → no instance noise), IMG_8753: stabilize dominates at ~108 s of ~141 s analyze, split **passA (phaseCorrelate motion scan) ~52 s, solveB (BFMatcher brute-force knnMatch) ~34 s, ORB feature extraction ~4 s, bg ~6 s**. Decode is already cached (~0, DEC-113). So ORB *extraction* was never the cost — the motion scan and the O(features²) matcher are.
- **Tried + REJECTED (accuracy):** identity static homographies (IMG_8751 −0.45 mph), reg subsample (`LANESIGHT_REG_STRIDE`; stride 3 regressed 8751 −0.46 — non-monotonic/fragile), pass A subsample (`LANESIGHT_PASSA_STRIDE`; stride 2 regressed 8751 −0.49). Common cause: 8751's speed is hypersensitive to the stabilization reference/registration, so any shortcut that changes the per-frame registration or the reference frame fails the ±0.2 gate. All left gated OFF (default = exact original).
- **Tried + REJECTED (server-fragile):** ORB features 4000→1500 cut the matcher and passed the Mac gate (±0.13) but STARVED IMG_8753's homography on the SERVER (ball_speed came back unavailable in the in-container smoke) — the Mac gate can't see platform-CV differences. Left env-tunable, default 4000.
- **SHIPPED (accuracy-neutral, live `lanesight-api-canon10`):** parallelize pass A across the worker pool (bit-identical greys/motion/reference — local regression Δ+0.000 on all 4 clips; the reference CHOICE is unchanged, which is what 8751 needs), and pin `LANESIGHT_CV_WORKERS=4` to `--cpu` (workers() used `min(cpu_count(),12)` but cpu_count() reports the host node's 16+ cores, so it oversubscribed 4 throttled vCPUs). Raised the deploy smoke curl timeout 420→580 s (the 885-frame worst-case clip sat at the limit).
- **The real blocker — NOT met: <60 s.** The server has SEVERE, uncontrollable instance variance: the SAME IMG_8753 work measured **108, 196, 266, 382, 391, 413 s** across revisions/instances. This swamps every algorithmic gain and makes a clean before/after impossible from deploy-smokes. The dominant lever is therefore **infrastructure, not CV**: a consistently-provisioned analysis path (CPU-always-allocated / min-instances warm / a committed machine type / a dedicated non-concurrency-8 worker / 8+ vCPU once the 20-vCPU region quota is raised — 8×3=24 was rejected). 8 vCPU (cost-neutral on vCPU-seconds, halves memory-seconds) is the recommended next step but is quota-gated.
- **CPU-throttling hypothesis — TESTED + DISPROVEN (2026-11-01).** Hypothesis: the service is CPU-throttled outside request processing (Cloud Run default `cpu-throttling=true`), explaining Job 108 s vs service 266-413 s. Checked: the setting was at its default (throttled; only `startup-cpu-boost` set). Deployed canon11 `--no-cpu-throttling` (min-instances 0) and measured IMG_8753 ×5 on the LIVE service: wall 234/304/235 s (+ 2 runs 503/000 under sequential load), server stabilize 173-462 s, median ~235 s — **did NOT converge to the Job's 108 s**, and variance persisted on a warm no-throttle instance (back-to-back 234 then 304 s). So the Job↔service gap and the variance are **shared/burstable-vCPU hardware** (noisy neighbours / different machine pools), not throttling. `--no-cpu-throttling` switches to instance-based billing (bills idle instance time) with no speed benefit and showed 503s under load → **reverted** (canon12, back to default throttled + request-based billing). The dedicated-worker/quota plan STANDS and is in fact supported by the data: Cloud Run **Jobs** ran this work ~2× faster + steadier than the service, so moving analysis to a Job-style worker (or a committed machine type / 8+ vCPU post-quota) is the lever. FLANN/LSH for solveB (the ~34 s matcher) remains a valid CV follow-up, to be measured in the Job env (not deploy-smokes).
- **gen1/gVisor hypothesis — TESTED + DISPROVEN (2026-11-01).** Hypothesis: the service defaults to the gen1 (gVisor) execution environment, whose syscall interception is slow for multi-threaded OpenCV/numpy, while Cloud Run Jobs are always gen2 (microVM). Checked: the service was indeed gen1 (annotation blank = default). Deployed canon13 `--execution-environment gen2 --concurrency 1` (throttling default, request billing, 4 vCPU) and measured IMG_8753 ×5 on the live service: successful runs **221 s and 268 s** wall (still ~2× the Job's 108 s), plus **3 of 5 runs 503'd** — concurrency 1 churns instances (each request waits for a cold/busy instance). So gen2 does NOT converge either, and concurrency 1 made availability worse. **Reverted to canon12** (gen1 default, concurrency 8). Conclusion across all three tests (throttling, gen1, concurrency): none explains the Job↔service gap — the Cloud Run **service machine pool is simply ~2× slower and noisier** than the Jobs pool for this CPU-bound work. → **Proceed with the Job-style analysis worker** (Cloud Run Job per shot, or a persistent dedicated worker), durable-jobs API (DEC-110) unchanged for the app: POST returns the job id immediately, the Job does analyze_clip + save_shot_result + flips the analysis_job row, the app polls `/jobs/:id` as today. FLANN/LSH for solveB stays a follow-up, measured in the Job env.
- **Ephemeral-Job premise — step-0 control TESTED, 2× did NOT hold (2026-11-01).** Before migrating, confirmed the diag Job sizing == the service (both 4 vCPU / 8 GiB / gen2), then re-ran IMG_8753 in THREE fresh Job executions at that identical sizing: **255 s, 247 s, 265 s** total (analyze ~215-245 s after startup) — i.e. ≈ the service's ~235 s, NOT the 108 s seen once in the earlier in-container A/B. The 108 s was a lucky warm sample; the Jobs pool ITSELF varies 108-265 s. So at equal resources there is **no systematic Job-vs-service speedup** — the 2× was variance, and (per the step-0 rule) this is a *shared-vCPU variance* finding, not a Job-pool advantage. The ephemeral-Job-per-shot migration would therefore NOT deliver the speedup, so it is **built but left gated OFF, and NOT stood up** (no `lanesight-cv-analyze` Job / IAM created): `ops/analyze_worker.py` + the API trigger/drain/reaper (`LANESIGHT_JOB_WORKER`, default off) are complete and tested (reuse the shared `_build_run` closure so results are byte-identical) and remain an option ONLY if a future quota increase lets a per-shot Job use materially MORE vCPU than the service can (the real lever is vCPU-per-analysis, not Job-vs-service). The in-service path stays the default + only path. `_build_run` extraction (harmless refactor) is kept.
- **CORRECTION (2026-11-01, Shayne) — the regression began with canon2, it is the canonical PRIME, not "shared-vCPU variance".** The attempt log is unambiguous: pre-canon (cv2 decode, 10-28→10-30) stabilize was a STEADY 97-132 s; canon2→canon13 (canonical decode-once) stabilize is an ERRATIC 167-462 s with decode_s≈0. Root cause: the DEC-113 decode-once **prime** (numpy YUV→BGR + bilinear upsample of the WHOLE clip, then a ~5.25 GB BGR cache) runs INSIDE stabilize's first pass, so its cost hid in stabilize and the old per-store timer missed it (decode_s≈0). Instrumented `prime_s` + re-measured on the live service: canon14 (8 GiB) prime 82 s; canon15 (16 GiB) prime **74/97/100/108/116 s** over 5 runs. So (a) the prime is ~90 s of pure added cost vs pre-canon (~half of stabilize), and (b) **8 GiB was memory-pressured** — the 5.25 GB cache left ~0.75 GB headroom, producing the 462-517 s spikes; **16 GiB removed the spikes** (wall steadied to 224-272 s, no >300 s) but NOT the ~90 s prime. My earlier "shared-vCPU variance / Job 2× / step-0" reasoning was CONFOUNDED — every one of those measurements was canonical, so they all carried the prime; it was never a Job-vs-service or throttling story. **Quota request + ephemeral-Job worker are ON HOLD** (both stay built/gated-off) until the prime is fixed and re-measured. **Fix in progress:** speed up the YUV→BGR conversion (fixed-point / compiled kernel) keeping bit-identical cross-platform output, target stabilize back to the pre-canon steady ≤180 s, then <60 s. 16 GiB kept for now (removes the spikes; accuracy-identical 18.631).
- **Numba fast-conversion attempt — FAILED the server gate (2026-11-01).** Built a numba fixed-point INTEGER YUV→BGR kernel (`cv/_yuv_nb.py`): on Mac, within ±0.2 of baseline (all 4 clips) and prime 11s→3-5s (~16× parallel). Deployed canon16 — but the in-container smoke returned **15.601 vs 18.7** (−3.1): the numba output DIVERGES on the server (x86) vs Mac (arm64) despite integer math (numba codegen/version difference), so "integer ⇒ bit-identical cross-platform" was wrong. Smoke caught it, auto-rolled-back to canon15. Numba is now **gated OFF** (`LANESIGHT_YUV_NUMBA=1`, default numpy float — the proven cross-platform-deterministic path); the speedup is real but needs the numba cross-platform bug resolved (version pin / shift semantics) before it can ship. So the ≤180 s target is still open; prod stays canon15 (16 GiB float: spikes gone, steady ~250 s, accuracy-correct 18.631).
- **Numba root-caused but still blocked (2026-11-01 pm).** The parallel-vs-serial divergence IS real + fixed: `parallel=True` (prange) diverged x86 vs arm64; **serial numba is bit-identical cross-platform — proven by per-frame md5 in the Cloud Run Job == Mac** (8e2fe323c4e0 / 38167d586b6e, maxdiff 2 vs numpy on both; diag result read via GCS since Job logs read back empty). BUT enabling numba (canon16 parallel AND canon17 serial) still produced a **deterministic 15.601 vs 18.7** on the server smoke — identical both times, and the conversion is proven identical, so it's a **numba-RUNTIME side-effect on the downstream CV** (its threading layer perturbing cv2 ORB/RANSAC), not the pixels. So numba stays **opt-in/OFF** (`LANESIGHT_YUV_NUMBA=1`; numpy float is the proven default on both platforms); prod stays canon15 (16 GiB numpy). Isolating the numba-runtime/threading interaction is the remaining step before the ~90 s prime can be cut. **Cost (DEC-043):** canon15 (16 GiB, ~264 s) ≈ **$36/1000 — over the $25 alert**; it drops under once the prime is cut + memory returns to 8 GiB (both gated on the numba-runtime fix). Quota + Job-worker remain on hold.
- **Numba RESOLVED + ENABLED (2026-11-01 pm).** The 15.6 was the server's fragile impact anchor amplifying the INTEGER kernel's maxdiff-2 vs numpy. Fix: a numba **FLOAT32** kernel (`_yuv_nb`) that reproduces `yuv420p_to_bgr`'s numpy float conversion **EXACTLY (maxdiff 0, serial AND parallel, Mac)** — so enabling it is a no-op downstream. Deployed canon18 (parallel) → smoke **18.631 == numpy (PASS)**, confirming the float kernel matches numpy on the server too (the integer maxdiff-2 was the whole problem). **numba is now the DEFAULT** (`LANESIGHT_YUV_NUMPY=1` forces numpy; `LANESIGHT_YUV_NB_PARALLEL=1` on in the deploy). Server effect: **prime 90→42 s, stabilize 165→134 s, total ~264→189 s** (16 GiB). canon19 (8 GiB) also passes at 223 s (prime 54 s, mild residual cache pressure but NO 460 s spike — the fast prime cured it). **Cost:** both ≈ $25.7-25.9/1000 (at the alert; the 8 GiB memory saving is offset by the longer duration). The remaining lever to ≤180 s / <60 s + clearly under $25 is the ORB **registration** (~92 s, DEC-115 — stride/threshold cuts were rejected for accuracy; FLANN/LSH is the next safe try). Quota + Job-worker stay off (not needed — the Job pool had no advantage at equal sizing). prod = canon19 (8 GiB numba) / canon18 (16 GiB numba) interchangeable.
**Date:** 2026-10-31 (corrected + numba enabled 2026-11-01) · **Status:** numba FLOAT conversion ENABLED (bit-identical to numpy, proven by the smoke == 18.631 on the server); analysis ~264→189 s (16 GiB) / 223 s (8 GiB). ≤180 s / <60 s now gated on the ORB registration (FLANN), not the prime. · **Supersedes:** — (~90 s numpy conversion + the 5.25 GB cache's 8→16 GiB memory pressure). canon15 (16 GiB) live, accuracy-identical, spikes gone but still ~250 s (prime-bound). Parallel pass A + workers pin retained. Quota + Job-worker HELD. Next: faster conversion → ≤180 s steady → <60 s (pass A parallel, FLANN/LSH). Standard-tier gate. · **Supersedes:** —

### DEC-114 — canon2 follow-ups: engine-version quarantine + re-run + recompute; 8 GiB cost; tiered benchmark wired (2026-10-31)
**Decision:** Follow-ups after the canonical-decode deploy (DEC-113), all on `dev-build-v0` + live `lanesight-api-canon3` (engine bumped to **lanesight-cv-0.7.0**).
1. **Engine-version compatibility (DEC-103).** `measurements.legacy` flag (migration `add_measurements_legacy_flag`) + `read_shot_records` excludes it, so baselines / consistency / score / achievements never mix engine versions. **Re-ran every retained clip** on 0.7.0 in place (`ops/rerun_retained_clips.py`, matched by sha256→`content_hash`, overwritten via `save_shot_result`): 13 retained clips (shot-clips bucket) → **8 re-analyzed, 5 failed** (all 5 were already-failed framing captures — no good data lost; several previously had an implausible 26.25 mph that 0.7.0 now honestly reports unavailable). **Marked 665 measurements legacy** (all pre-0.7.0 real `lanesight_video` rows — the WHOLE ball-CV output, not only speed, because the canonical decode changed every CV metric and DEC-103 forbids mixing engines): LS Smoke 380, Shayne 171, Carlton 76, Staged·active 38 (the seed tool had run real analyses there). **Recomputed baselines + score for the 3 real accounts** (`ops/recompute_real_accounts.py`): LS Smoke 0, Carlton 9→2, Shayne 27→1 baselines, scores not-yet-eligible — the honest pre-Beta reset (DEC-051): after quarantining the ~14%-low data there is little valid 0.7.0 data, so stats are "building". The **7 staged showcase accounts were left untouched** — their history is synthetic (never engine-measured, so unaffected by the bug) and recomputing under the 90-day score window could alter the curated demo; re-seed via the DEC-063 tool if ever needed (Staged·active's 38 real rows are flagged legacy so a future recompute excludes them). Note: most retained clips are `source='upload'`, which never feeds Stats/Score (DEC-055) regardless.
2. **Cost (DEC-043).** Server-measured median analysis = **~190 s/shot** (n=29). Per-shot compute at 4 vCPU, Cloud Run us-east1 rates: **4 GiB = $0.0201, 8 GiB = $0.0220** (+9.4%, +$1.9/1000). vs the caps: the **$5/1,000 target is NOT met at either tier** — it is DURATION-bound (190 s), pre-existing and not caused by the 8 GiB bump; the **$25/1,000 alert is not tripped** ($22.0); the **$100/mo cap is fine** (~4,500 shots/mo of headroom; 33 real shots to date). Fixed `LANESIGHT_VCPU=4,LANESIGHT_GIB=8` in the deploy so the per-shot `cost` jsonb records the real instance (was logging 4 GiB). **Decision: keep 8 GiB** (correctness/robustness for the full-clip decode-once; the +9% is immaterial at beta volume). If the $5 target later binds it is a duration-optimization effort, and the memory tier can drop then (a trimmed clip's cache fits ~4-6 GiB; only the rare untrimmed clip needs 8).
3. **Tiered benchmark wired.** `ops/tier_for_diff.sh` classifies a diff → quick|standard; `ops/regression_tier.py` + `regression_reference.json` run the IMG_8751-54 ball_speed regression (±0.2, escalate-to-Full on breach, skips if clips absent). The **deploy wrapper** computes+logs the tier vs the serving revision's commit and runs the Standard regression as a hard pre-build gate when CV/metric code changed; the **pre-commit hook** (`ops/git-hooks/pre-commit`, installed) runs pytest every commit (Quick) and the regression when CV/metric is staged (Standard), skippable via `LANESIGHT_SKIP_HOOK=1`.
**Date:** 2026-10-31 · **Status:** ACCEPTED — migration applied, canon3 live, data operation complete, tooling committed. · **Supersedes:** —

### DEC-113 — Canonical SDR decode shipped (DEC-107 server speed-gap fix), SDR-only partial rollout (2026-10-31)
**Decision:** The server-vs-Mac speed gap (IMG_8753 16.04 server vs 18.71 Mac, ~14% low) is the YUV→BGR **colour conversion** differing across platforms (the raw YUV420P is bit-identical; Mac ffmpeg 9.0.2 vs container ffmpeg 5.1/cv2 differ ~1% per channel, red-biased, and the 2-point homography impact anchor amplifies it ~14×). Fix: decode raw YUV420P via ffmpeg (bit-identical) + convert YUV→BGR in **pure numpy** driven by the clip's colour metadata (`cv/decode.py`), so the same bytes come out on Mac and Linux. Shipped **SDR-only** (`LANESIGHT_FFMPEG_DECODE=1`): all 64 recent live+upload captures are bt709 SDR (0 HDR), so canonical covers 100% of real shots. HLG HDR stays on the existing `convert_sdr` path, gated behind `LANESIGHT_CANONICAL_HDR` (STEP 2).
- **Perf (the deploy blocker):** the numpy conversion is ~11 s/pass; a full analysis makes ~4 passes over overlapping-but-PARTIAL frame ranges so the lazy frame cache never reached EOF and re-converted every pass → the first deploy (`canonsdr`) **timed out** the 420 s smoke and auto-rolled-back (safe). Fix: `stabilize._prime_canonical` decodes the whole canonical clip ONCE into the frame cache up front; every pass then serves from RAM (decode-once). IMG_8753 (885 f, 1080p, untrimmed): **56 s→21 s** on Mac, speed unchanged. Needs headroom → deploy bumped to **--memory 8Gi + LANESIGHT_FRAME_CACHE_MB=5500** (a 5.25 GB untrimmed clip fits; longer clips fall back to per-pass decode, slower but correct). Non-canonical (HDR/cv2) clips keep the lazy cache (prime returns False once, no re-probing).
- **Gate + live:** Mac==server within 0.1 mph — live rev `lanesight-api-canon2` serves IMG_8753 at **18.631** vs Mac 18.711 (Δ 0.08 < 0.1; the residual is downstream OpenCV platform variance, not decode — frames are bit-identical). Smoke reference updated to 18.71 ±0.2. 397 tests pass; IMG_8751-54 all analyze (8751/8754 HDR unchanged on the cv2 path: 18.615/18.232).
- **Tiered benchmark (improvement-loop testing policy, set 2026-10-31):**
  - **Quick** (every commit): pytest + smoke clip, byte-identical to the last run. ~1 min.
  - **Standard** (auto when a diff touches `lanesight_core/cv/`, decode, or metric code): IMG_8751-54 + a small labeled set in the Cloud Run Job; report coverage/accuracy deltas + new failures. ~10-15 min. **Blocks the deploy on failure.**
  - **Full** (nightly on prod, before promoting any CV change to production, and for background-search finalists): whole library + locked test, full scoreboard. Never blocks routine commits.
  - **Escalate** Standard→Full automatically if any metric moves beyond its tolerance or a new failure appears. Pick the tier by diff path in the deploy wrapper / pre-commit; log which tier ran with each commit.
- **STEP 2 (HDR canonical) — mechanism ready, GATED OFF (blocked by STEP 3):** the decode-once prime extends to HLG for free (`canonical_frames` tone-maps via `_hlg_to_709`); 8751/8754 decode-once and finish fast (passes=1, cached=10). BUT the numpy HLG→709 tone-map differs from `convert_sdr` by **+6.7 on red** (means otherwise match <1; p95 diff 12, max 83 in highlights), and that red shift **breaks ball tracking** (8751 BALL_TRACK_NOT_FOUND, 8754 no speed). So HDR stays on the working `convert_sdr` path (`LANESIGHT_CANONICAL_HDR` off) until STEP 3 hardens detection or the tone-map is matched. No HDR in live captures, so no production exposure.
- **STEP 3 (colour-shift robustness) — MEASURED; not a threshold fix:** per-stage sensitivity (inject gamma/hue/red/brightness on all frames, bg recomputed from them): impact detector is already adaptive (`base+5·sd`); refine is self-calibrating (per-video HS model). On a good-contrast clip (8753) the speed pipeline is **very tolerant** — gamma 0.8–1.25 gives identical 18.711, hue ±8° / red −15…+20% move speed <0.3%, t_impact never moves. So the original "~1% → 14%" was the *platform-specific nonlinear cv2 conversion* (fixed by canonical decode above), NOT clean colour shifts. The real residual: a **lower-contrast clip (8752) breaks** at gamma≥1.2 / hue≥8° — the fragile stage is `track.extract_blobs`, whose fixed `thr=35` on the max-channel background diff. Under contrast compression the ball's diff falls from p99≈47 to ≈19 toward the stable noise floor (median≈2–3). Experiments: **neither** lowering the absolute threshold (thr=15 → baseline regresses to 17.99 AND shifted case returns garbage 28.7 from noise blobs) **nor** a relative-contrast threshold (`rel·bg_luma`, floor) recovers the shifted case without regressing baselines — once the ball≈noise margin collapses, any threshold low enough to catch the ball admits confusers. **Proper fix (scoped follow-up, needs the full labelled set):** a stronger ball discriminator — bring the `refine.py` per-video HS colour model forward to the detection stage, or a multi-cue (diff+colour+motion) detector — validated in shadow, not a threshold constant. This also unblocks STEP 2 (HDR).
**Date:** 2026-10-31 · **Status:** ACCEPTED — committed to `dev-build-v0` (c21c494) + deployed live (`lanesight-api-canon2`). STEP 1 done. STEP 2 (HDR) gated off pending STEP 3. STEP 3 measured — detector-redesign follow-up scoped (not shipped; threshold tweaks proven insufficient). Tiered-benchmark wiring pending. · **Supersedes:** the cv2-decode speed gap noted in DEC-107.

### DEC-112 — Pin-spot depth anchor: shadow only, NOT promoted (2026-10-31)
**Decision (overnight run):** `cv/pins_anchor.py` — a spec-fixed, impact-independent, center-agnostic near-lane depth anchor (foul Z=0 + the 7 visible perimeter pin spots, head pin Z=60 ft; the centre-column back pins 5/8/9 are occluded down-lane) — stays SHADOW-gated and does NOT feed speed/baselines/coaching. It reuses the arrow V-fit structure (sweep depth only; lateral from the detected edges; score the bright pin body above each projected base; reflection-reject). It detects 7/7 pins on all of IMG_8751-54 incl. both portrait clips (the arrow fit declined on portrait).
- **Why not promoted:** (1) the DEC-065 pose solver is ILL-CONDITIONED on this POV — foul+pins are near-coplanar + far → reproj 3.6-6.4 px, inconsistent focal/pin_height, head depth 67-126 ft (worse than the planar 58-63 ft); the planar anchor is retained but carries a ~±0.5 mph residual (base-vs-body offset + far-lane conditioning). (2) Against a track-crossing 60 ft truth (offset-invariant Δt; NOT visually frame-confirmed — see below), the pin anchor ties/beats the impact anchor on only 2/4 clips (8752 pin 0.10 vs impact 0.47; 8753 tie; 8751/8754 impact better), failing the "ties/beats on all 4" gate.
- **Ground-truth labels are BLOCKED:** `foul_cross_s` / `first_pin_contact_s` (validation/cv_eval/labels/IMG_875x) are unfilled; autonomous visual labeling is blocked because the analysis TRIM/stabilization shifts track time off the original clip time (at track t_imp the original frames still show standing pins), so track events can't be mapped to original frames without the stabilization transform. The 60 ft Δt (hence speed) is still valid (a time difference cancels the offset); the absolute frame labels need Shayne, or a pins-scatter frame-diff pass.
**Status:** ACCEPTED — shadow harness committed; promotion pending (a) a better-conditioned capture or a non-PnP pin solve, and (b) Shayne's visual foul_cross/first_pin_contact labels. **Never** in baselines/score/coaching.
- **Canonical speed-truth definition (2026-11-01, confirmed everywhere):** truth = `foul_cross` (first frame the ball's SHADOW / contact point on the lane is over the foul line, Z=0) → `first_pin_contact` (ball centre at first head-pin contact), a travel of **Z_IMPACT = 59.44 ft** = 60 ft − (4.30+2.38)/12 (ball-centre offset at contact). True speed = 59.44 ft ÷ Δt. The engine uses 59.44 ft for the depth anchor (`metrics.Z_IMPACT` → `lane_homography`), the `speed_avg_foul_to_pins_mph` average, and the entry distance (`entry.z_ft=59.44`) — all consistent. The ONLY `60.0` in the code is `speed_avg_60ft_mph`, a **separate release-anchored nominal-60 secondary** (release precedes the foul crossing); it is NOT the truth metric and is now commented as such in `metrics.py`.
- **Labels DELIVERED (2026-11-01, supersedes the "BLOCKED" note above):** Shayne labelled foul_cross + first_pin_contact for all four clips (`pin_anchor_labels.json`). Frame-mapping done via each track point's own original-frame index `i` (t = i/fps; the foul→pin INTERVAL is trim-offset-independent). Engine vs labels: **foul-cross frame within ±1 (+1/+1/0/−1), pin-impact frame 0–3 (+1/+3/+1/0)**; resulting engine foul→pins average vs truth **MAE 0.12 mph, bias −0.12, max 0.28 (8752)** — the impact anchor is validated against ground truth. Pin-anchor (fixed-geometry) early speeds still disagree with the impact anchor by up to ~0.7 mph (8753), so the pin anchor remains shadow-only.

### DEC-111 — Metric independence: never fail the whole shot for one missing dependency
**Decision (Shayne, 2026-10-30):** A broken single stage must not discard the metrics that don't depend on it. Compute everything the near lane and the ball's tracked path allow; mark only the genuinely-undeterminable metrics `unavailable` with a reason; hard-fail only when *nothing* is measurable.
- **Speed and revs** come from the FIRST part of the lane (release/skid, ~4–24 ft) and must not depend on pin impact. Revs are already geometry-free (DEC-109). Speed still rides the impact-anchored homography; the target is to anchor the near-lane depth scale on the Z=15 arrow row so it no longer needs the impact.
- **Throw line** (entry board/angle/breakpoint) needs the ball's path down the lane, not the impact *moment*.
- **Shipped now:** `IMPOSSIBLE_SPEED_SCALE` and `TRACK_TOO_SPARSE_FOR_SPEED` no longer fail the shot — they fall back to the DEC-109 partial (rev measured, scale-dependent metrics withheld, `capture_quality.impact='scale_unreliable'`). The near-anchor mechanism is built (`lane_homography_at`, `early_speed_from_H`, `arrows.py`) but runs SHADOW-only (gated by `LANESIGHT_NEAR_ANCHOR_SHADOW`).
- **Mechanism PROVEN, detector is the only gap (2026-10-30 oracle test):** feeding the near-anchor path the TRUE Z=15 point (derived from the impact homography) reproduces the impact-anchored early speed to **0.0 mph** on IMG_8751 (18.408=18.408) and IMG_8753 (18.685=18.685). So the geometry is correct; impact-free speed works the instant the arrow row is located correctly. The first arrow DETECTOR does not yet locate it (declined 3/4; 9.6 vs 18.7 on the 4th) — that's isolated vision work needing frame inspection (and may depend on whether the mounted down-lane POV images the 15 ft arrows cleanly). Oracle vs detector is recorded in `capture_quality.near_anchor_shadow` when the shadow flag is on.

**Why:** A missed pin moment (or a mid-lane anchor, or a sparse far track) was throwing away a valid rev/speed read by failing the entire shot. The core stats should survive a partial capture.
**Date:** 2026-10-30 · **Status:** ACCEPTED — partial-fallback shipped; near-anchor shadow-gated pending the detector. **Extends:** DEC-109.

### DEC-110 — Analysis jobs are durable (resolvable cross-instance), not in-process only
**Decision (2026-10-30):**
- Every analysis job is persisted to Supabase (`analysis_job` table, migration 034) on each transition: queued → running → done/failed. The row carries the same public shape the client already decodes (`id/kind/state/reason/timings/result/failure`) plus `user_id`/`shot_id`.
- `GET /jobs/:id` reads the in-process queue first, then **falls back to the durable row**, scoped to the owner. A poll that lands on a different Cloud Run instance, or arrives after the instance scaled to zero / restarted, now resolves instead of 404ing.
- Persistence is **best-effort**: a store write that fails is logged and swallowed — durability can never fail an analysis.
- Client recovery stays keyed on the **shot** (session/uploads lookup + state), not the job id: in sync mode the `job_id` only returns on completion, which a dropped request never saw. The durable job is the server-side half; the client's reconcile + resume-poll is the other half.

**Why:** The job queue was `SerialJobQueue._jobs` in instance memory only, so `GET /jobs/:id` 404'd whenever the poll didn't land on the instance that ran it (concurrency 8, max-instances 3) or after scale-to-zero. The shot analyzed and persisted, but the client could never re-resolve its job — the "analysis hang + lost session" of 2026-10-29. Verified live: a 202 s inline job persisted `done` + resolved via `GET /jobs/:id` after the fact.
**Date:** 2026-10-30 · **Status:** ACCEPTED — migration 034 applied, deployed (rev `lanesight-api-durjobs`).

### DEC-122 — No analysis fails as a whole because one part failed (partial results + stage report)
**Decision (Shayne, 2026-11-02):** Every analysis — shot and form, on BOTH the iPhone and the server (shadow)
engine — runs to completion and RETURNS a result. It is never aborted because one stage could not produce its
metric. Each returned analysis carries:
- **(a) every metric that WAS measured** (with status measured | best_effort | low_confidence);
- **(b) every metric that was NOT measured**, marked `unavailable` with the **stage** that failed and the
  **reason** — no fallback, no estimated numbers (unmeasured ⇒ unavailable + reason, DEC-086 honesty);
- **(c) a per-stage report**: decode, stabilize, lane, foul line, ball track, impact, pose, form events — each
  `ok` / `failed` + reason + key diagnostics.
**An attempt is `failed` ONLY if the video can't be read or the code crashes** — and even then the stage report
(whatever was reached) is stored. **"Nothing measured" is still a COMPLETED analysis with a stage report, not a
failure.** This extends DEC-109/DEC-110 (metric-independence partials for impact/scale/sparse-track) to EVERY
stage and former-fatal code.
- **Former-fatal codes → partial** (audit, shot + form): `PIN_IMPACT_NOT_DETECTED`, `FOUL_LINE_NOT_IN_VIEW`,
  `FORM_DELIVERY_NOT_ISOLATED`, `SHADOW_UNAVAILABLE`, `BALL_TRACK_NOT_FOUND`, `LANE_NOT_DETECTED_*`,
  `LANE_GEOMETRY_UNUSABLE`, `TRACK_TOO_SPARSE_FOR_SPEED`. For each, measure what does NOT depend on the failed
  stage (e.g. rev rate needs only the ball track, not impact/geometry; a form timing metric that doesn't depend
  on the delivery-isolation gate) and withhold the rest with the reason. A dependency chain that blocks
  everything (e.g. no lane ⇒ no ball track ⇒ no rev) still returns a completed all-`unavailable` record + stage
  report — it does not raise.
- **App (dev/TestFlight):** show the partial result normally; each missing metric reads
  **"Not measured — <reason>"**; a **"What worked"** stage list (✓/✗ + reason) appears on the shot/form detail.
  A failed stage must NEVER hide a stage that succeeded.
- **Outcome tracking (Supabase, append-only history; `measurements` stays the user-facing current values):**
  a versioned **`metric_catalog`** (key, capture_mode, required stages, introduced_in); **`analysis_metric_outcome`**
  (one row per attempt × EVERY catalog metric, incl. unavailable: engine iphone|server, engine_version, status,
  value, unit, confidence, machine-countable `reason_code` enum, reason_detail, failed_stage);
  **`analysis_stage_outcome`** (one row per attempt × stage: status ok|failed|skipped, reason_code, duration_ms,
  diagnostics jsonb). Written for EVERY attempt (incl. failed/crashed — whatever was reached) from both engines,
  with per-attempt context (camera view/group, device, fps, resolution, capture mode, `profiles.staged_kind`).
  Views: metric success-rate by metric × engine_version × camera-view × week; top reason_codes per metric; stage
  failure funnel; iPhone-vs-server agreement per metric — **staged/test accounts excluded by default.**
**Why:** in testing (and for beta/production observability) a single weak stage was blanking an entire shot/form —
hiding the metrics that DID work and making failures uncountable. Returning a partial + a machine-countable
stage/metric outcome for every attempt turns "it failed" into "exactly these metrics/stages failed, here, for
this camera/engine, N% of the time" — the data that drives per-metric promotion (DEC-106) and the DEC-118
supported-camera guidance.
**Date:** 2026-11-02 · **Status:** ACCEPTED — implementation in progress (pipeline partial+stage-report refactor,
engines, app, outcome tables + views). **Builds on:** DEC-086 (coded failures, honest unavailable), DEC-109/110
(metric-independence partials), DEC-103/106 (engine provenance / per-metric promotion), DEC-118 (camera support).
**Supersedes:** the hard-fail behavior of the former-fatal codes above (they become partial results).

### DEC-126 — Usability first: the iPhone engine is primary for live shots; tune accuracy after the switch
**Decision (Shayne, 2026-11-02):** The on-device **iPhone engine is now the PRIMARY** measurement path for live
shots; the **server becomes the shadow/reference**. The switch happens on usability, not accuracy — **accuracy
and iPhone↔server parity are tuned AFTER the switch, not before it.** **No accuracy gate blocks the switch.** The
ONLY blockers are: the on-device analysis **crashes**, or it returns **a result slower than 30 s**. Everything
else (speed/board deltas vs. the server, per-metric accuracy) is tuned in place once the iPhone path is primary.
**Honesty rules still apply (DEC-086/DEC-122):** an unmeasured metric is `unavailable` + reason + failing stage —
never a fabricated or estimated number — on the iPhone path exactly as on the server.
**Why:** holding the on-device switch behind an accuracy/parity gate (DEC-103) stalls the offline-first, instant
on-lane experience indefinitely; a fast, local, honest result the bowler gets immediately beats a marginally more
accurate server result they wait for. Parity work is real but belongs after the primary path is in users' hands.
**Date:** 2026-11-02 · **Status:** ACCEPTED.
**Amends:** DEC-102 (offline-first hybrid) and DEC-103 (on-device stays shadow until the accuracy gates pass) —
the iPhone→primary switch no longer waits on those gates; only the crash / >30 s blockers apply. DEC-117's
phone-primary-with-server-review parity tolerance becomes a POST-switch tuning target, not a precondition.

### DEC-127 — On-device-first metrics + a lightweight metrics-only server call; two deliberate result states
**Decision (Shayne, 2026-11-02):** Finalizes the DEC-126 architecture into a clean split of responsibilities.

**1. All video metrics compute on the phone.** The on-device engine produces every result-card metric — speed,
rev rate, and the **board metrics** (entry/target/breakpoint) — ported from the server. **Honesty is a per-shot
property, not a validation-against-truth property (Shayne, 2026-11-02):** a real user's shot has no ground truth,
so a metric the engine measures is **`measured` (status `ok`) and counts toward the LaneSight Score exactly like a
server-measured metric.** There is **no "best_effort because the engine isn't validated"** label — that conflated
a development QA activity with runtime logic. The only honest downgrades are derived from *this shot's own data*:
`unavailable` + reason_code + failing stage when a metric genuinely can't be measured (track too short, foul
crossing extrapolated > 6 ft, far lane not read), and the foul→pins *average* speed stays `best_effort` solely
because its method approximates the impact frame (DEC-112) — identical on server and device, and not a Score input.
The 7 truth clips (IMG_8751–54, …) are the **developer gate** that the port is correct *before a build ships* —
they never appear in app logic or per-shot scoring. **This reverses DEC-126's "on-device metrics are best_effort,
not measured" treatment and the shadow outcome writer's blanket `scalar_status='best_effort'`.**

**2. A new lightweight metrics-only endpoint returns score + coaching.** After measuring, the phone calls a NEW
endpoint with **metrics JSON only** — the metric values + their status/reason codes, capture context, ball,
session, user — **no video**. The server computes the **score / tier update + coaching insight + recommended
adjustment** from that metrics record using the existing server logic, refactored so **score/insights take a
metrics record, not a video**. Target: **< 2 s server time, payload in KB.**

**3. The result screen renders ONCE**, when (1) and (2) are both done. **Target ≤ 15 s from shot end.** The shown
result is **never updated piecemeal** and **never shifts content** after it appears.

**4. Offline path.** Wait up to **10 s** for the server call; if it doesn't return, render the **full on-device
metrics** with coaching marked "available when back online", **queue** the metrics call, and **attach the coaching
to the shot in history** when it lands. A screen the user is currently viewing is never mutated; queued coaching
enriches the saved shot (and optionally sends a notification) instead.

**5. Video upload is background + afterward.** The clip uploads after the result is shown — **Wi-Fi only by
default, with a user setting to allow cellular.** The **server shadow analysis** on that video is for
validation / the comparison check **only** and **never changes what was shown.**

**6. Outcome tracking (DEC-122) is fed by the on-device metrics in the metrics call**, so `analysis_metric_outcome`
rows are written without waiting for the video.

**Presentation — two deliberate result states, each rendered once, never filled in on screen:**
- **Complete Analysis:** shot outcome + validated metrics + AI coaching + recommended adjustment + confidence
  indicators where appropriate.
- **Offline Analysis:** all on-device measurements, a clear offline status, and one concise line that coaching
  needs connectivity. No empty cards, loading placeholders, or half-populated sections — the coaching section is
  simply **absent**, replaced by that line.
- **Progress screen before the result:** "Analyzing your shot" → "Generating coaching" → "Your results", advancing
  as each step actually completes; show the result the moment everything is ready (no artificial waits).
- When queued coaching arrives later, **enrich the saved shot in history** and optionally send a notification;
  never change a screen the user is currently viewing. No content shifting on the result screen.
- **Design:** no Figma yet for the offline state or the progress steps — built from the "01 - Design Standards"
  tokens and logged in `03_ENGINEERING/APP_DESIGN_CHANGES.md` with **DIFFERS: no Figma yet** so the designs can
  catch up.

**Verify on device:** 3 clips with Wi-Fi on (tap → result time), 1 with airplane mode (offline path); report
payload size, server time, total time, and board deltas vs the server. Install Release.

**Why:** puts a fast, honest, offline-capable result in the bowler's hands immediately (the DEC-126 goal) while
keeping the server authoritative for score/coaching — but on a KB-scale, <2 s call instead of a multi-minute video
round-trip. Decoupling tracking + coaching from the video upload means neither the result nor the outcome rows
wait on the network.
**Date:** 2026-11-02 · **Status:** ACCEPTED.
**Amends/extends:** DEC-126 — concrete end-to-end primary-path switch, **and reverses its "on-device metrics are
best_effort, not measured" treatment**: measured on-device metrics are `measured`/`ok` and count toward the Score;
validation-against-truth is a developer build gate, not a runtime per-shot label. DEC-102/DEC-103 (the server's role
on the live path narrows to the metrics-only score/coaching call + video shadow validation); DEC-068/DEC-080
(the blocking "Analyzing" screen becomes the three-step progress screen above). Honesty rules DEC-086/DEC-122 and
the score/tier definitions (DEC-036/DEC-038/DEC-090) are unchanged — only their **input** becomes a metrics record.

### DEC-128 — Form analysis runs on-device (MediaPipe Pose), matching the DEC-126/127 shot architecture (2026-11-03)
**Decision (Shayne, 2026-11-03):** Form analysis moves on-device, the same way shots did in DEC-126/127. The
iPhone measures the form events + metrics locally with **MediaPipe Pose Landmarker (heavy, VIDEO mode)** — the
same model family + 33-point BlazePose topology the server reference uses (`lanesight_core/form/pose.py`), for
parity — **not** Apple Vision (Vision has no foot-index/heel landmarks, which the step count + approach timing
depend on). Then a lightweight metrics-only call (`POST /shots/metrics`, `capture_mode=form`) returns the
server-authoritative coaching + fundamentals + Score; the result renders once (Complete, or Offline when the
call can't reach the server); the clip uploads in the background (Wi-Fi only by default) and is analysed as a
server **shadow** for comparison; DEC-122 outcome rows are written from both engines.
- **Engine:** `ios/LaneSight/Sources/OnDevice/Form/` is a faithful 1:1 port of `form/pose.py` + `fundamentals.py`
  — events E1–E8 (ball start, pushaway, top of backswing, bottom of arc, release; slide plant E5, slide stop E8),
  swing times, rhythm (downswing/backswing), drift (unavailable — no floor calibration), slide length
  (unavailable), step count (**best_effort**, DEC-121), the DEC-095 honesty gates (release-vs-slide-stop,
  ball-start→release, chronological order), partial results + per-stage report + reason codes (DEC-122), and the
  slo-mo detect/correct path. Replaces the Apple-Vision `OnDeviceFormShadow`.
- **Parity gate (DEC-121 tolerances):** `examples/form_ondevice_golden.py` freezes the Python reference's
  per-clip events/metrics (`validation/form_ondevice_golden.json`) as the on-device target; `OnDeviceFormGateTests`
  runs the engine on all labeled clips (8824/25/26 side, 8846/47/48 rear; **IMG_8980 held out**) and asserts
  determinism (10 runs identical), on-device events within ±2 frames of the server reference (engine parity) +
  step count exact vs the reference, and reports the ground-truth deltas + runtime (<30 s/clip Beta gate).
  **The ground-truth ceiling is the reference itself** — on the labeled set the reference leaves E2 null on all
  clips, mis-segments 8826/8980, and the step count is best_effort ±1–2 (DEC-120/121); on-device matching the
  reference is the correct outcome, not exceeding it.
- **App:** Form uses the same flow as shots (DEC-126/127): on-device metrics → `POST /shots/metrics`
  (`capture_mode=form`) for coaching → one Complete/Offline result screen → background Wi-Fi-only upload →
  server form video shadow (`POST /shots/{id}/shadow_video`, now enabled for form) → outcome rows from both
  engines. `shot_from_metrics` gains a form branch that synthesises the form record from the device
  events+metrics and runs `engines.after_form_analyzed` (the same pure fundamentals the video path uses:
  timing_checkpoints T1–T4, swing_timing vs baseline, measured positions M1–M7, coaching cues, focus).
**Why:** the same wins as DEC-117/126 for shots — instant offline feedback at ~$0/clip, no server CV latency, and
the server stays authoritative for coaching/Score/tiers. One capture → one result screen for both products.
**Date:** 2026-11-03 · **Status:** ACCEPTED — engine + parity golden + gate test + Python reference committed
(447 pytest pass); app wiring + server form metrics/shadow branches on `feat/form-ondevice`. iOS build +
MediaPipe pod/xcframework + the on-device parity-gate run on Shayne's iPhone are PENDING (no Xcode/device in the
build session). **Builds on:** DEC-126/127 (shot on-device-first + metrics endpoint), DEC-118 (Form MVP metrics +
Beta gates), DEC-120/121 (form event baseline + tolerances + step-count honesty), DEC-122 (partial results +
outcome rows), DEC-057 (form fundamentals). **Supersedes:** the Apple-Vision `OnDeviceFormShadow` as the on-device
form measurer.

## Superseded decisions
- DEC-029 / DEC-033 — server-side-only analysis **amended by DEC-102** (offline-first, hybrid: on-device measurement where validated, server stays fallback + reference). Server-authoritative coaching/score/tiers unchanged.
- DEC-092 — near-term optimize-server-first order and "metric math stays on the server" **stand**; only the **long-term scope** is amended by DEC-102 (on-device metric math becomes the target once the DEC-103 gates pass). DEC-092 P3's observation interface is realized as `MeasurementEvidence` (DEC-103).
- DEC-062 — production CV freeze **lifted for the shadow/validation track only** (DEC-102); production CV behavior stays frozen until the DEC-103 gates pass.
- DEC-096 — "leaving the Lab tab doesn't end the session" superseded in part by DEC-099 (the tab bar is hidden on the Active Session; End session is the way out).
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
