# Local Runner Spec (at-lane, Mac-only)
Status: BUILT (Milestones 1–3); Milestone 4 in progress (shot-window trimming done; staged results open)  
Version: 1.3  
Last Updated: 2026-10-14  
Owner: Shayne

Personal testing tool: phone records, the MacBook analyzes and shows everything. Not the Stage 7 UI (DEC-017). It doubles as Seed Dataset collection (M1-15) and the first accept/reject feedback loop (M4-06).

## 0. Implementation status (v1.3)
Code: `lanesight-core/lanesight_runner/`. Setup and use: `lanesight-core/README.md` → "At-lane runner".
- **Done:** Milestones 1–3 (ingest, queue, probe/timing checks, shot card with tier badges, inputs, Power, speech, session stats, Ruby variance, CSV export). 34 tests pass (13 runner tests).
- **Deviation from §2 / §5:** storage is SQLite (`~/LaneSightData/lanesight_runner.db`), not local Supabase. Reason: no Docker needed at the lane, single user. User inputs are columns on `shots` instead of separate tables; the original video read is never overwritten. Moving to the `schema.sql` tables happens with the cloud stage.
- **Deviation from §3:** clips are copied to `~/LaneSightData/sessions/<id>/`, not the repo (Documents may sync to iCloud). The watcher uses "new file while a session is active" instead of file dates, because AirDrop can keep the original recording date.
- **Verified end-to-end on the Mac (2026-10-14):** IMG_8754 and IMG_8751 run through the real server (session → upload → convert → analyze → card → spoken adjustment → replay PNG → CSV). Numbers reproduce the `validation/` reference within tolerance: speed ±0.1 mph, rev rate exact, pins exact, boards ≤1 (entry up to 1.0). Loft can come back `unavailable` on a clip where touchdown isn't seen (IMG_8754), which is an honest state, not a wrong value. The other two validation clips not yet run.
- **HDR without zscale (2026-10-14):** the validation clips are iPhone HDR (HLG/BT.2020) and this Mac's Homebrew ffmpeg was built without `zscale` (libzimg), so the original tone-map chain failed and every HDR clip was rejected. `convert_sdr` now falls back to a portable numpy HLG inverse-OETF + BT.2020→709 gamut + 709 gamma (decoded via OpenCV so colours and frame count match the pipeline). Recovers lane-wood saturation (0.6% → ~10% of pixels match the lane mask). ffmpeg's zscale path is still used when present. PQ (smpte2084) without zscale is refused, not guessed. Shooting SDR (HDR Video off) remains the recommended capture; this is the safety net.
- **Milestone 4 — shot-window trimming (2026-10-14, `lanesight_runner/trim.py`):** most of a clip is dead set-up time; the shot (release → travel → pin settle) is only ~6–9 s, usually near the end. A cheap low-res pre-pass (~3.7 s) measures lane-region motion energy (camera motion removed by phase correlation) and takes the earliest sustained burst as the shot; the clip is stream-copied (lossless) to `[burst − 4 s, burst + 1.8 s]` and only that is converted/analysed. Result on IMG_8754 (HDR): **279 s → 81 s (3.4×)** — convert 163→43 s, analyse 116→33 s; SDR clips (no conversion) run ~3×. Numbers hold vs `validation/` (speed/boards/rev/pins; entry 19.0 vs 18.77). The tail is deliberately short: a longer tail lets the AMF rake sweep pollute the background and the far-end ball track, pushing entry board/angle several boards off. Audio was tried for the window and rejected (pin crash is quieter than ambient noise). Safety net: if the windowed analysis throws (window cut the shot), it retries on the full clip; `lanesight_core` is unchanged. After a successful windowed run the trimmed shot **replaces** the stored clip and the SDR/cache working files are deleted (≈102 MB → ≈31 MB per shot); if the fallback ran, the full clip is kept. Margins were tuned on IMG_8754/8751 — re-validate on the seed dataset.
- **Open:** Milestone 4 staged results (Stage A ≤30 s vs Stage B background). Analysis is now ~35–80 s/clip; the next lever is splitting fast metrics (speed/boards/pins/adjustment) from slow ones (rev rate, replay).

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
