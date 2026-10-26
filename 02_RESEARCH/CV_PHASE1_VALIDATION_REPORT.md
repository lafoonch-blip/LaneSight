# CV Phase-1 Validation Report (geometry proof) — DEC-062
Version: 1.2 (pose-based architecture ADOPTED — DEC-065; §3.6 + §5 added)
Last Updated: 2026-10-26
Status: Phase-1 gate CLEARED. **Pose-based geometry adopted (DEC-065, Shayne 2026-10-26).** Near-to-mid lane
(0–16 ft) is RECOVERABLE and independently validated (held-out arrows in band 12/12; self-cal focal ~1640 px
std 45; near board focal-robust to ≤0.2 board at ±10% focal) — ships as 🟡 partial without mandatory
calibration. The §3.5 near_field_homography path FAILS on real labels (0/17, reproj 16–2,600 boards) and is
replaced by the pose. FAR-lane (40–60 ft) stays `unavailable` — not estimated — until the Phase-2 mid-lane
reference + a real ball-measurement test (the §3.4 "physical limit" sub-conclusion is amended → "unvalidated",
not asserted; §3.1–3.3 far-degeneracy-of-the-homography evidence stands). Capture-position recommendation
still shown for the ungated metrics; ML still frozen (DEC-062). Evidence §3/§3.6; architecture + validation
status §5; three-question answers §4.1.

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

> **Scope of this verdict (Shayne, 2026-10-26):** this establishes a limitation of **this specific camera
> configuration** (elevated, off-axis, multi-lane ball-return) **under the single-plane homography method**,
> on the available visual evidence — NOT that all elevated viewpoints or all reconstruction techniques are
> unusable. A full 3D pose (PnP) using pins as 3D landmarks, or a lower/squarer elevated position, is untested
> and is exactly what Phase 2 evaluates. The product goal remains: extract the maximum accurate information
> from any ordinary phone recording, returning partial results rather than rejecting a video.

## 3. RESULTS — geometry proof on Shayne's verified labels (2026-10-26)

Shayne labeled 15 clips: foul corners + 7 pin spots as exact anchors, plus arrows/dots/approach-dots as
interval checks. **The result is decisive and label-robust: a lane-plane calibration cannot be recovered
from these elevated ball-return views.** Three independent lines of evidence:

### 3.1 The foul+pins homography is degenerate / ill-conditioned

Solving a homography from the verified exact anchors (`_geom_proof.json`):

| Clip | anchors | reproj RMSE (boards) | reproj RMSE (ft) | sensitivity @entry (boards/px) | arrows in USBC band |
|------|---------|----------------------|------------------|--------------------------------|---------------------|
| IMG_8893 | 9 (foul+7pin) | 21.9 | 37.3 | 3.5 | 0/7 |
| IMG_8894 | 9 | 19.4 | 29.7 | 16.1 | 0/7 |
| IMG_8896 | 9 | 35.8 | 49.6 | 1.4 | 0/7 |
| IMG_8897 | 9 | 30.9 | 28.6 | 17.4 | 0/7 |
| IMG_8899 | 9 | 332 | 79 | 2133 | 0/7 |
| IMG_8902 | 8 (pins only) | 13.5 | 0.77 | 8.9 | 0/7 |
| IMG_8903 | 9 | 33.8 | 26.9 | 0.53 | 0/7 |
| IMG_8904 | 9 | 213 | 28 | 94 | 0/7 |
| IMG_8907 | 9 | 589 | 342 | 3.9 | 0/7 |
| IMG_8908 | 9 | 193 | 424 | 1.8 | 0/7 |
| IMG_8910 | 9 | 34 | 30 | 2594 | 0/7 |
| IMG_8895 / 8898 | 9 | — | — | — | findHomography degenerate (collinear) |
| IMG_8900/8901/8905/8909 | <4 | — | — | — | too few exact anchors (foul/pins not labelable) |

