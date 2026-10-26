# CV Phase-1 Validation Report (geometry proof) — DEC-062
Version: 0.3 (SCAFFOLD — A + framing + observability + tooling + gate questions + uncertainty attribution; B/C pending labeling)
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

## 0.1 Far-lane observability — answers the ±1-board question (before labeling)

Shayne's additional consideration: is the ball big/sharp enough near the pins to localize its board to
±1 board? The rigorous result (`cv/calib/resolution.py`) is **scale-invariant** — it does not depend on how
many pixels the lane spans, because the ball image and the board width both scale with pixels-per-foot:

> **lateral board error ≈ k_centroid · (BALL_IN/LANE_IN) · BOARDS ≈ k_centroid · 8.07 boards.**
> Clean, sharp, well-segmented ball (k≈0.12) → **≈0.97 board.** Blurred/small/occluded ball (k≈0.30) → **≈2.42 boards.**

**So ±1 board at the pins is only achievable with a sharp, cleanly-segmented far ball AND valid far-lane
calibration. Under realistic back-half blur it is not — and more pixels do not fix it;** pixel scale governs
only whether the ball is big enough to *detect* at all. This is a strong prior for the decision gate: if
Run C can't reach ±1 board on the clean clips, it's a physical limit → **capture-position recommendation**,
not more CV. (Per-clip pixel-scale context is in `calib_landmarks/_resolution_summary.json`, but note it's
measured at the end of the *detected* lane region, which on foreshortened clips is short of the true pins and
thus over-states the pin-area ball size — we do not claim per-clip resolvability from it.)

## 0.2 Tooling built (Option B + verification tool) — ready for labeling

- **Auto-prefill** (`cv/calib/autofill.py`): foul-line endpoints from the existing `find_lanes` + best-effort
  approach dots, all marked **`suggested` (UNVERIFIED)** with source + confidence. Ran on all 17:
  **15/17 got foul suggestions** (8895 also an approach dot); **8900/8901/8908 produced none** (find_lanes
  fails — foul off-frame / no saturated wood), which is itself the signal those need manual foul labeling.
- **Verification tool — two front-ends, same schema + safeguards** (original-pixel storage, verified-only
  calibration, merge never clobbers verified, suggested amber vs verified green):
  - **Browser (recommended, reliable):** `python -m lanesight_core.cv.calib.label_server "<…>/calib_landmarks"
    --autofill` → open `http://localhost:8765/` in Chrome. Stdlib http.server; renders everywhere. (opencv
    5.0.0's cv2 Cocoa window is unreliable on macOS — the browser tool is the dependable path.)
  - **cv2 (fallback):** `python -m lanesight_core.cv.calib.label_tool "<…>/calib_landmarks" --autofill`.
- Suggestions written into each `calib_landmarks/<clip>.landmarks.json` (merged over the templates; no
  verified work exists yet to clobber).

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

### 4.1 Three questions this report must answer (Shayne, 2026-10-25)

1. **Can correct geometry recover accurate ball measurements from elevated camera positions?** → the B
   column (manual geometry + auto track) vs truth, split by camera class (near-level vs elevated).
2. **Which measurements remain impossible from insufficient visual resolution?** → the C column (manual
   geometry + manual centers): a metric C still can't hit is resolution-limited, not CV-fixable. The
   far-lane observability result (§0.1) already predicts breakpoint + pin-area board are the hardest.
3. **What minimum camera-position guidance delivers coaching-grade results?** → derived from which camera
   class first clears the per-metric gates (e.g. "foul line in frame + camera below ~X ft elevation").

### 4.2 Uncertainty attribution (answers "where does the error come from")

`cv/calib/ablation.uncertainty_attribution()` decomposes entry-board uncertainty into the three sources, so
we invest where it actually binds:
- **landmark placement** — Monte-Carlo jitter of the verified landmark pixels → re-solve → Δentry std.
- **calibration conditioning** — the solved per-pixel sensitivity at the entry reference × labeling σ.
- **ball-center localization** — jitter of the ball centers, floored by the scale-invariant centroid bound
  (§0.1). *If this dominates, the limit is resolution/capture — a camera-position recommendation, not more
  labeling or calibration.*

Run per clip alongside B/C; report the dominant source. This is the signal that tells us where Phase-2+
investment belongs.

## 5. Open items blocking a verdict

- **Verify the auto-suggested landmarks** in the label tool for the **first six priority clips** (8907,
  8893, 8895, 8903, 8900, 8908), adding pins + any missing points. Tooling + suggestions are ready
  (`calib_landmarks/`). Then run B/C on those six — **do not wait for all 17** (Shayne's Step 4).
  **Guidance (Shayne): do not force a barely-visible landmark — mark it ambiguous (`b`) or not-visible
  (`v`).** We're testing whether the video HAS the information, not manufacturing a calibration. Interval
  landmarks (arrows/dots) are consistency checks only; exact anchors are foul + pin spots.
- Hand-label ball centers on the failing clips for Run C (the label tool can be pointed at per-frame crops;
  for the first pass, Run B uses the existing auto track so B can run immediately after geometry verify).
- Measurement definitions D-1..D-5 (`CV_MEASUREMENT_DEFINITIONS.md`): ratify D-1/2/3; get Ruby def (D-4) +
  USBC edition (D-5) — needed before B/C errors are read as accuracy.
- Decide handling of IMG_8901 (re-stabilize vs exclude — find_lanes finds no wood; likely invalid input).

**After the six clips are verified and B/C run, STOP at the §4 gate before expanding development** (Shayne).
