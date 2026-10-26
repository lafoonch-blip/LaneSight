# LaneSight Build Plan
Status: CANONICAL  
Version: 3.11  
Last Updated: 2026-10-26  
Owner: Shayne  
Supersedes: v3.9 (MVP+ Multi-Bowler Session Tracking added — DEC-060); v3.8 (DV-03 lanesight_api done — live e2e on the real project passed; shots/measurements persistence + remaining §3 endpoints are follow-ups); v3.7 (DV-02 engines landed — score/tiers/benchmarks/achievements/routing/owner, 127 tests; Form P1 values deferred to a pose backend + clips); v3.6 (DV-01 done — migrations 006–010 applied to LaneSight, advisor clean, RLS tested; DV-03 gains Keychain secrets + pg_dump backups); v3.5 (DV-01 reconcile: Supabase project confirmed, 004+005 pulled into the repo, DV migrations renumbered from 006); v3.4 (Dev Build v0 stage with DV-00…DV-05, and MVP exit recast as Shayne's judgment — DEC-045…053); v3.3; v3.2 (performance/reliability targets recast as target state, upload in MVP, serial analysis, cost caps — DEC-043); v2.5 (Stage 7 native SwiftUI + AVFoundation capture, Stage 8 analyze_clip entry — DEC-029); v2.4; v2.3; v2.2; v1.0 (phase ordering). Task IDs from v1.0 keep their meaning. Where a v1.0 task moved, the new task notes it with "(was X)".

Sequence (DEC-017): **Back end → UI → Cloud.** MVP scope: DEC-019. Moving camera is in MVP back end: DEC-018. Metric definitions: DEC-022.

The back end has to satisfy the contracts in `LaneSight_PRD_UI_Spec_v1`:
- §7 metric targets
- §8 recommendation engine
- §12 data model
- §13 API

Its color tokens are superseded by DEC-016.

**How to use:**
- `[x]` = done and verified against the eval set.
- `[~]` = prototype built and working on the 4 validation shots, not yet eval-verified.
- `[ ]` = not started.

Tasks keep their IDs forever.

Size: S = days · M = 1–3 weeks · L = 1–2 months

---

## Status (2026-10-14)
`lanesight-core` v0.5.0 is a Python package with 54 passing tests:
- **Stage 1:** automatic video pipeline for tripod and handheld video, including pin reading (4 of 4 correct) and rev rate.
- **Stage 3:** scoring and LaneTalk-parity stats.
- **Stage 4:** insights, adjustments, spare targeting and transition.
- **Stage 5:** Postgres schema with row-level security, plus sensor variance.
- **Stage 6:** `ShotRecord` contract, session analytics, heatmap and replay render.

Validation vs Ruby: `02_RESEARCH/VIDEO_VS_RUBY_VALIDATION.md`.

**Next blocker:** Seed Dataset v1 (M1-15), so prototypes can be eval-verified (~21 shots captured in the 2026-10-15 live session with Ruby S2; none at 240 fps yet). The runner v2 UI is built (`03_ENGINEERING/runner_v2/RUNNER_V2_SPEC.md`) and the sensor comparison (M5-05) is the active next step once Ruby data can be matched by timestamp.

---

## Stage 1 — Back-end metrics engine (fixed camera)  (L)
*Every shot metric as close to ground truth as video allows, with confidence and "unavailable" states.*
- [x] M1-01 Auto lane geometry: edges, foul line, vanishing point, pin deck (was P0-04, now automatic). Works on well-framed tripod clips; the 21-clip finish-rate gap is non-standard framing (far / oblique multi-lane / foul off-frame), each failing honestly. Oblique multi-lane diagnosed: the mask close bridges thin gutters and merges adjacent lanes — fix = multi-lane separation + the app framing gate (DEC-033/035). See CURRENT_STATE
- [x] M1-02 Ball detection + tracking robust to glare, occlusion and loft (was P0-05/06)
- [x] M1-03 Release, touchdown and impact event detection
- [x] M1-04 Speed + speed profile. Headline = **60 ft foul→pins average**, reliable after far-lane track recovery (`extend_forward`, DEC-036); release/skid kept as secondary `speed_release`. Validated vs Ruby (live session): MAE 0.83 (≈0.35 excluding outliers). Residual = a ~9 % near-field homography Z-scale on `speed_release` (needs Specto). **Entry board + angle recovered** by the same fix (serves DEC-031 Accuracy)
- [x] M1-05 Loft
- [~] M1-06 Board crossings: laydown, 7 ft dots, arrows (15 ft), 30/40/50 ft, entry. Launch angle and entry angle with confidence (was P0-07)
- [~] M1-07 Breakpoint: board + distance (geometric), with glare-robust lateral measurement
- [~] M1-08 Pin reading: before/after pin state, strike/non-strike, leave, with per-pin confidence and occlusion flags (was P0-08). Reads from video only; reports **unreadable** (never a guess) when the deck is blocked or the clip ends before the pins settle — DEC-026 (2026-10-15)
- [~] M1-09 Rev rate: surface-periodicity estimator, confidence-gated. Reports **unavailable** when the period search lands on the band rail (no clear repeat → `60 ÷ period` is the 4–10 Hz ceiling/floor, not a reading) — DEC-027, never the wall value. Reports a **capture-adaptive precision band** `rev² / (60·fps)` (~±40 rpm at 60 fps, halving at 120) rather than false precision — DEC-028; at 60 fps the whole-frame-lag quantum limits it to ~±40 (confirmed vs Ruby: distinct throws collapse to one value). Real gain needs 120 fps. **Phase refinement built (2026-10-16):** after the robust coarse autocorrelation argmax, the frequency is refined with long-baseline phase coherence over all crop pairs (narrow ±15 % window, so no harmonic jump) — the "count many rotations" principle from the community Speed & Revs calculator, higher-resolution than single-period autocorrelation. **Killed the snapping** (five live shots no longer collapse to one value): MAE 22→20 rpm, shot-to-shot corr 0.60→0.69, every clip now reads a distinct value tracking Ruby. Still open: a **high-contrast ball mark** (tape) in capture guidance for feature-angle tracking; blind-validate the sensor-equivalent factor
- [ ] M1-10 Spin axis: axis rotation + tilt from period-lag surface flow, camera rotation from VP + homography. **Needs paired Ruby axis data as ground truth** — enter tilt/rotation on validation shots now so this can be blind-validated later (see `01_PRODUCT/SENSOR_VS_VIDEO_METRICS.md` §3)
- [ ] M1-11 PAP: finger/thumb-hole tracking at 240 fps, a marker option, or entered from the profile with drift detection
- [~] M1-12 Per-metric confidence + explicit unavailable states (was P0-09)
- [ ] M1-13 Automatic delivery segmentation in long clips (several shots per video)
- [~] M1-14 Evaluation harness: labeled clip set → MAE / median / p90 / bias / failure rate per metric (was F-07). Built 2026-10-16: `examples/eval_session.py` (finish rate + per-metric values via the real `core.analyze_clip` path) + `examples/score_vs_ruby.py` (timestamp match to Ruby + variance). Reports MAE / **median / p90** / bias / within-gate per metric (2026-10-16). Baseline on the 21-clip live session: finish 57 %, speed MAE 0.83 (after far-lane recovery, DEC-036), rev MAE 20 (after phase refinement). Still to add: a locked labeled set
- [ ] M1-15 Capture Seed Dataset v1: 30–50 shots with Ruby data, a few at 240 fps (was P0-02)

**Gate:** On the locked test set, all of the following hold:
- speed ±0.5 mph
- path and entry ≤1 board median
- strike/non-strike ≥95%
- rev rate ±30 rpm where supported
- ≥90% of clips finish with no manual repair
- every failure shows as a clear failure state

## Stage 2 — Moving-camera measurement  (M–L)
*The same metrics from handheld, head-mounted and smart-glasses video (DEC-018).*
- [x] M2-01 Per-frame lane-plane registration to a reference frame (handheld shot validated: 380 px of motion)
- [ ] M2-02 Segment-wise references for large head turns; chained registration with drift correction
- [ ] M2-03 Rolling-shutter and motion-blur handling; frame quality scoring
- [ ] M2-04 First-person capture: release is visible but the bowler isn't; handle the foul line at the bottom edge and lane partly out of frame
- [ ] M2-05 Eval: the same shots filmed tripod + handheld + head-mounted, with per-metric degradation report (was P8-03/04/05)

**Robustness design for shaky / far / occluded POV (Meta glasses end goal).** The current single-reference-frame + background-median stabiliser assumes a near-fixed camera; it holds for tripod (8 px) and mild handheld (380 px) but breaks on a walking/head-turning POV, and lane detection fails when too little lane is in frame (the "1.0% wood" failures on far-back live-session clips). The ordered unlocks, hardest-impact first:
1. **IMU + chained registration (M2-02)** — register frame-to-frame with optical flow and fuse the glasses' gyro/accel so measurement coasts through motion blur and brief occlusion where pixels alone fail; re-anchor periodically to lane landmarks (foul line, arrows, gutter edges) to kill drift.
2. **Persistent lane world-model** — once the geometry is seen, hold it and track the *camera pose* against it, so "board 10 at 40 ft" stays known even when the ball is blocked or the lane is partly out of frame (ties into M2-04).
3. **Frame quality scoring (M2-03)** — score blur / exposure / lane-visibility and drop or downweight bad frames, so a shaky clip degrades to "80 good frames of 120" instead of a hard failure, and metric confidence honestly reflects the clean data behind it.
4. **Physics-constrained trajectory with explicit gap infill** — a rolling ball's path is smooth with monotonic late curvature; fit that model to the visible arcs and interpolate through occlusion gaps, but **only report an interpolated metric when the visible track brackets it** (extends the existing `far['t']` impact and masking-band pin-occlusion gates). Never fabricate across an un-bracketed gap — report unavailable, per DEC-026/027.

Through-line: robustness means degrading gracefully with calibrated confidence, never a guess. A glasses clip will legitimately yield more `unavailable` states than a tripod; that is correct behaviour and the runner UI already handles it. **Blocker:** none of this can be tuned or validated without a paired tripod + handheld + glasses capture (M2-05) — the same dependency shape as the Seed Dataset.

**Gate:** Moving-camera metrics stay within 1.5× the fixed-camera error on the eval set.

## Stage 3 — Game, scoring and stats engine  (M)
*LaneTalk-parity stats from video pin reading, manual entry or a future center feed (DEC-020).*
- [~] M3-01 Frame/game model: balls, pinfall, 10th frame, splits, fouls (manual-correction API still to do)
- [~] M3-02 Scoring: totals, frame-by-frame, marks
- [~] M3-03 Stats:
  - strike %
  - spare %
  - spare conversion % (by leave, by single-pin vs multi-pin, by pin)
  - open frames
  - first-ball average
  - splits and split conversion
  - clean games
  - doubles, turkeys, strings
- [~] M3-04 Pocket % (entry board in pocket range), strike % given a pocket hit (carry), common leaves by pocket miss
- [~] M3-05 Aggregations: shot, game, session, ball, oil pattern, lane, date range, all-time; trends and rolling averages
- [ ] M3-06 `ScoringAdapter` contract for center/scoring-system imports with provenance (DEC-009)

## Stage 4 — Insights and adjustments engine  (M)
*Read the shot and the pins, then recommend the next shot (UI Spec §8, DEC-005).*
- [~] M4-01 Shot reading: high / pocket / light / Brooklyn from entry board and angle; leave diagnosis (e.g. 10-pin leave = weak or light, 4-pin = high)
- [~] M4-02 Intent vs actual: target error at the arrows and at the breakpoint; execution classification (EXECUTED / EXECUTION_MISS / REACTION_CHANGE / MIXED / NO_INTENT / LOW_CONFIDENCE) (was P4-01)
- [~] M4-03 Strike adjustments: feet, target, parallel (2-and-1 / 3-and-2 rules), speed, launch, ball change; magnitude from board error; a strike never triggers a move; "no adjustment yet" when evidence is thin (was P4-04)
- [~] M4-04 Spare system: target line for each leave (straight cross-lane line + 3-6-9 from strike stance), adjusted for handedness
- [~] M4-05 Lane transition model per session: breakpoint and entry drift on comparable well-executed shots; observed vs inferred (was P4-03)
- [~] M4-06 Every recommendation stores reason, evidence window, confidence and version. Accept/reject feedback loop still to do (was P4-05/06)
- [~] M4-07 Oil pattern context: pattern length and volume shape the expected breakpoint ("length − 31" rule of thumb) and recommendations
- [ ] M4-08 Coaching rules review with a certified coach before beta — include ball-recommendation weights and configured-reaction (layout/surface) magnitudes (DEC-044)

## Stage 5 — Profile, arsenal, oil patterns, sensor variance (back end)  (M)
- [~] M5-01 Bowler profile: handedness, style, baseline speed/rev/axis, PAP (schema) (was P2-01)
- [~] M5-02 Arsenal: BallModel catalog → UserBall → versioned BallConfiguration (layout, pin/PSA, PAP used, weight) → surface and maintenance events (schema) (was P2-02/03/04)
  - **2026-10-21 (DEC-044):** ball catalog built — 211 current balls, 10 brands, photo link + 15 lb specs + published ratings + normalized reaction (`lanesight-core/data/ball_catalog/`, migration `002_ball_catalog.sql`, `seed_ball_catalog.sql`, `lanesight_core/arsenal/`). Configured reaction from layout + current surface (`configured.py`, migration `003_ball_configuration_surface.sql`). Provisional recommenders: `rank_for_condition`, `arsenal_gaps`. Tested; migrations verified on Postgres 16. **Applied to the LaneSight Supabase project (`europwryibstnmipbvam`) with `ball_models` seeded (211); 004/005 reconciled into the repo 2026-10-22 (see DV-01a).**
  - Still to do: arsenal UI (photo, layout entry, surface log); measured-shot calibration per configuration; oil absorption / games since resurface; periodic catalog refresh.
- [~] M5-03 Ball per shot and per session; per-ball performance and reaction shape
- [~] M5-04 Oil pattern library: name, length, volume, ratio, source, selectable at session start (schema; seed data still to do)
- [~] M5-05 `SensorAdapter` + shot matching by timestamp; per-metric LaneSight vs sensor variance per shot and summary (variance done; **timestamp matching done 2026-10-16** via QuickTime creation time + set-up delay in `examples/score_vs_ruby.py`, gaps left unmatched; in-runner `SensorAdapter` ingest still to do) (was P0-10, P2-06; DEC-021)
- [~] M5-06 Measurement provenance everywhere: source, confidence, algorithm version (was P2-07)

## Stage 6 — Virtual replay payload  (S–M)
- [~] M6-01 Shot replay contract: top-down trajectory (lane coordinates), key points (laydown, arrows, breakpoint, entry), speed along the path, pin before/after, metric cards with confidence
- [~] M6-02 Heatmaps: session dispersion at arrows/breakpoint/entry; lane usage over time; consistency ellipses (UI Spec §4.5)
- [~] M6-03 Server-side replay rendering (image done; video still to do) for sharing

## Stage 7 — UI  (L) — starts after the Stage 1–6 gates
*Native SwiftUI in Xcode, iOS-first (DEC-029). Xcode project in the repo next to `lanesight-core`. Figma Dev Mode feeds frames + tokens; colors → DEC-016 palette as SwiftUI color assets. SwiftUI models are Codable mirrors of the `ShotRecord` contract (schema v1).*
- [ ] U-01 Flows + mockups (was B-03; Figma in progress 2026-10); brand per DEC-016
- [ ] U-02 iOS app per UI Spec §3–4: Home, Session Setup, Live, Shot Details, Lane Transition, Statistics, History, Settings/Arsenal (was P1-01..P1-11)
- [ ] U-03 Audio feedback (Audio Coach) (was P3-07)
- [ ] U-04 AVFoundation capture: locked 60 fps + 240 fps slo-mo, **real per-frame timestamps** (not a nominal fps tag), in-app recording per DEC-028/029; upload client to the CV service

## Stage 8 — Cloud + instant at-lane analysis  (M–L)
- [ ] C-01 Supabase (auth, Postgres, storage); apply `models/schema.sql` (was F-04)
- [ ] C-02 FastAPI CV service + job queue; GPU when needed; API per UI Spec §13 (was F-05). Analysis entry = `core.analyze_clip` (the DB-free path the runner + eval harness share); Mac first, then cloud (DEC-029). On-device Core ML/Vision is a later latency optimization, not v1
- [ ] C-03 Latency: ≤10 s cloud and ≤5 s edge after pin impact (UI Spec §10); on-device vs cloud split decided as a DEC (was F-03). The current pipeline runs well over this and must be optimized. **Target state for public launch, not a dev/beta gate (DEC-043)**; every optimization is checked against the DEC-043 cost caps (≤$100/mo beta, ≤$5 per 1,000 analyzed shots) before adoption.
- [ ] C-02a Serial analysis per session: the next shot's analysis starts only when the current one has finished (DEC-043); no in-session concurrency in MVP
- [ ] C-04 Offline capture queue; signed uploads; privacy retention controls
- [ ] C-05 Multi-user accounts, realtime `shot.analysis.completed`

## Dev Build v0 — iPhone developer build  (L) — DEC-045…053
*The first iOS build, for Shayne's iPhone, run live against the real pipeline on his Mac over Tailscale. Purpose: exercise every core feature end to end, collect feasibility data (coverage, failure reasons, timings) and capture session feedback. Full brief and acceptance detail: `03_ENGINEERING/dev_build_v0/HANDOFF.md`. Builds on the Stage 1–8 back end; does not replace those stages. No pinfall (DEC-050); rules are owner-only (DEC-046); no mock numbers.*

- [ ] **DV-00 Record & reconcile (docs).** Add DEC-045…053 to DECISIONS.md; add this stage + `L-dev-0` to the registers; fix MVP exit (DEC-047). **Done when** docs are consistent and Shayne has reviewed the diff.
- [x] **DV-01a Reconcile (2026-10-22).** Confirmed LaneSight = Supabase `europwryibstnmipbvam` (VendHub org). The project already has `001_core_schema_v1` (= repo `schema.sql`), `002`, `003`, **`004_rls_hardening`** and **`005_ball_catalog_refresh`** applied, with `ball_models` seeded (211). Pulled 004 + 005 into `lanesight_core/models/migrations/` verbatim; `schema.sql` stays the unnumbered 001 baseline (no `001_*.sql`). **New migrations number from 006.**
- [x] **DV-01 Database — migrations 006–010 (2026-10-22).** Reconciled against the live schema (extended existing `recommendations`/`recommendation_outcomes`/`shot_intents`/`shots`/`profiles`/`sensor_devices`/`oil_patterns` rather than re-creating; handoff's `bowler_profile`→`profiles`, `user_sensor`→`sensor_devices`). `006` rules & benchmarks (owner-only RLS); `007` score/tiers/achievements + `L-dev-0` seed + params-free `achievement_definition_public` view; `008` dev-build fields (`dob`/`delivery_style`/`approach_steps`, sensor `name`/`is_default`, shot `capture_mode`/`bowler_in_view`/`source`/`sensor_used`/`sensor_id`, `session_feedback`); `009` oil-pattern fields + House shot/Unknown seeds; `010` invoker-view + column-level grant fix (clears advisor ERROR). Rule-content seeding (`lanesight-core/rules/*.yaml`) and the oil importer are deferred to DV-02 (owner-reviewed content; Power P′ ranges pending Shayne, HANDOFF §7).
  - **Branch-first wasn't possible** — Supabase branching needs the Pro plan and the org is Free. Per Shayne: validated locally first (PG16 + Supabase shim, 001–010 from scratch + idempotency + RLS tests, `lanesight_core/models/tests/run_rls_tests.sh`), took a timestamped backup (`~/LaneSightData/backups/`), then applied to the (empty) LaneSight project.
  - **Done:** migrations apply clean; advisor shows **no errors** (only the intended 8 INFO `rls_enabled_no_policy` on owner-only tables, DEC-046); RLS verified — clients can't read rules/`params` (column-level grant to `authenticated` only, no `anon`), draft/retired achievements hidden, users see only their own rows; `ball_models` checksum unchanged (211 rows, md5 `c02f62043c64cfe80d99be12e40ab2ae`).
- [~] **DV-02 Engines in `lanesight-core` (2026-10-22).** Landed as pure, DB-free packages (params in, dicts out; runner persists): `score/` — Accuracy (DEC-031), Consistency (DEC-032), Performance S′, Power P′, `L-dev-0` composite + eligibility + snapshot, and session-end tiers with 15×2 hysteresis; `benchmarks/` — personal baseline (N=10), L3→L2→L1→L0 resolution, Within/Watch/Outside, one-primary-focus prioritizer; `achievements/` — all 10 SCORE_TIERS §5 rule types + streak break/skip rule; `insights/routing.py` — target-vs-actual + execution class (no "did you hit your mark", DEC-049) and execution-miss→form-cue routing (DEC-005/006); `owner.py` — reset plan (DEC-051). Unit tests: `test_score` (17), `test_benchmarks` (8), `test_achievements` (10), `test_routing` (5), `test_form` (5); **full suite 127 passed**. DV-02 engines don't touch `cv/`, so IMG_8751–8754 reproduce unchanged.
  - **Blocked / deferred (reported to Shayne):** (1) **Form P1 metric values** need a pose-estimation backend (not in deps) + the 2026-10-17/20 training clips (not in repo) — `form/analyze_form_clip` ships the contract + a `pose_backend` hook and returns every P1 metric `unavailable` until then (no fabricated pose numbers). (2) **Rule/drill/achievement content** (`lanesight-core/rules/*.yaml`) is owner-reviewed and not yet authored; engines run on it but it's empty. (3) **Power P′ reference ranges** pending Shayne (HANDOFF §7), so the overall score stays "building". (4) Capture-view classifier + spot-check tips are implemented as pure logic; their **video feature extraction + threshold validation** need real captures. (5) bowler-in-view on shot clips needs the same person/pose detection as Form P1.
- [x] **DV-03 `lanesight_api` (Mac service) — 2026-10-22.** FastAPI with a committed OpenAPI spec at `lanesight-core/lanesight_api/openapi.json` (the iOS contract); endpoints per HANDOFF §3; serial job queue (DEC-043) with states + reasons + per-step timings (OPS-01); frame-timestamp verification against decoded video; launchd plist + `tailscale serve` notes + health check + start/stop README. **Live e2e PASSED 2026-10-22** (`examples/e2e_dev_build.py`, IMG_8807 against the real project with a temp user): real clip → serial analyze (≈24 s: probe 0.09 / window 1.21 / analyze 22.7) → shot metrics → L-dev-0 recompute (building: s_perf 40, a_acc 79; c_cons/p_power null) → session end → feedback → CSV; score_snapshots + feedback written to Supabase and cascade-deleted on cleanup. **Follow-up:** persist `shots`/`measurements` to Supabase (currently in-memory in PgStore) and implement the remaining §3 endpoints (see `/_unimplemented`). **Secrets (decided 2026-10-22):** store the LaneSight DB connection string and the Supabase **service key** in the **macOS Keychain** — never in the repo or a `.env`; the Mac service reads them from the Keychain at launch. From this point, **pre-migration backups use real `pg_dump`** (schema + data) to `~/LaneSightData/backups/<timestamp>/`, replacing the DV-01 MCP logical-export fallback. **Done when** a scripted end-to-end test (real clip → job → shot result → score/achievement → summary → feedback → CSV) passes against the real Supabase project with a test user, with timings logged.
- [ ] **DV-04 iOS app (`ios/LaneSight`).** Xcode project (bundle `com.lanesight.app`, Dev/Beta/Prod xcconfig, Swift 6 strict concurrency, `LaneSightKit` generated from the OpenAPI spec); every screen in `02_DESIGN/dev_build_v0/` (map in HANDOFF §4) to `IOS_STANDARDS.md`; AVFoundation capture (1080p120 SDR preferred, real per-frame timestamps, advisory spot check, intent entry); background upload queue; notification ordering (≤1 popup/shot, never while recording, tier > achievement); session-end feedback sheet → summary (DEC-053); Supabase auth + Keychain + 13+ DOB gate + in-app deletion; privacy (purpose strings, `PrivacyInfo.xcprivacy`, Supabase-only SDKs); dev panel. **Done when** the app installs from Xcode, every screen is reachable, a real shot shows real results/recommendation/score/achievement/sensor question, session end → feedback → summary, and nothing on screen is hardcoded sample data.
- [ ] **DV-05 First live session.** Pre-flight the Mac service over Tailscale from cellular; Shayne bowls 2–3 games (Shot, a few Form, one upload); review feedback/coverage/failure reasons/timings/recommendation 👍👎/unlocks; write a findings note in `02_RESEARCH/`; fix, rebuild, send to TestFlight internal.

## MVP exit
**MVP exit is Shayne's call (DEC-047).** He runs the MVP (and the Dev Build v0 that feeds it) indefinitely and decides when it's ready for the friends Beta. The Stage 1–8 gates and the DV acceptance criteria are **readiness evidence, not automatic exit criteria** — they inform the judgment; they don't trip it. (Supersedes the former automatic gate: "all Stage 1–8 gates pass, and a private beta of 10–25 league bowlers runs real sessions"; was P1-12.)

---

## Post-MVP
- **Session/League Mode:** continuous capture, user recognition, rolling buffer (was Phase 3). First step: Multi-Bowler Session Tracking (below)
- **Multi-Bowler Session Tracking (MVP+, DEC-060):** see the section below

## MVP+ — Multi-Bowler Session Tracking (DEC-060; planned, not started)
**What it does:** at session start the user picks who to track (themselves and, optionally, friends). The phone records the whole session from a tripod. LaneSight works out who is about to throw, analyzes only the tracked bowlers' deliveries, ignores everyone else, and after the session compares the tracked bowlers side by side.

**Flow**
1. **Session setup › Who are we tracking?** "Me" plus up to N friends. A friend is a LaneSight user who accepts an invite, or a guest profile under the user's account.
2. **Enroll each tracked bowler (~30 s each):** a front photo and a back photo, handedness, and the ball(s) they'll throw (ball color and pattern is a strong signal). Optional short walk-past clip.
3. **Record the full session** on a tripod. Rolling buffer; deliveries are segmented automatically (DEC-014).
4. **Attribute each delivery:** at approach start, match the bowler on the approach to an enrolled bowler using clothing and body appearance, handedness, ball appearance and approach position (DEC-015 multi-signal; face may support but never drives the match).
   - High confidence → analyzed for that bowler.
   - Not enrolled → discarded quickly, never stored.
   - Uncertain → held for a quick "Who threw this?" review at session end; never guessed.
5. **Session end:** per-bowler summaries plus **Compare** (bowler 1 vs bowler 2): speed, rev, accuracy, consistency, entry, form checkpoints where measured.

**Rules and privacy**
- Friends and guests must consent before being tracked. A guest's data belongs to the inviting account unless they claim it.
- Enrollment photos and appearance models are **session-scoped** and deleted after the session unless the bowler opts in to "remember me" (DEC-015).
- No permanent face ID. No tracking of minors without a guardian's consent (13+ gate, DEC-047).
- Biometric-privacy laws (e.g. Illinois BIPA) need legal review before launch.
- Non-enrolled people's footage is discarded and never analyzed.

**Tasks (draft)**
| ID | Task | Notes |
|---|---|---|
| MB-01 | Enrollment capture + appearance signature | Front/back photos, handedness, ball appearance; session-scoped storage |
| MB-02 | Continuous capture + delivery segmentation | DEC-014 rolling buffer; on-device segmentation to limit upload cost |
| MB-03 | Bowler attribution | Person detection/tracking at approach start + re-identification; confidence + "uncertain" queue |
| MB-04 | Per-bowler routing of Shot/Form analysis | Reuses the existing pipelines; one analysis at a time (DEC-043) |
| MB-05 | Session-end review + per-bowler summaries | "Who threw this?" for uncertain deliveries |
| MB-06 | Compare view (bowler 1 vs 2) | Same metric definitions; unavailable stays unavailable |
| MB-07 | Friend invites, guest profiles, consent | Data ownership; claim a guest profile later |
| MB-08 | Attribution validation | Target: ≥98% correct on accepted deliveries, 0 non-enrolled deliveries stored; measured on real multi-bowler sessions |

**Depends on:** Dev Build v0 results, moving to cloud analysis (Stage 8), and cost review (continuous video is far heavier than tap-to-record).

- **Team Lane Management** (was Phase 5)
- **League integration:** bowler registers with leagues; league stats merged into the profile with provenance (was Phase 6)
- **USBC membership connection:** one profile across practice, leagues and tournaments (was P6-04)
- **LaneSight Leagues** league management (was Phase 7)
- **Centers, coaches, tournaments, more sensor partners** (was Phase 8)

## Candidate features (suggested, not yet committed)
- Spare-shooting coach with per-leave targets and a conversion tracker per pin
- Consistency / repeatability score (prototype exists)
- Carry analysis: strikes vs pocket hits and leave patterns
- Ball-change suggestions from transition + arsenal (cover, layout, surface)
- Surface maintenance reminders (games since resurface or oil extraction)
- Warm-up scouting: other bowlers' lines as transition evidence (UI Spec §5)
- Shot compare: side-by-side replay of two shots, balls or sessions
- Goals, practice drills, personal bests and achievements
- Sharable replay cards

## Ongoing tracks
- R-01..R-04, B-01/B-02, L-01..L-03, G-01..G-03 unchanged from v1.0
- F-02 (git/monorepo) done 2026-10-14: code in `lanesight-core/`. F-06 (CI) is still needed for the Stage 1–6 back end

## Performance Lab workstream (DEC-040/041; planned, not implemented)
- [ ] PL-01 Specify Shot vs Form mode selection and independent Practice/League/Tournament activity type; preserve current Shot MVP.
- [ ] PL-02 Extend Session/VideoAsset/Measurement contracts with mode, perspective, confidence, model version, consent and retention.
- [ ] PL-03 Assemble annotated bowler-view video dataset and validate initial approach metrics by angle/fps; report unavailable honestly.
- [ ] PL-04 Design Form Analysis results, baseline/side-by-side replay, and Home Performance Lab entry in Figma.
- [ ] PL-05 Prototype coach video sharing, timestamped annotations, corrections and drill assignments with revocable permissions.
- [ ] PL-06 Evaluate Ruby/F5 sensor exports or SDK rights and optional adapter ingest; do not assume access.
- [ ] PL-07 Explore authorized Conqueror X/Brunswick scoring pilot and shot/pin event availability.
- [ ] PL-08 Implement single-score history/trend/PB only after DEC-038 P formula and recency smoothing are approved; no separate Improvement Score.


## Newly approved UX / deferred capability — 2026-10-19 (DEC-042)
- [ ] **UX-PL-01 (MVP):** Performance Lab hub presents **Start Live Session**, **Upload Video to Analyze** (MVP per DEC-043; an uploaded clip is analyzed as one shot until M1-13 exists), **Compare to a PBA Pro (Coming Soon; disabled)**. Preserve Shot/Form capture-mode choice and session activity semantics (DEC-040, DEC-035). Never route disabled tile to a nonfunctional view.
- [ ] **UX-PL-02 (MVP):** Accessibility and empty/loading/error states for hub, returning to active session, and uploaded-video ingestion; measure against proposed SLOs without presenting them as achieved SLAs.
- [ ] **PBA-01 (POST-MVP):** rights-cleared limited pro benchmark catalog and licensing provenance; no unlicensed pro video hosted or analyzed.
- [ ] **PBA-02 (POST-MVP):** synchronized user/pro clip comparison with validated approach/timing metrics; source, confidence, angle comparability and unavailability gating.
- [ ] **PBA-03 (POST-MVP):** optional verified compatible speed/rev comparison; separate pro reference from personal/coach baseline and LaneSight Score.
- [ ] **OPS-01 (MVP instrumentation):** capture-to-feedback timestamps, analysis p50/p95/p99, valid metric yield, failure reasons, job trace, upload retry and compute/storage cost per 1,000 shots. Targets in `03_ENGINEERING/PERFORMANCE_RELIABILITY_SLO_PROPOSAL.md` are **target state** (DEC-043): measured and reported in dev/beta, not enforced. Cost per 1,000 shots is reported against the DEC-043 caps. First slice: p50/p95/p99 per pipeline step from `examples/eval_session.py` over the live-session clips (no new infrastructure).
- **Design instruction:** no Figma updates until image mockup review and approval; concept images are illustrative only.

## MVP design handoff work items — 2026-10-26 (DEC-075–082)
Detail and acceptance criteria: `03_ENGINEERING/MVP_HANDOFF.md` §3. Designs: Figma "Target state – v3.7" (`02_DESIGN/target_state/README.md`).
- [ ] **MVP-01** key-position frame capture during Form analysis
- [ ] **MVP-02** pose landmarks stored per key frame; client-drawn skeleton (confident joints only)
- [ ] **MVP-03** camera-view detection (side / rear / front) and metric availability by view
- [ ] **MVP-04** one key measurement per key position
- [ ] **MVP-05** provisional MVP LaneSight Score (DEC-077) with eligibility progress
- [ ] **MVP-06** recommendation `why` + `expected` text
- [ ] **MVP-07** "vs your typical" session comparison
- [ ] **MVP-08** per-metric detail endpoint (avg, spread, range, coverage, trend, by ball, by pattern)
- [ ] **MVP-09** last-used setup prefill
- [ ] **MVP-10** upload kept on phone with automatic and manual retry
- [ ] **MVP-11** Analyzing screen: keep awake, lock clip settings, auto-open results (DEC-068/080)
- [ ] **MVP-12** Home "next focus"
- [ ] **MVP-13** first-use states and camera permission screens
