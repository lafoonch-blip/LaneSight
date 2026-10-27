# LaneSight Master Context
Status: CANONICAL  
Version: 1.5  
Last Updated: 2026-10-25  
Owner: Shayne  
Supersedes: v1.4; v1.2; v1.1; archived `LaneSight_Master_Product_Build_Context_v2.docx`

## 1. What LaneSight is
LaneSight is the digital platform for bowlers: a hardware-agnostic bowling intelligence system that combines video, optional sensor telemetry, scoring/league records, equipment history and coaching into one persistent Bowler Profile.

**North star:** become the place where a bowler plays, improves, manages equipment, understands performance, connects with teammates, and eventually manages league participation.

**Tagline:** See More. Bowl Smarter.

## 2. Commercial strategy
Do not launch as an all-in-one league platform. Progressively earn the right to expand:

**Measure → Profile → Coach → Team → Connect → Manage → Platform**

1. Free/low-friction Shot Analyzer creates the first wow moment.
2. Saving results creates a Bowler Profile.
3. Arsenal and sensor fusion deepen personalization.
4. Session/League Mode + Audio Coach create weekly habit.
5. Team Lane Management creates invitations/network effects.
6. Authorized scoring, league and sanctioned data make LaneSight the bowler’s home.
7. Once bowler penetration creates pull, expand into league management and center software.

## 3. Product pillars
- **Profile:** persistent bowling identity, history, records and achievements.
- **Play:** leagues, schedules, scores, tournaments and standings.
- **Perform:** video/sensor shot telemetry and trends.
- **Coach:** execution analysis, lane intelligence, recommendations and Audio Coach.
- **Equipment:** arsenal, drilling/layout, PAP, surface, maintenance and observed performance.
- **Team:** teammates, shared lane map and team lane strategy.

Future branded areas: LaneSight Profile, Live, Coach, Arsenal, Team, Leagues and Centers.

## 4. Foundational technical sequence
1. Stable tripod video + manual calibration.
2. Automatic ball detection/tracking.
3. Sensor integration + shot synchronization.
4. Fixed-camera Session Mode.
5. League Mode with session-scoped user recognition.
6. Multi-shot intelligence.
7. Coaching/recommendation feedback loops.
8. Handheld/shaky video.
9. POV/head-mounted video.
10. Smart-glasses integrations.

## 5. Fixed-camera measurement model
Pipeline: `video → lane geometry → ball detection → tracking → pixel-to-lane mapping → trajectory → metrics`.

Trajectory point: `P_i = (t_i, x_i, y_i)` where x is lateral board and y is feet downlane.

Core outputs when confidence supports them:
- launch board and angle
- arrow board
- speed
- breakpoint board and distance
- entry board and angle
- pin result
- confidence/source

Board convention: Board 1 is right gutter and Board 39 is left gutter looking from foul line toward pins. Handedness is separate.

## 6. Sensor fusion
Sensor support happens early but remains optional. Use a `SensorAdapter` abstraction so no single device becomes a dependency. Normalize speed, RPM, axis rotation, axis tilt, loft, timestamp and confidence when available.

Every measurement retains source and confidence. Overlap such as speed is valuable for validation. The key engineering problem is matching `Sensor Shot N` to `Video Shot N`, initially using event/release timestamps with tolerance.

## 7. Bowler Profile
The profile should increasingly build itself through normal bowling rather than long forms. It can eventually aggregate:
- sanctioned/member records where officially supported
- league/team/schedule/standings data
- scoring-center/session results
- LaneSight shot telemetry
- sensor release telemetry
- arsenal/configuration history
- coaching observations/recommendations/outcomes
- team data with explicit permission

External data always retains provenance, season/context and authority level.

## 8. Arsenal
Distinguish `BallModel` from the user’s physical `UserBall`.

Canonical hierarchy: `Ball Model → User Ball → Configuration History → Surface History → Shot History → Observed Performance`.

Track factory specs plus actual weight, PAP, drilling/layout, pin/PSA/VAL information, finger/thumb setup, current surface, surface products, resurfacing and maintenance. Never overwrite historical configuration.

League/Live UI always has a clear **Current Ball** control. Auto-detection should suggest/confirm switches rather than silently changing unless confidence is exceptionally high.

## 9. League Mode
Phone remains on a tripod while LaneSight watches the pair. Enroll the user for the session (“This is me”) using multi-signal person re-identification: appearance, silhouette, pose/motion, approach path, handedness, ball appearance and optional supporting face signal. Do not depend on permanent facial recognition.

High-confidence user deliveries are analyzed/saved. Low-confidence non-user deliveries are ignored. Uncertain candidates can be held for review. Non-user footage should be discarded quickly and no named profiles/stats should be created for non-enrolled bowlers.

## 10. Audio Coach
Canonical experience: `phone on tripod → League Mode → earbud → bowl → recognize shot → analyze vision + sensor → speak concise feedback before next shot`.

Modes can include Off, Metrics, Coach and Coach + Recommendations. Audio should prioritize actionable feedback rather than reading every metric.

## 11. Execution vs lane reaction
Every shot begins from intent: `Feet → Launch → Arrows → Breakpoint → Entry`.

