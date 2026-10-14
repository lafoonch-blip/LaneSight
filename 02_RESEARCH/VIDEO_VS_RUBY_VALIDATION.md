# Video vs Ruby sensor validation log

Goal: estimate shot metrics from a single phone video and compare them with the Ruby in-ball sensor's numbers for the same shot.

## Scope (set by Shayne, 2026-10-13)
- Measure the **ball and the lane only**, so LaneTalk can show ball motion and metrics and recommend adjustments.
- The bowler is out of scope. Approach and swing timing are not targets.
- Design constraint: a smart-glasses (first-person) camera never sees the bowler. Every metric and every adjustment insight must therefore come from the ball's path and the lane.
- The algorithms must generalize to any video. No hand-picked points; per-video constants are learned automatically.

### Target metrics (ball + lane)
- Ball speed (average, plus a speed profile)
- Loft
- Laydown board
- Board at the arrows
- Launch angle
- Breakpoint (distance and board)
- Skid / hook / roll lengths
- Entry board and entry angle
- Pocket hit (high / flush / light)
- **Rev rate, axis tilt, axis rotation, PAP** (required, per Shayne 2026-10-13)

### Adjustment logic to build on
Inputs: entry board and entry angle compared with the pocket (17.5 for right-handers), and breakpoint compared with intended.
Outputs: feet/target moves using standard 2-and-1 and 3-and-2 style rules, plus speed and hand changes.

## Pipeline v0.4 (automatic, no manual points)
Code: `lanesight_cv` package. Run: `python3 run_all.py VIDEO OUT`.

1. **Stabilize**
   - ORB + RANSAC homography to a reference frame (the middle of the longest steady stretch).
   - Features are restricted to the lane surface.
   - Background plate = temporal median of the warped frames.
   - Works for a handheld phone (shot 2 moved up to 380 px).
2. **Lane geometry**
   - Lane = saturated wood. The foul line is the near boundary of the lane mask and may be tilted.
   - Edges come from robust line fits of wood runs. All lanes share one vanishing point.
3. **Ball tracking**
   - Background subtraction, size-gated by depth, with glare fragments merged and static artifacts rejected.
   - RANSAC trajectory linking.
   - Backward airborne extension for lofted balls: a round blob with no arm attached.
4. **Impact**
   - A band just beyond the ball's top that moves with the ball (only pins can trigger it), aligned by phase correlation.
   - Matches the visual frame on all 4 shots, within 1 frame.
5. **Touchdown**
   - First sharp rise in the ball blob's height/width after at least 2 flat, round airborne frames, because the reflection or shadow joins the ball on contact.
   - Returns nothing if the touchdown was occluded.
6. **Refine**
   - A per-video ball color model re-measures the ball in the near and mid lane; raw detections are used past ~40 ft.
7. **Metrics**
   - Homography from the foul line plus the ball contact point at impact (59.44 ft).
   - Lateral path smoothed with robust LOESS.
8. **Rev rate (prototype, `revrate.py`)**
   - The ball's surface pattern repeats once per revolution.
   - Method: scale-normalized ball crops along the track (hue/saturation, inner disc), appearance autocorrelation over time lag, then the period with a parabolic sub-frame peak.

## Findings after 4 shots
- **Speed = 60 ft / (release → impact).**
  - Release and impact are verified frame by frame on all 4 shots.
  - Within 0.5% of Ruby on shots 1–3, but **+3.3% on shot 4**.
  - On shot 4 the timing gives 17.42 mph against Ruby's 16.9. Either Ruby carries about ±3% error, or its speed isn't purely timing-based.
  - A third reference (the lane scoreboard mph, or a radar) is needed to tell which.
- **Loft** = early speed × (touchdown − release).
  - 1.37 vs 1.5, 2.21 vs 2.0, 1.77 vs 2.5 ft.
  - Mean absolute error 0.36 ft, about 1 frame at 60 fps. Shooting at 120/240 fps would tighten this.
- **Breakpoint: the video and Ruby measure different things.**
  - Ruby went from 41 to 39 ft on shot 4; the video's geometric breakpoint (furthest-right point) gave 39.5 / 43.2 / 35.8 / 36.0 ft.
  - Ruby's breakpoint and skid length are almost certainly rotational: skid → hook, from spin vs speed.
  - The geometric breakpoint (board and distance) is still the right metric for lane-play adjustments, so it is reported as its own metric, not as a Ruby-equivalent.
- **Rev rate: a clear periodic signal on every shot with a visible ball.**
  - The pattern repeats every ~9.5–10 frames at 60 fps (ball ≥32 px wide, first ~1.5 s of travel).

