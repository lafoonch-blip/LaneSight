# Training Videos 2026-10-20: Calibrated Metrics (v2)
Status: RESEARCH RESULTS (prototype; not yet in lanesight-core; no Ruby ground truth for these shots)
Version: 2.0
Last Updated: 2026-10-21
Supersedes: the shot/footwork parts of `TRAINING_VIDEOS_2026-10-20_ANALYSIS.md` v1.0. Its swing-timing table still stands.
Note: copied into the repo from the claude.ai Project on 2026-10-22. The prototype scripts (`marks.py`, overlay renderer, calibration fits) ran in claude.ai sessions and are **not** in the repo; reproduce them in `lanesight-core`.

## What changed
v1 treated the frames as pictures. v2 measures them on a calibrated floor plane built from known bowling dimensions.

**Calibration inputs per clip:**
- Foul-line corners: lane width 41.5 in = 39 boards.
- The 12 ft approach-dot row: dots on boards 5–25, spaced 5 boards.
- The pin deck: front-pin base row at about 61 ft.

**How well it fits:**
- **All three references agree to ≤1.4 in on every clip.**
- Independent check: fitted on the foul line and dots alone, the calibration predicted the pin deck's lateral position to within about 3 px.
- Hypothesis test: putting the dots at 15 ft instead of 12 ft roughly triples the fit error, so 12 ft is right.
- The approach is the same plane as the lane, so feet get real board and distance positions too.

**Three corrections found along the way:**
1. **Ball contact point.** The pipeline's ball track already *is* the floor-contact point. v1 added a radius on top of that, which shifted every position toward the camera and made speed read 1–2 mph low.
2. **Loft artifact.** Just after release the ball is still dropping, and that hides part of its forward motion in the image. Speed is therefore measured from 4 ft onward.
3. **Far-end calibration.** Without the deck constraint the far end was off by 6–9 ft. That is the cause of the "late speed faster than early speed" contradiction.

**Debug overlays:** `overlay_45/46/47/48.mp4`. They show the projected board grid, distance lines, skeleton, detected foot plants (distance and board), and the ball floor-contact track (distance and board) on every frame.

## Approach and footwork (calibrated, rear view)
| Metric | 8845 (120 fps) | 8846 (30) | 8847 (60) | 8848 (60) | Read |
|---|---|---|---|---|---|
| Stance, left foot | 11.5 ft · bd 24.4 | 11.5 ft · bd 25.6 | 11.6 ft · bd 26.8 | 11.9 ft · bd 25.2 | Stance at the 12 ft dots |
| Stance, right foot | 12.4 ft · bd 19.1 | 12.5 ft · bd 18.7 | 12.9 ft · bd 20.8 | 12.7 ft · bd 19.9 | |
| Steps | 4 | 4 | 4 | 4 | R-L-R-L(slide); frame-verified |
| Step landing intervals | 0.37, 0.41, 0.64 s | 0.37, 0.37, 0.57 | 0.37, 0.40, 0.58 | 0.43, 0.37, 0.60 | Last = time to the slide-foot plant |
| First step → release | 1.47 s | 1.42 s | 1.47 s | 1.45 s | Very repeatable |
| Slide-foot plant → release | 0.05 s | 0.12 s* | 0.12 s | 0.05 s | Release synchronization |
| Finish, slide toe to foul line | 15.9 in | 16.2 in | 13.2 in | 18.1 in | Finishes 13–18 in behind the line |
| Finish board (slide foot) | 21.1 | 23.4 | 23.9 | 22.5 | |
| **Drift** (slide foot, stance → finish) | **−3.3** | **−2.2** | **−2.9** | **−2.7** | ~3 boards right every shot (USBC: ≤2 is fine; consistent direction) |
| Approach length (stance → finish) | 9.9 ft | 10.0 | 10.3 | 10.2 | |
| Average approach speed | 5.5 ft/s | 5.7 | 5.7 | 5.7 | |
| Slide length | ~2 in | (17 in)† | (17 in)† | ~1 in | Short slide; landing frame blurred |

\* 30 fps: ±1 frame = ±33 ms.

