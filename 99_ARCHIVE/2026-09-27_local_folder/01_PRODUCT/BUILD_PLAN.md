# LaneSight Build Plan
Status: CANONICAL  
Version: 1.0  
Last Updated: 2026-09-27  
Owner: Shayne  
Supersedes: —

The full path from empty repo to the complete platform in PRD v3. Phases follow the PRD and DECISIONS. Each phase ends in an **exit gate**. Don't start building the next phase until its gate passes (PRD §16: build what users have shown they need, not just what's buildable).

**How to use:** Check a box when it's done and verified. Tasks keep their IDs forever, so agents and commits can reference them (e.g. `P1-04`). When a phase gate passes, update `00_CONTEXT/CURRENT_STATE.md`.

Size: S = days · M = 1–3 weeks · L = 1–2 months · XL = quarter+ (solo-dev estimates, rough)

---

## Phase F — Foundations  (S–M)
- [x] F-01 Project context system: master context, current state, decisions, domain docs
- [ ] F-02 Put the LaneSight folder + code under git (GitHub); decide monorepo layout (`ios/`, `cv/`, `api/`, `web/`, `docs/`)
- [ ] F-03 Decide open platform questions and record as DECs: native Swift vs cross-platform; on-device vs server CV for Shot Analyzer
- [ ] F-04 Create Supabase project (dev + prod), auth, storage buckets for video
- [ ] F-05 Python CV service skeleton (FastAPI) with a job queue and a reproducible CLI entry point
- [ ] F-06 CI: lint, tests, typecheck on every push
- [ ] F-07 Evaluation harness skeleton: run pipeline on a labeled clip set → MAE / median / p90 / bias / failure-rate report
- [ ] F-08 Order the first bowling sensor (see P0-08)

## Phase 0 — Technical proof & founder dataset  (L)
*Prove stable rear video can reconstruct a trajectory with trustworthy metrics.*
- [ ] P0-01 Lock the capture spec: tripod position/height, 1080p/60fps, framing checklist
- [ ] P0-02 Record Seed Dataset v1: 30–50 controlled tripod shots with intended target noted
- [ ] P0-03 Build a simple annotation tool; hand-label ball position on a subset; reserve a locked test set
- [ ] P0-04 Lane geometry model (39 boards, 60 ft, arrows at ~15 ft) + manual tap-to-calibrate homography
- [ ] P0-05 Ball detection (benchmark ≥2 detector approaches; record the winner as a DEC)
- [ ] P0-06 Frame-to-frame tracking + trajectory smoothing → `P_i = (t_i, x_i, y_i)`
- [ ] P0-07 Metric engine: launch board/angle, arrow board, speed, breakpoint, entry board/angle (regression, not two-frame)
- [ ] P0-08 Pin result: strike / non-strike minimum
- [ ] P0-09 Per-metric confidence + explicit "unavailable" states
- [ ] P0-10 Sensor: define `SensorAdapter` contract, pull data from first sensor, match sensor shot ↔ video shot by timestamp
- [ ] P0-11 First benchmark session vs a trusted reference (sensor speed now; Specto when available)

**Exit gate:** On the locked test set, speed ≈ ±0.5 mph, median path error ≤ 1 board, entry ≤ 1 board, strike/non-strike ≥ 95%, ≥ 90% of supported clips finish without manual repair, and every failure shows as a clear failure state instead of a wrong number.

