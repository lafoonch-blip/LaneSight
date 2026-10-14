# LaneSight Build Plan
Status: CANONICAL  
Version: 2.2  
Last Updated: 2026-10-14  
Owner: Shayne  
Supersedes: v2.0 (status update only); v1.0 (phase ordering). Task IDs from v1.0 keep their meaning. Where a v1.0 task moved, the new task notes it with "(was X)".

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
`lanesight-core` v0.5.0 is a Python package with 17 passing tests:
- **Stage 1:** automatic video pipeline for tripod and handheld video, including pin reading (4 of 4 correct) and rev rate.
- **Stage 3:** scoring and LaneTalk-parity stats.
- **Stage 4:** insights, adjustments, spare targeting and transition.
- **Stage 5:** Postgres schema with row-level security, plus sensor variance.
- **Stage 6:** `ShotRecord` contract, session analytics, heatmap and replay render.

Validation vs Ruby: `02_RESEARCH/VIDEO_VS_RUBY_VALIDATION.md`.

**Next blocker:** Seed Dataset v1 (M1-15), so prototypes can be eval-verified.

---

## Stage 1 — Back-end metrics engine (fixed camera)  (L)
*Every shot metric as close to ground truth as video allows, with confidence and "unavailable" states.*
- [x] M1-01 Auto lane geometry: edges, foul line, vanishing point, pin deck (was P0-04, now automatic)
- [x] M1-02 Ball detection + tracking robust to glare, occlusion and loft (was P0-05/06)
- [x] M1-03 Release, touchdown and impact event detection
- [x] M1-04 Speed (Ruby-comparable definition) + speed profile
- [x] M1-05 Loft
- [~] M1-06 Board crossings: laydown, 7 ft dots, arrows (15 ft), 30/40/50 ft, entry. Launch angle and entry angle with confidence (was P0-07)
- [~] M1-07 Breakpoint: board + distance (geometric), with glare-robust lateral measurement
- [~] M1-08 Pin reading: before/after pin state, strike/non-strike, leave, with per-pin confidence and occlusion flags (was P0-08)
- [~] M1-09 Rev rate: surface-periodicity estimator, confidence-gated. Blind-validate the sensor-equivalent factor
- [ ] M1-10 Spin axis: axis rotation + tilt from period-lag surface flow, camera rotation from VP + homography
- [ ] M1-11 PAP: finger/thumb-hole tracking at 240 fps, a marker option, or entered from the profile with drift detection
- [~] M1-12 Per-metric confidence + explicit unavailable states (was P0-09)
- [ ] M1-13 Automatic delivery segmentation in long clips (several shots per video)
- [ ] M1-14 Evaluation harness: labeled clip set → MAE / median / p90 / bias / failure rate per metric (was F-07)
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
- [~] M5-05 `SensorAdapter` + shot matching by timestamp; per-metric LaneSight vs sensor variance per shot and summary (variance done; adapter + matching still to do) (was P0-10, P2-06; DEC-021)
- [~] M5-06 Measurement provenance everywhere: source, confidence, algorithm version (was P2-07)

## Stage 6 — Virtual replay payload  (S–M)
- [~] M6-01 Shot replay contract: top-down trajectory (lane coordinates), key points (laydown, arrows, breakpoint, entry), speed along the path, pin before/after, metric cards with confidence
- [~] M6-02 Heatmaps: session dispersion at arrows/breakpoint/entry; lane usage over time; consistency ellipses (UI Spec §4.5)
- [~] M6-03 Server-side replay rendering (image done; video still to do) for sharing

## Stage 7 — UI  (L) — starts after the Stage 1–6 gates
- [ ] U-01 Flows + mockups (was B-03); brand per DEC-016
- [ ] U-02 iOS app per UI Spec §3–4: Home, Session Setup, Live, Shot Details, Lane Transition, Statistics, History, Settings/Arsenal (was P1-01..P1-11)
- [ ] U-03 Audio feedback (Audio Coach) (was P3-07)

## Stage 8 — Cloud + instant at-lane analysis  (M–L)
- [ ] C-01 Supabase (auth, Postgres, storage); apply `models/schema.sql` (was F-04)
- [ ] C-02 FastAPI CV service + job queue; GPU when needed; API per UI Spec §13 (was F-05)
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