LaneSight must distinguish whether the bowler missed the intended shot or executed it but experienced changed reaction.

Internal classes can include: EXECUTED, EXECUTION_MISS, REACTION_CHANGE, MIXED, LOW_CONFIDENCE.

After a non-strike ask: **Did you hit your intended line?** Yes / No / Not sure.
- Yes: can contribute to lane evidence if release is comparable.
- No: exclude from lane-transition evidence; retain for execution coaching.
- Not sure: retain with reduced weighting.

Execution Coach tracks directional bias and variance. Systematic misses can justify execution adjustments; random scatter should favor consistency coaching rather than moving the target.

Lane Coach uses comparable well-executed shots to infer transition. It must be willing to say **No adjustment recommended yet**.

## 12. Recommendation learning
Track: `Observation → Recommendation → Bowler adjustment → Next shot(s) → Outcome → Recommendation success`.

This creates both a bowler feedback loop and a LaneSight learning loop.

## 13. Team Lane Management
With explicit teammate enrollment, LaneSight can understand how a team is collectively playing the pair.

Build a shared Team Lane Map using bowler, ball/configuration, intended line, actual trajectory, execution classification, timestamp and result. Estimate traffic zones and observed reaction changes. Team strategy should seek playable, repeatable alternatives and favorable lane development—not blindly minimize “degradation.”

Warmup can produce a team brief and individualized starting recommendations. Team invitations are a major organic growth loop.

## 14. External ecosystem
Strategic targets include USBC, LeaguePals, LaneTalk, center scoring systems and bowling sensors. Do not assume APIs or permissions. Use adapter interfaces and verify official access before promising integrations.

LaneSight should initially be the consumer intelligence layer over authoritative sources, not immediately replace them.

## 15. League management expansion
League Mode and League Management are separate.

After bowler/team traction, LaneSight Leagues can progressively add teams, rosters, schedules, lane assignments, handicaps/scratch formats, substitutes, absences, pre/post-bowls, position rounds, standings, communications, score ingestion and later dues/payments/prize-fund workflows.

Market-entry principle: do not lead with “replace your league software.” Create enough bowler pull that secretaries and centers have a reason to adopt LaneSight.

## 16. GTM
Initial target users: serious league bowlers, tournament bowlers and coaches.

Growth loop: `Free Shot Analyzer → Profile → Arsenal/Sensor → League Mode → Shareable Replay → Team Invite → Connected Records → Secretary/Center Pull`.

Do not lead with proprietary hardware, smart glasses, complicated onboarding or unverified partner promises.

## 17. Brand
Master brand: **LaneSight**. Official logo: the Figma brand-standards logo (lane-and-arc mark + "LaneSight" wordmark, tagline "See More. Bowl Smarter."), see DEC-054. Use it on dark backgrounds; don't stretch, recolor or redraw it. App/web icons use the arc mark (`02_DESIGN/brand/`).

Current color direction:
- Midnight Navy #0B1320
- Lane Blue #007BFF
- Electric Blue #00D2FF
- Cool Gray #A7B0BE
- Ice White #F7F9FC

These are current concept colors; production accessibility and print values still need finalization.

## 18. Current stack direction
- native SwiftUI iOS app (DEC-029); CV analysis server-side for MVP (DEC-033)
- web/debug and later admin tooling
- Python FastAPI / CV services
- OpenCV + PyTorch
- detector/tracker benchmark rather than premature lock-in
- Postgres/Supabase
- object storage
- async jobs
- Supabase Auth
- structured logging/model provenance
- native/service TTS
- adapter layers for sensors and external bowling/scoring systems

## 19. Data model anchors
User, BowlerProfile, BallModel, UserBall, BallConfiguration, SurfaceEvent, BallMaintenanceEvent, OilPattern, Session, SessionLane, LeagueSession, Shot, ShotIntent, UserShotFeedback, ShotClassification, VideoAsset, Calibration, TrajectoryPoint, Measurement, MeasurementSource, PinState, SensorDevice, SensorShot, Observation, Recommendation, RecommendationOutcome, TransitionState, SessionIdentity, UserMatchDecision, TeamLaneState, ExternalIdentity, ExternalDataConnection, League, LeagueSeason, Team, TeamMembership, ScoreRecord, MembershipRecord and ExternalMetric.

## 20. Validation
Use personal bowling video as Seed Dataset v1. Collect controlled fixed-camera shots and manually annotate a subset. Split data by session/center/bowler where possible and reserve a locked test set. Specto is a periodic high-quality benchmark, not a dependency.

