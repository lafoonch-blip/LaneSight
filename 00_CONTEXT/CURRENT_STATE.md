# LaneSight Current State
Status: CANONICAL  
Version: 1.29  
Last Updated: 2026-10-25  
Owner: Shayne  
Supersedes: v1.28

## Where these docs live (DEC-025)
- **Source of truth:** GitHub `lafoonch-blip/LaneSight` (`main`). Edit here; read `AGENTS.md` first.
- **Mirrors (read-only):** the Google Drive LaneSight folder and the claude.ai LaneSight Project. Re-sync them after every change.
- **Code:** `lanesight-core/` in this repo (F-02 done 2026-10-14). On Shayne's Mac, `~/Developer/LaneSight/` is a clone of this repo; pull before working. (Relocated from `~/Documents/LaneSight` on 2026-10-22 so the launchd API service can start at login — macOS TCC blocks background jobs from reading `~/Documents`, `~/Desktop`, `~/Downloads`.)
- The September 2026 local docs are archived in `99_ARCHIVE/2026-09-27_local_folder/`. Historical only.

## Building now
**Active workstream (2026-10-22): Dev Build v0** — the first iOS build, for Shayne's iPhone, running against the real pipeline on his Mac over Tailscale (DEC-045…053; see the Dev Build v0 section below and `03_ENGINEERING/dev_build_v0/HANDOFF.md`). The back-end accuracy/robustness work continues in parallel.

The back end (DEC-017), stage by stage: metrics engine → moving camera → scoring/stats → insights/adjustments → profile/arsenal/oil/sensor → replay payload. UI and cloud come after. The app stack is decided (DEC-029): **native SwiftUI**, AVFoundation capture (60/240 fps, real frame timestamps), FastAPI + Supabase backend, Xcode project in this repo next to `lanesight-core`; Figma design in progress (Shayne).

## Where things stand
- **Recommendation guardrails + design 3.7 (2026-10-25, GUARDRAILS 3.7 handoff; SHOT_REVIEW 14b234c8):** the lane session exposed the real failure — a close/off-axis camera corrupts the far-lane depth scale, so some shots came out with impossible metrics (late speed > early, entry board off by ~7) and others didn't analyze. Shipped (committed on the Dev Build branch, **not yet deployed to the live Mac service**):
  - **B — plausibility gate (DEC-061):** `capture_quality.far_lane` ("limited" + a camera-spot reason) and far-lane metrics flagged `low_confidence` (not shown as measured) when the depth scale is implausible; `speed_release` → `best_effort`. Verified on 14b234c8 (flagged) and IMG_8753 (not false-flagged). Values unchanged.
  - **C — recommendation state machine:** insights carry an explicit `state` (`move | low_confidence_move | strike_repeat | execution_miss | pins_unknown | no_reliable_data`) + confidence + note; a single shot never moves more than 2-and-1 (3-and-2 needs 2+ agreeing shots); boards clamped 1–39.
  - **API — `POST /shots/{id}/pins`** (user reports the leave when the deck was unreadable) + insights now recomputed with the thrown intent + session history, so the execution check and transition read actually run (they never did on the API path).
  - **D — pins:** read the deck from frames that still see it (recovers a clear settled frame); report the observed signal, not the false "bowler stepped into view". 14b234c8 now reads its strike.
  - **E — uploads deduped by content hash** (migration 016); score-reset script for the contaminated session written (`ops/reset_contaminated_score_2026-10-25.sql`, do not auto-run).
  - **F — iOS 3.7:** shot card renders from `state` + the camera banner; one status mapping; "boards" not "ft"; SessionReview read-only; Under-13 block. **G — profile photo** `/me/avatar` + `location` column (migration 017).
  - **A — far-lane calibration (the real metric fix) is NOT done** — it's deep CV that must be validated against the regression clip + IMG_8751–8754 and benefits from the lane clips Shayne records next. Until then the honest flags (B) stop confident-wrong advice. **Biggest lever right now is capture framing: stable camera behind the lane, square to it, whole lane in frame.**
  - **Deployed 2026-10-25 (Shayne authorized):** migrations 016 + 017 applied to live; score-reset run (3 pre-DEC-055 uploads detached from session 3338e9ec, derived score/tier/achievement/finding/notification state cleared for the owner); `com.lanesight.api` restarted (pid live, mode live, new `/shots/{id}/pins` + `/me/avatar` routes serving); branch `dev-build-v0` pushed to GitHub.
  - **Pale-lane + training-clip work (2026-10-25):** the 17 pale-maple clips (IMG_8893–8910) took the lane detector from 0/17 → 3/17 analysing (saturation-floor retry), with the rest honestly flagged or failing with clear errors (no crashes, no garbage advice). Detection robustness for elevated / approach-dominant framings is the remaining coverage work — see `02_RESEARCH/TRAINING_CLIPS_2026-10-25_pale_lanes.md`.