Reprojection residuals of **tens to hundreds of boards**, far-lane sensitivity up to **2,600 boards per
pixel**, and **0/7 arrows** landing in their USBC 12–16 ft band on every clip. (A valid homography fits
coplanar points to sub-board residual; this is not label noise — it's the configuration.)

### 3.2 Why — three geometric defects of this camera class (confirmed, not conjectured)

1. **Pins are off-plane.** The labelable pin feature is the pin *body* (~15 in above the lane). A homography
   assumes one plane (Y=0); mixing foul (Y=0) with pin bodies violates it — exactly the handoff's "don't
   treat top-of-pin pixels as lane-plane points." (8902, pins-only, also collapses: all 8 pins sit in a 2.6 ft
   depth band → degenerate, maps every arrow to Z≈61 ft.)
2. **No mid-lane depth anchors.** The only on-plane fiducials that are labelable here — foul (0 ft), approach
   dots (≈ −12 ft), guide dots (≈ 7 ft), arrows (≈ 14 ft) — **all cluster in Z ≈ −12…+16 ft**. A homography
   fit to those extrapolates the 60 ft pins to **160–230 ft** (8907 fully diverges). Nothing anchors the
   16–60 ft lane.
3. **Catastrophic far conditioning.** Even the best-posed clips show ≥3–17 boards of entry error per *pixel*
   of landmark/detection error — and the far ball is only ~5 px with a scale-invariant ±1-board floor of
   ≈0.97 board (§0.1). No achievable labeling or detection precision survives this.

### 3.3 Run A vs Run B (auto track; filling from analyze())

