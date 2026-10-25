# Foundational Form Metrics & Benchmarks
Status: DRAFT (for Shayne's review)
Version: 0.1
Last Updated: 2026-10-25
Owner: Shayne
Builds on: FORM_ANALYSIS_SPEC, BENCHMARKS_AND_RECOMMENDATIONS_SPEC (L0–L3 layers, owner-only rules), DEC-041/046/047
Code checked: `lanesight-core/lanesight_core/form/pose.py` + `analyze.py` on branch `dev-build-v0` (2026-10-25)
Proposed home: `01_PRODUCT/FORM_BENCHMARKS.md`

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