- **Ball catalog + configured reaction (2026-10-21, DEC-044):** 211 current balls from 10 brands with stock-photo links, 15 lb specs, published ratings and a normalized expected reaction; a bowler's ball reaction is adjusted for its layout and current surface. Code and data in `lanesight-core` (`lanesight_core/arsenal/`, `data/ball_catalog/`); migrations 002/003 **applied to the LaneSight Supabase project** (`europwryibstnmipbvam`), `ball_models` seeded (211 rows), along with `004_rls_hardening` and `005_ball_catalog_refresh` (reconciled into the repo 2026-10-22 — see Dev Build v0 below). Adjustment sizes and recommendation weights are provisional (M4-08).
- `lanesight-core` in `lanesight-core/` (54 tests passing, re-run 2026-10-15):
  - automatic video pipeline: tripod + handheld, pin reading, rev rate
  - scoring/stats, insights/adjustments, spare targeting
  - Postgres schema
  - shot record + replay
  - capture-tier and sensor capability engine
- At-lane local runner built (`lanesight-core/lanesight_runner/`, `03_ENGINEERING/LOCAL_RUNNER_SPEC.md` v1.2): AirDrop → Mac analysis → shot card + spoken adjustment, pin correction, Ruby entry, CSV export. **Verified end-to-end on the Mac (2026-10-14)**: IMG_8754/IMG_8751 run through the real server and reproduce the validation numbers within tolerance (speed ±0.1 mph, rev/pins exact, boards ≤1). The iPhone validation clips are HDR and this Mac's ffmpeg lacks zscale, so `convert_sdr` now has a portable numpy HLG→SDR fallback (no libzimg needed); recommended capture is still SDR (HDR Video off). **Shot-window trimming done (2026-10-14):** a motion pre-pass finds the ~6–9 s shot and trims the dead set-up time — IMG_8754 went 279 s → 81 s (3.4×), numbers preserved; the trimmed shot then replaces the stored clip (~102 MB → ~31 MB).
- **Runner v2 UI rebuilt (2026-10-15, `03_ENGINEERING/runner_v2/RUNNER_V2_SPEC.md`):** single-page dashboard (all panels full-width, no tabs) — Latest Shot (clip/lane view + oil toggle + board/arrow guides, Shot Metrics with vs-avg deltas, split What-went-well / What-to-watch analysis), Session Overview (5 KPIs, metrics chart, accuracy/consistency rings, shot-distribution scatter), Shots list, Lane Transition (status + trend rows). Full **Ruby sensor integration**: per-shot entry (axis tilt/rotation, PAP over/up, setup + pushaway/backswing/downswing/release timing, swing height; "Copy last shot") shown in the Rotation panel with an axis diagram and approach-breakdown bars, all labeled "Ruby" (see `01_PRODUCT/SENSOR_VS_VIDEO_METRICS.md`).
- **CV accuracy hardening (2026-10-15):** pale / low-contrast lanes now detect via a dark gutter-edge fallback; impact time is fixed to when the ball reaches the pins (its farthest tracked point), correcting an inflated distance scale; the post-shot trim tail was lengthened so pins settle in view, **decoupled** from the stabiliser so it never perturbs the shot metrics; and crash guards were added for off-frame foul lines and sparse tracks.
- **Pin reading is video-only and honest (DEC-026):** when the deck is blocked (bowler steps in) or the clip ends before the pins settle, the result is reported **unreadable** with a reason and excluded from strike/open/carry stats — never a guessed strike. Fix pins to record the real result.
- **Rev rate is honest too (DEC-027):** when the ball's surface pattern has no clear repeat, the period search hits the edge of its 4–10 Hz band and `60 ÷ period` returns the band ceiling (~672 sensor-equivalent) — a wall value, not a reading. That rail landing is now detected and rev rate reported **unavailable** with a reason instead of the ceiling. Fixed the three live-session shots that read ~672 vs Ruby ~400; the correct interior reads (404/448/350) are unchanged.
- **Rev rate reports a capture-adaptive precision band (2026-10-16, DEC-028):** the appearance autocorrelation only resolves whole-frame lags, so at 60 fps rev is quantized to ~±40 rpm (five different throws, Ruby 378–444, collapsed to an identical 403.5; sub-frame interpolation didn't fix it). Rev now carries its real uncertainty `rev² / (60·fps)` — ~±40 at 60 fps, ~±20 at 120, ~±10 at 240 — shown as "value ± band" with confidence tempered by the band width. The value is unchanged; this stops false precision. The real resolution gain comes from **120 fps capture**, which also unlocks axis (M1-10). **Phase refinement (2026-10-16):** after the coarse autocorrelation seed, the rev frequency is refined with long-baseline phase coherence over all crop pairs (narrow window, no harmonic jump) — the "count many rotations" principle from the community Speed & Revs calculator. This **killed the snapping**: MAE 22→20 rpm, shot-to-shot corr 0.60→0.69, and every clip now reads a distinct value tracking Ruby (was five shots stuck at an identical 403.5).
- **Evaluation harness + first Ruby accuracy pass (M1-14, M5-05, 2026-10-16):** `lanesight-core/examples/eval_session.py` scores a whole clip folder through the real pipeline (`core.analyze_clip`, extracted so the runner and the harness share one path); `examples/score_vs_ruby.py` matches videos to Ruby by timestamp (QuickTime creation + ~30 s set-up delay) and reports variance. On the 21-clip live session: **finish rate 57 %** (12 done, 8 clear lane-detection failures, **0 crashes** after the off-frame-foul-line fix). Accuracy vs Ruby on the matched shots — **speed MAE 1.11 mph, bias +1.10**, **rev resolution-limited** as above. The finish-rate gap is entirely lane detection on oblique / multi-lane framing (not far-back). Ground truth stored in `validation/ruby_live_session_2026-10-15.json`.
- **Speed over-read is upstream of the formula (2026-10-16 investigation):** tested four speed definitions (current `60 ft ÷ (release→impact)`, covered-distance, robust roll-slope, deceleration-aware quadratic) against Ruby — **none beats the current one** (it has the lowest MAE, 1.11); the alternatives add per-clip noise. Two upstream causes, both in the CV not the arithmetic: (a) **short back-half tracking** — when the ball track fades before the 59.44 ft headpin (e.g. 52.9 ft on IMG_8807), dividing a fixed 60 ft by the short interval inflates speed ~12 %; (b) **lane-geometry scale** — a few clips (IMG_8819/8815) track to the pins yet imply ~2 mph high, a homography-scale question Ruby alone can't adjudicate (needs Specto) and partly Ruby imperfection. **Resolution (2026-10-16):** first tried release speed as the headline (DEC-030), then found the real fix — **far-lane track recovery (`extend_forward`, DEC-036).** The ball stays *detected* to ~61 ft, but on trim-degraded stabilisation the jittery far ball was dropped by the RANSAC refine / trailing-segment trim, stopping the track ~6 ft short and inflating the 60 ft speed. `extend_forward` walks forward through the dropped far candidates along the fitted trajectory. With the ball reaching the pins, the impact anchor sits at the true 59.44 ft, so the **60 ft average is accurate again and is the headline `ball_speed`**: MAE 0.83 (≈0.35 excluding the corrupted 8815 + geometry-outlier 8819), **entry board recovered** (was unavailable) and **entry angle corrected** (1.4° → realistic 3.8–5.6°) — required for the new primary Accuracy metric (DEC-031) and the DEC-034 entry gate. Release/skid speed stays as secondary `speed_release` (reads ~9 % low from a **near-field homography Z-scale residual**, the remaining speed lever, settle against Specto). The >30 mph scale-sanity guard still fails honestly when the back half can't be recovered.
- **Finish-rate gap is framing, diagnosed (2026-10-16):** all 9 of the 21-clip failures are non-standard framing, each failing *honestly* with a clear message (gate's "clear failure state" met): far / washed-out ("no lane-colored wood", 0.3–3.4 %), **oblique multi-lane** ("wood found but no common VP"), and too-low (foul line off the bottom of frame, the 120 fps IMG_8831). Root cause of the oblique cluster: at an oblique multi-lane angle the `lane_mask` morphological close **bridges the thin gutters**, merging adjacent lanes into one wood-run track → double-width, garbage edge fits (residuals 45–210 px) → VP gate fails; the gutter-edge fallback then rejects the oblique geometry on its overlap/width gates. Fix paths: (a) **multi-lane separation** — stop bridging gutters / split merged tracks / relax the gutter-fallback gates for oblique views (focused CV work, regression-tested against the 12 working clips); realistic multi-lane views with the throw lane centred (IMG_8817) are worth supporting, extreme cross-lane (IMG_8810) and far/too-low are poor framing; (b) the app's **capture-quality / framing gate** (DEC-033/035) prevents far / too-low / extreme-oblique framing before analysis. On well-framed tripod clips the pipeline already succeeds — the 12 "done" are the well-framed ones.
- **First live lane session held 2026-10-15** (practice, ball + Ruby S2, ~21 shots recorded, 14 analyzed). Next: Ruby↔video shot matching by timestamp (M5-05), continued accuracy on marginal / off-angle clips, and staged results (fast metrics first).
- Validated against Ruby on 4 shots (pre-session baseline):
  - Speed is within 0.5% on 3 of 4 shots.
  - Loft is within ~1 frame.
  - Rev rate tracks Ruby at a stable ratio.
  - Pins: 14 of 14 runs correct (the live-session clips add real occlusion/framing cases — see pin honesty above).
- The capture-tier test (30/60 fps × 720/1080p) set provisional per-tier guarantees. See `01_PRODUCT/METRIC_CAPABILITIES.md` and DEC-023 (proposed).
- Details: `02_RESEARCH/VIDEO_VS_RUBY_VALIDATION.md`.

## Validation roadmap (`02_RESEARCH/VALIDATION_PLAN.md`)
- **Ruby:** in hand.
- **Witsee and F5 sensors:** Shayne plans to acquire both for cross-sensor validation of rev rate, axis tilt/rotation and release speed.
- **Specto center sessions:** planned, as ground truth for lane position (foul-line board, launch angle, entry board/angle, entry speed). Specto is the key reference for the Stage 1 gate.

## MVP (DEC-019)
- Shot metrics with confidence: speed, rev rate, loft, laydown, arrows, breakpoint board/distance, entry board/angle, pin leave; axis and PAP where feasible
- Fixed and moving camera (DEC-018)
- Virtual replay: trajectory, heatmap, key points
- Insights and next-shot adjustments from the shot + pins; spare targeting
- LaneTalk-parity stats: strike %, spare %, conversion by leave, opens, first-ball average, pocket/carry
- Bowler profile, arsenal with drilling/layout, ball per shot/session
- Session and all-time trends
- Oil pattern library
- Optional sensor pairing with variance display (DEC-021)
- UI, then cloud storage and instant at-lane analysis

## Not MVP
- League integration/registration
- League management
- USBC membership connection
- Team Lane Management
- Center scoring integrations (assumed later via `ScoringAdapter`; DEC-020)
- Payments

## Current blockers / discovery
- Seed Dataset v1: 30–50 varied shots with sensor data, some at 240 fps (~21 captured in the 2026-10-15 live session with Ruby S2, varied camera distance; none at 240 fps yet)
- Ruby export: no confirmed file export; Ruby data is hand-entered today. Confirm what the app can export (R-02) so shot-matching (M5-05) can be automated
- Specto session(s): find a local Specto center and confirm data access/export
- Witsee + F5 purchase; confirm what data each app exports
- Meta glasses test clips, native recording + live stream. Third-party live stream is reportedly capped at 720p/30.
- Decision on DEC-023 (minimum capture requirements)

## Latest major strategic decision
Back end first, with moving-camera measurement and coaching/stats in MVP (DEC-017/018/019).

## Brand
- Master brand: LaneSight
- Logo: official Figma brand-standards logo (lane-and-arc mark + LaneSight wordmark), DEC-054; icon pack in `02_DESIGN/brand/`; shipped in the iOS app as the app icon and in the Welcome + Home headers
- Tagline: See More. Bowl Smarter.

## Product direction update — 2026-10-18 (DEC-040/041)
- **Approved direction, not shipped:** Performance Lab is the central analytics UX with separate Shot Analysis and Form Analysis capture modes, one camera view selected per recording. Session activity type (Practice/League/Tournament) stays independent of analysis mode. Preserve existing Shot MVP scope; prototype bowler-facing pose/form capture and coach video review as parallel follow-on work.
- **Coaching roadmap:** original/annotated form video, confidence-labeled metrics, baseline comparisons, coach comments/corrections and drills with explicit sharing consent. Ruby sensor entry exists in runner; vendor API integration is **not verified**. Investigate Ruby/F5 and scoring providers without claiming access.
- **Score direction:** one LaneSight Score with long-term trends and PB, no separate Improvement Score, no Form pillar. DEC-038's 40/25/25/10 remains spec-only; Power & Carry normalization and recency smoothing remain open. Achievements remain independent.
- **Implementation next:** add capture-mode field and form video asset metadata; form measurement feasibility/validation harness; coach share permissions; scoring trend UI; preserve source/quality/version for every metric. Update Figma after specifications. See `01_PRODUCT/PERFORMANCE_LAB_STRATEGY.md`.


## Performance Lab roadmap decision — 2026-10-19 (DEC-042)
- Three entry tiles: **Start Live Session**, **Upload Video to Analyze**, and **Compare to a PBA Pro**.
- Pro comparison tile is visible but **disabled / Coming Soon for MVP**; full pro comparison is **post-MVP**, depends on footage rights and validated form/shot comparisons.
- Image concept mockups requested for review; **do not edit Figma yet**.
- Performance and reliability targets are **proposed**, not achieved SLAs: `03_ENGINEERING/PERFORMANCE_RELIABILITY_SLO_PROPOSAL.md`.
- Pro reference requirements: `01_PRODUCT/PBA_PRO_COMPARISON_PROPOSAL.md` v1.1. Maintain approved Shot/Form analysis modes from DEC-040, capture limitations per DEC-035.


## Dev Build v0 — 2026-10-22 (DEC-045…053)
The active build. A **developer build of the LaneSight iOS app on Shayne's iPhone**, used live at the lanes, exercising every core feature end to end against the **real** `lanesight-core` pipeline on his Mac. Three purposes: test all core functionality, collect feasibility data on every core metric (coverage, failure reasons, timings), and capture session feedback after every session. Full brief: `03_ENGINEERING/dev_build_v0/HANDOFF.md`; approved screens: `02_DESIGN/dev_build_v0/` (24 `.dc.html` + `canvas.json`).

- **Architecture:** SwiftUI app (`ios/LaneSight`, bundle id `com.lanesight.app`) → Supabase Auth (Apple/Google/email) → `lanesight_api` (FastAPI, launchd) on the Mac, reached over **Tailscale** (`tailscale serve` → localhost HTTPS). The API reuses `lanesight_runner/core.py` (`analyze_clip`); the pipeline is not forked. Video stays on the Mac (`~/LaneSightData`); the Supabase service key is Mac-only.
- **In scope:** Shot + Form (P1) analysis, live capture + upload, recommendations/benchmarks (owner-only rules), LaneSight Score `L-dev-0` + tiers + achievements, Score/Throw/Form stats, profile/arsenal/sensors/settings/account deletion, session feedback, dev panel + CSV export.
- **Out of scope:** pinfall/game scoring (DEC-050), leagues/tournaments ("Soon"), PBA comparison (disabled tile), cloud workers / R2, smart glasses, replay playback, coach sharing, Ruby references in app UI, payments.
- **Score:** `L-dev-0` (DEC-048), a no-pinfall dev/Beta formula; see `01_PRODUCT/METRIC_AND_SCORING_LOGIC.md`. The target formula remains DEC-038.
- **Capture is never blocked by framing (DEC-045):** an advisory spot check suggests a better position; it never gates recording.
- **Build phases:** recorded in `BUILD_PLAN.md` as the Dev Build v0 stage (`DV-00…DV-05`). DV-00 (docs), DV-01 (DB, migrations 006–010 live) and most of DV-02 (engines) are done.
- **DV-02 engines (2026-10-22):** pure, DB-free packages in `lanesight_core/` — `score/` (L-dev-0 + Accuracy/Consistency/Performance/Power + tiers), `benchmarks/`, `achievements/`, `insights/routing.py` (target-vs-actual + form routing), `owner.py` (reset). **Deferred, honestly unavailable:** Form P1 metric *values* (need a pose backend + the 2026-10-17/20 clips), rule/drill YAML content (owner-reviewed, draft in `03_ENGINEERING/dev_build_v0/RULES_AND_POWER_REVIEW.md`), and Power P′ reference ranges (ball weight 15 lb confirmed; ranges still await approval).
- **DV-03 lanesight_api (2026-10-22):** FastAPI Mac service — Keychain creds (PostgREST via service_role; ES256/JWKS auth), serial job queue (DEC-043), reuses `analyze_clip`, committed OpenAPI spec, launchd + `tailscale serve`. **Live e2e PASSED** against the real project (IMG_8807): real analyze (~24 s) → L-dev-0 → feedback → CSV, with score_snapshots + feedback written to Supabase and cascade-cleaned. Follow-ups: persist `shots`/`measurements`; remaining §3 endpoints. Full suite 134 tests pass.

**Open before Phase 1 (Shayne-side / to confirm):**
- **Supabase project (confirmed 2026-10-22):** LaneSight = `europwryibstnmipbvam`, ACTIVE_HEALTHY, us-east-1, in the **VendHub** org (`wmprtjakyzfgszjqjtky`). Never touch the org's other projects (`vendhub`, `LandForge`).
- **Migrations (DV-01 done 2026-10-22):** LaneSight Supabase (`europwryibstnmipbvam`) is now at **001→010**. 001–005 were already applied (004/005 reconciled into the repo verbatim); **006–010 (Dev Build v0 schema) applied 2026-10-22** after local validation (PG16 + Supabase shim) and a timestamped backup — branching wasn't available (Free plan), so applied to the empty project with Shayne's OK. 006 rules/benchmarks (owner-only), 007 score/tiers/achievements + `L-dev-0`, 008 dev-build fields, 009 oil-pattern library, 010 invoker-view fix. **Security advisor: no errors** (only intended INFO `rls_enabled_no_policy` on owner-only rule tables, DEC-046). RLS verified (rules/`params` unreadable by clients, own-rows-only); permanent test at `lanesight_core/models/tests/run_rls_tests.sh`. `ball_models` unchanged (211, md5 `c02f62043c64cfe80d99be12e40ab2ae`). New migrations extend the live tables (`oil_patterns`, `recommendations`, `shot_intents`, `sensor_devices`, …), never re-create them.
- **OAuth:** Google (iOS + web client IDs → Supabase Auth) and Sign in with Apple (App ID capability + Services ID/key → Supabase Auth) need setup on Shayne's side.
- **`lanesight-core/tailscale/`** is an untracked folder of unknown purpose — ask Shayne before using or deleting it.