## Phase 1 — Free Shot Analyzer (acquisition wedge)  (L)
*A bowler gets a useful analysis in minutes and wants to save it.*
- [ ] P1-01 iOS app shell: onboarding (handedness only), record/upload one shot
- [ ] P1-02 Upload → async analysis job → progress states → result
- [ ] P1-03 Assisted calibration UI (auto-suggest lane edges, user confirms/adjusts)
- [ ] P1-04 Result screen: annotated replay + top-down path + metric cards with confidence
- [ ] P1-05 Intended target input + target error
- [ ] P1-06 Current Ball picker (simple list for now)
- [ ] P1-07 Account creation via "Save to profile"; shot history list
- [ ] P1-08 Shareable replay / result card (link + image export)
- [ ] P1-09 Privacy: delete source video, keep derived data; privacy policy + terms
- [ ] P1-10 Analytics events: analysis started/completed, save, share, return visit
- [ ] P1-11 Apply brand: LS monogram app icon, palette, dark-first UI
- [ ] P1-12 TestFlight private beta with 10–25 serious league bowlers

**Exit gate:** Beta users complete analyses without help, a meaningful share of them save and share results, and some come back for a second session unprompted.

## Phase 2 — Bowler Profile + Arsenal + Sensor Fusion  (L)
*LaneSight becomes a personal bowling record.*
- [ ] P2-01 BowlerProfile with baselines and trends (speed, accuracy, entry)
- [ ] P2-02 Arsenal data model: BallModel → UserBall → BallConfiguration (versioned) → SurfaceEvent → MaintenanceEvent
- [ ] P2-03 Ball catalog seed (factory specs) + search/add flow
- [ ] P2-04 Edit actual weight, PAP, layout, surface; never overwrite history
- [ ] P2-05 Per-ball performance based on configuration
- [ ] P2-06 Sensor fusion in product: pair a device, auto-match shots, show source for each metric
- [ ] P2-07 Measurement provenance everywhere (source, confidence, algorithm version)
- [ ] P2-08 Second sensor adapter (proves vendor-neutral design)

**Exit gate:** Users set up an arsenal, profiles fill in through normal use, and a real share of active users connect a sensor or maintain ball data.

## Phase 3 — Session Mode + League Mode + Audio Coach  (XL)
*LaneSight becomes part of league night.*
- [ ] P3-01 Long tripod recording with automatic delivery segmentation
- [ ] P3-02 Rolling buffer; discard non-user footage quickly (DEC-014)
- [ ] P3-03 "This is me" session enrollment + multi-signal re-identification (DEC-015)
- [ ] P3-04 Hold-for-review queue for uncertain matches
- [ ] P3-05 Left/right lane tracking, game/frame sequence
- [ ] P3-06 Always-visible Current Ball control + ball-switch detection with confirmation
- [ ] P3-07 Audio Coach: TTS through earbuds, modes (Off / Metrics / Coach)
- [ ] P3-08 After non-strikes, ask "Did you hit your intended line?" Yes / No / Not sure
- [ ] P3-09 Battery, heat, and storage handling for a 3-game session
- [ ] P3-10 Research competition rules for live audio in sanctioned leagues; add rules-aware mode toggles
- [ ] P3-11 Field test across multiple centers and lighting conditions

**Exit gate:** Beta users run League Mode week after week, recognition errors are rare, and a full session works on one phone charge.

## Phase 4 — Coaching intelligence  (L)
*Move from measuring shots to decisions bowlers trust.*
- [ ] P4-01 Shot classification: EXECUTED / EXECUTION_MISS / REACTION_CHANGE / MIXED / LOW_CONFIDENCE
- [ ] P4-02 Execution Coach: directional bias vs variance, speed/tempo/release drift
- [ ] P4-03 Lane Coach: transition inferred from comparable well-executed shots (never presented as measured oil)
- [ ] P4-04 Recommendations: feet, target, parallel move, speed, ball change, and "No adjustment recommended yet"
- [ ] P4-05 Evidence + reasoning shown in plain language
- [ ] P4-06 Outcome loop: Observation → Recommendation → Adjustment → Outcome
- [ ] P4-07 Pro-tier paywall + willingness-to-pay test (PRICING.md hypotheses)

**Exit gate:** Bowlers follow recommendations often and outcomes improve measurably when they do. Some users pay.

