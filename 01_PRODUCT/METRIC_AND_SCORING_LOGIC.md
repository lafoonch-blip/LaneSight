# Metric & Scoring Logic (current-state register)
Status: CANONICAL
Version: 1.3
Last Updated: 2026-10-22
Owner: Shayne

**Purpose.** One page that states the **current** formula for every LaneSight metric and score, so nobody has to trace the supersession chain in `DECISIONS.md` (e.g. speed is DEC-022 → DEC-030 → DEC-036). 

**Authority.** `00_CONTEXT/DECISIONS.md` is the authority — each row below points to the **governing DEC**. If a formula changes: add a new DEC and supersede the old one in `DECISIONS.md`, then update the one row here. Never let this page and the DECs disagree; if they do, the DEC wins and this page is fixed.

**Status column.**
- **Implemented** = computed in `lanesight_core` today (code path given), validated where noted.
- **Spec-only** = defined in docs, **not yet built** in `lanesight_core`. Do not describe spec-only scores as live.

**No fabricated values.** Any metric/score that can't be measured is `unavailable` with a reason (DEC-026/027/034); weights are never silently re-balanced (DEC-037).

---

## 1. Composite scores (all **spec-only** today — defined, not yet in `lanesight_core`)

### LaneSight Score — `L` (0–1,000) · DEC-038 (supersedes DEC-037 composite)
`L = round(10 × (0.40·S + 0.25·A + 0.25·C + 0.10·P))`, S/A/C/P each 0–100.
- **Inputs:** Performance S (DEC-037 subformula carried forward by DEC-038), Accuracy A (DEC-031), Consistency C (DEC-032), Power & Carry P (DEC-038; **normalization NOT DEFINED**).
- **Status:** **SPEC-ONLY / currently unavailable**: P formula and validation do not exist. Never substitute Impact Energy joules (DEC-024) as normalized P, set P=0, or reweight other components.
- **Gating:** all four components required; baseline ≥10 readable/corrected games, ≥30 valid intent-labeled shots, ≥10 comparable shots, and sufficient validated P inputs (minimum TBD). Missing/unreliable input → “Building your LaneSight Score” or explicit unavailable reason. No invented scores.
- **Windows:** 90-day rolling index, trend vs prior 90-day qualifying window only. Provisional/calibration status until real-world validation.
- **Tiers (provisional):** Bronze 0–399; Silver 400–549; Gold 550–699; Platinum 700–849; Onyx 850–1000. No percentiles without a real sample. Tiers attach to overall qualifying L only.
- **Home:** badge + L + tier + qualified trend + next-tier progress; directly beneath four tiles S 40%, A 25%, C 25%, P 10%, displaying unknown values as unavailable.
- **Standard vs Advanced:** envisioned complementary data-coverage modes, **not yet defined/calibrated score alternatives**. Do not issue Standard-only L on the advanced formula.

### LaneSight Score — `L-dev-0` (0–1,000) · DEC-048 — **dev/Beta build only**
The score **actually used in Dev Build v0 and friends Beta**, because DEC-038's `S` and `P` need pinfall and game scores the dev build doesn't collect (DEC-050). **This is not the target formula — DEC-038's `L` remains the target** and this one never substitutes for it outside dev/Beta. Always labeled **"Beta · dev formula"** in the UI.
`L-dev-0 = round(10 × (0.40·S' + 0.25·A + 0.25·C + 0.10·P'))`, each component 0–100.
- **S′ (performance, no pinfall)** = `0.6 × pocket% + 0.4 × angle%`, where pocket% = share of shots whose **entry board** is in the pocket range (16–19 right-handed, mirrored for left) and angle% = share of shots with **entry angle** in 4–6°. Replaces DEC-037's game-score `S`.
- **A** = Accuracy, DEC-031 (unchanged; see below).
- **C** = Consistency, DEC-032 (unchanged; see below).
- **P′ (power from ball data)** = average of entry speed, rev rate (**only when its DEC-028 band is within target**, else excluded — never the rail value), entry angle and ball weight, each normalized against **owner-editable reference ranges** in `engine_config`. **Carry is excluded** (no pinfall). Replaces DEC-038's undefined `P`.
- **Eligibility floors:** 20 / 20 / 10 / 10 shots (S′ / A / C / P′). Below a floor, that component is Building/unavailable, not 0.
- **Window:** 90-day rolling. **Snapshot on every recompute** with the formula version and inputs (auditable history).
- **No silent reweighting** of the four weights (DEC-037/048).
- **Status:** **Spec-only today**; implemented in `lanesight-core` under BUILD_PLAN **DV-02**. Dev/Beta only.

