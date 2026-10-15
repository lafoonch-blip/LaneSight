# Runner v2 UI spec
Status: BUILT (2026-10-15); some "Small add" items still open
Version: 1.4
Last Updated: 2026-10-15
Owner: Shayne
Supersedes: v1.3

Design sources: `runner_v2_mock.dc.html` in this folder (shell + Shots-list styling tokens) and the three target renders in `reference/` (01 Session Overview, 02 Latest Shot, 03 Lane Transition — the richer per-panel look). Both are design-tool mocks: **every number in them is mock data.** In the runner, every value comes from `/api/state`, i.e. the stored shot records and your inputs. Never hard-code or fill in a value.

**Layout (built):** a single-page dashboard — all panels stacked full-width, nothing hidden behind tabs (tabs were tried in step 1 and removed; this is a glance dashboard for checking a shot right after it analyzes). Order top→bottom: Latest Shot → Session Overview → Shots in Session → Lane Transition.

Build into the existing runner (`lanesight-core/lanesight_runner/static/index.html` + `card.py` / `server.py`). Keep everything that works today: SSE refresh, inputs, speech, CSV export, the tier badges and their rules.

## Layout
- Header: LaneSight logo, watch status, queue status with the current step, Speech toggle, user.
- Left nav: Session (this page), Sessions (history), Analysis (cross-session trends), Arsenal (balls with weight/RG), Settings.
- Title row: session name (editable), center + lane, pattern, shot count, duration, ball, type; Change ball/pattern, Export CSV, End session.
- Panels, stacked full-width in order:
  1. **Latest Shot Analysis** (top — checked right after a shot): prev/next; view tabs Overview / Top-down / Rotation / Compare. Overview = clip/lane view with actual path + target line + Break Point / Entry Board callouts and checkbox toggles (Oil pattern / Target line / Boards / Arrows; each disabled when its data is absent). The **Oil pattern** overlay is the session's selected pattern from the library (length + where oil is heavier/lighter across boards) projected through the lane homography, labeled "modeled, not a scan"; hidden when the pattern is Unknown. Shot Metrics grid with ✓/est badges and a "vs avg" delta on each metric that has a session average. Rotation = full **Ruby** panel: axis-of-rotation diagram + axis tilt/rotation, PAP (over/up), swing height, setup time, and an approach-and-swing breakdown bar chart (pushaway/backswing/downswing/release). Analysis & Recommendation: verdict + confidence, split **What went well / What to watch**, next move; quick inputs (hit mark, fix pins, Ruby, advice right/wrong). When pins are **unreadable** (DEC-026) the verdict is "Couldn't read the pins" with the reason, and the metrics still show from the video.
  2. **Session Overview**: 5 KPI tiles (avg speed, avg rev rate, strikes, spares, avg pins — each with delta vs last session where available) + speed/rev-rate line chart split Early/Mid/Late (Total / First Half / Second Half / Last 5); **Accuracy & Consistency** rings (repeatability + speed/rev consistency from the real SD) and a **Shot Distribution** scatter (entry angle vs breakpoint board + ±1 SD ellipse). Strike %, avg pins etc. count only shots whose pins the video read (unreadable excluded).
  3. **Shots in Session** (Ruby-app style, compact, no thumbnails): session-average pills on top; one row per shot = result box (X strike / "/" spare / "–" open / "?" unreadable, color-coded) · time + shot # + leave · line bar (boards 39→1, white tick = breakpoint, yellow dot = entry, dashed = target breakpoint) · colored pills: rev rate (purple), speed (blue), entry angle (teal), entry board (green), Power (amber), loft (red). Filters All / Strikes / Spares / Opens; scrolls; click a row to open it in Latest Shot. Pills show "—" when the value is unavailable.
  4. **Lane Transition Analysis**: ball-traffic heatmap on a perspective lane (where the ball traveled, from the smoothed paths; NOT oil) with Ball traffic / Entry / Breakpoint / Speed tabs; a **Lane Transition Status** panel (holding / moderate / significant + score ring, early→recent trend rows for breakpoint / entry angle / entry board / carry, direction, recommended adjustment); Key Takeaways from the transition rule, speed and entry-angle trends.
