# Runner v2 UI spec
Status: DRAFT
Version: 1.2
Last Updated: 2026-10-14
Owner: Shayne

The design is `runner_v2_mock.dc.html` in this folder (also on the claude.ai canvas "LaneSight Runner v2"). It's a design-tool file: read the markup for layout and styling, and the `renderVals()` script at the bottom for the shape of each panel's data. **Every number in it is mock data.** In the runner, every value comes from `/api/state`, i.e. the stored shot records and your inputs. Never hard-code or fill in a value.

Build into the existing runner (`lanesight-core/lanesight_runner/static/index.html` + `card.py` / `server.py`). Keep everything that works today: SSE refresh, inputs, speech, CSV export, the tier badges and their rules.

## Layout (matches the ChatGPT reference look)
- Header: LaneSight logo, watch status, queue status with the current step, Speech toggle, user.
- Left nav: Session (this page), Sessions (history), Analysis (cross-session trends), Arsenal (balls with weight/RG), Settings.
- Title row: session name (editable), center + lane, pattern, shot count, duration, ball, type; Change ball/pattern, Export CSV, End session.
- 2×2 grid:
  1. **Session Overview**: 4 KPI tiles (avg speed, avg rev rate, strikes, spares, each with delta vs last session) + speed/rev-rate line chart split Early/Mid/Late; Total / First Half / Second Half / Last 5.
  2. **Lane Transition Analysis**: ball-traffic heatmap on a perspective lane (where the ball traveled, from the smoothed paths; NOT oil) with Ball traffic / Entry / Breakpoint / Speed tabs; Key Takeaways from the transition rule, speed and entry-angle trends, and the recommended adjustment.
  3. **Shots in Session** (Ruby-app style, compact, no thumbnails): session-average pills on top; one row per shot = result box (X strike / "/" spare / "–" open, color-coded) · time + shot # + leave · line bar (boards 39→1, white tick = breakpoint, yellow dot = entry, dashed = target breakpoint) · colored pills: rev rate (purple), speed (blue), entry angle (teal), entry board (green), Power (amber), loft (red). Filters All / Strikes / Spares / Opens; scrolls; click a row to open it on the right. Pills show "—" when the value is unavailable.
  4. **Latest Shot Analysis**: prev/next; tabs Overview (clip frame with actual path + your target line + Break Point / Entry Board callouts, 0.25× play) / Top-down / Rotation (Ruby values) / Compare; Shot Metrics grid with ✓/est badges; Analysis & Recommendation: verdict, Key Factors checklist (pocket, entry angle, breakpoint vs target, hit your mark), next move; quick inputs (hit mark, fix pins, Ruby, advice right/wrong).
- Shot list rows are a CSS grid, never a `<table>` with a repeat inside it.

## Features by status
**Built (keep, restyle):** KPIs speed/revs/strike/spare/pocket/carry (`card.session_stats`), repeatability (`insights.session.consistency`), top-down replay PNG, result + pins + hidden-pin flag, Power ring, next-shot advice + alternatives + spare line, advice feedback, metric cards with tiers + "how measured" tooltip, inputs (target line, hit mark, pin correction, Ruby, shot type), lane-transition takeaway (`insights.adjust.transition`), speech, CSV.

**Small add (data exists, needs UI/API):**
- Avg Power and hit-mark count KPIs; deltas vs the previous session (all sessions are in the DB); range filter.
- Header queue + current step: stream the latest `timings.steps` line while a shot is processing.
- Video + tracked path: serve the clip (`/api/shots/{id}/video`, the SDR copy for HDR clips); draw `trajectory.pixel` on a canvas over a `<video>`, synced to `trajectory.pixel[i].t`. Pixel coordinates are in the stabilized reference frame: correct with the stored per-frame homographies (`*_stab.pkl` `Hs`) or limit the overlay to tripod clips (camera motion under 25 px) and say so. 0.25× playback.
- Target line on the video: project the intent boards (laydown 0 ft, arrows 15 ft, breakpoint at the shot's breakpoint distance) through the lane homography.
- Launch angle card (in the record, low confidence = est) and axis tilt card (Ruby value, labeled as Ruby).
- "Missed by" line under hit-your-mark: `insights.reading.execution_check` misses.
- Shot-by-shot chart: speed + revs (Entry + breakpoint, Arrows, Power tabs) from the cards; dashed half-way line.
- Lane usage: all first-ball smoothed paths (`trajectory.smoothed`) top-down, latest highlighted, breakpoint ellipse from `consistency.breakpoint_ellipse`, spread at arrows/breakpoint/entry.
- Game: build frames from first-ball/spare order with `scoring.game` (pins down from the effective pins); handle 10th frame; a frame you can't score shows blank, never a guess.
- Shots list thumbnails: ffmpeg frame grab at release time, cached next to the clip.
- Capture + timing bar: probe + per-step seconds from `timings.steps`.

**New work (later):** compare two shots; extra lane-read rules (speed trend, which misses leave which pins).

## Not in the runner (and why)
Oil heatmap (video can't measure oil), "ideal path" (no validated model; your target line instead), axis/rotation from video (needs 120+ fps; Ruby only), Arsenal/Coaching/League navigation (app, Stage 7).

## Done when
- Every panel renders from a real session in `~/LaneSightData` (the 2 HDR clips + any new clips); empty states and `unavailable` reasons show where data is missing.
- No value on screen that isn't from `/api/state` or your input.
- `python3 -m pytest` passes; add tests for new API endpoints and the frame builder.