## 20a. Terminology
| Term | Meaning | Not to be confused with |
|---|---|---|
| **BallModel** | Commercial ball product (manufacturer, name, factory core/cover specs). Shared reference data. | UserBall |
| **UserBall** | One physical ball a bowler owns. Has its own configuration and surface history. | BallModel |
| **BallConfiguration** | Versioned drilling/layout/PAP/weight/grip state of a UserBall. Never overwritten. | Surface state |
| **Current Ball** | The UserBall the bowler is throwing right now in Live/League Mode. | Default ball |
| **Shot / DeliveryEvent** | One delivery. DeliveryEvent is the raw detection in a session; Shot is the analyzed, user-owned record. | Frame, clip |
| **ShotIntent** | What the bowler meant to do (feet, target, breakpoint). Basis for execution vs reaction. | Measured trajectory |
| **Measurement** | One value + unit + source + confidence + algorithm version + timestamp. | A bare number |
| **Execution Coach** | Coaching about the bowler's repeatability: bias, variance, speed/release drift. | Lane Coach |
| **Lane Coach** | Coaching about lane reaction/transition, using only comparable well-executed shots. | Execution Coach |
| **LaneState / TransitionState** | LaneSight's *inferred* reaction model for a lane over time. Never presented as measured oil. | Oil pattern |
| **TeamLaneState** | Shared, permissioned LaneState built from enrolled teammates' shots on a pair. | Individual LaneState |
| **Session Mode** | Long tripod recording segmented into deliveries (practice). | League Mode |
| **League Mode** | Session Mode + "This is me" enrollment + Current Ball + Audio Coach on league night. Consumer feature. | League management |
| **League management / LaneSight Leagues** | Secretary/admin software: rosters, schedules, standings, dues. Later-stage B2B. | League Mode |
| **SessionIdentity** | Session-scoped enrollment used to recognize the user; expires unless user opts in. | Permanent face ID |
| **SensorAdapter** | Vendor-neutral interface for release-telemetry devices. | A specific sensor |
| **Seed Dataset v1** | Founder's own controlled tripod shots used for initial development/annotation. | Training set for production |
| **Board** | Lateral lane position, 1 = right gutter, 39 = left, viewed foul line → pins. Handedness is separate. | Handedness-relative boards |

## 20b. Open questions
- **First sensor:** which device (F5, Witsee, other) and whether its data is accessible via SDK/API/export.
- **Calibration:** manual tap-to-calibrate vs assisted auto-detect for MVP; acceptance thresholds.
- **Accuracy reference:** what serves as ground truth before Specto sessions (sensor speed? manual annotation?).
- **Integrations:** whether USBC, LeaguePals, LaneTalk or scoring systems offer any official partner/API path.
- **Competition rules:** what live Audio Coach use is permitted in sanctioned league play.
- **Privacy:** retention window for raw video; how non-user footage is purged in League Mode.
- **Pricing:** free-tier analysis limits; when to test willingness to pay.
- **Resolved:** client platform (native SwiftUI, DEC-029); where CV runs (server-side for MVP, DEC-033); Accuracy and Consistency definitions (DEC-031/032); capture default (DEC-028); metric launch bar (DEC-034); MVP screen scope (DEC-035).

## 21. Explicitly superseded framing
- LaneSight is **not** primarily a Meta smart-glasses app.
- POV is **not** the first measurement environment.
- Sensor fusion is **not** a late partnership-only feature.
- Full league management is **not** the MVP.
- A missed-execution shot is **not** discarded from all coaching.
- Capture is **not** limited to single intentional clips; League Mode records continuously on a tripod with a rolling buffer and fast discard of non-user footage (see DEC-014).
- "No facial recognition" is replaced by session-scoped multi-signal re-identification; face may be one optional supporting signal, never permanent ID by default (see DEC-015).
- UI Spec v1 color tokens (#168CFF, #45C9FF, #07111B…) are **not** the brand palette; use section 17 (see DEC-016).
- Everything in `99_ARCHIVE/` is historical. Do not use it as a requirement source.

## 22. Canonical documents
Source of truth: GitHub `lafoonch-blip/LaneSight` (`main`); Google Drive and the claude.ai Project are read-only mirrors (DEC-025). Start with `AGENTS.md`.

- Product strategy PRD: `01_PRODUCT/LaneSight_PRD_Product_Strategy_v3.docx`
- Current build state: `00_CONTEXT/CURRENT_STATE.md`
- Decisions: `00_CONTEXT/DECISIONS.md`
- Detailed implementation docs: `03_ENGINEERING/`

## 23. 2026-10-18 product direction (DEC-040/041)
**Positioning:** LaneSight is the comprehensive metrics/stats and improvement platform for serious bowlers. Performance Lab offers user-selected **Shot Analysis** (ball/lane/pins) OR **Form Analysis** (bowler approach/mechanics); never require two cameras. Existing Practice/League/Tournament activity types are independent of mode. Form capture supports recording/upload, baseline comparison, and eventual coach sharing, timestamped annotation, corrections and drill feedback. Prioritize trustworthy measurement, vendor-neutral optional sensors (Ruby feasibility first), scoring integration exploration, and a unified source/confidence-tagged shot record. Form and coaching are new roadmap tracks, not already-shipped capabilities.

**Scoring:** One 0–1000 LaneSight Score only, with the DEC-038 four pillars and tiers; show gradual historical score improvement, no separate Improvement Score. Form measurements are diagnostic, not a fifth score pillar. Achievement unlocks do not alter score (DEC-039). Missing sensor data does not reduce ability; composite remains unavailable until DEC-038's missing Power & Carry normalization is solved. See DEC-041 and the metric register.
