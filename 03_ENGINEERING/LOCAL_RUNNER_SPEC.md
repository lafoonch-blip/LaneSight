# Local Runner Spec (at-lane, Mac-only)
Status: DRAFT  
Version: 1.0  
Last Updated: 2026-10-14  
Owner: Shayne

Personal testing tool: phone records, the MacBook analyzes and shows everything. Not the Stage 7 UI (DEC-017). It doubles as Seed Dataset collection (M1-15) and the first accept/reject feedback loop (M4-06).

## 1. Flow
1. Start a session on the Mac: type (practice), ball, oil pattern.
2. Record one shot on the iPhone (tripod, 1080p60) and AirDrop it to the Mac. It lands in `~/Downloads`.
3. The runner detects the clip, copies it into the session folder, and runs `lanesight-core`.
4. The browser page on the Mac updates with the shot card. The Mac speaks the adjustment through the current audio output (AirPods).
5. Between shots, enter intent, "hit your mark?", pin correction, Ruby values and adjustment feedback.

## 2. Stack
- Python 3, FastAPI + Uvicorn, served on `localhost` only
- `watchdog` for the folder watch
- Postgres via local Supabase (`supabase start`, Docker Desktop), using the existing `models/schema.sql`. Add tables only where the schema lacks something (see §5) as a migration.
- Front end: one HTML page, vanilla JS or HTMX, updated by Server-Sent Events. No build step.
- Speech: macOS `say`
- Everything lives in the `lanesight-core` repo under `runner/`.

## 3. Ingest
- Watch `~/Downloads` (configurable) for `.mov`/`.mp4` created after the session started. Ignore everything else.
- Wait until the file size is stable for 2 s before reading (AirDrop writes progressively).
- Copy to `data/sessions/<session_id>/<shot_no>.<ext>`. Never modify the original.
- Process one clip at a time from a queue; a new clip while one is running waits.
- **Frame timing:** iPhone clips are HEVC and may be variable frame rate. Read real frame timestamps (ffprobe/PyAV) and verify the decoded fps before any timing metric. If OpenCV can't decode HEVC, transcode with ffmpeg first. A clip with mismatched timing must fail visibly, not produce a speed.
- Assign the capture tier (`capabilities.py`) before analysis and show it on the card.

## 4. Staged results
Inspect the existing entry point (`run_all.py` / `ShotRecord`) before changing anything.
- **Stage A (target ≤30 s):** release, impact, speed, pins/leave, laydown, arrows, breakpoint board, entry board/angle, Power, adjustment. Speak the adjustment when A completes.
- **Stage B (background):** rev rate, loft, replay image, heatmap update.
- If the pipeline can't be split cleanly, run it whole first and log timings; split later based on data.
- Log wall-clock time per pipeline step to the shot record and show the total on the card.
- Failures show a clear failure state with the reason. No placeholder or fallback numbers.

## 5. Data
Use existing schema tables for session, shot, measurements (with source, confidence, algorithm version), ball and oil pattern. Add if missing:
- `shot_intent` (target board at arrows, breakpoint board, feet board): optional
- `user_shot_feedback` (hit mark: yes/no/not sure)
- `pin_correction` (corrected leave, original read)
- `sensor_reading` (source = "Ruby", manual entry: speed, rev rate, loft, tilt, rotation, breakpoint)
- `recommendation_feedback` (thumbs up/down, note, did you follow it)
- `timing` (per-step ms)

## 6. Page layout (single screen, laptop-sized)
- **Header:** session type, ball (changeable; "Current Ball"), oil pattern, shot count, running game stats (strike %, spare %, pocket %).
- **Shot card (latest shot):** replay image, metric cards with tier/confidence badges (Guaranteed / Best effort / Unavailable with reason), pin diagram with leave, Power, adjustment (primary + secondary) with reason and confidence.
- **Quick inputs:** intent, hit mark (Y/N/?), pin correction, Ruby fields, adjustment 👍/👎 + note. Keyboard shortcuts for Y/N/?.
- **Shot list:** shot #, speed, rev, Power, arrows, breakpoint, entry, leave, ball. Click to reopen a shot.
- **Variance panel:** LaneSight vs Ruby per shot and running mean/MAE (DEC-021).

## 7. Speech
- `say` the primary adjustment only, ≤12 words, e.g. "Light. Move feet two left, eyes one left."
- Speak "No adjustment yet" when that's the engine's answer.
- Toggle on/off on the page.

## 8. Export
- CSV export per session: every metric, confidence, tier, user inputs, Ruby values, timings. This feeds the eval harness (M1-14).

## 9. Acceptance
- Running the 4 existing validation clips through the runner reproduces the current `lanesight-core` numbers exactly.
- AirDrop → shot card on screen works end to end, with timings logged.
- A clip at 30 fps shows loft as Unavailable with the reason.
- A non-video file and a half-written file in Downloads are ignored without errors.
- All existing tests still pass; new tests cover ingest, timing validation and the API.

## 10. Not in scope
Auth, cloud, iOS app, League Mode, continuous capture, sensor APIs, multi-user.

## 11. Milestones
1. Ingest + queue + run existing pipeline + timing log + raw results on page
2. Shot card, inputs, DB writes, speech
3. Session stats, shot list, Ruby variance, CSV export
4. Staged results + speed optimization based on the timing log
