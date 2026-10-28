# Foundational Form Metrics & Benchmarks
Status: DRAFT (for Shayne's review)
Version: 0.3
Last Updated: 2026-10-28
Owner: Shayne
Builds on: FORM_ANALYSIS_SPEC, BENCHMARKS_AND_RECOMMENDATIONS_SPEC (L0–L3 layers, owner-only rules), DEC-041/046/047
Code checked: `lanesight-core/lanesight_core/form/pose.py` + `analyze.py` on branch `dev-build-v0` (2026-10-25)
Proposed home: `01_PRODUCT/FORM_BENCHMARKS.md`

## 0. Shayne's fundamentals v1 (owner rules, 2026-10-25, DEC-057)
These are the default **L0 fundamentals** for form findings and feedback. They are owner rules (DEC-046): stored as rule data, editable only by Shayne, never shipped to the app. Every verdict shows the measured value next to it; a metric that can't be measured from the clip's view is Unavailable with a reason, never a guess.

### 0.1 Timing checkpoints (early / on time / late)
Events are from FORM_ANALYSIS_SPEC §3 (E2 ball start, E3 ball at hip, E4 top of backswing, E5 slide start, E7 release, E8 slide stop; S1…Sn foot contacts).

| # | Checkpoint | Rule | How it's measured | Early | Late | View | Phase |
|---|---|---|---|---|---|---|---|
| T1 | Pushaway | When the foot **after** the pushaway step lands (step 2 of a 4-step, step 3 of a 5-step), the ball is in line with the ball-side leg (right thigh for a right-hander) | Ball (or bowling wrist) fore-aft position vs ball-side thigh at that foot contact | Ball already past the leg | Ball not yet at the leg | Side ★ | P2 |
| T2 | Ball start step | 4-step: ball moves on step 1. 5-step: ball moves on step 2 | `ball_start_step` (E2 in S_k) vs the profile's approach steps | Before that step | After that step | Side | P1 (exists) |
| T3 | Backswing apex | Ball at the top of the backswing as the slide starts | E4 − E5 (s) | Top reached before the slide starts | Top reached after the slide started | Side ★ | P2 |
| T4 | Leverage window | Release after the slide foot stops | E7 − E8 (s) | Release before the slide foot stops (loses power and balance) | Foot stopped and still waiting for the ball (forces muscling) | Side ★ | P2 |

- **On-time windows are owner settings.** Start values are provisional and must be tuned on real clips before they're shown as validated: T1 ±1 in of the thigh line, T3 ±0.05 s, T4 0 to +0.10 s after slide stop.
- **Repetition rule** before a finding becomes the session focus: ≥3 of the last 5 comparable deliveries (BENCHMARKS spec).

### 0.2 Measured positions
| # | Metric | Rule / target | How it's measured | View | Phase |
|---|---|---|---|---|---|
| M1 | Foul-line distance | Track how far the slide toe is from the foul line **when the slide stops** (E8). Personal trend; no fixed target | Slide toe to foul line at E8 (in) | Side or rear, foul line visible | P2 |
| M2 | Spine tilt | Forward tilt 15–30°, kept steady through the approach; no lift at release | Torso angle from vertical through the approach and at E7; flag a rise of >5° into release (provisional) | Side | P2 |
| M3 | Balance arm | Non-bowling arm out to the side ~90° from the body | Off-arm abduction angle at E7 | Front / rear | P2 |
| M4 | Shoulders | Bowling shoulder slightly lower; chest square or slightly open to the target; no over-rotation | Shoulder-line tilt at E7 (front/rear); chest rotation needs rear/overhead | Front / rear | P2 (tilt), P3 (rotation) |
| M5 | Follow-through | Hand finishes up toward the ear/forehead ("answer the phone") | Bowling-wrist height vs head after E7 | Side / front | P2 |
| M6 | Finish hold | Hold the finish until the ball reaches the pins | Finish hold (E8→E9); target is an owner setting (start ≥ 2.5 s ≈ ball travel time) | Any | P1 (exists) |
| M7 | Pendulum swing | Relaxed, gravity-driven swing; don't muscle the ball down | Proxy only: downswing time vs the bowler's baseline and T4 "late". No direct "muscling" metric | Side | P3 |

### 0.3 Coaching cues only (not measured)
Phone video can't reliably see these yet, so they appear only as cue/drill text attached to a measured finding, never as a measured result:
- Pushaway direction "match ball movement to footwork" (covered by T2).
- **Behind and under:** firm or slightly cupped wrist, hand under the ball.
- **Inside-out path:** hand slightly inside the ball before release, rolling outside on the follow-through.
- **Finger exit:** thumb out first, then middle and ring fingers.
- **Avoid "suitcasing":** hand not on top or fully on the side early.
- **Avoid a broken wrist:** wrist not collapsing backward.
- Non-bowling arm palm facing down or back (part of M3; palm not measured).

### 0.4 Swing-timing comparison
- The Form results swing-timing bar shows **this delivery vs the bowler's baseline** (pushaway, backswing, downswing, release), with the difference per phase.
- The baseline comes from **Profile › Form baseline**: entered by the bowler or "use my average". If none is set, only this delivery shows, with a prompt to add one.
- **Baseline values (DEC-099), seconds:** Pushaway `pushaway_time` (ball starts moving → ball at hip, E2→E3) · Backswing `backswing_time` (hip → top of backswing, E3→E4) · Downswing `downswing_time` (top → bottom of the swing, E4→E6) · Release `release_time` (bottom of the swing → release, E6→E7, usually ≤0.10 s) · optional Total (= `swing_time`, ball start → release; otherwise the sum). Modes: `average` | `entered` | none (`null`). Server sanity bound 0 < t ≤ 3 s per value (not a target). Shortcut: "Use this delivery as my baseline" on a Form result saves that delivery's measured phases only.

## 1. What Form Analysis captures today
**Method:** MediaPipe pose plus ball/wrist event detection. Every value carries a status (Measured, Best effort, Unavailable + reason) and a confidence.

### 1.1 Headline metrics (P1, returned per delivery)
| Key | What it is | Unit | View |
|---|---|---|---|
| `step_count` | Foot contacts in the approach | count | side ★, rear (feet visible) |
| `ball_start_step` | Step on which the ball starts moving | step # | side ★ |
| `approach_time` | Approach start → release | s | any (unreliable when feet leave frame) |
| `rhythm_ratio` | Last 3 steps' pace vs first 2 (should speed up) | ratio | side ★ |
| `pushaway_time` | Ball start → ball at hip | s | any |
| `backswing_time` | Ball at hip → top of backswing | s | any |
| `downswing_time` | Top → bottom of arc | s | any |
| `swing_time` | Ball start → release | s | any |
| `backswing_height_rel` | Top of backswing vs shoulder line (torso lengths; − = below) | ratio | side ★, rear (relative) |
| `finish_hold` | Time balanced at the line after release | s | any |
| `drift_boards` | Slide-foot finish board − stance board | boards | rear (needs approach dots) |

### 1.2 Supporting values (extras, also stored)
| Key | What it is |
|---|---|
| `step_intervals` | Duration of each step |
| `first_step_to_release` | First step → release |
| `slide_to_release` | Slide-foot plant → release (release sync) |
| `ball_at_hip_to_release` | Ball at hip → release |
| `tempo_ratio` | Downswing ÷ backswing |

### 1.3 Measured in research, not yet in the engine
From the 2026-10-20 calibrated analysis; these are candidates for P2:
- stance board and distance, finish board, slide-toe-to-foul-line distance
- approach length and approach speed, slide length
- swing line at the bottom (wrist vs shoulder)
- head over slide foot, head movement top → release
- laydown vs slide foot
- spine tilt, hip tilt, knee flex (side view needed for absolute values)
- follow-through height, shoulder tilt at release
- timing at slide (ball position when the slide foot plants): the headline early/late indicator, P2

## 2. Which metrics can be set as a benchmark
**Rule:** a metric is benchmarkable only if it is:
1. **measured reliably** from a normal camera view (status Measured, or Best effort with a known band);
2. **coachable**: the bowler can change it on purpose;
3. **not just a style trait.** Style traits are benchmarked only when a coach sets them; LaneSight never sets a default for them.

### 2.1 Foundational form benchmarks: enterable now (P1)
| Metric | Benchmark type | Default reference (L0/L1) | Typical coach entry | View needed |
|---|---|---|---|---|
| Ball start step | exact value | 4-step: step 1 · 5-step: step 2 (NBA) | "step 2" | side |
| Step count | exact value | bowler's stated approach | "5" | side / rear |
| Rhythm (rhythm_ratio) | min/max | last 3 steps quicker than first 2 (BTM) | "≤ 0.85" | side |
| Swing time | target ± tolerance **or** consistency (SD) | personal baseline only | "1.50 s ± 0.05" | any |
| Tempo (downswing ÷ backswing) | target ± tolerance or consistency | personal baseline only | "0.50 ± 0.05" | any |
| Backswing height | range | style template (L1): thumb waist–shoulder; no-thumb / 2-handed shoulder–above head | "at shoulder (−0.1 to +0.1)" | side ★ |
| Slide → release sync | max | personal baseline | "≤ 0.08 s" | side / rear |
| Finish hold | min | USBC "post the shot" | "≥ 1.5 s" | any |
| Drift | max \|boards\| + direction **and** consistency | ≤ 2 boards, repeatable (USBC) | "≤ 2, SD ≤ 1" | rear |

### 2.2 Foundational form benchmarks: enabled when P2 is validated
| Metric | Benchmark type | Default reference | View |
|---|---|---|---|
| Timing at slide (ball position at slide-foot plant) | range (clock position / swing angle) | none sourced; coach-set only | side |
| Backswing peak vs pivot step | target ± tolerance (ms) | peak at pivot-step compression (NBA) | side |
| Stance board / distance | exact ± tolerance | coach/bowler set | rear |
| Finish distance from foul line | range | personal / coach | side / rear |
| Swing line at bottom | max offset from shoulder line | straight pendulum (coaching) | rear |
| Head over slide foot at release | max offset | NBA leverage checkpoint | side / front |
| Slide length | range | personal / coach | side |
| Slide-knee flex / spine tilt at release | range | coach-set only | side |
| Laydown vs slide foot | consistency | USBC: consistency | rear |

### 2.3 Track but don't benchmark
- **Approach time:** unreliable when the feet leave the frame; use `first_step_to_release` instead once validated.
- **Pushaway / backswing / downswing splits individually:** shown as context. Coaches benchmark swing time and tempo, which capture them.
- **Follow-through height, shoulder tilt, hip tilt:** diagnostic only until a coach asks.
- **Approach speed:** research only (P3).

## 3. How a benchmark is entered
Every benchmark is one row in the L3 coach profile, or in a self-set goal later. Fields:
- **Type:** `exact`, `target ± tolerance`, `min`, `max`, `range`, `consistency (SD ≤ x)`, or `match my baseline snapshot`.
- **View required:** auto-filled from §2. If a session's clips can't measure it, progress shows "not measured this session", never a miss.
- **Style scope:** applies to the bowler's delivery style.
- **Priority** (1–5) and an optional **focus** flag.
- Optional coach cue / drill text.
- **Source**, **author** and **version**. Findings record which version they were judged against.

**Self-set goals:** DEC-046 says self-coached editing isn't in MVP. A bowler can't edit targets yet, but can **"lock my best session as my goal"**, which freezes their personal baseline as the benchmark.

## 4. How progress is shown
- Per metric:
  - **Status vs benchmark:** Within / Watch / Outside, using the repetition rule (≥3 of the last 5 comparable deliveries).
  - **Trend:** the last 5 sessions moving toward or away from the target.
  - **Consistency:** spread vs the benchmark's tolerance.
- **Form progress summary:** "6 of 8 benchmarks within target · 2 improving". It counts only metrics measured in the window. It is not a score, and it never feeds the LaneSight Score (DEC-041).
- **Benchmark source shown:** "Coach target · [Coach]", "Your goal (locked Oct 20)", or "Fundamental".

## 5. Decisions needed
1. Approve the P1 benchmark list (§2.1). Benchmarks not on it stay display-only.
2. Allow bowlers to "lock my best session as my goal" in the dev build, or wait for the Coaching tab?
3. Should the default L0 references (ball-start step, drift ≤ 2, finish hold ≥ 1.5 s, rhythm) apply automatically to every bowler, or only after the bowler opts into "fundamentals" mode?