- Shot list rows are a CSS grid, never a `<table>` with a repeat inside it.

## Features by status
**Built (2026-10-15):** single-page dashboard shell + title row; KPIs speed/revs/strike/spare/avg-pins with deltas vs the previous session + range filter (Total/First/Second/Last 5); repeatability + speed/rev **consistency rings** and **shot-distribution scatter**; speed/rev chart; Shots list (Ruby-style rows, filters, session-avg pills, click-to-open); Latest Shot lane view (oil/target/boards/arrows toggles, path + callouts) + Shot Metrics with vs-avg deltas + split What-went-well/What-to-watch analysis with confidence; **Lane Transition status** panel + trend rows + ball-traffic heatmap + takeaways; top-down replay, Power ring, next-shot advice + alternatives + spare line, advice feedback, metric tiers + "how measured" tooltip, inputs (target line, hit mark, pin correction, shot type); header queue + current step; **full Ruby panel** (axis diagram, axis/PAP/swing-height/setup, approach-breakdown bars; "Copy last shot"); **pin-unreadable** honest display (DEC-026); speech, CSV.

**Small add — still open (data exists, needs UI/API):**
- Video + tracked path on a `<video>`: serve the clip (`/api/shots/{id}/video`, the SDR copy for HDR clips); draw `trajectory.pixel` on a canvas, synced to `trajectory.pixel[i].t`. Pixel coords are in the stabilized reference frame: correct with the stored per-frame homographies (`*_stab.pkl` `Hs`) or limit to tripod clips (camera motion < 25 px) and say so. 0.25× playback. (Currently the Overview shows a rendered perspective lane, not the clip.)
- Target line on the video: project the intent boards (laydown 0 ft, arrows 15 ft, breakpoint at the shot's breakpoint distance) through the lane homography.
- "Missed by" line under hit-your-mark: `insights.reading.execution_check` misses.
- Shot-by-shot metric chart tabs (Entry+breakpoint, Arrows, Power); dashed half-way line (current chart is speed+revs only).
- Lane usage top-down: all first-ball smoothed paths, latest highlighted, breakpoint ellipse (`consistency.breakpoint_ellipse`), spread at arrows/breakpoint/entry.
- Game sheet: frames from first-ball/spare order with `scoring.game`; 10th frame; an unscoreable (or unreadable, DEC-026) frame shows blank, never a guess.
- Frames strip + thumbnails: ffmpeg frame grabs at key points (foul/launch/mid-lane/breakpoint/entry/impact), cached next to the clip.
- Capture + timing bar: probe + per-step seconds from `timings.steps`.
- Rotation "side view" ball-roll comparison (needs Ruby axis data); Trajectory/Rotation vs session-avg comparisons.

**New work (later):** compare two shots; extra lane-read rules (speed trend, which misses leave which pins); the richer per-metric ratings + multi-session Trends (Analysis nav) per `SENSOR_VS_VIDEO_METRICS.md`.

## Not in the runner (and why)
Measured or inferred oil maps (video can't measure oil; the overlay shows the published pattern only), "ideal path" (no validated model; your target line instead), axis/rotation from video (needs 120+ fps; Ruby only), Arsenal/Coaching/League navigation (app, Stage 7).

## Done when
- Every panel renders from a real session in `~/LaneSightData` (the 2026-10-15 live session + any new clips); empty states and `unavailable` reasons (including pin-unreadable) show where data is missing. ✓ for the built panels.
- No value on screen that isn't from `/api/state` or your input. ✓
- `python3 -m pytest` passes (50 tests); add tests for the remaining "Small add" API endpoints and the frame builder when built.