| Shot | Ruby rpm | Video rpm (lane, sliding windows) | Ruby / video |
|---|---|---|---|
| 1 | 428 | 377–392 (median ~385) | 1.11 |
| 3 | 407 | 364–371 (~366) | 1.11 |
| 4 | 411 | 359–366 (~361) | 1.14 |
| 2 | 392 | not enough unoccluded frames | — |

  - Rate is constant down the lane (no decay), so the gap isn't skid friction mid-lane.
  - The constant ~12% offset has two candidate explanations: spin lost at touchdown, or Ruby measuring at release / defining rpm differently.
  - Ruby-equivalent ≈ 1.12 × video rpm gives 432 / 410 / 404 vs 428 / 407 / 411 (±1.5%). This needs blind validation on new shots before it is trusted.

## How axis tilt, axis rotation and PAP can come from video (plan)
- **Spin axis (3D).** Fit a rigid rotation ω to the ball surface's motion between frames. For a pixel on the disc at normalized (x, y), the sphere point is p = (x, y, √(1−x²−y²)) and its image flow is the projection of ω × p.
  - At ~43° per frame direct optical flow is unreliable. Compare frames about one period apart instead (e.g. 10 frames apart when the period is 9.6 frames): the residual rotation is small, and the flow gives the axis direction.
- **Into lane coordinates.** Rotate ω from the camera frame into lane coordinates, using the camera orientation from the lane vanishing point plus the lane homography. Focal length comes from the lane rectangle's homography or the iPhone metadata.
  - Axis tilt = elevation of ω above the lane plane.
  - Axis rotation = horizontal angle of ω relative to the direction of travel.
  - Both are measured at the first clean frames after touchdown. Ruby reports them at release.
- **PAP.** PAP is the point where the spin axis meets the ball's surface, measured from the grip center (inches over and up). It needs a reference on the ball:
  - Option A: detect and track the thumb and finger holes when they face the camera.
  - Option B: a one-time small tape or marker dot at a known spot relative to the grip.
  - Option C: PAP is stable per bowler and ball, so measure it once (Ruby or pro shop) and use video to detect drift.
  - At 60 fps, blur makes the holes unreliable; 240 fps slo-mo makes A realistic.

## Results (auto v0.4; shots 3 and 4 run blind first)

| Shot | Ruby speed | Video speed | Error | Ruby loft | Video loft | Ruby BP | Video BP (extreme / flat-end) |
|---|---|---|---|---|---|---|---|
| 1 (Ruby #18) | 17.0 | 17.09 | +0.5% | 1.5 | 1.37 | 41 | 39.5 / 43.0 |
| 2 (Ruby #17) | 17.8 | 17.71 | −0.5% | 2.6 | occluded | 41 | 43.2 / 47.5 |
| 3 (Ruby #16) | 17.4 | 17.33 | −0.4% | 2.0 | 2.21 | 41 | 35.8 / 38.6 |
| 4 (Ruby #14) | 16.9 | 17.46 | +3.3% | 2.5 | 1.77 | 39 | 36.0 / 42.5 |

Ruby axis values (targets for the axis work):

| Shot | Rev rate | Axis tilt | Axis rotation |
|---|---|---|---|
| 1 | 428 rpm | 31° | 71° |
| 2 | 392 rpm | 34° | 66° |
| 3 | 407 rpm | 31° | 68° |
| 4 | 411 rpm | 33° | 68° |

Video-only outputs:

| Output | Shot 1 | Shot 2 | Shot 3 | Shot 4 |
|---|---|---|---|---|
| Laydown board | 16.1 | 15.4 | 18.0 | 18.2 |
| Board at arrows (15 ft) | 12.3 | 14.4* | 13.8 | 13.4 |
| Breakpoint board | 9.3 | 11.9 | 11.2 | 9.9 |
| Entry board | 18.7 | 17.2 | 21.2 | 19.9 |
| Entry angle | 4.8° | 2.8° | 4.7° | 5.8° |

\* interpolated across the occlusion gap

## Next steps
1. **Rev rate:** validate the 1.12 factor blind on new shots. Test at 120/240 fps, where the per-frame rotation drops from 43° to 21° or 11°.
2. **Spin-axis fitting** (axis tilt and rotation) using period-lag flow, then compare with Ruby 31–34° tilt and 66–71° rotation.
3. **PAP:** decide on hole tracking vs a marker vs a one-time entry. Capture 240 fps clips.
4. **Speed discrepancy:** settle it with the lane scoreboard mph.
5. **Glasses video:** needs testing.
