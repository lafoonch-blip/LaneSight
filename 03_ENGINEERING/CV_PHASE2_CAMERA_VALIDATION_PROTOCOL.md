# CV Phase 2 — Controlled Camera-Position Validation (protocol)
Version: 1.0
Last Updated: 2026-10-26
Status: Protocol + harness ready; awaiting Shayne's recordings. Production CV frozen (DEC-062); no ML.
Objective: find the **minimum practical recording setup that reliably supports full-shot analysis**, and the
boundary where analysis degrades to partial. Follows DEC-062 Phase 1 (`02_RESEARCH/CV_PHASE1_VALIDATION_REPORT.md`).

> Phase 1 showed the elevated multi-lane ball-return view can't support far-lane metrics under a single-plane
> homography. Phase 2 tests whether a **lower / squarer** position recovers them, and establishes the floor.

---

## 1. Camera positions (one bowler, one ball, one lane, same session)

| Pos | Setup | Height | Placement | Purpose |
|-----|-------|--------|-----------|---------|
| **A** | Low rear | tripod **2–3 ft** | centered **behind the lane**, square | best-case baseline (expected 🟢) |
| **B** | Mid rear | tripod **4–5 ft** | centered behind the lane, square | practical everyday position |
| **C** | Elevated rear | tripod **5–6 ft** | centered behind the lane, square | isolate elevation (height-only vs A/B) |
| **D** | Ball return | original elevated, **off-axis** | ball-return / settee | negative control (= Phase-1 cohort) |

A→B→C isolate **height** with placement held square-and-centered; D adds the **off-axis** factor. ~**5 shots
per position**. **Record the same shots simultaneously** from all four if possible (same delivery → the only
variable is the camera), else same bowler/ball/lane/oil back-to-back.

**Capture settings (all cameras identical):** 1080p, **120 fps** (rev band + release timing; 60 fps minimum),
**SDR (HDR off)**, locked exposure/focus if available, whole lane foul-line→pins in frame, phone stable.
Keep the **original** files (no AirDrop re-encode); note each clip's position tag in the filename
(`POS_A_shot01.mov`, …).

## 2. The far-lane reference problem (must solve before trusting entry/breakpoint)

Ruby gives speed/rev/loft but **cannot** validate entry board, breakpoint, or board-at-distance (and its
speed definition is unconfirmed — D-4). So Phase 2 needs an **independent far-lane reference**:

1. **Primary — cross-camera reference.** If Position **A** (low/square) passes the 🟢 calibration + observability
   checks, its calibrated trajectory is the **ground-truth entry/breakpoint/board(Z)** for the *same
   simultaneous shot* seen from B/C/D. This is the "independently calibrated footage" reference. (Validate A
   itself against manual landmarks + physical tape marks below before trusting it.)
2. **Physical anchor check.** Before shooting, place **removable tape marks at known boards and distances**
   (e.g. board 10/20/30 at 15 ft and at 40 ft) measured with a tape from the foul line, and record one empty-lane
   framing per position. These give absolute board(Z) truth independent of any camera, and validate A.
3. **Ruby (secondary only).** Speed/rev as a definition-matched cross-check (flag the mismatch; never entry/bp).
4. **Optional — second synchronized camera** at a known pose for a shot subset, as an extra trajectory reference.

Acceptance of a reference: A's reprojection residual < 0.5 board on held-out tape marks AND its mapped tape
boards within ±0.5 board of the tape truth. If A fails this, fall back to tape marks + a 2nd camera.

## 3. What to measure, per position

Run the Phase-1 harness per clip (manual landmarks via the labeler → calibration → reconstruction), and record:

