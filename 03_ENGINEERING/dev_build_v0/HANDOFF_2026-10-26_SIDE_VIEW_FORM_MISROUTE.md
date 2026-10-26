# Claude Code Handoff — Side-view form clip produced confident-wrong shot results
Status: READY FOR BUILD
Version: 1.0
Last Updated: 2026-10-26
Owner: Shayne
Evidence: IMG_8905 (10-25 training videos; 1080x1920, 59.94 fps, 30.3 s), side view of the approach, recorded for **Form** analysis. Phone screenshots 2026-10-26 12:10.

## What happened
- The clip came back as a **Shot** card: Target vs Actual, "Move Right 8 ft", ball metrics, score progress. No form metrics at all.
- The camera is on the approach looking along the foul-line row, across many lanes. There's no pin deck, and the ball travels across or away from the frame. **No lane metric can be measured from this view.** But the pipeline fitted a lane anyway and labeled almost everything MEASURED: speed early 15.8 / late 19.4, breakpoint 2.0, entry 10.5.
- Shayne: the thumbnails and almost every metric are far off.

## Root causes (to confirm)
1. **Mode routing:** a form/side-view clip went down the shot pipeline. Check the capture mode → API job type → `analyze_clip` path, and the upload path too.
2. **No view gate on the ball pipeline:** nothing refuses a clip with no down-lane view or pin deck. It must return `no_reliable_data` with a camera tip (DEC-061), not fabricated geometry.
3. **The backend on the phone is pre-3.7:** "8 ft", "Breakpoint 0", and late speed > early shown as MEASURED are exactly the 14b234c8 failures that GUARDRAILS 3.7 fixes. Confirm which commit `com.lanesight.api` is running.
4. **Display bugs (DEC-061 violations):**
   - Rev Rate 358.8 and Launch Angle 2.5 show numbers while UNAVAILABLE.
   - The achievement progress shows raw floats ("16.635 / 20", "359.359 / 450").
   - The rev caption says 120 fps, but the clip is 59.94 fps.
5. **Thumbnails:** the wrong frame or crop was picked. Check how the thumbnail frame is chosen for form vs shot clips.
6. **Contamination:** this shot counted toward LaneSight Score parts (3/20 …) and achievement progress in Shayne's real account.

## Build
1. **Route by mode end to end.** A Form clip runs only the form pipeline, and its card shows only form metrics (DEC-056). Add a test using IMG_8905.
2. **Add a capture-view classifier** (rear / side / down-lane / unknown) before either pipeline. The shot pipeline refuses side or unknown views with `no_reliable_data`, a camera tip, and no move. The form pipeline gets the classified view.
3. **Status rule in iOS:** UNAVAILABLE never renders a number. Round achievement progress to the metric's display precision. Take fps from the clip probe, never a constant.
4. **Thumbnails** come from the analysis's own key frame: release for form, mid-track for shot. Never fall back to frame 0.
5. **Regression set:** IMG_8905, 14b234c8, IMG_8751–8754. 8905 must yield form metrics or an honest unavailable state with zero shot metrics. The others must stay unchanged.
6. Write the score/achievement reset for the 8905 shot as SQL in `ops/`. **Do not run it.**

## Needs Shayne
Deploy (migrations 016/017 and the new ones, then restart `com.lanesight.api`), run the reset SQL, re-test IMG_8905 on the phone.
