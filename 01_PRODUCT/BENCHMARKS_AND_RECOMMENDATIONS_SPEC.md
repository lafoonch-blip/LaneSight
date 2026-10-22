# Benchmarks & Recommendations — Form + Ball Metrics
Status: DRAFT (for Shayne's review)
Version: 0.3
Last Updated: 2026-10-21
Owner: Shayne
Builds on: FORM_ANALYSIS_SPEC (norms policy §7), BUILD_PLAN Stage 4 (M4-01…M4-06), MASTER_CONTEXT §11–12
Governing: DEC-005/006 (no target move after execution miss; "no adjustment yet"), DEC-041 (form is diagnostic, not a score pillar), DEC-042 (per-metric status, no estimated values)
Proposed home: `01_PRODUCT/BENCHMARKS_AND_RECOMMENDATIONS_SPEC.md`

## 1. Purpose
Once a form or ball metric is measured, LaneSight needs to answer three questions:
1. **Compared to what?** — the benchmark the value is judged against.
2. **Does the gap matter?** — is it real (confidence, repetition) and does it affect results?
3. **What should the bowler do?** — a lane/ball adjustment, a form cue/drill, or nothing yet.

This spec defines a layered benchmark model (best-practice baseline → personal → coach) and a recommendation engine that covers both lane adjustments (existing M4) and form corrections (new).

## 2. Principles
- **Deviation is not a fault.** Many "non-standard" traits (high backswing, early "roller" timing) are styles elite players use. A deviation becomes a finding only when it is inconsistent, or linked to worse outcomes for *this* bowler, or flagged by their coach.
- **Personal baseline first.** External norms are shown only where sourced (FORM spec §7). Everything else compares the bowler to their own best shots.
- **Every comparison carries its benchmark layer** (Reference / Style / Personal / Coach). Bowlers see a plain label; rule internals are owner-only (§8).
- **Only Measured metrics are compared.** Unavailable or low-confidence values never trigger a finding (DEC-042).
- **Patterns, not single shots.** Form findings need repetition (default ≥3 of the last 5 comparable shots, or a session trend). Single-shot exceptions: foul, fall/loss of balance.
- **One primary focus at a time.** Coaches consistently limit work to a few items; LaneSight surfaces one primary form focus per session plus at most two secondary notes.
- **Root cause before symptom.** Fix upstream (stance → ball start → timing → swing → release → finish) before downstream.
- **Rules + evidence, not black-box AI.** Rules are data with reasons, evidence windows, confidence and version (M4-06). An LLM may phrase advice; it never makes the call.
- **"No recommendation yet" is a valid answer.**

## 3. Benchmark model (four layers)

| Layer | What it is | Who sets it | When available |
|---|---|---|---|
| **L0 Reference** | Sourced fundamentals and published ranges, versioned, with citation and source quality | LaneSight (curated) | Day 1 |
| **L1 Style template** | Ranges keyed to delivery style: one-handed with thumb / one-handed no thumb / two-handed; plus 4-step / 5-step and handedness | LaneSight (curated); bowler picks at setup | Day 1 |
| **L2 Personal baseline** | Rolling mean ± band from the bowler's own *good* shots | Computed | After N qualifying shots |
| **L3 Coach profile** | Per-metric target, tolerance, priority, enable/disable, notes | Coach (or bowler, self-coached) | Post-MVP (Coaching tab) |

**Resolution order per metric:** L3 Coach → L2 Personal (if established) → L1 Style → L0 Reference → *no benchmark* (show value only).
The bowler UI shows only a plain label of the layer used, e.g. "vs your baseline (24 shots)" or "Coach target · Coach Name". Rule internals stay admin-only (§8).

### 3.1 L0 Reference — what we can source today
| Metric | Reference | Source | Use |
|---|---|---|---|
| Ball start step | Step 1 (4-step), step 2 (5-step), in time with the slide-foot step | NBA, FORM spec §4.2 | Timing finding |
| Backswing peak | At pivot-step compression | NBA | Timing finding |
| Drift | ≤1–2 boards, repeatable direction | USBC (bowl.com) | Footwork finding |
| Finish | Hold at the line until the ball reaches the pins | USBC | Balance finding |
| Step rhythm | Early steps slower, last three quicker | BTM | Rhythm note |
| Slide→release (elite) | 640 ± 95 ms | Seiferheld 2023 | Owner-only reference (not shown in MVP) |
| Foul-line distance (elite) | Men 0.35 m, women 0.16 m | Chu 2002 | Owner-only reference (not shown in MVP) |
| Average-bowler ball | ~17 mph release, ~250 rpm | USBC (E.A.R.L. design basis) | Context only, never a target |
| Entry angle | ~3–4° typical for 180–200 averages | USBC | Shot-reading context |

Everything not in this table (spine tilt, knee flex, backswing height, swing time, tempo) is **personal-baseline only** until a coach sets a target.

### 3.2 L1 Style templates
Templates hold *which metrics matter* and *expected ranges/relationships*, not ideals:
- **Speed–rev balance** band per style (rev-dominant vs speed-dominant vs matched) — drives lane/ball advice, not form grading.
- **Style options (decided 2026-10-22):** one-handed with thumb, one-handed no thumb, two-handed. Bowler picks at setup; changeable in profile. No stroker/tweener/cranker labels.
- **Backswing height** expected range per style (one-handed with thumb: typically waist–shoulder; no-thumb and two-handed: often shoulder–above head). Two-handed also changes ball-start and swing-line rules (both hands on the ball through the swing).
- **Timing tendency** expected (e.g. roller/early timing is a recognized style; flag only when it causes balance loss or rev loss).
- Ranges for ball metrics start as wide placeholders and are **tightened from LaneSight data** once the seed dataset exists. Until then, style templates select rules and labels, not numeric targets.

### 3.3 L2 Personal baseline
- **Qualifying shots:** status Measured, confidence ≥ threshold, same capture view + fps tier, classification EXECUTED (or user "hit my mark = yes"), and outcome in pocket. Form-only clips with no pin outcome: **all Measured shots** count (decided 2026-10-22).
- **Statistic:** median and robust band (median ± 1.5 × MAD); also SD for consistency metrics.
- **Established when:** N ≥ 10 qualifying shots per view (decided 2026-10-22; owner-configurable). Before that: "building your baseline (6/10)".
- **Windows:** rolling last 30 qualifying shots + "all-time" + per-ball and per-pattern slices for ball metrics.
- **Drift protection:** baseline only updates from qualifying shots; a coach can freeze ("lock") a baseline snapshot as the target.

### 3.4 L3 Coach benchmark profile
Per bowler, per metric:
- `mode`: target value / range / match-baseline-snapshot / consistency-only / ignore
- `target`, `tolerance_low`, `tolerance_high`, `units`
- `priority` (1–5) and `focus` flag (the coach's current primary focus overrides LaneSight's prioritizer)
- `cue_text` / `drill_ref` overrides (coach's own language)
- `effective_from`, `effective_to`, `version`, `author`, `note`
- Profiles can start from a **template** (LaneSight style template or the coach's own saved template) and be cloned across students.
- Bowler can view, not edit, a coach profile. **Self-coached editing is not in MVP** (decided 2026-10-22); it arrives with the Coaching tab.
- Every finding stores which profile version it was judged against, so history stays interpretable when targets change.

## 4. Comparison logic
For each Measured metric on each shot:
1. Resolve benchmark (§3).
2. Classify: **Within** / **Watch** (outside band once, or trending toward edge) / **Outside** (meets repetition rule).
3. Compute two separate signals:
   - **Level**: value vs target/band.
   - **Consistency**: shot-to-shot spread vs baseline spread. Inconsistency is often the more useful finding than level.
4. Weight by measurement uncertainty: if |value − target| < metric uncertainty, classify Within.
5. Outcome linkage (per bowler, once ≥30 shots): correlate each form metric's deviation with pocket %, carry, target error at arrows/breakpoint, rev rate and speed. A deviation with no outcome link stays informational unless a coach flags it.

## 5. Recommendation engine
Two engines share one evidence store and one prioritizer.

### 5.1 Lane/Ball engine (existing M4 — unchanged core)
Feet/target/parallel moves, speed, launch, ball change. New inputs from Form:
- If a miss is classified EXECUTION_MISS **and** a form finding explains its direction, route it to the Execution Coach: no lane move, form cue instead (DEC-005/006).
- Coaching sources describe directional symptoms we can use as priors: early timing → ball misses outside / never picks up; late timing → pulls inside the target. Confirm per bowler from data before relying on them.

### 5.2 Form engine (new): Finding → Cause → Cue → Drill → Verify
Each rule is a data record:

```
rule_id, version, sources[]
trigger: metric(s), comparison (level|consistency|trend), repetition rule, min confidence, required view/fps
candidate_causes[]: ranked upstream causes, each with a check metric
cue: ≤12 words, spoken-friendly
drill_ref: drill library id
expected_change: metric + direction + rough magnitude
verify: metric to watch over next N shots; success/fail criteria
applicability: styles, step count, handedness
```

**Starter rule catalog (P1/P2 metrics only):**

| Finding | Trigger | Likely upstream causes (check) | Cue / drill | Verify |
|---|---|---|---|---|
| Early timing | Timing at slide: ball ahead of slide vs baseline/target, repeated | Early ball start (ball-start step), short pushaway, slow feet (cadence) | Later or more extended ball start; ball-start drill; faster/forward feet | Timing at slide, backswing peak vs pivot step |
| Late timing | Ball behind at slide; backswing peak after pivot step | Late ball start, short key step, tension/"control" | Get the ball moving with the key step; "get it going" drill | Ball-start step, backswing-peak offset |
| Timing inconsistency | SD of phase splits > baseline band | Variable ball start; variable step 1 | One-step / short-approach drill for repeatable start | Split SD |
| Drift excessive | |finish − start| > 2 boards or > coach tolerance | Ball start direction across body; walking toward target line | Walk to a spot; align feet to target | Drift mean + SD |
| Drift inconsistent | Drift SD > 1 board | Same | Same | Drift SD |
| Short / unstable finish | Hold < baseline or sway > band | Early timing, over-speed, approach too fast | Post the shot until pin hit; balance-hold drill | Finish hold, sway |
| Rhythm inverted | Last 3 steps not quicker than first 2 | Rushing early steps | Slow first steps, accelerate to the line | Cadence ratio |
| Backswing height variance | Apex SD > baseline band | Muscled swing, ball start height varies | Consistent ball start height; free-swing drill | Apex SD |
| Swing line off | Bottom-of-arc offset vs shoulder line > band (rear view) | Pushaway direction | "Place it here" ball-start direction drill | Swing-line offset |

Drills and cues are written in our own words, reviewed against coaching sources, and carry source references in the rule record. **Decided 2026-10-22:** write our own now; owner reviews before publish; coach partner review later.

### 5.3 Prioritizer
Score each open finding: `severity (distance in bands) × confidence × outcome_impact × upstream_weight`, then:
- Coach `focus` flag wins outright.
- Pick one **primary** focus; at most two secondary notes.
- Suppress downstream findings when an upstream finding plausibly explains them (e.g., hide "short finish" while "early timing" is primary).
- Hold a focus for a minimum number of shots (default 10) before switching, to avoid whiplash.

### 5.4 Learning loop
Store `Observation → Recommendation → Followed? → Next N shots → Outcome` (MASTER_CONTEXT §12). Per rule, track success rate per style/stratum; demote rules that don't move their verify metric. Coach thumbs-up/down on a finding is a strong label.

## 6. Data model additions
- `benchmark_reference` (metric, range, units, source, source_quality, applicability, version)
- `style_template` (+ `style_template_metric`)
- `personal_baseline` (bowler, metric, view, fps_tier, slice, median, mad, sd, n, window, computed_at)
- `coach_profile` (bowler, coach, version, effective dates, template_id) + `coach_profile_metric`
- `finding` (shot/session, metric, benchmark_layer, benchmark_version, level_status, consistency_status, confidence)
- `recommendation` (extends M4-06: engine = lane|form, rule_id, rule_version, cue, drill_ref, evidence window)
- `recommendation_outcome` (followed, verify metric before/after, success)
- `form_rule`, `drill` (library, versioned content)

## 7. Phasing
- **MVP (Shot Analysis focus):** L0 + L2 for ball metrics; M4 lane engine with execution routing; style template chosen in bowler profile (rules/labels only).
- **Form P1:** L2 for timing splits, step count/cadence, finish; rules: timing inconsistency, short finish, rhythm. Early/late timing rules after the timing-at-slide metric passes validation (P2).
- **Post-MVP (Coaching tab):** L3 coach profiles, templates, coach cues/drills, coach focus flag, coach review of findings.
- **Later:** data-derived style ranges, per-bowler outcome models, coach-authored rules.

## 8. Rule administration (owner-only)
The fundamentals (L0 references, L1 style templates, the form rule catalog, drill library and prioritizer weights) are **owner-maintained and never shown to bowlers or coaches.**

**What users see vs. what the owner sees**
| Item | Bowler / Coach | Owner (admin) |
|---|---|---|
| Finding + cue + drill | ✓ | ✓ |
| Plain benchmark label ("vs your baseline", "Coach target") | ✓ | ✓ |
| Coach's own targets (L3) | ✓ (coach edits, bowler views) | ✓ |
| L0 reference ranges, sources, source quality | — | ✓ edit |
| L1 style templates | — (bowler only picks a style name) | ✓ edit |
| Rule triggers, thresholds, repetition rules, cause trees | — | ✓ edit |
| Prioritizer weights, baseline N, confidence thresholds | — | ✓ edit |
| Rule performance (success rate per rule/stratum) | — | ✓ view |

**Storage and access**
- Rules live as data in Supabase tables (`benchmark_reference`, `style_template`, `form_rule`, `drill`, `engine_config`) with RLS: read/write for the `rules_admin` role only. No client role can select them.
- The engine (lanesight-core) evaluates rules server-side / in the runner and returns only findings and cues. Rule data never ships in the iOS app bundle or API responses.
- Each published version is also exported to `lanesight-core/rules/*.yaml` in Git for history and diffs.

**Editing workflow**
- States: Draft → Tested → Published → Retired. Only Published rules run for users.
- **Test before publish:** a draft is replayed against the eval set and recent sessions, showing how many findings/recommendations would change, before you publish.
- Every change records author, timestamp, reason and the version id; findings store the rule version they used, so you can roll back.

**Where you edit them**
- **Now (local-first):** a "Rules" page in the local runner listing every rule and reference, with edit, test-replay and publish.
- **Later:** the same page as an auth-protected admin route on the Vercel web app (admin role only), not in the consumer app.

## 9. Decisions (2026-10-22)
1. **Baseline threshold:** 10 qualifying shots per view (owner-configurable).
2. **Form-only clips (no pin result):** all Measured shots qualify for the baseline.
3. **Self-coached target editing:** not in MVP; comes with the Coaching tab.
4. **Style:** bowler picks at setup from one-handed with thumb, one-handed no thumb, two-handed.
5. **Drills/cues:** write our own now from cited sources; owner reviews before publish; coach partner later.
6. **Elite research references:** owner-only in MVP; not shown to bowlers.
