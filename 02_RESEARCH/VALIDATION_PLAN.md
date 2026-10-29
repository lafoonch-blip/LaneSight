# Validation Plan: sensors + Specto
Status: DRAFT  
Version: 1.1  
Last Updated: 2026-10-29  
Owner: Shayne

> **DEC-105 (2026-10-29): Ruby is removed from the validation process.** It is no longer a ground-truth /
> accuracy reference. The ongoing gate for CV changes is the **regression baseline** (`ops/perf_benchmark.py` —
> a new run vs a saved reference run, within tolerance) plus **Specto** for absolute accuracy where available.
> The Ruby references below and in `validation/` remain only as historical record. (Ruby as a user-pairable
> sensor, DEC-021, is unaffected.)

Goal: prove every LaneSight metric against an independent reference before it is labeled "Guaranteed" (`01_PRODUCT/METRIC_CAPABILITIES.md`). Each reference covers different metrics, so together they close the gaps.

## 1. References and what each validates

| Reference | Status | Validates (video vs reference) | Can't validate |
|---|---|---|---|
| **Ruby** (in-ball) | In hand; 4 shots done | Speed (timing-based), rev rate, loft; axis/PAP as targets for the future video axis fit | Lane position: laydown, arrows, breakpoint board, entry |
| **Witsee** (in-ball) | Planned purchase | Rev rate, axis tilt/rotation, release speed (vs video **early** speed), swing height (sensor-only) | Lane position |
| **F5 / Storm** (in-ball) | Planned purchase | Rev rate, axis tilt/rotation, release speed (vs early speed), track flare (sensor-only) | Lane position |
| **Specto** (center overhead cameras) | Planned sessions | **The lane-position ground truth:** foul-line board, launch angle, entry board (59.5 ft), entry angle (52–55 ft), entry speed; plus any further points shown in its 10-point view | Rev rate, axis, PAP |

Specto is the only reference for lateral metrics (boards, angles) that the Stage 1 gate depends on. It's the most important session to book.

## 2. Matching metric definitions (do this before comparing)
- **Entry board:** Specto measures at 59.5 ft; LaneSight measures at 59.44 ft (headpin contact). That's a negligible difference, but compare at 59.5.
- **Entry angle:** Specto measures direction between 52 and 55 ft; LaneSight averages the last 1.5 ft. **Add a Specto-compatible entry angle (52–55 ft) to the comparison export.**
- **Launch angle:** Specto uses 0 = straight down lane, positive = toward the headpin. Our sign convention must match.
- **Foul-line board:** Specto calculates the ball back to the foul line (a projection, not the laydown). Compare to our path extrapolated to 0 ft, not to the touchdown board.
- **Speed:**
  - Specto reports entry speed.
  - F5 and Witsee report release speed.
  - Ruby is timing-based.
  - Compare each to the matching LaneSight speed (late / early / average). Never cross them.
- **Rev rate:** each sensor gets its own conversion factor, fitted on half the shots and tested on the other half (blind).

## 3. Session protocol
1. **Record:**
   - A phone on a tripod behind the approach at 1080p/60 (the reference capture).
   - A second phone at 30 fps or handheld, for the capture-tier matrix.
   - When available, Meta glasses: a native recording plus the live stream.
   - At least 2–3 shots per session at 240 fps slo-mo, for rev rate, axis and PAP work.
2. **Sync:**
   - Say the shot number out loud on video, or show it on the phone screen.
   - Screenshot or export every sensor and Specto shot with its timestamp.
   - Keep the sensor app shot numbers (e.g. Ruby #14–#18).
3. **Vary the shots on purpose:**
   - different lines (feet/target)
   - speeds (slow/normal/fast)
   - a few spare shots (10 pin, 7 pin, multi-pin)
   - at least one ball change

   All four shots so far had Ruby breakpoints of 39–41 ft and three were strikes, so variety is what's missing.
4. **Note:** center, lane number, oil pattern (name/length), ball, and the intended target for each shot.
5. **Volume:** 30–50 shots per reference type is the M1-15 Seed Dataset. Hold back 20% as a locked test set.

## 4. Analysis (automated)
- An evaluation harness (M1-14) ingests each reference's export (manual CSV until an API exists) and matches shots by order + timestamp.
- Output per metric × capture tier: MAE, median, p90, bias, failure rate.
- Results update `METRIC_CAPABILITIES.md` (Guaranteed / Best effort) and `VIDEO_VS_RUBY_VALIDATION.md`.
- Cross-checks:
  - Sensor vs sensor (Ruby vs Witsee vs F5 on the same shots) shows how much the references disagree with each other.
  - LaneSight should be judged against that spread, not against one sensor as truth (the shot-4 speed gap, +3.3% vs Ruby, is exactly this question).

## 5. Open items
- **Data access:** confirm what Specto exports (CSV? per-shot screen?) and whether Witsee/F5 export anything beyond app screens (R-02).
- **In-ball sensors:** they require drilling or an insert. Plan which ball each goes in, and log the ball in the arsenal.
- **Specto:** check which local centers have it installed, and whether the center will share the data.
