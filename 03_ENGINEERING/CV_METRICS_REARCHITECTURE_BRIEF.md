# LaneSight — CV tracking & metrics: context brief for an outside review
Version: 1.0
Last Updated: 2026-10-25
Owner: Shayne
Purpose: A self-contained briefing to hand to another AI (ChatGPT/o-series) or a CV engineer, asking how to
re-architect ball tracking and metric extraction so it works from ANY phone camera position. No repo access
is assumed — everything needed to reason about the problem is in this document.

---

## 1. What LaneSight is
A mobile app that analyzes a ten-pin bowling shot from **one ordinary phone video** — no sensors on the ball or
lane, no special camera, no calibration ritual. The bowler props a phone somewhere near their lane, bowls, and
the app returns coaching-grade measurements of the shot. Today the video is uploaded to a Mac that runs the CV
pipeline (Python: OpenCV + numpy, no ML yet); results sync to the phone.

### The product promise and the core tension
We want to measure **as many metrics as possible, as accurately as possible, from wherever the phone happens to
be**. The guiding rule is **accuracy over coverage**: a wrong number that drives wrong coaching is worse than an
honest "couldn't measure this." Entry board, for example, decides pocket vs. light vs. high — a 2-board error
flips the advice — so a confidently-wrong entry board is a real failure, not a cosmetic one.

The problem we're trying to solve in this brief: **the pipeline only works well from a narrow range of camera
positions** (roughly: tripod behind the foul line, square to the lane, whole lane in frame). From the casual
positions people actually use — phone on the ball return, elevated looking down the lane, off to one side — it
produces wrong numbers or fails. We think the measurement architecture needs rethinking, not just tuning.

---

