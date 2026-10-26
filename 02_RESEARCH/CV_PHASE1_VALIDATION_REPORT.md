# CV Phase-1 Validation Report (geometry proof) — DEC-062
Version: 0.1 (SCAFFOLD — A column + framing finding filled; B/C pending labeling)
Last Updated: 2026-10-25
Status: In progress. This is the report that decides which architectural investment pays off (handoff §10).
Fills in as labeling + the A/B/C/D ablation run. The **framing finding** below already changes the Phase-1
plan and is the most important thing in this file today.

Related: `03_ENGINEERING/CV_REARCHITECTURE_RESPONSE_2026-10-25.md` (plan), `CV_MEASUREMENT_DEFINITIONS.md`
(score against these), `TRAINING_CLIPS_2026-10-25_pale_lanes.md` (the Run-A baseline narrative).

---

## 0. Headline finding — the real camera framing breaks a premise of the plan

I rendered the stabilized background plate for all 17 clips and inspected four spanning every outcome class
(IMG_8902 works, IMG_8893 elevated-fail, IMG_8900 foul-not-found, IMG_8907 false-34-mph). **All four show
the same vantage, and it is not the one the pipeline assumes:**

- The phone is at the **back settee / ball-return**, held up and **elevated**, looking **across many lanes**
  (lane numbers 31–40 are visible along the pin deck), not squared-up behind a single lane.
- The near ~40–50% of every frame is the **approach** (behind the foul line), not the playing lane. The
  playing lane's 60 ft is **compressed into a thin upper band**; a ball-return track crosses right where the
  foul line should be — which is exactly why foul detection fails (IMG_8900/8908).
- **Mid-lane arrows (15 ft) and guide dots (7 ft) are at best marginally resolvable** — they sit in the most
  foreshortened band. **Approach dots (behind the foul line) are often the best-resolved fiducials in frame.**
- The **pin deck (60 ft) is visible but small** (pins ~5–15 px tall depending on elevation).

**Why it matters (updates response §4 / §5):** the Phase-1 plan assumed we'd anchor calibration on arrows +
dots + pin spots across ≥3 longitudinal zones. For *this* camera class those mid-lane anchors are largely
absent. The realistically available anchors are **approach dots (≈ −12..−15 ft) + foul line (0 ft) + lane
edges/gutters (continuous) + pin deck (60 ft)** — a long baseline with a **large unobserved mid-lane gap
(≈15–55 ft)**. Consequences to carry into B/C:
- **Breakpoint (the mid-lane turn) will usually be censored** — correct behavior, not a failure.
- **Entry board (near the pins) may still be recoverable** if the pin-deck end is well-anchored.
- **The solver and labeling should treat approach dots + pin spots as primary**, not arrows. (Already
  reflected: approach-dot landmarks added to `lane_geometry`.)
- This also reframes the *product* answer: for elevated ball-return framings, the honest output may be
  "approach/early metrics eligible, pin-area board precision limited" + a capture nudge to get lower / put
  the foul line in frame — exactly the camera-position-aware behavior in handoff §13.

> Caveat: 4 of 17 inspected directly; the pattern was uniform. The per-clip table below marks camera class
> for all 17 from the plates + the Run-A narrative; confirm each during labeling.

---

## 1. Run-A baseline (existing auto geometry + auto track)

Re-confirmed the `run_A` wiring end-to-end via `cv.calib.ablation` on cached stabilizations:
- **IMG_8902** → ok, `entry_board@59.44 = 18.4`, `ball_speed = 17.2`, strike. (positive control)
- **IMG_8893** → ok but `entry_board = None` (far-lane read refuses to place entry), `ball_speed = 14.3`.

Full A column for all 17 is in `TRAINING_CLIPS_2026-10-25_pale_lanes.md` (3 analyze / 6 flagged / 8 fail).
To regenerate deterministically: `python -m lanesight_core.cv.calib.ablation A "<clip>.MOV" <out> --handed R`.

## 2. Per-clip triage (camera class + labelability + priority)

Outcome from the Run-A narrative. "Labelability" = how reliably a human can place the geometry fiducials on
the plate. Priority = value of labeling it for the B/C gate.

