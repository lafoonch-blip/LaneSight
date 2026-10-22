# Owner review — Power P′ ranges + rules/drills/achievements (DRAFT)
Status: **DRAFT FOR SHAYNE'S APPROVAL — nothing is live.** (DEC-046: all rule data is owner-only and must be reviewed before publish.)
Version: 0.1
Last Updated: 2026-10-22
Owner: Shayne
Prepared by: Claude Code (DV-02)

Everything below is a **proposal**. The engines (`lanesight_core/score`, `benchmarks`, `achievements`) run on this data once it is seeded, but it is **not seeded yet**. When you approve, it is written to the owner-only tables (`engine_config`, `benchmark_reference`, `style_template`, `form_rule`, `drill`, `achievement_definition`) and exported to `lanesight-core/rules/*.yaml` for history (BENCHMARKS §8). Edit any value before approving.

---

## 1. Power P′ reference ranges (DEC-048, HANDOFF §7)

P′ normalizes each input to 0–1 against a `[low, high]` range (low = weak, high = strong) and averages them. Carry is excluded. These ranges are **owner-editable** in `engine_config` and gate the overall score (until they're set, the score stays "building").

**Observed from the validation data (Shayne's shots):**

| Input | IMG_8751–8754 (video) | Ruby ground truth | Live session (10/15) |
|---|---|---|---|
| Entry/pocket speed (mph) | 15.8–17.3 | 16.9–17.8 | ~16–18 |
| Rev rate (rpm) | 403–425 | 392–428 | ~378–444 |
| Entry angle (deg) | 2.8–5.2 | — | — |
| Ball weight (lb) | not captured | — | — |

**Proposed ranges** (anchored to your data, widened to published context so your current shots sit mid-scale and there's headroom both ways — not a grade, just a 0–1 normalizer):

```yaml
# engine_config key: power_ref_ranges  (owner-editable; DEC-048)
power_ref_ranges:
  entry_speed_mph: [14.0, 20.0]   # your pocket speed ~16-17 -> ~0.4-0.5; USBC design-basis ~17
  rev_rate_rpm:    [250, 500]     # your ~400-425 -> ~0.6-0.7; USBC average bowler ~250
  entry_angle_deg: [2.0, 6.0]     # your 3-5 deg -> ~0.3-0.75; USBC "good" entry ~4-6
  weight_lb:       [14.0, 16.0]   # typical; set to your ball weight
```

**Questions for you:** (a) your ball weight; (b) do you want the ranges anchored to *your* data (above) or to a population reference? (c) rev uses the video `rev_rate` which is a calibrated estimate — OK to include, or weight it lower?

---

## 2. engine_config (prioritizer, baselines, thresholds)

```yaml
baseline_min_n: 10                 # qualifying shots per view before a personal baseline is "established" (DEC-046)
confidence_min: 0.5                # metrics below this are not compared (DEC-042)
repetition_rule: 3                 # out-of-band shots before a finding is "Outside" (of last 5 comparable)
prioritizer_weights:               # severity * confidence * outcome_impact * upstream_weight, then per-metric:
  timing: 1.2
  drift: 1.0
  finish: 0.8
focus_hold_shots: 10               # hold one primary focus this many shots before switching
```

---

## 3. L0 benchmark references (BENCHMARKS §3.1) — `benchmark_reference`

```yaml
# shown_to_user: true  -> a plain label may cite it; false -> owner-only (elite research), never shown
- metric: ball_start_step      ; reference: "step 1 (4-step) / step 2 (5-step), in time with the slide-foot step" ; source: NBA ; source_quality: medium ; shown_to_user: true
- metric: backswing_peak       ; reference: "peaks during pivot-step compression" ; source: NBA ; source_quality: medium ; shown_to_user: true
- metric: drift_boards         ; low: -2 ; high: 2 ; units: board ; reference: "<=1-2 boards, repeatable direction" ; source: USBC ; source_quality: high ; shown_to_user: true
- metric: finish_hold          ; reference: "hold at the line until the ball reaches the pins" ; source: USBC ; source_quality: high ; shown_to_user: true
- metric: step_rhythm          ; reference: "early steps slower, last three quicker" ; source: BTM ; source_quality: medium ; shown_to_user: true
- metric: entry_angle_deg      ; low: 3 ; high: 4 ; units: deg ; reference: "~3-4 deg typical for 180-200 avg (shot-reading context)" ; source: USBC ; source_quality: medium ; shown_to_user: true
- metric: slide_to_release_ms  ; low: 545 ; high: 735 ; units: ms ; reference: "elite 640 +/- 95 ms" ; source: "Seiferheld 2023" ; source_quality: high ; shown_to_user: false   # OWNER-ONLY
- metric: foul_line_distance_m ; reference: "elite men 0.35 m, women 0.16 m" ; source: "Chu 2002" ; source_quality: high ; shown_to_user: false   # OWNER-ONLY
```

## 4. Style templates (BENCHMARKS §3.2) — `style_template` (+ metrics)

```yaml
- id: one_handed_thumb      ; name: "One-handed, with thumb"    ; metrics: { backswing_height_rel: {matters: true, note: "waist-to-shoulder typical"} }
- id: one_handed_no_thumb   ; name: "One-handed, no thumb"      ; metrics: { backswing_height_rel: {matters: true, note: "often shoulder-to-above-head"} }
- id: two_handed            ; name: "Two-handed"                ; metrics: { backswing_height_rel: {matters: true, note: "often above head"}, ball_start_direction: {matters: true, note: "both hands through the swing"} }
```
(Ranges are placeholders — tightened from LaneSight data once the seed dataset exists, BENCHMARKS §3.2.)

## 5. Drills — `drill`

```yaml
- id: DRILL-ball-start  ; name: "Ball-start timing"      ; description: "Start the ball later/more extended so it moves with the key step." ; sources: [NBA, BTM]
- id: DRILL-get-going   ; name: "Get it going"           ; description: "Trigger the ball with the first step; avoid holding it in the setup." ; sources: [BTM]
- id: DRILL-one-step    ; name: "One-step / short approach"; description: "Groove a repeatable ball start from a one-step drill." ; sources: [NBA]
- id: DRILL-walk-spot   ; name: "Walk to a spot"          ; description: "Align feet to the target line; walk to a fixed finish spot to control drift." ; sources: [USBC]
- id: DRILL-post        ; name: "Post the shot"           ; description: "Hold the finish position until the ball hits the pins; balance-hold." ; sources: [USBC]
- id: DRILL-slow-first  ; name: "Slow first steps"        ; description: "Start slow, accelerate into the slide (rhythm)." ; sources: [BTM]
- id: DRILL-free-swing  ; name: "Free swing"              ; description: "Let the swing fall freely at a consistent ball-start height." ; sources: [NBA]
- id: DRILL-place-it    ; name: "Place it here"           ; description: "Set the ball-start direction so the swing lines up behind the target." ; sources: [NBA]
```

## 6. Form rules (BENCHMARKS §5.2) — `form_rule` (P1/P2; P1 live when Form P1 metrics validate)

```yaml
- id: RULE-timing-inconsistency ; status: draft ; trigger: {metric: phase_splits, comparison: consistency, repetition: "SD>baseline band"} ; causes: [variable_ball_start, variable_step1] ; cue: "Groove a repeatable ball start" ; drill_ref: DRILL-one-step ; verify: {metric: split_sd, over_shots: 10}
- id: RULE-short-finish        ; status: draft ; trigger: {metric: finish_hold, comparison: level, rule: "< baseline"} ; causes: [early_timing, over_speed, fast_approach] ; cue: "Post the shot until it hits" ; drill_ref: DRILL-post ; verify: {metric: finish_hold, over_shots: 10}
- id: RULE-rhythm-inverted     ; status: draft ; trigger: {metric: cadence_ratio, rule: "last 3 not quicker than first 2"} ; causes: [rushing_early_steps] ; cue: "Slow the first steps, speed up to the line" ; drill_ref: DRILL-slow-first ; verify: {metric: cadence_ratio, over_shots: 10}
- id: RULE-drift-excessive     ; status: draft ; trigger: {metric: drift_boards, rule: "|finish-start|>2 or > coach tol"} ; causes: [ball_start_across_body, walking_to_target] ; cue: "Walk to your spot" ; drill_ref: DRILL-walk-spot ; verify: {metric: drift_boards, over_shots: 10}   # needs floor calibration — pending
- id: RULE-early-timing        ; status: draft ; trigger: {metric: timing_at_slide, rule: "ball ahead of slide vs baseline, repeated", min_fps: 120} ; causes: [early_ball_start, short_pushaway, slow_feet] ; cue: "Start the ball a touch later" ; drill_ref: DRILL-ball-start ; verify: {metric: timing_at_slide, over_shots: 10}   # P2
- id: RULE-late-timing         ; status: draft ; trigger: {metric: timing_at_slide, rule: "ball behind at slide", min_fps: 120} ; causes: [late_ball_start, short_key_step, tension] ; cue: "Get it going with the key step" ; drill_ref: DRILL-get-going ; verify: {metric: timing_at_slide, over_shots: 10}   # P2
- id: RULE-backswing-variance  ; status: draft ; trigger: {metric: backswing_height_rel, comparison: consistency, rule: "apex SD>band"} ; causes: [muscled_swing, variable_ball_start_height] ; cue: "Same ball-start height, free swing" ; drill_ref: DRILL-free-swing ; verify: {metric: apex_sd, over_shots: 10}
- id: RULE-swing-line-off      ; status: draft ; trigger: {metric: swing_line_offset, rule: "bottom-of-arc offset vs shoulder line > band (rear)"} ; causes: [pushaway_direction] ; cue: "Place the ball start behind the target" ; drill_ref: DRILL-place-it ; verify: {metric: swing_line_offset, over_shots: 10}   # P2, rear view
```

## 7. Achievements — `achievement_definition` (SCORE_TIERS §4 launch catalog)

**Active now** (rule_type maps to `lanesight_core/achievements` evaluators):

```yaml
- id: ACH-050 ; name: "Welcome to LaneSight" ; category: onboarding ; rule_type: one_time       ; params: {condition: profile_complete} ; status: active
- id: ACH-051 ; name: "First Analysis"       ; category: onboarding ; rule_type: one_time       ; params: {condition: first_valid_shot} ; status: active
- id: ACH-052 ; name: "Getting Started"      ; category: onboarding ; rule_type: one_time       ; params: {condition: first_completed_session} ; status: active
- id: ACH-053 ; name: "Data Driven"          ; category: volume     ; rule_type: cumulative     ; params: {target: 100} ; status: active
- id: ACH-054 ; name: "Shot Scientist"       ; category: volume     ; rule_type: cumulative     ; params: {target: 1000} ; status: active
- id: ACH-055 ; name: "Arsenal Builder"      ; category: arsenal    ; rule_type: cumulative     ; params: {target: 5} ; status: active
- id: ACH-049 ; name: "Dedicated Bowler"     ; category: volume     ; rule_type: cumulative     ; params: {target: 25, unit: sessions} ; status: active
- id: ACH-048 ; name: "Practice Warrior"     ; category: streak     ; rule_type: weekly_streak  ; params: {target_weeks: 4} ; status: active
- id: ACH-010 ; name: "Dialed In"            ; category: accuracy   ; rule_type: count_qualifying ; params: {target: 10, qualify: "intent shot within +/-1 arrow board"} ; status: active
- id: ACH-011 ; name: "Precision Master"     ; category: accuracy   ; rule_type: window_ratio   ; params: {target_ratio: 0.90, min_sample: 30, qualify: "within +/-1 arrow board"} ; status: active
- id: ACH-013 ; name: "Pocket Hunter"        ; category: accuracy   ; rule_type: window_ratio   ; params: {target_ratio: 0.80, min_sample: 30, qualify: "entry board in pocket"} ; status: active
- id: ACH-014 ; name: "Breakpoint Boss"      ; category: accuracy   ; rule_type: window_ratio   ; params: {target_ratio: 0.90, min_sample: 30, qualify: "within +/-2 breakpoint boards"} ; status: active
- id: ACH-023 ; name: "Line Locked"          ; category: accuracy   ; rule_type: streak         ; params: {target: 10, qualify: "within +/-1 arrow board"} ; status: active
- id: ACH-016 ; name: "Speed Demon"          ; category: power      ; rule_type: best_measured  ; params: {threshold: 20, direction: above, metric: ball_speed} ; status: active
- id: ACH-017 ; name: "Rev Machine"          ; category: power      ; rule_type: best_measured  ; params: {threshold: 450, direction: above, metric: rev_rate} ; status: active   # band must fully clear 450
- id: ACH-018 ; name: "Powerhouse"           ; category: power      ; rule_type: count_qualifying ; params: {target: 10, qualify: ">=18 mph AND >=400 rpm"} ; status: active
- id: ACH-020 ; name: "Efficiency Expert"    ; category: accuracy   ; rule_type: window_ratio   ; params: {target_ratio: 0.80, min_sample: 30, qualify: "entry angle 4-6 deg"} ; status: active   # redefined (DEC-051)
- id: ACH-021 ; name: "Mr. Consistent"       ; category: consistency; rule_type: window_spread  ; params: {max_sd: 0.5, min_sample: 30, metric: ball_speed} ; status: active
- id: ACH-022 ; name: "Repeatable Release"   ; category: consistency; rule_type: window_spread  ; params: {max_cv: 0.05, min_sample: 30, metric: rev_rate, requires: "rev band <= +/-20 (120 fps)"} ; status: active
- id: ACH-026 ; name: "Rising Star"          ; category: progress   ; rule_type: baseline_delta ; params: {delta: 25} ; status: active
- id: ACH-027 ; name: "Level Up"             ; category: progress   ; rule_type: baseline_delta ; params: {delta: 50} ; status: active
- id: ACH-028 ; name: "Century Climber"      ; category: progress   ; rule_type: baseline_delta ; params: {delta: 100} ; status: active
- id: ACH-056 ; name: "Silver Status"        ; category: tier       ; rule_type: first_tier     ; params: {tier: silver} ; status: active
- id: ACH-057 ; name: "Gold Status"          ; category: tier       ; rule_type: first_tier     ; params: {tier: gold} ; status: active
- id: ACH-058 ; name: "Platinum Status"      ; category: tier       ; rule_type: first_tier     ; params: {tier: platinum} ; status: active
- id: ACH-059 ; name: "Onyx Club"            ; category: tier       ; rule_type: first_tier     ; params: {tier: onyx} ; status: active
- id: FORM-001 ; name: "Post It"             ; category: form       ; rule_type: count_qualifying ; params: {target: 10, qualify: "finish hold >= 1.5 s"} ; status: active   # activates when Form P1 validates
- id: FORM-002 ; name: "Metronome"           ; category: form       ; rule_type: window_spread  ; params: {max_sd: 0.05, min_sample: 10, metric: swing_time} ; status: active   # activates when Form P1 validates
```

**Coming later** (defined inactive, shown as "Coming later"): the pinfall/game-score set (ACH-001…009, 015, 024, 029…033, 042…047), competition (034…041), research (012, 019, 025), and ACH-060 — seeded `status: coming_later` with `inactive_reason`, enumerated from `01_PRODUCT/ACHIEVEMENTS.md`.

---

## Approve / edit
Reply with edits (especially: your ball weight, and whether to anchor P′ to your data or a population reference). On approval I'll seed these into the owner-only tables + `lanesight-core/rules/*.yaml` and flip FORM-001/002 live once Form P1 validates.