## 2. What we measure (target metrics)
Per shot, from the single clip:
- **Ball speed** — full 60 ft foul-line→pins average, plus **speed early vs. speed late** (does the ball slow
  down the lane? a real ball loses ~1–3 mph; "speeding up" is our #1 symptom of a bad depth scale).
- **Ball path** — lateral position in **boards** (1 = right gutter … 39 = left gutter) as a function of
  **distance** (feet from the foul line), i.e. the full trajectory curve.
- **Launch angle** (at release), **entry angle** (at the pins, ~52–55 ft is the coaching-standard window).
- **Entry board** — which board the ball crosses the pins on (pocket is ~board 17.5 for a right-hander).
- **Breakpoint** — the board where the ball is farthest right (for a RH hook) and the distance it occurs.
- **Laydown board** (where the ball touches down), **board at 7 ft**, **board at the arrows (15 ft)**.
- **Rev rate** (ball revolutions/min), **loft** (distance the ball carries in the air before touchdown).
- **Pins standing** after the shot (strike / the specific leave).
- Later: axis rotation, axis tilt, PAP (not yet attempted from video).

We have **ground truth** for a handful of clips from a Ruby bowling sensor (per-shot speed, rev, axis, timing)
plus visual pin reads. On well-framed clips the pipeline matches Ruby within ~0.1 mph on speed and ≤1 board.

---

## 3. The lane is a known, rigid, fully-specified object
This is the biggest asset we are underusing. Regulation ten-pin geometry is exact and fixed:
- Lane length **60 ft** foul line → head pin; width **41.5 in** = **39 boards** (~1.0637 in per board).
- **Targeting arrows** inlaid at **~15 ft** (7 arrows, every 5th board).
- **Guide dots** on the lane surface near **7 ft**; **approach dots** at **12 ft and 15 ft BEHIND** the foul line.
- **Gutters** flank the playing surface on both sides for the full 60 ft — **but the approach (behind the foul
  line) has no gutters.** So the gutters uniquely mark the playing lane, and the **foul line is exactly where the
  gutters begin**.
- **Pins** stand in a known triangle at ~60 ft: 10 pins on spots 12 in apart, base row at 60 ft.
- Range-finder dots, the foul line itself, and the two lane edges are all fixed, known-distance references.

In other words: there are many **world points at known (board, distance) coordinates** visible in almost any
shot of the lane. We currently use almost none of them for calibration.

---

## 4. Current pipeline (stage by stage)
Classical CV, deterministic, OpenCV + numpy. No machine learning anywhere yet.

**(1) Stabilize.** Estimate a per-frame homography to a reference frame (feature matches), build a **median
background plate** of the empty lane, and record total camera motion (px). Handheld jitter is removed; a panning
or bumped camera is flagged by large motion.

**(2) Detect the lane** (from the background plate):
- Threshold "lane-colored wood" in HSV (hue ~5–25, saturation > ~105, value > 70). *Just added:* if that finds
  nothing (pale blonde maple reads low-saturation), retry at saturation floors 70 then 50.
- Per image row, find wood "runs"; link runs across rows into left/right **edge lines** modeled as `x = a*y + b`
  (robust fit).
- Solve a **single vanishing point** shared by all edges (least squares), keep only lanes whose edges agree.
- Fallback for pale lanes: seed edges from the **dark gutter → wood boundary** (RANSAC) instead of wood color.
- **Foul line** = the **near (bottom) boundary of the lane-wood mask**, fit as a line across the lane.

**(3) Calibrate = ONE planar homography** (`cv2.getPerspectiveTransform`) from exactly **4 image points**:
- the two **foul-line corners** → world (0, 0 ft) and (41.5 in, 0 ft);
- a far **"impact cross-line"** at **Z ≈ 59.4 ft**, whose image is *synthesized*: it passes through the ball's
  extrapolated position at impact and through the lane's horizon (built from the vanishing point), intersected
  with the left/right edge lines → world (0, 59.4) and (41.5, 59.4).
- This maps image → lane plane: **X = inches from the left edge, Z = feet from the foul line.**
- The ball's impact image position is extrapolated along the track; the vertical coordinate is extrapolated in
  `u = 1/(row − vp_y)`, which is projectively linear in distance.

**(4) Track the ball.** Background-difference blobs inside the lane ROI (warp each frame to the plate, diff,
connected components), link blobs into a track using vanishing-point + motion consistency, **extend backward**
(to catch loft/airborne frames) and **extend forward** ("far-lane recovery" toward the pins), and **detect
impact** when the ball reaches the pin-deck ROI.

**(5) Compute metrics.** Map the pixel track to (X, Z) via the homography. `board = X/41.5*39`. Fit board-vs-Z;
infer handedness from the late hook direction. **Speeds** are linear fits of Z vs. time over windows (early
~4–24 ft, late ~45–60 ft). **Breakpoint** = minimum board over 15–55 ft. **Entry board/angle** evaluated at
Z = 59.4 ft (only if the track reaches past ~56 ft). **Rev rate** from the periodicity of the ball's surface
pattern across frames (frame-rate-limited at 60/120 fps). **Loft** = early-lane speed × (touchdown − release).
**Pins** read by projecting the known pin spots through the homography and checking white-pixel ratios in a
settled post-impact frame (with occlusion recovery).

**(6) Plausibility gate** (just added, our stopgap): mark the far-lane metrics unreliable and refuse to give
advice when **late speed > early speed**, when the path **jumps > 3 boards** between neighboring samples, or when
**entry/breakpoint computes off the lane** (outside 0–40 boards). Also a hard stop if computed speed > 30 mph
(physically impossible → the ball was lost in the back half and the distance scale is garbage).

---

## 5. The core architectural weakness
**The homography is anchored at only two depths — the foul line (Z=0) and a far line that is itself *estimated*
from the vanishing point plus the ball's position — with no real downlane references in between.** A planar
homography is only as good as its correspondences, and here the far anchor is a guess. So:
- If the camera isn't roughly behind the foul line and square, the vanishing point and the synthesized far line
  are off, and **depth (feet) is mis-scaled** — compressed near, stretched far — which corrupts every
  distance-dependent metric (entry board, entry angle, breakpoint, late speed).
- The **foul line is taken as the near edge of the wood**, which is wrong whenever bare approach wood is in the
  frame (it's the same color as the lane and has no gutters to separate it).
- The ball is a **sphere whose center sits ~4.3 in ABOVE the lane plane**; we back-project the centroid as if it
  were on the plane. For low/close cameras this parallax adds a distance error that grows with viewing angle.

---

## 6. Observed failure modes (evidence)
**17 recent amateur clips** (1080×1920 portrait, 60 fps, SDR, pale maple lanes), phone propped in various casual
spots. With the old code **all 17 failed** (pale wood below the saturation threshold). After the pale-lane +
plausibility fixes:
- **3/17 produced trustworthy metrics** — these were shot **near lane height**, square-ish, foul line and the
  whole lane in frame (e.g. entry board 14.2 / 18.7 / 20.0, speeds that slow correctly down the lane, correct
  strike reads).
- **6/17 flagged implausible** — e.g. entry board computed as **45 (off a 39-board lane)** from an elevated
  angle; "speeds up down the lane"; impossible 34 mph; one clip with ~14,000 px of camera motion.
- **8/17 couldn't be read** — "**pin impact not detected**" (ball faded/blurred before the pins, 4 clips);
  "**foul line not found**" (bare approach wood ran into the lane, 2 clips); lane edges didn't form a consistent
  vanishing point; degenerate geometry from an awkward angle.

**Patterns:**
- **Camera height / foreshortening dominates.** Elevated "looking down the lane from the ball return" crushes 60
  ft into a thin vertical band → far-lane depth resolution collapses → entry board lands off the lane.
  Interestingly, a *close side view* with the bowler filling half the frame still worked, because it was near
  lane level — so it's foreshortening, not left/right offset, that kills us.
- **Approach vs. lane confusion.** When the phone sits on/behind the approach, the foul line isn't the near edge
  of the wood, and detection either fails or anchors in the wrong place.
- **Back-half ball loss.** The ball blurs/fades or gets lost in lane clutter before the pins, so impact (our
  60 ft reference) is never found and the whole shot is lost.
- A separate earlier case: a **close, off-axis** clip tracked the ball correctly in pixels but the depth mapping
  put entry at board 10.5 instead of ~17–18 and made late speed 19.4 > early 15.8 — same root cause (the two-
  point homography), different framing.

---

## 7. Constraints & resources
- Runtime: OpenCV, numpy, and small PyTorch models are all fine (runs on a Mac; cloud later). Per-shot latency of
  a minute or two is acceptable.
- We can **collect and label our own clips** (we control the data) — multiple centers, lane colors, phone
  positions, 60 and 120 fps, portrait and landscape.
- We have **sensor ground truth** (Ruby) for some clips: speed, rev rate, axis, release timing — usable to
  validate and even to supervise a model.
- Determinism matters for trust (same clip → same numbers); current output can drift slightly between runs of
  the same file, which we also want to fix.

---

## 8. What we're asking you
Please critique the current design and propose a more robust architecture for **measuring the metrics in §2 from
an arbitrary single-camera phone position.** Be concrete and opinionated about the approach, the build order, and
the accuracy/robustness tradeoffs.

1. **Calibration/geometry.** Should we replace the single two-point homography with a calibration that detects
   **multiple known lane fiducials** (arrows at 15 ft, dots at 7/12/15 ft, pin spots at 60 ft, gutter lines,
   foul line, lane edges) and solves a **full homography or camera pose (PnP)** from them, so the camera can be
   anywhere? How would you make that robust — which fiducials are most reliably detectable, how few points can
   we get away with, RANSAC vs. optimization, and how to **self-check** the fit (reprojection residuals, known
   cross-ratios) so we *know* when to trust it vs. fall back to "unknown"?
2. **Ball-above-plane parallax.** How should we handle the ball center being ~4.3 in above the lane plane when
   back-projecting the track to the surface, especially for low/close cameras where the error is largest?
3. **Robust ball tracking** through the back-half fade and to impact — classical (appearance model + Kalman +
   optical flow, motion priors) vs. a small learned detector/tracker. What would you build first?
4. **Where ML earns its place vs. classical CV:** lane/gutter/arrow/pin **segmentation or keypoint detection**,
   ball detection/tracking, pin counting. What's the **minimal, highest-leverage** model to train, and roughly
   what quantity/kind of labeled data would it need?
5. **Approach vs. playing-lane disambiguation** — the gutters are the signal (the foul line is where they begin);
   how would you make this bulletproof across lane colors and camera heights?
6. **Prior art** — papers/datasets/techniques for single-uncalibrated-camera sports-surface homography, 3D ball
   trajectory reconstruction, or pin/keypoint detection we should build on.

When you answer, assume we'll implement in Python and want a staged plan: what to build first for the biggest
robustness gain, what to validate it against, and where to draw the "refuse rather than guess" line.

---

## 9. (If images are attached)
We can attach frames: a **working** clip (near lane level, foul line visible), an **elevated** failure (lane
crushed to a thin band), and an **approach-on-the-near-side** failure (bare approach wood runs into the lane).
Please use them to ground your recommendations in what's actually visible.