† On 8846 and 8847 the chosen landing frame caught the foot still moving, so treat slide length as **unresolved**. All four finishes show the foot stops 1.3–1.7 ft behind the foul line, within a few inches of where it lands.

## Body position at release (rear view, projected)
| Metric | 8845 | 8846 | 8847 | 8848 |
|---|---|---|---|---|
| Slide-knee flexion (est.) | 61° | n/a‡ | 57° | n/a‡ |
| Spine lateral tilt (toward bowling side) | 34° | 36° | 44° | 35° |
| Hip line tilt | 28° | 31° | 48° | 31° |
| Head vs slide foot (toward bowling side) | 11.0 in | 13.4 | 16.5 | 11.3 |
| Head movement, top of backswing → release (lateral / vertical) | 2.9 / −2.9 in | 1.3 / −2.3 | 2.9 / −1.8 | 2.5 / −1.8 |
| Ball laydown vs slide foot (lateral) | 11.4 in | 12.3 | 11.8 | 11.4 |

**Knee method:**
- Thigh and shin lengths are measured in inches while standing, using the floor scale at the feet: thigh about 17–18 in, shin about 15–17 in.
- At release, each segment's foreshortening gives its lean. Flexion = thigh lean + shin lean.
- Accuracy is ±10–15°. Good for shot-to-shot comparison; the absolute value needs a side view.

‡ The hip, knee and ankle weren't all visible with enough confidence at release.

## Ball path (calibrated)
| Metric | 8845 | 8846 | 8847 | 8848 |
|---|---|---|---|---|
| Speed 0–15 ft | 17.9 mph | 17.9 | 18.0 | 18.0 |
| Speed 15–30 ft | 16.7 | 17.3 | 18.1 | 18.1 |
| Speed 30–45 ft | — | 18.2 | 16.8 | 17.9 |
| Average foul → headpin (frame-verified impact) | 17.8 | — (impact not verified) | 17.8 | 16.7 |
| Laydown board | 10.4 | 11.8 | 12.8 | 11.8 |
| Board at arrows (15 ft) | 6.2 | 8.5 | 9.9 | 5.7 |
| Breakpoint | — (tracked to 31 ft) | bd 7.5 @ 34 ft | bd 7.6 @ 23 ft | bd 2.5 @ 35 ft§ |
| Entry board / angle | — | 17.2 / 4.6° | 20.2 / 4.8° | §12.0 / 1.3° |
| Pins (video) | deck blocked by bystander | 2 pin | 10 pin | strike ✓ |

**What the ball numbers show:**
- Speed is now physically consistent: about 18 mph off the hand, slowing to 16.7–17.8 mph average.
- The 45–60 ft segment still reads low (~15 mph) on 8847/8848 because the pipeline's far-lane track lags the ball (§).

§ IMG_8848's far track stalls at 52 ft and then jumps, so its breakpoint and entry are unreliable. This is a tracker problem, not calibration.

**Uncertainty (no ground truth for these shots):**
- Speed about ±0.5 mph.
- Near boards about ±0.5.
- Far boards and entry about ±2 boards.
- Footwork positions about ±0.3 ft (MediaPipe foot points).

**Next step:** capture new sessions with Ruby running.

## Swing timing (unchanged from v1)
| Metric | Session mean |
|---|---|
| Backswing | 0.78 s |
| Downswing | 0.40 s |
| Ball at hip → release | 1.21 s |
| Tempo | 0.51 |
| Backswing height | about shoulder height |

## What to port into lanesight-core (after review)
1. **Floor calibration from multiple references** (foul corners + approach dots + pin deck, least squares), with the fit residual stored as calibration quality. This also makes the low-camera framing work where the automatic lane finder currently fails.
2. **Use the ball contact point as-is.** Measure speed from ≥4 ft (loft artifact). Validate with average ≤ release speed.
3. **Far-lane tracking:** fix the stalled track near the pins (8848) and the lost track at 30 ft (8845, occluded by the arm).
4. **Form module:** foot plants on the floor plane (stance, drift, finish, approach length and speed, step timing), release synchronization, knee estimate from foreshortening, head stability, laydown relative to the slide foot.
5. **Overlay renderer** as a standard debug output for every analyzed clip.
6. **Capture checks:** detect Slo-mo exported at 30 fps (8845), and warn on 30 fps (8846).

