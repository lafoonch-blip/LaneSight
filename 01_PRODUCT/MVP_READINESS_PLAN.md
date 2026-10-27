# MVP Readiness Plan — Everything Needed Before (and During) the MVP App Build
Status: DRAFT (for Shayne's review)
Version: 0.2
Last Updated: 2026-10-22
Owner: Shayne
Inputs: BUILD_PLAN v3.5, CURRENT_STATE v1.19, FEATURE_REVIEW, DECISIONS (DEC-017…044), BENCHMARKS_AND_RECOMMENDATIONS_SPEC v0.3, FORM_ANALYSIS_SPEC v0.1
Proposed home: `01_PRODUCT/MVP_READINESS_PLAN.md`

## 1. Two finish lines
To start the app build sooner, this plan separates two finish lines:

| Finish line | Meaning | Who uses it |
|---|---|---|
| **Build-ready** | Scope, data contracts, API and designs are frozen, so Claude Code can build the SwiftUI app against real back-end endpoints | Shayne-only MVP testing |
| **Beta-ready** | Stage 1–6 accuracy gates pass on the locked eval set; cloud, privacy and age gate live | Friends Beta |

**MVP exit (decided 2026-10-22):** Shayne tests and uses the MVP for as long as he wants and decides when it is ready for Beta. The Stage 1–8 gates are tracked as readiness evidence for that call, not as automatic exit criteria. BUILD_PLAN "MVP exit" (private beta of 10–25 league bowlers) needs updating to match.

Accuracy work does not block the app build. The app is built against the `ShotRecord` contract and the per-metric Measured / Unavailable states, so accuracy keeps improving underneath it.

## 2. Readiness by area

Legend: ✅ done · 🟡 prototype or partial · ⬜ not started · **S** = Shayne action · **C** = Claude Code work

### 2.1 Ball / shot metrics (Stage 1)
**Status 🟡.**
- Speed, loft, release, impact and pins are working.
- Rev rate comes with a ±band.
- Boards, breakpoint and entry are prototypes.
- Finish rate is 57% on the live session; every failure is non-standard framing and fails honestly.

| Remaining | Owner | Blocks build? |
|---|---|---|
| Capture Seed Dataset v1: 30–50 shots with Ruby; some at 120/240 fps; SDR (HDR off); a few with tape on the ball | S | No (blocks Beta) |
| Lock the labeled eval set; eval-verify M1-06/07/08/09 | C | No |
| Multi-lane separation for oblique framing (M1-01) | C | No |
| Capture/framing gate logic that the app calls before analysis (DEC-033/035) | C | **Yes**: the app needs the API |
| **Axis tilt/rotation and PAP from video stay in MVP (decided 2026-10-22).** Show a value only when calculable; otherwise blank with an Unavailable reason. Track accuracy against sensor data (Ruby now; F5/Witsee later) in the eval harness. Needs 120+ fps capture and the M1-10/11 CV work | C (+S capture) | No (fields and Unavailable states go in the contract now) |

### 2.2 Moving camera / smart glasses (Stage 2)
**Status 🟡.** Handheld is validated; head-turn, rolling shutter and first-person view are not started, and all of it is blocked by the paired capture (M2-05).
- **Recommend:** tripod + handheld in MVP; smart glasses as best effort in Beta, gated on the M2-05 paired capture (tripod + handheld + glasses, same shots). The app shows more Unavailable states for glasses, by design.
- **S:** get Meta glasses test clips (native recording + live stream).

### 2.3 Form metrics (Form Analysis)
**Status 🟡.** Rear-view prototype exists: timing splits, swing height, finish hold on the 10-20 clips. Side-view 120 fps is not captured yet.

| Remaining | Owner |
|---|---|
| Record a side-view session at 120 fps with the bowler ≥40% of frame height (unlocks step count, cadence, timing at slide) | S |
| Two-annotator frame labels on ~30 deliveries (step contacts, events E0–E9) | S (with a C labeling tool) |
| Package the P1 pipeline in `lanesight-core`: `analyze_form_clip`; status per metric; eval mode in `eval_session.py` | C |
| Decide whether Form is in the MVP | Decision |

### 2.4 Fundamental rules and benchmarks
**Status:** spec v0.3 is decided; nothing is built yet.

| Remaining | Owner |
|---|---|
| Supabase migration 005: `benchmark_reference`, `style_template`, `form_rule`, `drill`, `engine_config`, `personal_baseline`, `finding`; admin-only RLS | C |
| Seed L0 references + starter rules + drill text as YAML in `lanesight-core/rules/`; loader + versioning | C |
| Baseline (N=10) + comparison + prioritizer engine; tests on the 10-17 and 10-20 clips | C |
| Owner-only Rules page in the local runner (view, edit, replay test, publish) | C |
| Review and approve the starter cues/drills text | S |

### 2.5 Insights and adjustments (Stage 4)
**Status 🟡.** Shot reading, intent vs actual, strike moves, spare system, transition and oil context are all prototypes.

| Remaining | Owner |
|---|---|
| Primary + secondary recommendation ranking | C |
| Shot-intent capture + "Did you hit your mark?" in the API | C |
| Accept/reject feedback loop and `recommendation_outcome` (M4-06) | C |
| Route execution misses to form cues (benchmarks spec §5.1) | C |
| Ball-change suggestions wired to the arsenal (`rank_for_condition`) | C |
| Eval-verify recommendations on the seed dataset | C (after S capture) |
| Certified-coach review of rules and weights (M4-08): **Beta gate, not build gate** | S |

### 2.6 AI feedback wording
- Decided: rules + evidence make the call; an LLM may only phrase it (FEATURE_REVIEW §2.8).
- **Recommend for MVP:** templated text from rule records ($0, deterministic, ≤12-word spoken cue). Optional LLM phrasing comes later behind a flag, checked against the DEC-043 cost caps.

### 2.7 Ball arsenal
**Status ✅/🟡.** 211-ball catalog is live in Supabase; configured reaction (layout + surface) is built.

| Remaining | Owner |
|---|---|
| API: catalog search, add ball to arsenal, layout entry, surface log, current ball per session | C |
| Layout preset ↔ pin/PAP mapping (FEATURE_REVIEW decision 4) | C draft, S approve |
| Catalog terms-of-use check for linked manufacturer photos | S |

### 2.8 Scoring and stats (Stage 3)
**Status 🟡.** Frames, scoring and LaneTalk-parity stats are prototypes.
- **C:** manual pin/score correction API; aggregation endpoints (session, ball, pattern, all-time); eval-verify.

### 2.9 LaneSight Score and achievements
- **Score (DEC-038/041):** the formula and smoothing are still spec-only, and **implementation is blocked by the decision below.**
- **Achievements (DEC-039):** in the MVP. Implement only rules fed by verified inputs (scoring, streaks, onboarding); thresholds stay provisional.
  - **C:** achievement engine + seed rules.
  - **S:** approve the launch set.

### 2.10 Oil patterns
- **Status:** schema only.
- **Decided 2026-10-22:** build a pattern library the same way as the ball catalog. Pull an initial list of published patterns (name, length, volume, ratio, source link) and refresh it on a schedule. Keep "House shot", "Unknown" and user-entered patterns too.
- **C:** source research (Kegel and other published pattern libraries), scraper/importer + seed in `lanesight-core/data/oil_patterns/`, Supabase migration + seed, scheduled refresh job, terms-of-use notes per source.
- **S:** approve the sources after the terms check.

### 2.11 Replay and heatmap
- Static replay image + trajectory + heatmap are in MVP (prototypes). Replay playback is post-MVP (decided).
- **C:** expose the replay payload in the API.

### 2.12 Platform: API, cloud, capture
| Remaining | Owner | Blocks build? |
|---|---|---|
| **Freeze the API contract:** OpenAPI generated from `ShotRecord` + session, arsenal, findings and stats | C | **Yes** |
| FastAPI service wrapping `core.analyze_clip` (Mac first); serial job queue (C-02a); upload endpoint | C | **Yes** |
| Supabase auth (email/Apple), storage buckets, retention | C | **Yes** |
| 13+ age gate; Beta/Prod feature toggle; delete account | C | Yes (small) |
| OPS-01 instrumentation (per-step timings, cost per 1,000 shots) | C | No |
| Offline capture queue (C-04) | C | No (Beta) |
| AVFoundation capture with real timestamps, 60/120/240 fps, SDR (U-04) | C (in app build) | — |
| CI (F-06) for `lanesight-core` | C | No |

### 2.13 Design (Figma)
- Home is approved; Performance Lab replaces Sessions.
- **S:** approve mockups for Performance Lab hub, Live Session, Upload, Shot Detail, Form results, Stats, Arsenal (catalog, layout, surface), Achievements, Settings/onboarding (age gate). Then recreate them in Figma from components and flag missing components.
- **C:** produce image mockups for each remaining screen on request.
- **Fix:** the bottom nav still lists "Sessions" (Home, Stats, Sessions, Leagues, Tournaments). Confirm it becomes "Performance Lab" or "Lab".

## 3. Critical path to build-ready
1. **Decisions** (§4).
2. **Freeze contracts:** API spec + Supabase migrations 005+ (rules, findings, intent, recommendation outcome, achievements).
3. **Back-end service:** FastAPI on the Mac wrapping `analyze_clip` + rules engine + arsenal/stats endpoints; tested end to end with existing clips.
4. **Designs approved** for the MVP screen list (in parallel with 2–3).
5. **App build starts** (Stage 7) against real endpoints. No mock data in the shipped paths.

**In parallel, not blocking the app:** Seed Dataset + eval-verify (Beta gate), side-view form capture + labels, multi-lane fix, glasses clips, coach review.

## 4. Decisions (2026-10-22)
| # | Decision | Answer |
|---|---|---|
| D1 | Form Analysis in MVP | **Yes, P1 metrics** (timing splits, step count/cadence, finish), labeled Best effort; P2 in Beta |
| D2 | Smart glasses in MVP | **Tripod + handheld in MVP**; glasses best effort in Beta after the M2-05 paired capture |
| D3 | AI feedback wording | **Templates** from rule records; LLM phrasing later behind a flag |
| D4 | LaneSight Score | **Provisional DEC-038 formula, labeled "Beta score"**; hidden in production mode until validated |
| D5 | MVP exit | **Shayne's call**: he tests indefinitely and gives the word for Beta |
| D6 | Axis/PAP from video | **In MVP**; populate when calculable, blank + reason otherwise; accuracy tracked vs sensor |
| D7 | Oil patterns | **Published-pattern library**, pulled initially and refreshed on a schedule, like the ball catalog |
| D8 | League-night capture | **Tap to record per shot** |

## 5. Shayne's at-lane checklist (one or two sessions)
- [ ] Rear lane view, tripod, 60 fps SDR, ~25 shots with Ruby (Seed Dataset)
- [ ] Same shots at 120 fps (rev band + axis groundwork); 5 at 240 fps
- [ ] Tape mark on the ball for 10 shots
- [ ] Side bowler view, 120 fps, bowler ≥40% of frame, ~20 shots (Form P1)
- [ ] Handheld + glasses on the same shots as the tripod, ~10 (M2-05)
- [ ] Note intent (feet/arrows/breakpoint) and "hit mark?" per shot
