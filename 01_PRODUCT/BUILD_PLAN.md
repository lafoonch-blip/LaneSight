# LaneSight Build Plan
Status: CANONICAL  
Version: 3.0  
Last Updated: 2026-10-16  
Owner: Shayne  
Supersedes: v2.5 (Stage 7 native SwiftUI + AVFoundation capture, Stage 8 analyze_clip entry — DEC-029); v2.4; v2.3; v2.2; v1.0 (phase ordering). Task IDs from v1.0 keep their meaning. Where a v1.0 task moved, the new task notes it with "(was X)".

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
- [ ] M4-08 Coaching rules review with a certified coach before beta

## Stage 5 — Profile, arsenal, oil patterns, sensor variance (back end)  (M)
- [~] M5-01 Bowler profile: handedness, style, baseline speed/rev/axis, PAP (schema) (was P2-01)
- [~] M5-02 Arsenal: BallModel catalog → UserBall → versioned BallConfiguration (layout, pin/PSA, PAP used, weight) → surface and maintenance events (schema) (was P2-02/03/04)
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
- [ ] C-03 Latency: ≤10 s cloud and ≤5 s edge after pin impact (UI Spec §10); on-device vs cloud split decided as a DEC (was F-03). The current pipeline runs well over this and must be optimized.
- [ ] C-04 Offline capture queue; signed uploads; privacy retention controls
- [ ] C-05 Multi-user accounts, realtime `shot.analysis.completed`

## MVP exit
All Stage 1–8 gates pass, and a private beta of 10–25 league bowlers runs real sessions (was P1-12).

---

## Post-MVP
- **Session/League Mode:** continuous capture, user recognition, rolling buffer (was Phase 3)
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