### Performance index — `S` (0–100) · DEC-037 subformula retained by DEC-038
`S = 0.50 × (avg game ÷ 300 × 100) + 0.25 × strike% + 0.25 × spare-conversion%` (percentages as points, e.g. 62).
- **Inputs:** average game score, strike %, spare conversion % — game statistics (partially implemented). **Status: SPEC-ONLY composite**, provisional weighting, sample/verification gates apply.

### Power & Carry — `P` (0–100) · DEC-038
- **Formula:** **TBD, not approved**; candidate evidence includes measured entry speed, weight/Impact Energy (DEC-024), pocket-hit and carry outcomes, with accuracy and scoring double-counting explicitly audited.
- **Status:** SPEC-ONLY / undefined; **gating:** unavailable until a normalized, validated formula and minimum dataset are approved by a new DEC. Not equivalent to joules.

### Session Score (0–1,000) · DEC-038
- **Formula:** TBD (same four-pillar concept but separate session aggregation/sample eligibility). SPEC-ONLY, unavailable until defined; never grants overall tier.

### Accuracy — `A` (0–100) · DEC-031
Execution vs **intent**; never uses pinfall.
- `arrow error = |actual arrow board − intended arrow board|`; `breakpoint error = |actual breakpoint board − intended breakpoint board|` (geometric breakpoint, DEC-022).
- `arrow score = 100 × max(0, 1 − min(arrow error ÷ 5, 1))`; `breakpoint score = 100 × max(0, 1 − min(breakpoint error ÷ 8, 1))`.
- `A = round(0.60 × arrow score + 0.40 × breakpoint score)`.
- On-target indicator: arrows ≤1 board, breakpoint ≤2 boards. No intended line → "—" ("Set a target line to measure accuracy"), never 0.
- **Inputs:** actual arrow board + breakpoint board (**implemented**, see §2), intended line (user input).
- **Parameters provisional:** the 5- / 8-board scales and 60/40 weights are starting values, validate before release (DEC-031, DEC-034).

### Consistency — `C` (0–100) · DEC-032
Repeatability around the bowler's own center; independent of intent.
- `spread = robust SD = 1.4826 × median absolute deviation`.
- `component score = 100 × max(0, 1 − spread ÷ (3 × target))`; **targets:** speed ≤0.5 mph, rev ≤30 rpm, actual arrow board ≤1 board, actual breakpoint board ≤2 boards.
- `C = equal-weight average of the available components` (an unavailable/too-imprecise component is excluded, never counted as zero spread; show reduced coverage).
- **Window:** 10 most recent comparable shots (same ball configuration + same intended line). <5 → "Building consistency", 5–9 provisional, 10 → normal.
- **Rev excluded** when its capture-adaptive uncertainty (DEC-028) exceeds the 30 rpm target (e.g. ~±40 rpm at 60 fps).
- **Inputs:** per-shot speed, rev, arrow board, breakpoint board (**implemented**, see §2).

### Power → Impact Energy — `E` (joules) · DEC-024
`E = ½ · m · v²`, `m = ball_weight_lb × 0.45359` (kg), `v = entry speed_mph × 0.44704` (m/s).
- **v = entry (pocket) speed**, not the headline ball speed. Example: 15 lb (6.80 kg) at 15.4 mph (6.88 m/s) → ~161 J.
- Calculated only when ball weight is known and entry speed is measured with confidence; else unavailable. **Best effort** until entry speed passes validation (DEC-034).
- Inputs: ball weight (user), entry/pocket speed (`speed_late`, **implemented**, see §2). Translational KE only; ignores rotational energy; not a strike/carry prediction.

---

## 2. Video metrics (**implemented** in `lanesight_core/cv/`)

Headline hierarchy (DEC-035): **Rev Rate · Speed · Accuracy · Consistency**; second row: Breakpoint · Strike % · Power · Entry Angle.