## Phase 5 — Team Mode + Team Lane Management  (XL)
*Individual users turn into team network effects.*
- [ ] P5-01 Team entity, invites, explicit per-teammate consent
- [ ] P5-02 Multi-bowler enrollment on one camera; separate profiles and histories
- [ ] P5-03 Shared TeamLaneState + Team Lane Map (traffic zones, recent paths)
- [ ] P5-04 Traffic/overlap analysis and team strategy recommendations
- [ ] P5-05 Warm-up team brief
- [ ] P5-06 Invite tracking as the main growth loop

**Exit gate:** Teams with 3+ active users exist and keep growing, and invites are accepted at a healthy rate.

## Phase 6 — Connected Bowling Profile  (L, gated on partners)
*LaneSight becomes the bowler's home for their whole bowling life.*
- [ ] P6-01 Adapter framework: ExternalBowlingDataAdapter, ScoringAdapter, Membership adapter
- [ ] P6-02 First official integration (whichever partner grants access first: LaneTalk, LeaguePals, or a scoring system)
- [ ] P6-03 Import scores, averages, schedules, standings with full provenance
- [ ] P6-04 USBC membership/sanctioned records if officially supported
- [ ] P6-05 Home screen becomes the weekly bowling dashboard (tonight's league, recent form, insights)

**Exit gate:** A meaningful share of users connect at least one external source and imported games arrive without manual entry.

## Phase 7 — LaneSight Leagues (league management)  (XL)
*Start only once enough bowlers in a league already use LaneSight.*
- [ ] P7-01 Web admin app for secretaries (Vercel)
- [ ] P7-02 Leagues, seasons, teams, rosters, schedules, lane assignments
- [ ] P7-03 Rules engine: handicap/scratch, subs, absences, pre/post-bowls, position rounds
- [ ] P7-04 Standings + league communications/notifications
- [ ] P7-05 Score ingestion from connected center systems
- [ ] P7-06 Dues, payments, prize funds (last, once core ops are proven)
- [ ] P7-07 Pilot with 1–3 friendly league secretaries

**Exit gate:** Secretaries adopt it voluntarily and say it saves them admin time.

## Phase 8 — Centers, ecosystem, advanced capture  (XL, ongoing)
- [ ] P8-01 Center dashboards + scoring-system integrations
- [ ] P8-02 Coach / pro-shop dashboards with permissioned athlete sharing (Coach tier)
- [ ] P8-03 Handheld / moving-camera stabilization
- [ ] P8-04 POV / head-mounted capture adapter
- [ ] P8-05 Smart-glasses capture adapter (DEC-012: an input adapter, never the product)
- [ ] P8-06 Tournament systems, manufacturer and additional sensor partnerships
- [ ] P8-07 Competition-safe modes and configurable rules profiles

---

## Ongoing tracks (run alongside the phases)
**Research & partnerships**
- [ ] R-01 Map official API/partner paths: USBC, LeaguePals, LaneTalk, BLS, scoring vendors
- [ ] R-02 Sensor landscape: data access terms for F5, Witsee, others
- [ ] R-03 Patent / prior-art scan for bowling CV and sensor fusion
- [ ] R-04 Competitive teardown (verify current features and pricing on the web)

**Brand & design**
- [ ] B-01 Vector LS monogram master + all lockups (horizontal, stacked, mark-only, one-color)
- [ ] B-02 Finalize accessible screen colors + print values
- [ ] B-03 Core user flows + mockups for each phase before building it

**Business & legal**
- [ ] L-01 Form an entity; trademark search/filing for "LaneSight"
- [ ] L-02 Privacy policy, terms, data-retention policy (video, biometrics-adjacent signals)
- [ ] L-03 App Store listing + marketing site

**Go-to-market**
- [ ] G-01 Recruit beta bowlers from your own leagues/center
- [ ] G-02 Seed shareable replays to bowling communities and coaches
- [ ] G-03 Metrics dashboard per stage (activation, habit, trust, network, aggregation)