| Clip | A entry (auto geom+track) | B entry (manual foul+pins geom + auto track) | sensitivity @entry (boards/px) |
|------|---------------------------|----------------------------------------------|--------------------------------|
| IMG_8893 | None (auto refuses) | **None** (manual geom can't place entry) | 3.5 |
| IMG_8903 | 22.0 (flagged off-lane) | **None** | 0.53 |
| IMG_8907 | 7.4 (flagged) | **None** | 3.9 |
| IMG_8899 | 14.2 (flagged) | **None** | 2133 |

**Run B returns entry=None on every clip** — a hand-verified foul+pins homography is too degenerate to map
the auto ball track to a valid entry reference, even where the auto pipeline (A) emits a (flagged,
implausible) number. "Correct geometry" from this vantage does not produce a usable far-lane measurement;
it produces no measurement. (Run C — manual ball centers — is moot: with no valid far-lane homography, better
centers cannot be placed on the lane plane. The §0.1 scale-invariant bound already shows even perfect centers
give ≈1–2.4 board lateral error at the pins.)

### 3.4 PnP (3D pose) — confirms it's the position, not the method (2026-10-26)

Phase 1 tested only a single-plane homography. A full 3D camera pose (`cv/calib/pose.py`, solvePnP, pins as
3D points) was tried on the verified labels. The code is verified correct — it recovers a **known synthetic
pose to 0.0 px** and shows a good position (~10 ft standoff, 48 in high, square) is **well-conditioned
(0.33 board/px at entry)**. But on the real ball-return clips PnP returns **physically impossible poses
(camera below the lane)** with ~5 px reprojection, and the fitted pin height collapses to ~0 inconsistently:
the pins' height structure is **unobservable** at that standoff, so there is no 3D information to disambiguate
pose (the planar-ambiguity + unknown-intrinsics failure the review warned about). **A better reconstruction
technique does not rescue this camera position** — the limit is positional. (Bonus: `pose.py` also *estimates*
camera height/standoff/angle from labels — useful for Phase-2/3 classification by recovered pose.)

### 3.5 Partial results — what IS recoverable from these positions (the 🟡 path)

The far lane fails, but the **near lane does not**. A near-field calibration from the on-plane fiducials
(`solve.near_field_homography`: foul Z=0 exact + approach dots / guide dots / arrows at band-midpoint Z — all
painted on the surface, so coplanar, unlike the pins) is well-conditioned where the fiducials bracket the
ball. Per-region board sensitivity (boards per pixel), on the well-labeled clips:

| region | 0 ft (laydown) | 7 ft | 15 ft (arrows) | 40 ft | 59 ft (entry) |
|--------|----------------|------|----------------|-------|----------------|
| typical sensitivity | **0.25** | **0.32** | **0.41** | 0.65 | 0.86 |

0–15 ft is both **precise** (≤0.41 board/px) **and accurate** (INTERPOLATED within the labeled fiducial span,
foul→arrows). 40–60 ft is EXTRAPOLATED beyond the deepest fiducial → locally smooth but **biased** (the same
homography puts the 60 ft pins at 160–230 ft), so it is not trustworthy despite the modest sensitivity number.

**So from an elevated ball-return clip LaneSight can still return** (🟡 Partial): **laydown board, board at
7 ft / arrows (15 ft), early/skid speed, launch angle — plus all form metrics** (form needs no lane calibration
at all). It should mark entry board/angle, breakpoint, and late/full-lane speed `unavailable` with a reposition
reason. This is the data basis for the "never reject a whole video" rule; the region-aware `eligibility.classify`
(`near_calib_valid`) encodes it.

Report columns (filled above/below as runs complete): A entry (auto geom+track), B entry (manual
foul+pins geom + auto track), calibration sensitivity @entry, dominant uncertainty source. Per
`CV_MEASUREMENT_DEFINITIONS.md` there is **no Ruby ground truth for this cohort**, so B is read for
plausibility/conditioning, not against a truth value (D-4).

### 3.6 Fixed near-field run + calibrated-focal pose — CORRECTIONS to §3.4/§3.5 (2026-10-26, pending Shayne)

> **Status: these two findings revise §3.4 and §3.5 and need Shayne's sign-off before the §4 verdict text is
> amended. §3.4/§3.5 above are left intact for history. The near-field-recovery product promise and DEC-062's
> "physical limit" framing both depend on which of these stands.**

Running the near-field path end-to-end on the 17 verified clips (the "fixed" run — `phase2.py --flat`, which
now computes `near_field_homography` and gates it, instead of only scoring the far homography) and
re-examining the PnP pose with the focal treated as a free parameter produced two results that **do not match
§3.4/§3.5**:

**(a) §3.5's near-field homography does NOT hold on the real labels (confirmed, decisive).** The near
homography (foul + dots/arrows at USBC band-midpoint Z) reprojects its own fiducials at **16–2,600 boards**
RMSE on every clip; **near-field calibration is VALID on 0/17** under an honest gate (reproj ≤ 0.75 board +
conditioning + the fiducials must bracket 0–15 ft). §3.5's "0.25–0.41 board/px, precise + accurate" reported
only the *sensitivity* (a local derivative of a globally-wrong fit) and omitted the *reprojection residual*
that exposes the fit as invalid. Residual structure shows why: `approach_dot`s fit at d_ft≈0 while the
guide-dots land ~5 ft shallow (they are foul-line locator dots at Z≈0, not the 6–8 ft guide dots the geometry
assumes) and arrows land 8–11 ft deep — a systematic Z-model mismatch, not label noise, amplified by this
oblique view into ±50-board lateral errors. **So the near_field_homography partial-results path, as written,
yields nothing trustworthy on this cohort.** `eligibility.classify`/`calibration_readiness` now fail it
closed; the runner reports 0/17 🟡 honestly.

**(b) §3.4's "pose doesn't help — positional limit" is too strong for the near-to-mid lane.** §3.4 ran PnP at
the *nominal* focal (2304 px) and read off physically-impossible poses. Treating the focal as a free parameter
(`pose.fit_focal`, reproj-minimizing) changes the picture: the focal that best explains foul+pins is **tightly
consistent across clips — median 1640 px, range 1505–1675, std 45 (n=12)** — i.e. a single calibratable lens
constant, *not* the nominal. At that focal the pose reprojects foul+pins at **<1.7 px**, and the
**independently-labeled arrows (held out of the solve) land in their USBC 12–16 ft band on 11/12 clips (7/7
each)** — genuine cross-validation (`pose.interval_backprojection`). So the 0–16 ft lane **is** geometrically
recoverable from this elevated ball-return position with the correct intrinsics; a better model + the right
focal does rescue the near-to-mid lane.

**Unresolved caveats on (b) — why this is "re-examine", not "reversed":** the focal is *fitted per clip*, not
independently calibrated (the tight cross-clip agreement is strong evidence it is a real constant, but a
one-time checkerboard/known-object calibration on the same phone+capture settings would confirm it); the
recovered camera height resolves *negative* (the planar-PnP chirality / coplanar ambiguity §3.4 flagged — it
reproduces correct lane coordinates but the sign needs resolving); and **there is still no independent
held-out fiducial past 16 ft**, so the pins (the only far anchor) cannot validate themselves and **far-lane
recovery (entry/breakpoint at 40–60 ft) remains unproven** — §3.1–§3.3's far-lane verdict is untouched by this.

**Net for the decision:** the honest partial-results path on this cohort is **form metrics (no calibration) +
the calibrated-focal pose for the near-to-mid lane**, pending a one-time intrinsics calibration — **not** the
near_field_homography, which this run shows fails here. Options for Shayne: (1) accept a one-time phone
intrinsics calibration and make the pose the near/partial path (and run the far-lane test with a mid-lane tape
reference to settle 40–60 ft); (2) keep the capture-reposition recommendation and drop the near_field_homography
promise; (3) both. All reproducible: `python -m lanesight_core.cv.calib.phase2 "<clips>" --flat --no-video`
and `pose.fit_focal` / `pose.interval_backprojection` (tests in `test_calib.py`).

## 4. Phase-1 decision gate (Shayne, 2026-10-25)

| Ablation result | Next action |
|---|---|
| Manual geometry fixes most failures | Automate landmark detection (Phase 2) |
| Manual geometry works, tracking still fails | Improve ball detection/tracking (Phase 3) |
| Manual geometry + manual tracking still errors | Investigate camera resolution, pose, reconstruction (physical limit) |
| All three improve substantially | Begin automated calibration + learned tracking |

**VERDICT (2026-10-26): row 3 — "manual geometry + manual tracking still produces errors → investigate
camera resolution, pose, reconstruction."** The investigation (§3) concludes it is a **physical limit of the
camera position**, not a fixable perception/geometry bug. So the Phase-1 action is **NOT** "automate landmark
detection" and **NOT** ML — it is a **capture-position recommendation** (handoff §13) plus honest
per-metric eligibility: emit near-field metrics where observable, mark far-lane metrics `unavailable` with a
"move the camera lower / square to one lane / foul line in frame" reason. ML development stays frozen.

**Standing rule:** do **not** start training ML models until this gate is cleared. Complete the geometry
proof first. Production CV path stays frozen (DEC-062).

### 4.1 Answers to the three questions (Shayne, 2026-10-25)

**1. Can correct geometry recover accurate ball measurements from elevated camera positions? — NO (for the
far lane).** Even with hand-verified anchors, a lane-plane calibration is degenerate/ill-conditioned from
this vantage (§3.1–3.2): foul+pins give 20–330 boards of reprojection residual and up to 2,600 boards/px of
far-lane sensitivity; 0/7 arrows land in-band on every clip; the near-field on-plane fiducials extrapolate
the 60 ft pins to 160–230 ft. **Near-field** quantities (laydown, early/skid speed, launch angle) may still
be recoverable — they live where the fiducials are — but entry board/angle, breakpoint, and late/full-lane
speed cannot.

**2. Which measurements remain impossible from insufficient visual resolution? — all far-lane / pin-area
metrics.** entry board, entry angle, breakpoint board/depth, late & full-lane speed. Three compounding
causes: the only far anchor (pins) is off-plane + single-depth; the 16–60 ft lane has no on-plane anchor;
and the far ball is ~5 px with a scale-invariant ±1-board floor of ≈0.97 board (§0.1). This is a physical
limit, not a software gap.

**3. What minimum camera-position guidance delivers coaching-grade results?** The camera must see on-plane
lane fiducials spanning the FULL depth and the ball to the pins. Concretely: **down near lane level (not up
on the ball return), squared to a single lane, with the foul line in frame and the downlane range targets
(33–44 ft, which are painted ON the lane) resolvable, ball trackable to the pins.** The elevated, multi-lane
ball-return vantage this cohort used is below the floor for far-lane coaching metrics. (This cohort has no
near-level clip to show the positive contrast directly; the historical IMG_8751–8754 set — accurate entry —
was shot from a lower, squarer position, consistent with this.)

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

## 5. Pose-based architecture adopted (DEC-065) — validation status (2026-10-26)

Per Shayne: proceed with the **pose-based geometry + independent validation**, keep the goal of accurate
analysis from **ordinary phone videos without mandatory calibration**, and **do not promise far-lane metrics**
until the new geometry *and* real ball measurements pass testing. This section records what is built and what
is validated vs pending. Code: `cv/calib/pose.py` (`calibrate`, `plane_homography`, `reconstruct_near`,
`fit_focal`, `interval_backprojection`) and `cv/calib/validate_pose.py`. Additive; production CV frozen
(DEC-062); no ML.

**Architecture.** `pose.calibrate(landmark_set)` solves a 3D camera pose from foul+pins and **self-calibrates
the focal** (fit from the labels; source pluggable explicit > EXIF > fitted — no checkerboard required). It
returns a `PoseCalibration` with the induced **image↔lane-plane homography**, so the existing tested
reconstruction core (`ablation.reconstruct_from_homography`) runs on a pose unchanged. `reconstruct_near`
returns near-lane metrics and forces far-lane outputs `unavailable` with a reason.

**Independent validation on the 17-clip cohort** (`validate_pose.py`, run at the session-median focal):

| signal | result | reading |
|---|---|---|
| self-calibration focal | median **1640 px**, range 1505–1675, **std 45** (n=12) | a consistent lens constant → calibratable without mandatory user calibration |
| pose reprojection (foul+pins) | **< 1.8 px** every clip | the pose fits the exact anchors tightly |
| **near geometry — held-out arrows in USBC 12–16 ft band** | **12/12 clips** | independent check (arrows are NOT in the solve) → near-lane *position* is recovered |
| near conditioning (board/px) | 0.17 @0 ft · 0.22 @7 ft · 0.27 @15 ft | well-conditioned through the arrows |
| focal sensitivity of a near **board** reading, ±10 % focal | **≤ 0.2 board** | near lateral-board metrics are focal-robust → no mandatory calibration needed for them |
| far lane (40–60 ft) | **UNVALIDATED** | no independent held-out fiducial past 16 ft; **not reported** |

**What this validates (ships as 🟡 partial):** near-lane **lateral board** metrics — laydown board, board @ 7 ft,
arrows board — and launch angle, plus all form metrics (no lane calibration). These passed an independent
held-out check on 12/12 clips and are robust to the self-calibrated focal.

**What stays gated (`unavailable`, never estimated):**
- **Near speed / any depth-dependent near metric:** the lateral board is scale-invariant but *depth* (hence
  speed) scales with focal, so near speed carries focal uncertainty — report the band or use an EXIF/known
  focal; do not ship a bare number yet.
- **All far-lane metrics (entry board/angle, breakpoint, late/full-lane speed):** gated until the Phase-2
  mid-lane tape / cross-camera reference confirms the far geometry **and** a real tracked ball reproduces a
  known far position within tolerance (`CV_PHASE2_CAMERA_VALIDATION_PROTOCOL`).

**Honest caveats (reported in code, not hidden):** the focal is a *fit* (consistency across clips is strong
evidence it is a real constant, but a one-time EXIF/known-object confirmation removes the last assumption); the
coplanar foul+pins give a planar-PnP sign ambiguity so the recovered camera height can read negative
(`sign_caveat` — lane coordinates are still correct); and real-ball near reconstruction across the cohort is
pending usable tracks (the production tracker fails lane-detection on this elevated framing — a separate
issue), so near geometry is validated via the arrows, which are real painted features on the ball's plane and
region, with the centroid-precision floor from `resolution.py` (§0.1).

**Next (to lift the far-lane gate):** record the Phase-2 positions with removable tape at known boards/distances
(and/or a synchronized second camera), run `validate_pose.py` + `reconstruct_near`/far against that reference,
and only then promote far-lane metrics from `unavailable` to measured. Until then the app shows the near set
and a capture note for the rest.