## Addendum 2026-10-21: Oct 15 Ruby session re-scored on current `main`
- **Clips:** 18 matched to Ruby by timestamp. **13 finished**.
- **Failures (5):**
  - 2 with no lane in frame (8828, 8830)
  - 1 oblique view across several lanes (8817)
  - 2 where impact wasn't detected (8821, 8829)
- **Not run:** 8831 (known 12-minute failure).

| Speed definition | MAE vs Ruby | Bias | Median abs. error | Within ±0.5 mph |
|---|---|---|---|---|
| Pipeline 60 ft average (current headline) | 0.65 | +0.64 | 0.52 | 46% |
| 4–20 ft segment | 1.66 | −1.57 | 1.57 | 0% |
| **4–40 ft segment** | **0.57** | **+0.24** | **0.25** | **54%** |

**What this shows:**
- The 4–20 ft segment reads about 9% low. This is the known near-field scale problem in the pipeline's lane-edge/vanishing-point homography.
- On the training clips, calibrating with the approach dots and pin deck removed that error (0–15 ft read about 18 mph, consistent with later segments).
- **Next step:** auto-detect the approach dots and pin deck on these clips, re-fit the homography, and re-score. If near-field bias disappears, adopt multi-reference calibration in `lanes.py`/`metrics.py` and re-evaluate the 4–40 ft speed definition as the headline.

**Side-view clips (8823 and 8826 are Shayne, 8824 is the other bowler; front-diagonal camera):**

| At release | 8823 | 8826 | 8824 |
|---|---|---|---|
| Slide-knee bend | 40° | 35° | 45° |
| Trail-knee bend | 85° | 86° | 47° |
| Forward torso lean | 14° | 18° | 50° |

- Rear-view knee estimates read high and this diagonal view reads low. A true side view is needed for absolute knee angle.

## Addendum 2: pin-base recalibration test on the Oct 15 Ruby clips (negative result)
**Test:** re-anchor each clip's homography at the detected pin-base row (60 ft), keeping the pipeline's lane edges and foul line. Score the same 13 clips against Ruby.

**Result: speed got worse.**

| Speed definition | MAE vs Ruby | Bias |
|---|---|---|
| Recalibrated 4–40 ft | 3.08 mph | +1.59 |
| Recalibrated foul → impact average | 0.83 | +0.83 |
| Current pipeline 4–40 ft | 0.57 | +0.24 |
| Current pipeline 60 ft average | 0.65 | +0.64 |

**Contradiction across references (IMG_8807):**
- The pipeline puts 60 ft about 25 px above the visible pin bases, and the lane dot row at 4.7 ft.
- The pin-base anchor puts the dots at 6.5–6.8 ft (consistent with standard 7 ft dots), but speeds then read about 10% high against Ruby.
- No single projective lane model satisfies the foul line, 7 ft dots, pin base and Ruby speed at once.

**Likely causes, in order:**
1. Lens distortion bending the lane edges, so the fitted vanishing point is biased.
2. These dots aren't at 7 ft.
3. Ruby's speed definition (unknown averaging window).

**Decision:** keep the current pipeline geometry. **4–40 ft remains the best speed definition so far** (MAE 0.57, bias +0.24, median error 0.25). Do not adopt the pin-base anchor.

**To resolve:**
- Tape-measure the dot distance at this center.
- Record one clip with a known object at measured distances.
- Test undistortion: iPhone lens model, or a straight-edge fit along the full lane.
- The approach-dot calibration on the 10/20 training clips used references behind the foul line, which this camera position doesn't see.

## Addendum 3 (2026-10-21 night): lens distortion ruled out; depth calibration is the real problem
**1. Lens distortion ruled out.**
- Sub-pixel lane-edge points over the full visible lane (8807, 8813, 8815, 8832) fit a straight line to 0.4–1.0 px rms.
- A curved fit adds nothing: under 1 px of sag.
- iPhone video arrives distortion-corrected. Drop this hypothesis.