| Metric | How | Acceptance target* (vs reference) |
|--------|-----|-----------------------------------|
| Calibration validity | reprojection residual (boards/ft), held-out residual, longitudinal zones, interval(arrow) consistency | residual < 0.75 board; arrows within USBC band; ≥3 depth zones |
| Far-lane conditioning | sensitivity @entry (boards/px) | **≤ 1.5 boards/px** (so ~0.5 px labeling → <1 board) |
| Ball tracking coverage | fraction of 0–60 ft with detections; last tracked Z | ≥ 90% of 0–55 ft; tracked to ≥ 55 ft |
| Ball speed | definition-matched vs Ruby (release) / cross-camera | **± 0.5 mph** |
| Board at known distance | mapped board vs tape at 15 ft / 40 ft | **± 0.75 board** |
| Entry board | vs cross-camera reference @ declared plane | **± 0.75 board** |
| Entry angle | vs reference @ 52–55 ft window | **± 0.5°** |
| Breakpoint board / depth | vs reference | **± 1 board / ± 2 ft** |
| Metric-eligibility rate | % of metrics passing their per-metric gate | reported per position |

*Targets are development goals (handoff §8) **to validate, not assumed achieved**. Always report the
denominator and the failed-shot fraction.

## 4. Acceptance criteria → per-position classification

A position "supports full-shot analysis" (🟢) when, across its ~5 shots:
- calibration valid (residual + zones + arrow consistency) on ≥ 4/5, AND
- far conditioning ≤ 1.5 boards/px on ≥ 4/5, AND
- ball tracked to ≥ 55 ft on ≥ 4/5, AND
- entry board within ± 0.75 board of the reference (median over shots).

🟡 (partial) when near-lane calibration + early tracking pass but any far condition fails. 🔴 when calibration
is invalid / ball not usably tracked. The classifier (`cv/calib/eligibility.py`) applies exactly these checks
from the real diagnostics — **not** from estimated camera height (Shayne's requirement).

**Expected outcomes to confirm/refute:** A 🟢, D 🔴 (matches Phase 1). B and C locate the **elevation floor** —
the highest centered-square position that still clears 🟢. That height (± placement) is the capture guidance.

## 5. Harness (reuse Phase 1; ready now)

- **Labeling:** `label_server.py` (browser) on each position's plates → verified foul + pins (+ tape marks as
  exact `measured` landmarks where taped).
- **Calibration/diagnostics:** `solve.homography_from_landmarks` + `calibration_diagnostics` +
  `interval_consistency`.
- **Reconstruction + metrics:** `ablation.reconstruct_from_homography`; auto track from `pipeline.analyze`.
- **Uncertainty source:** `ablation.uncertainty_attribution` (landmark vs conditioning vs ball-center).
- **Observability:** `resolution.far_lane_ball_resolution`.
- **NEW classifier:** `cv/calib/eligibility.py` — turns the above into 🟢/🟡/🔴 + per-metric eligibility.
- **NEW runner:** `cv/calib/phase2.py` — ingests position-tagged clips, scores each, emits the comparison table.

Data layout: `~/LaneSightData/phase2/POS_<A..D>/<clip>.mov` + `.../calib/<clip>.{plate.png,landmarks.json}`;
tape truth in `.../tape_marks.json`; cross-camera sync map in `.../sync.json`.

## 6. How Phase 1 informs the Phase-3 capture-quality checks

The 🟢/🟡/🔴 experience (Phase 3) is driven by the **same observability checks**, computed live per shot — not
by camera-height heuristics:
- 🟢 **Full** — calibration valid + conditioning ≤ threshold + ball tracked to the pins.
- 🟡 **Partial** — near-lane calibration + early tracking OK, far conditioning/observability fails → emit
  laydown, early/skid speed, launch, and form; mark entry/breakpoint/late speed `unavailable` with a reason.
- 🔴 **Reposition** — calibration invalid / ball not usably tracked.

This directly supports the product decision to **never reject a whole video**: an elevated ball-return clip
can still yield approach timing, release mechanics, launch position, and early ball speed (🟡). Phase 2 fixes
the thresholds from real data instead of the provisional values above.

## 7. First steps for Claude Code when footage arrives

1. Drop clips under `~/LaneSightData/phase2/POS_*`; generate plates (`ablation.py plate`) + templates.
2. Label foul + pins + tape marks per position in the browser labeler.
3. `python -m lanesight_core.cv.calib.phase2 ~/LaneSightData/phase2` → per-position comparison + classification.
4. Fill the Phase-2 results into this doc; confirm A 🟢 / D 🔴 and locate the B/C elevation floor.
5. Only then (Phase 3) build the capture-quality surface from the validated thresholds.
