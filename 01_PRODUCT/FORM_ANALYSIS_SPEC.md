# Form Analysis — Swing & Approach Capture and Metrics Spec
Status: DRAFT (for Shayne's review)
Version: 0.1
Last Updated: 2026-10-19
Owner: Shayne
Governing: DEC-040 (Performance Lab, Form Analysis mode), DEC-041 (form is diagnostic, not a score pillar), DEC-042 (per-metric status, no estimated values), DEC-028 (high-frame-rate capture)
Proposed home: `01_PRODUCT/FORM_ANALYSIS_SPEC.md` (draft, not yet in the GitHub source of truth)

> Note for Dev Build v0 (2026-10-22): capture is never blocked by framing (DEC-045); §5 camera rules are now advisory tips from the spot check. P1 metrics are in scope (DEC-047). When the bowler is in view in a Shot clip, the P1 metrics that angle supports are shown too (DEC-049).

## 1. Purpose and scope
This spec defines how Form Analysis captures a bowler's **approach and armswing** and which measurements it produces. It is built from three things:
- what certified coaches evaluate and how they film for lessons (§2, §5);
- what published biomechanics actually measures (§4);
- our own pilot on clips IMG_8823, 8824 and 8826 (§9).

**In scope:** footwork, timing, armswing, posture/balance at the line, and the coach-review experience.

**Out of scope:** ball-in-lane metrics, which stay in Shot Analysis. Release-physics metrics (axis tilt/rotation, PAP, rev rate) also stay in Shot Analysis or sensor, because a bowler-facing camera does not see the ball after release well enough.

**Rules carried over from DECs:**
- One camera view per recording; no dual-camera requirement.
- Every metric gets Measured, Unavailable-with-reason, or Manual status.
- No fabricated pose metrics.
- Form metrics are baseline-relative diagnostics and never feed the LaneSight Score.

## 2. What coaches evaluate
The checkpoints below are what USBC-certified coaches and coaching sources consistently name. They become the event model in §3.

| Checkpoint | What coaches look for | Source quality |
|---|---|---|
| Stance / setup | Ball under the chin, just above waist height; body alignment to target; start board | NBA (coaching) |
| Ball start (pushaway) | Timing relative to the steps, plus direction. Too far toward the bowling side wraps behind the back; too far inside goes outside the head at the top | NBA, BTM (USBC Silver) |
| Ball passing the hip | Should happen as the non-bowling-side foot steps | BTM (Maja) |
| Top of backswing | Peaks during compression of the pivot step (the step before the slide). Height is a style trait, not a single ideal | NBA, BTM panel |
| Slide / key step | Slide-foot plant is the timing reference point. Slide length and stability matter | BTM, NBA |
| Release / leverage | Head behind, then over, the slide foot; knee ahead of hips; thumb exits ~3–4 in behind the toe (opinion) | NBA, BTM (Jowdy) |
| Laydown | Ball distance from the slide ankle at release; consistency matters | USBC |
| Drift | Start board vs. finish board (slide foot). Within 1–2 boards, repeatable, is fine; >2 boards is a problem | USBC (bowl.com) |
| Finish / post the shot | Hold balanced at the line until the ball reaches the pins | USBC |

**Timing vocabulary for the UI:**
- **Early timing:** the ball is ahead of the feet. The swing reaches the line before the slide finishes; the shoulder opens early; leverage is lost.
- **Late timing:** the feet are ahead of the ball. The bowler reaches the line before the ball and pulls; the shoulder over-rotates.
- **Ball start step:**
  - 5-step approach: step 2 traditionally. "Modern" timing is somewhat later; step 3 is too late (Mautner).
  - 4-step approach: step 1.

> Honesty note: no openly published source defines "on-time" as a specific ball angle at slide-foot plant. LaneSight must report the measured relationship (where the ball is at each step) and let coaches interpret it. It must not grade the bowler against an invented ideal.

## 3. Delivery event model
Every metric is derived from these timestamped landmarks. Frame timestamps come from the capture, not from nominal fps.

| ID | Event | Definition | Detectable from |
|---|---|---|---|
| E0 | Setup still | Last frame of stillness before the approach | all views |
| E1 | Approach start | First sustained forward movement of the body (center of mass / hips) | all views |
| S1…Sn | Foot contacts | Each step's heel/foot strike; last = slide-foot plant | side ★, rear (feet must be unoccluded) |
| E2 | Ball start | First sustained ball movement out of the setup hold | all views |
| E3 | Ball at hip | Ball center crosses the hip line going down | side ★, front, rear |
| E4 | Top of backswing | Ball's highest point behind the body | side ★ (true apex), front/rear (apex of image height) |
| E5 | Slide start | Slide foot plants and begins to slide | side ★, rear |
| E6 | Bottom of arc | Ball's lowest point before release | side ★, front |
| E7 | Release | Ball leaves the hand (separation) | side ★, front; needs ≥120 fps for ±1 frame |
| E8 | Slide stop | Slide foot stops moving | side ★, rear |
| E9 | Finish hold end | Bowler leaves the posted position | all views |

**Phase splits (same boundaries as Ruby so values are comparable):**
- pushaway = E2→E3
- backswing = E3→E4
- downswing = E4→E6
- release = E6→E7
- approach = E1→E7

## 4. Metric catalog and rollout phases
Rollout follows the Performance Lab instruction to validate the easy, robust metrics first.

- **P1:** first prototype; validate before showing users.
- **P2:** after P1 passes.
- **P3:** research; needs high fps or better models.

### 4.1 Footwork and approach
| Metric | Definition | Best view | Min fps | Phase | Reference / norm |
|---|---|---|---|---|---|
| Step count | Number of foot contacts S1…Sn | Side | 60 | P1 | 4- and 5-step are standard; also capture the user's stated count |
| Total approach time | E1→E7 (s) | Any | 60 | P1 | No published norm; personal baseline |
| Cadence and step rhythm | Duration of each step; ratio of the last 3 to the first 2 | Side | 60 | P1 | Coaching: early steps slower, last three quicker (BTM) |
| Slide time | E5→E8 | Side | 120 | P2 | Front-foot slide time correlated with average (Razman 2011); elite slide→release 640 ± 95 ms (Seiferheld 2023) |
| Finish stability | Post hold duration (E8→E9) and body sway during the hold | Any | 60 | P1 | USBC "post the shot" |
| Drift | Finish board − start board (slide foot) | Rear (needs board calibration) | 30 | P2 | USBC: ≤1–2 boards, consistent direction |
| Slide length | Slide-foot travel E5→E8 (in) | Side (needs scale) | 60 | P2 | Personal baseline |
| Foul-line distance | Slide toe to foul line at release | Side or rear | 60 | P2 | Elites: men 0.35 m, women 0.16 m (Chu 2002) |
| Approach speed | Hip travel speed over the last 2 steps | Side (needs scale) | 60 | P3 | Elite center-of-mass speed 2.63 ± 0.35 m/s (Seiferheld 2023) |

### 4.2 Timing (ball ↔ feet relationship)
| Metric | Definition | Best view | Min fps | Phase | Reference |
|---|---|---|---|---|---|
| Phase splits | pushaway, backswing, downswing, release (§3) | Side; front/rear workable | 60 (120 for release) | P1 | Ruby-comparable; pilot values in §9 |
| Swing time | E2→E7 | Any | 60 | P1 | Personal baseline |
| Ball-start step | Which step S_k contains E2 | Side | 60 | P1 | 5-step: step 2; 4-step: step 1 |
| Backswing peak vs. pivot step | E4 − (pivot-step contact), in ms | Side | 120 | P2 | Coaching target: peak during pivot-step compression |
| **Timing at slide** | Ball position (swing angle / clock) at E5 | Side | 120 | P2 | Headline "early / on-time / late" indicator. Always shown as a measured position, never as a grade |
| Timing consistency | Standard deviation of each split across shots | Any | 60 | P1 | Personal; shown as a consistency band |

### 4.3 Armswing
| Metric | Definition | Best view | Min fps | Phase | Reference |
|---|---|---|---|---|---|
| Backswing height | Ball apex relative to the shoulder line (above / at / below; degrees from vertical where possible) | Side ★ | 60 | P1 (relative) / P2 (angle) | Style-dependent: belt-to-shoulder up to above the head. Elite hand height 1.69 ± 0.22 m (Seiferheld) |
| Ball start direction | Lateral offset of the pushaway from the shoulder line | Rear | 60 | P2 | NBA: the ball start sets the swing line |
| Swing plane / direction | Lateral deviation of the ball path from a straight pendulum (rear view): wrap behind the back, loop | Rear ★ | 60 | P2 | Coaching: straight swing groove |
| Laydown distance | Ball-to-slide-ankle lateral distance at E7 | Rear / front | 120 | P2 | USBC: consistency |
| Arm speed at release | Angular velocity of the arm through E6–E7 | Side | 240 | P3 | ~600–620°/s (Chu 2002) |

### 4.4 Posture and balance at the line
| Metric | Definition | Best view | Min fps | Phase | Reference |
|---|---|---|---|---|---|
| Spine tilt at release | Torso angle from vertical at E7 | Side | 60 | P2 | Qualitative only in sources. Personal baseline |
| Knee flexion at release | Slide-knee angle at E7 | Side | 60 | P2 | No sourced target |
| Head over slide foot | Horizontal head-to-slide-toe offset at E7 | Side / front | 60 | P2 | NBA leverage checkpoint |
| Balance arm | Off-arm position/height at E7 | Front / rear | 60 | P3 | Qualitative |
| Shoulder rotation at release | Shoulder line vs. foul line | Rear / overhead | 120 | P3 | Early/late timing symptom |

**Not Form metrics:** axis tilt/rotation, PAP, rev rate, ball speed. These stay in Shot Analysis or sensor (METRIC_CAPABILITIES §3).

## 5. Capture protocol
### 5.1 Views
DEC-040 means one view per recording. Each view unlocks a different metric set, and the app shows that set before recording.

| View | Placement | Unlocks | Doesn't support |
|---|---|---|---|
| **Side (recommended default)** | Perpendicular to the approach, **1.5–2.5 lanes away**, lens at **hip height (~1 m)**, centered on the **last two steps + foul line**, landscape | Steps, cadence, all timing (incl. timing at slide), swing height, slide, posture, release frame | Drift, swing plane, ball start direction |
| **Rear** | Directly behind, slightly to the bowling-arm side, ~4–6 m back, lens at chest height, landscape, whole approach + foul line + first 15 ft of lane in frame | Drift (boards), ball start direction, swing plane, laydown, head/shoulder alignment, start/finish board | True backswing apex angle, knee flexion |
| **Front** | From the lane side on the channel cap (odd lane for right-handers), facing up the approach | Timing splits, balance arm, head, follow-through | Steps (often occluded), drift. **Center permission and safety required**; never on the lane bed |

**Why side is the default:**
- It covers the most P1 metrics.
- Our pilot used a front/lane-facing angle. The ball return hid the feet, so step count and timing at slide could not be measured (§9).

### 5.2 Camera rules
These apply to every Form recording.

- **Locked tripod, no panning or zooming.** Panning breaks timing and calibration; this is Vardakis's rule, and the right one for automation. A handheld or panning clip is accepted, but spatial metrics are marked Unavailable ("camera moved").
- **Landscape.**
- **Bowler large in frame:** standing height **≥ 40% of frame height** at setup. In our pilot the bowler was ~150–250 px of 1920 and pose estimation failed.
- **Full delivery in frame:** setup through the posted finish, with head and feet visible at all times. Keep the ball return and other bowlers out of the sightline.
- **Frame rate:**
  - **120 fps default**: ±8 ms per event, and release is resolvable.
  - **240 fps** for release / laydown close-ups.
  - **60 fps minimum**: release split shown with a ±17 ms band.
  - 30 fps: timing splits only, flagged low precision.
- **SDR (HDR off) and bright light.** At 120 fps the iPhone shutter is ≤1/120 s, which reduces arm and ball blur.
- **Record 2 s before setup to 2 s after the finish hold.** Auto-trim with the existing motion pre-pass.

### 5.3 Session protocol (from coaching practice)
- Warm up 6–7 shots before recording. Early shots are not representative (Minshew).
- **Record 5–8 deliveries per view per session.** Include misses, not only strikes (Vardakis).
- **Use the same camera spot every session.** The app saves the setup (view, distance class, height, lane side) and prompts the bowler to reuse it, so baseline comparison stays valid.
- Recommend a contrasting or striped shirt and a non-black ball. Both improve torso and ball tracking.
- Optionally put a strip of white tape on the ball. This is the USBC rev-count method and supports P3 release work.

### 5.4 Calibration and scale
- **Profile height** (entered once) normalizes body measures and gives scale in side view.
- **Ball diameter** (8.5 in) is a second scale reference whenever the ball is visible.
- **Approach boards / dots and the foul line** give board positions in rear view (drift, start/finish board), reusing the lane homography work from Shot Analysis.
- No calibration means relative metrics only (ratios, angles, timing). Absolute distances are marked Unavailable with a reason.

### 5.5 Etiquette, safety, privacy
- **Center permission and placement:** ask the center before filming. Keep the tripod off the approach and lane bed. Front-view capture from the channel cap needs staff OK.
- **Bystanders:** avoid filming other bowlers. Blur or exclude bystanders in shared or exported clips.
- **Age and consent:** 13+ gate (MVP terms). Form video is personal body video, so coach sharing needs explicit, revocable consent (Performance Lab coaching workflow).

## 6. Post-upload quality gate (DEC-042 style)
Capture is never blocked. Each check below makes the metrics it affects Unavailable, with the reason shown.

| Check | Affects | Unavailable message example |
|---|---|---|
| View classifier (side / rear / front / other) | Metric set | "Rear view: drift and swing plane measured; timing at slide needs a side view" |
| Bowler size < 40% frame height | Pose metrics | "You're too small in the frame for posture angles. Move the camera closer" |
| Feet occluded during steps | Step count, cadence, slide | "Feet hidden behind the ball return during steps 1–3" |
| Camera motion | Spatial metrics | "Camera moved; distances unavailable, timing still measured" |
| fps < 120 | Release split, timing at slide | "Recorded at 60 fps; release time shown ± 17 ms" |
| Clip truncated | Finish stability | "Clip ends before your finish hold" |
| Multiple people in frame | All | "More than one bowler moving — tap yourself to select" |

## 7. Analytics and presentation
- **Key-position strip:** the frame at each event (E1–E9) with timestamps. This is the format coaches already use; the pilot produced one automatically.
- **Phase timeline bar:** pushaway / backswing / downswing / release splits plus step markers on one time axis.
- **Shot-to-shot consistency:** mean ± SD per split and per angle across the session. Coaches and the research agree that repeatability matters more than any absolute value.
- **Baseline comparison:** current vs. personal best or baseline session, same view only, with aligned events.
- **Side-by-side and overlay video:** sync on release (E7) or slide start (E5), with slow motion and frame stepping. The pilot produced a release-synced side-by-side.
- **Coach layer (post-MVP):** timestamped comments, drawing (lines, angles, circles), voice-over, corrections that override engine events and are stored as source = coach, and assigned drills.
- **Norms policy:**
  - Show external reference ranges only where sourced (drift ≤2 boards; ball-start step; elite slide-time and foul-line figures labelled "elite research sample").
  - Everything else is personal-baseline only.
  - No "ideal form" score.

## 8. Validation plan
- **Ground truth:**
  - Manual frame annotation of E0–E9 and foot contacts by two annotators; inter-rater agreement must be reported.
  - Ruby timing splits as a cross-check. Ruby's boundary definitions are its own, so report the offset, not error.
- **Dataset strata:**
  - view (side / rear / front) × fps (60 / 120 / 240)
  - handedness × 1-handed / 2-handed
  - 4-step / 5-step
  - bowler size in frame
  - **Target:** ≥30 deliveries per primary stratum; ≥10 bowlers before any user-facing claim.
- **Acceptance targets (proposed):**
  - Event timing: median error ≤1 frame at 120 fps, 95th percentile ≤3 frames.
  - Step count: 100% on clean side-view clips.
  - Drift: ±1 board vs. manual board read.
  - Angles: ±5° vs. manual measurement.
  - Failure rate: report it per stratum.
- **Harness:** extend `examples/eval_session.py` with a form mode that scores annotated clips. Store per-metric status and failure reasons as DEC-042 telemetry.

## 9. Pilot evidence (2026-10-17)
**Setup:** three 60 fps clips, front/lane-facing view from the neighboring approach. Events were marked by ball-color tracking plus frame inspection; precision ±1–2 frames (pushaway onset ±3–4, approach start ±5).

| Split | Shayne IMG_8823 | Shayne IMG_8826 | Other bowler IMG_8824 |
|---|---|---|---|
| Approach start → ball start | 0.88 s | 0.93 s | 0.95 s |
| Pushaway | 0.42 s | 0.38 s | 0.38 s |
| Backswing | 0.68 s | 0.72 s | 0.70 s |
| Downswing | 0.37 s | 0.37 s | 0.45 s |
| Release | 0.03 s | 0.03 s | 0.03 s |
| Swing (ball start → release) | 1.50 s | 1.50 s | 1.57 s |
| Approach (start → release) | 2.38 s | 2.43 s | 2.52 s |
| Backswing apex | ~shoulder height | ~shoulder height | above head |

**What worked:**
- Ball-color tracking against a background median gave clean apex and bottom-of-arc events.
- Phase timing was repeatable across Shayne's two shots: identical 1.50 s swing.
- The higher backswing explained the other bowler's longer downswing.

**What failed (it drives §5):**
- Generic pose estimation was unusable at this bowler size (~8–13% of frame height).
- The ball return hid the feet, so step count, timing at slide and slide metrics were impossible.
- At 60 fps, release (2 frames) is at the resolution limit.
- The front view gives image-apex rather than true backswing angle.

**Conclusion:**
- Side view at 120 fps, with the bowler ≥40% of frame height, is the recommended Form default.
- Ball-color tracking plus pose is a viable P1 pipeline.

## 10. Open decisions
1. **Default Form view:** side (recommended) vs. rear. Rear is easier for bowlers to set up alone and gives drift.
2. **Timing at slide as the headline metric:** show it as a measured ball position plus coach-facing early/late label, or as raw position only until coaches validate the thresholds.
3. **Minimum fps** for Form: require 120, or allow 60 with bands.
4. **Two-handed bowlers:** separate event definitions (no pushaway in the classic sense) and their own baseline set.
5. **Coach correction data:** use it to retrain only with separate consent (per Performance Lab).
6. **Front-view support:** keep as a supported view, or advisory-only given center safety rules.

## Sources
- Minshew, "Lights, Camera, Action" Pt 1–2, Bowling This Month — https://bowlingthismonth.com/bowling-tips/lights-camera-action-part-1 · https://bowlingthismonth.com/bowling-tips/lights-camera-action-part-2/print
- Vardakis, "How to film your bowling for coaching", BowlingLife — https://bowlinglife.eu/how-to-film-your-bowling-for-coaching-panagiotis-vardakis
- USBC, "Dealing with drift" — https://bowl.com/dealing-with-drift ; "What's your rev rate?" — https://bowl.com/what-s-your-rev-rate ; DigiTrax/BowlersMAP — https://bowl.com/equipment-specifications/digitrax-and-bowlersmap
- National Bowling Academy: Technique, Tempo & Timing — https://www.nationalbowlingacademy.com/post/technique-tempo-and-timing ; Timing & Release — https://nationalbowlingacademy.com/video/timing-release-early-good-late-025367 ; Stance, Ball Start & Arm Swing — https://nationalbowlingacademy.com/post/stance-ball-start-and-arm-swing ; Alignment, Leverage & Timing — https://www.nationalbowlingacademy.com/class/upper-and-lower-body-alignment-leverage-and-timing
- Bowling This Month: Mautner, Modern vs Traditional Timing — https://www.bowlingthismonth.com/bowling-tips/modern-timing-vs-traditional/ ; Maja, Bowling 2.0: Timing — https://bowlingthismonth.com/bowling-tips/bowling-2-0-timing ; Backswings and Fast Feet — https://www.bowlingthismonth.com/bowling-tips/backswings-and-fast-feet/ ; Jowdy, The Timing Ideal — https://bowlingthismonth.com/bowling-tips/the-timing-ideal/print ; How to Fix Early Timing — https://bowlingthismonth.com/quick-tips/how-to-fix-early-timing
- Seiferheld et al. 2023, Sensors (IMU kinematics, Danish elites) — https://pmc.ncbi.nlm.nih.gov/articles/PMC10575452
- Chu, Zhang & Mau 2002, ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/634/559
- Razman et al. 2011 — https://eprints.um.edu.my/9545
- Specto data points — https://www.spectobowling.com/data-points
- AI Bowling (App Store; closest product analog: pose + phase markers) — https://apps.apple.com/ne/app/ai-bowling/id6475312282
- OnForm feature summary — https://www.trustradius.com/products/onform/details