**2. Lateral calibration is solid.**
- Auto-detected markings on IMG_8807 land exactly on their boards: foul-line approach dots on boards 5/10/15/20/25, and all 7 arrows on boards 5–35.

**3. The pipeline's depth (distance down the lane) mapping is wrong, and its Ruby agreement is partly coincidental.**

| Check | Pipeline geometry | Published reference |
|---|---|---|
| Arrows | 11.2–12.6 ft | about 12–16 ft (center ≈ 15–16) |
| Lane dots | 4.7–5.6 ft | about 7–9 ft |
| Mean speed 4–20 / 20–40 / 40–58 ft (13 clips) | 15.4 / 18.2 / 21.3 mph | a real ball decelerates |

- An accelerating ball is physically impossible, so near distances are compressed and far distances stretched.
- The 60 ft average and 4–40 ft speeds match Ruby only because these errors cancel. **Do not adopt 4–40 ft as the headline yet.**

**4. Two corrective fits failed and are rejected:**
- Pin-base anchor: mid-lane over-stretched.
- Physics self-calibration on one free parameter: unstable, with the track ending at 27–61 ft.
- Root cause is probably the edge/vanishing-point construction plus far-lane track noise. One parameter can't fix it.

**5. Decisive next step (no Ruby needed): tape-measure at the Oct 15 center.**
- Distance from the foul line to: the lane dots, the center arrow (board 20), and an outer arrow (board 5).
- With those, fit the homography from points (foul dots, lane dots, 7 arrows, pin deck) instead of edges + vanishing point.
- Re-score against Ruby; require a decelerating speed profile as an acceptance check.
- The detector for these markings is already written (`arrows.py`).

Sources for marking distances: [BowlingLife](https://bowlinglife.eu/bowling-lane-arrows-boards-explained), [GoBowling](https://gobowling.com/blog/how-long-is-a-bowling-lane-markings-explained/).

## Addendum 4: calibration from the lane markings (first physically plausible result)
**References:**
- Lane dots at 8 ft.
- Center arrow (board 20) at 15 ft; the arrow stagger is fitted (0.1 ft per arrow).
- Foul line, plus straight-edge constraints on both lane edges.
- Pin deck held out, used for validation only.
- `marks.py` auto-detects the markings. On IMG_8807 it found all 7 arrows (boards 5–35) and 9 lane dots (boards 3/5/8/11/14 each side).

**Coverage:** markings were found on 6 of the 13 clips. The other 7 need detector tuning (camera position and contrast).

| Speed (6 clips) | 4–20 ft | 20–40 ft | 40–58 ft | 4–40 ft | Foul → impact avg |
|---|---|---|---|---|---|
| Mean speed | 17.8 | 16.7 | 14.4 | — | — |
| Error vs Ruby: MAE / bias | 1.02 / +1.02 | **0.52 / −0.13** | — | 0.64 / +0.59 | 0.70 / +0.70 |

**What changed:**
- **The speed profile now decelerates**: 17.8 → 16.7 → 14.4 mph.
- Under the old edge/vanishing-point geometry the ball appeared to accelerate: 15.4 → 18.2 → 21.3 mph.
- **20–40 ft matches Ruby with almost no bias.** The 4–20 ft segment reads about 1 mph above Ruby, consistent with Ruby reporting a mid-lane or average speed rather than release speed (to confirm).

**Open issue: the far end.**
- With the pin deck held out, the deck maps to about 54 ft instead of 60 ft, and the ball track ends at 52–58 ft.
- The near references (0–15 ft) and the far pins disagree by about 10% at the far end, so 40–58 ft speed and entry metrics are not yet trustworthy.
- Forcing the deck into the fit gives a non-physical profile again. Candidate causes: deck-row detector bias, far-lane track noise, or lane non-planarity.

**Next:**
1. Tune marking detection for the remaining 7 clips.
2. Verify the deck row and the far ball track visually on 2–3 clips.
3. Confirm Ruby's speed definition.