| Metric | Current formula | Governing DEC | Code | Validation (live session vs Ruby) |
|---|---|---|---|---|
| **Ball speed** (headline) | 60 ft foul→pins average: `mph(60 ÷ (t_impact − t_release))`; ball tracked to the pins via far-lane recovery (`extend_forward`) | DEC-036 (←030←022) | `cv/metrics.py` `compute`, `cv/track.py` `extend_forward` | **median 0.52 mph** (at ±0.5 gate); p90 tail = near-field Z-scale (Specto) |
| **Speed — release** (secondary) | early/skid slope velocity (~4–24 ft) | DEC-036 | `cv/metrics.py` | reads ~9 % low from a near-field homography Z-scale residual (Specto) |
| **Entry / pocket speed** (`speed_late`) | path slope near the pins (`Z_IMPACT−15 … +2` ft) | DEC-022 | `cv/metrics.py` | feeds Power (DEC-024) |
| **Rev rate** | surface-pattern periodicity: autocorrelation of ball-crop hue/sat similarity → coarse period, **refined by long-baseline phase coherence** (narrow window, no harmonic jump); lane-rpm × `REV_SENSOR_FACTOR` for sensor-equivalent; **unavailable** when the search hits the band rail; reports a **±band = rev²/(60·fps)** | DEC-027 (rail→unavailable), DEC-028 (fps-adaptive band) | `cv/revrate.py`, `cv/pipeline.py` | **median 14 rpm** (±30 gate); distinct per-shot (snapping fixed) |
| **Entry board** | smoothed board-vs-distance path evaluated at the pins | DEC-031 input | `cv/metrics.py` | recovered by `extend_forward`; needs Specto for board-accuracy gate (DEC-034) |
| **Entry angle** | direction of the smoothed path near the pins (Specto-compatible: 52–55 ft) | — | `cv/metrics.py` | corrected 1.4° → realistic 3.8–5.6° after far-lane recovery |
| **Breakpoint board + distance** | geometric: farthest board the smoothed path reaches, and its distance | DEC-022 | `cv/metrics.py` | (not Ruby's rotational breakpoint — never equated) |
| **Laydown / 7 ft / arrows boards** | smoothed path at 0 / 7 / 15 ft | DEC-022 | `cv/metrics.py` | — |
| **Launch angle** | path direction just past the foul line | — | `cv/metrics.py` | low confidence |
| **Loft** | `early speed × (touchdown − release)` | DEC-022 | `cv/metrics.py` | ±0.45 ft at 60 fps |
| **Pins / strike / leave** | read from the settled deck; **unreadable** (not guessed) when the deck is occluded or the clip ends early | DEC-026 | `cv/pins.py` | occlusion via masking-band correlation |

**Capture-adaptive precision (DEC-028):** every metric's reported precision is derived from the actual fps / camera motion / track coverage, not a fixed figure. Rev is the first instance (band halves at 120 fps, quarters at 240).

---

## 3. Constants & conventions (from `lanesight_core/cv/`)
- `LANE_IN = 41.5` in (board-to-board usable width), `BOARDS = 39`, `BALL_IN = 8.59` in.
- `Z_IMPACT = 59.44` ft = ball centre at first headpin contact (60 ft − (4.30+2.38)/12).
- `mph(fps) = fps × 3600 / 5280`; mph→m/s `× 0.44704`; lb→kg `× 0.45359`.
- `REV_SENSOR_FACTOR = 1.12` (video lane-rpm → Ruby-equivalent; 4-shot calibration, pending blind validation).
- `RELEASE_OFFSET_S = 0.068` s (release precedes the extrapolated foul crossing).
- Rev search band: 4–10 Hz (= 240–600 lane-rpm before the factor).
- Board frame: absolute boards, 1 = right gutter … 39 = left gutter (handedness handled internally).

---

## 4. Validation bar (DEC-034) — none of these advertise "validated" until they pass on the locked set (Seed Dataset + Specto). Current: speed median at gate, rev median at gate, entry board + Accuracy/Consistency pending Specto; the composite scores (including the dev-build `L-dev-0`) are spec-only. Report bias and distributions, not just averages (`examples/score_vs_ruby.py` now gives MAE / median / p90 / bias).

---

## 5. Achievement rules register · DEC-039
Achievements are **not** scoring inputs; their triggers, statuses, tier-independent progress, first-unlock notification, Recent Activity event, and draft catalog live in [ACHIEVEMENTS.md](ACHIEVEMENTS.md). No unlock may modify L, S, A, C, P or tier. All achievement evaluation is **spec-only** until independently implemented and verified; missing data never yields fabricated progress.

## 6. Longitudinal score presentation — DEC-041 (SPEC-ONLY)
- **One score only:** no separate Improvement Score. Show the same qualifying LaneSight Score as a history line, time-filtered changes and personal best; gradual improvement must arise from measured performance, not uploads or achievements.
- DEC-038 formula and all gating remain unchanged; **Power & Carry P is still undefined**, so overall L and tier remain unavailable until validated. Do not create illustrative numeric L in production as if measured.
- Recency-weighted smoothing, baseline comparison windows, minimum eligible samples and tier hysteresis are **TBD**. Preserve prior score snapshots with formula version, eligibility, confidence and date so history is auditable. Missing sensor/form data must not lower ability; never silently reweight the four pillars.
- Form diagnostics and baseline comparisons are **not** fifth-pillar inputs; achievement unlocks never influence score. Existing DEC-038 Onyx range is 850–1000; no approved Legend tier.