| Clip | Run-A outcome | Camera class | Foul visible | Arrows/dots | Approach dots | Pins | Labelability | Priority | Expected Run-C ceiling |
|------|---------------|--------------|--------------|-------------|---------------|------|--------------|----------|------------------------|
| IMG_8899 | analyze (strike) | ball-return | marginal | low | yes | small | med | ctrl | good near, censored mid |
| IMG_8902 | analyze (strike) | ball-return (lower) | marginal | low | yes | small | **med-high** | **ctrl ✓viewed** | good near+entry |
| IMG_8904 | analyze (move) | ball-return | marginal | low | yes | small | med | ctrl | good |
| IMG_8893 | entry off-lane/None | ball-return **elevated** | no | ~none | yes | tiny (~5px) | low | **high ✓viewed** | likely UNOBSERVABLE far-lane |
| IMG_8895 | flagged (off-lane) | ball-return | marginal | low | yes | small | med | **high** | test geometry fix |
| IMG_8903 | flagged (off-lane) | ball-return | marginal | low | yes | small | med | **high** | test geometry fix |
| IMG_8896 | flagged (short/slow) | ball-return | marginal | low | yes | small | med | high | tracking-limited? |
| IMG_8901 | flagged (14k px "motion") | **stabilization diverged** | n/a | n/a | n/a | n/a | n/a | low | invalid input — exclude or re-stabilize |
| IMG_8907 | flagged (34 mph) | ball-return | marginal | low | yes | small | med | **high ✓viewed** | scale error — geometry should fix |
| IMG_8894 | fail: no impact | ball-return | marginal | low | yes | small | med | med | tracking (back-half) |
| IMG_8897 | fail: no impact | ball-return | marginal | low | yes | small | med | med | tracking |
| IMG_8898 | fail: no impact | ball-return | marginal | low | yes | small | med | med | tracking |
| IMG_8910 | fail: no impact | ball-return | marginal | low | yes | small | med | med | tracking |
| IMG_8900 | fail: foul not found | ball-return (approach-heavy) | **no** | low | **yes** | small | med | **high ✓viewed** | geometry (approach-dot anchor) |
| IMG_8908 | fail: foul not found | ball-return (approach-heavy) | no | low | yes | small | med | high | geometry (approach-dot anchor) |
| IMG_8905 | fail: no VP edges | ball-return | marginal | low | yes | small | med | med | geometry |
| IMG_8909 | fail: lane ROI empty | ball-return | marginal | low | yes | small | med | med | geometry |

**Suggested labeling order** (your #1 priorities, intersected with value): the **plausible-but-wrong**
clips first — **8907 (34 mph), 8893 (elevated/off-lane), 8895, 8903** — then the **foul-not-found** pair
**8900/8908** (test the approach-dot anchor), then the **positive controls 8902/8899/8904**, then the
no-impact group. **Exclude or re-stabilize 8901** (the "14k px" is the stabilizer diverging, not motion).

## 3. Ablation results (B/C — PENDING LABELING)

Fill per clip after labeling. Score against `CV_MEASUREMENT_DEFINITIONS.md` (resolve D-1..D-5 first).

| Clip | A entry | B entry (manual geom) | C entry (manual geom+centers) | Ruby/true | B−true | C−true | Calib sensitivity @entry (board/px) | Verdict |
|------|---------|-----------------------|-------------------------------|-----------|--------|--------|-------------------------------------|---------|
| … | | | | | | | | |

Report, per camera class and longitudinal region: calibration success; reprojection + held-out residuals;
ball recall + center error; board error; entry/angle/breakpoint error; metric-eligibility rate; CI coverage;
reproducibility; runtime; and **always the denominator + failed-shot fraction**.

## 4. Phase-1 decision gate (Shayne, 2026-10-25)

| Ablation result | Next action |
|---|---|
| Manual geometry fixes most failures | Automate landmark detection (Phase 2) |
| Manual geometry works, tracking still fails | Improve ball detection/tracking (Phase 3) |
| Manual geometry + manual tracking still errors | Investigate camera resolution, pose, reconstruction (physical limit) |
| All three improve substantially | Begin automated calibration + learned tracking |

**Standing rule:** do **not** start training ML models until this gate is cleared. Complete the geometry
proof first. Production CV path stays frozen (DEC-062).

## 5. Open items blocking a verdict

- Ground-truth labeling (landmarks on 17; ball centers on the failing ones). Plates + templates ready in
  `10-25 training videos/calib_landmarks/` (all 17). Needs a human/tool — not auto-generated.
- Measurement definitions D-1..D-5 (`CV_MEASUREMENT_DEFINITIONS.md`): ratify D-1/2/3; get Ruby def (D-4) +
  USBC edition (D-5).
- Decide handling of IMG_8901 (re-stabilize vs exclude as invalid input).
