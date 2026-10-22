# Training Videos 2026-10-20: Shot + Form Analysis
Status: RESEARCH RESULTS (prototype analysis; nothing here is validated product output)
Version: 1.0
Last Updated: 2026-10-21
Source: `~/Documents/LaneSight/Training Videos` IMG_8845–8848 (recorded 2026-10-20, ~7:55–9:00 pm)
Note: copied into the repo from the claude.ai Project on 2026-10-22. The prototype scripts behind these numbers ran in a claude.ai session and are not in the repo; reproduce them in `lanesight-core`.

## Clips
| Clip | Format as recorded | Notes |
|---|---|---|
| IMG_8845 | **120 fps Slo-mo, exported at 30 fps playback** (72.7 s file; real time ≈ 4× faster between 4.2 s and 68.7 s; confirmed from the audio pitch shift) | Re-timed to true 120 fps for analysis (16.1 s real). A bystander enters the frame after release |
| IMG_8846 | **30 fps** (not 60), 22.0 s | |
| IMG_8847 | 60 fps, 24.9 s | |
| IMG_8848 | 60 fps, 22.1 s | |

**Camera position (all four):**
- Portrait, behind the approach, lens ~waist height, beside the ball return.
- The bowler fills most of the frame during the approach, which is good for form.
- The approach floor runs into the lane at the bottom of the frame.

## Form metrics (rear view)
**Method:**
- MediaPipe Pose (heavy) on every frame, then automatic event detection from the bowling wrist relative to the hip and shoulder.
- **Bottom of arc and release were checked frame by frame** (release = last frame of hand contact before the ball is free).
- Hip and top-of-backswing events are automatic.

| Metric | IMG_8845 (120) | IMG_8846 (30) | IMG_8847 (60) | IMG_8848 (60) | Session mean |
|---|---|---|---|---|---|
| Backswing (ball at hip → top) | 0.78 s | 0.73 s | 0.75 s | 0.87 s | **0.78 s** |
| Downswing (top → bottom of arc) | 0.37 s | 0.40 s | 0.40 s | 0.42 s | **0.40 s** |
| Release (bottom → ball free) | 0.021 s | ~0.05 s* | 0.033 s | 0.033 s | — |
| Swing, ball at hip → release | 1.17 s | 1.18 s | 1.19 s | 1.32 s | **1.21 s** |
| Tempo (downswing ÷ backswing) | 0.47 | 0.55 | 0.53 | 0.48 | 0.51 |
| Backswing height (wrist vs shoulder, torso lengths; − = below) | −0.33 | −0.27 | −0.22 | −0.22 | about shoulder height |
| Swing line at the bottom (wrist vs bowling shoulder, torso lengths) | −0.16 | −0.22 | −0.10 | −0.07 | ball slightly inside the shoulder line |
| Shoulder tilt at release (projected) | 41° | 45° | 47° | 40° | 43° |
| Follow-through height (wrist above nose, torso lengths) | 0.50 | 0.49 | 0.40 | 0.42 | 0.45 |
| Finish hold (still after release) | 0.97 s | 1.06 s | 0.81 s | 1.88 s | 1.18 s |

\* At 30 fps the release is only 1–2 frames long; this value is at the resolution limit.

**Precision:**
- Event timing: ±1 frame (±8 ms at 120 fps, ±17 ms at 60, ±33 ms at 30).
- Automatic hip and top events: ±2–3 frames.

**Consistency:**
- Downswing is very repeatable (0.37–0.42 s).
- IMG_8848 has the longest backswing (+0.1 s) and the longest swing.
- This agrees with the 2026-10-17 front-view clips: downswing 0.37 s, backswing at shoulder height.

**Not reported:**

| Metric | Why |
|---|---|
| Approach time / approach start | The legs leave the bottom of the frame and the ball return hides the feet early, so the detected start varied 1.85–3.18 s. Unreliable |
| Step count, cadence, slide length, drift | Feet are visible only for the last 2–3 steps; no board calibration on the approach |
| Head over slide foot | Rear-view left/right labels swap and gave inconsistent values. Needs a side view |
| Knee bend, spine angle | Need a side view |

## Shot metrics (ball/lane)
**The automatic lane finder rejected all four clips:**
- 8846 and 8847: foul line not found.
- 8848: no vanishing point.
- The camera is low and close, so the approach and lane merge at the bottom of the frame.

**Workaround:** I fitted the lane edges and foul line by hand from each clip's background, then ran the **unchanged** pipeline.

**Treat every number below as unvalidated:**
- No Ruby data.
- Hand-fitted geometry.
- A low view, where board and distance error is high.

| Metric | IMG_8846 | IMG_8847 | IMG_8848 | IMG_8845 |
|---|---|---|---|---|
| Ball speed (60 ft avg) | 16.3 mph | 16.6 mph | 14.8 mph ✗ | failed (impact not detected) |
| Release speed | 14.4 | 15.1 | 13.4 | — |
| Laydown / arrows board | 12.2 / 8.0 | 12.9 / 9.7 | 12.8 / 4.7 | — |
| Breakpoint board | 7.0 | 8.1 | 2.3 ✗ | — |
| Entry board / angle | 21.5 / 5.1° | 21.0 / 4.0° | 13.6 / −2.5° ✗ | — |
| Loft | unavailable (30 fps) | 0.7 ft | 1.6 ft | — |
| Rev rate | unavailable | ~402 rpm (low confidence, ±40) | ~429 (low confidence) | — |
| Pins (video read) | 2 pin standing (unverified) | 10 pin standing (unverified) | strike ✓ | — |

**Checks by hand:**
- **8847:** impact frame matches (pipeline 19.28 s vs ~19.2 s by eye), so its speed is plausible.
- **8848:** the pipeline put impact at 17.47 s vs ~17.2 s by eye. Speed is about 1.5 mph low and entry is wrong. It needs the same fix as the live-session clips: better far-lane tracking.
- **8847:** the stabilizer reported 1,251 px of "camera motion" on a fixed mount. The bowler filling the frame fooled it. Mask the bowler before alignment.

## What this shows
1. **One clip can't serve both modes from this position.** This low rear view is good for form timing but poor for ball metrics. It matches DEC-040: one focus per recording.
2. **Slo-mo export trap.** IMG_8845 was saved with 30 fps playback, so its timestamps are 4× stretched. The app must read the real capture rate. The runner's `probe` also needs to detect slo-mo (the HEVC original, or the 120 fps flag) or every timing will be 4× wrong.
3. **8846 was recorded at 30 fps.** Check Settings → Camera → Record Video before the center session.
4. **Form timing is already measurable** with off-the-shelf pose plus wrist events, to ±1 frame on bottom and release. The P1 Form metrics in the Form spec look achievable from a rear view; feet and posture metrics need the side view.

## Recommended capture changes for the next session
- **Shot Analysis:** tripod higher (~5 ft) and 15–20 ft behind the foul line, so the foul line is clearly above the bottom of the frame.
- **Form Analysis:**
  - Side view at hip height, 1.5–2.5 lanes away, landscape, as the S/F scenarios in `CAPTURE_TEST_PLAN_v1`.
  - Keep a rear form view only for swing line and drift.
  - Frame the full body, feet included.
- **Slo-mo:** AirDrop with "All Photos Data" so the original 120 fps file arrives, not an exported 30 fps render.
- **Ruby running** for every clip, so shot numbers can be validated.
