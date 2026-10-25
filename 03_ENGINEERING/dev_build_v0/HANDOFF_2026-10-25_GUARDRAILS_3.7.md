# Claude Code Handoff — Recommendation guardrails, design 3.7, profile photo
Status: READY FOR BUILD
Version: 1.0
Last Updated: 2026-10-25
Owner: Shayne

## Read first
1. `CLAUDE.md`, `AGENTS.md` (read order and rules).
2. `00_CONTEXT/DECISIONS.md` → **DEC-061** (new), DEC-055, DEC-056.
3. `02_RESEARCH/SHOT_REVIEW_2026-10-25_14b234c8.md`: the evidence behind this work. Review frames are in `~/LaneSightData/out/review_14b234c8/`.
4. `02_DESIGN/dev_build_v0/README.md` **3.7** (changelog plus the new status-chip and move rules) and `03_ENGINEERING/dev_build_v0/HANDOFF.md` §4 (v1.9 adds rows 3a, 3b, 4c, 5a, 5b, 6a, 18a).

## How to run this
- Work continuously from A to H in order. Commit locally after each workstream. Run `python3 -m pytest` before every commit. Give one report at the end.
- Stop only if a test fails and you can't fix it, or the next action is irreversible outside the repo. For those, prepare everything and list it under **"Needs Shayne"**: applying migrations to live Supabase, resetting live score data, pushing to GitHub.
- Don't touch git branches you didn't create. Work on the current branch.
- No mock or fallback numbers. Anything that can't be measured is `unavailable` with a reason.
- Any change under `lanesight_core/cv/` must be re-run on `validation/` (IMG_8751–8754 vs Ruby) and on the regression clip below, with before/after numbers in the report.

## Regression clip (add it first)
- `~/LaneSightData/out/14b234c874cf4c34afb5865ea50d6be5_trim.mov`: 120 fps, portrait, a close and off-center camera behind the bowler.
- Ground truth from the video: entry about board **17–18** (pocket), deck clear afterward (strike), ball near the right edge at the breakpoint.
- Current output is wrong: entry 10.5, speed late 19.4 > early 15.8, breakpoint 2.0, "Move right 8", breakpoint target 0.
- Add it to the validation set with these expectations, in `validation/`, not the video (videos never go in the repo).

## A. Far-lane calibration (pipeline)
- Fix the pixel→lane mapping for close/off-axis cameras. The pixel track is correct; the downlane mapping is not. Segment speeds rise from about 14.6 to about 19.5 mph, so depth is compressed near the camera and stretched far away.
- Fit far references (pin deck, both gutters at the deck, dots and arrows), and check depth against known marks (arrows at 15 ft, dots at 7 ft, pin deck at 60 ft).
- **Accept:**
  - regression clip entry is within 16–19.5, and speed late < speed early;
  - IMG_8751–8754 are no worse than today against Ruby;
  - the same frames give the same numbers every run (14b234c8 currently differs from other runs of the same file: loft 0.97 vs 1.16).

## B. Plausibility gate (DEC-061)
- Before insights, check:
  - downlane speed must not rise by more than about 0.5 mph;
  - no lateral jump of 3 boards or more between neighboring samples, like the 4.76 spike at 42.5 ft;
  - calibration residuals are under threshold.
- On failure, mark far-lane metrics (breakpoint board/distance, entry board/angle, `entry_angle_52_55`, `speed_late`) as `low_confidence` or `unavailable` with a reason, and add `capture_quality.far_lane = "limited"` plus a reason for the camera-spot banner.
- `speed_release` admits about 9% low bias. Correct it, or label it `best_effort`. It must not be `ok` with a known bias in the note.

## C. Recommendation engine (`lanesight_core/insights/`)
1. Gate failed or key metrics not `ok` → the `no_reliable_data` state, no move.
2. Pins unreadable → `pins_unknown` state, no move. Add `POST /shots/{id}/pins` (the user's leave: strike, 10, 4/7, split, other, or picked pins). It stores the leave as `source: user`, recomputes insights and returns the new state.
3. Strike → repeat (existing branch), including when the user reports the strike.
4. Intent: pass the session/upload target into `strike_adjustment` consistently. Fix the `board_at_15ft` vs `arrows_board` key mismatch so `execution_check` actually runs. Arrows off by more than 1 board → `execution_miss`, repeat.
5. Cap each move at 2 (feet) and 1 (eyes). Larger moves need 2+ agreeing shots in the session.
6. Clamp every board to 1–39. Never project a breakpoint off the lane; if projection is unreliable, leave the breakpoint unset with a reason.
7. Return an explicit `state` on insights: `move | low_confidence_move | strike_repeat | execution_miss | pins_unknown | no_reliable_data`. Return `confidence` and `note` too. The app renders from `state`.
- Tests for each state, the cap, clamping and intent handling. The regression clip must come out `strike_repeat`, or `pins_unknown` if pins are still unread, and never a move.

## D. Pins
- The unread reason "bowler stepped into view" is wrong for the regression clip. The deck is visible and clear at about 7.5 s. Fix the detection, or report the true reason.
- The deck read must handle the sweep coming down after a strike.

## E. Uploads and data
- De-duplicate uploads by content hash. A duplicate returns the existing shot id; the app shows Failures › "You uploaded this clip before" with Open result / Analyze again.
- Uploads never feed score, achievements or stats (DEC-055). Check the engine path, and that achievement progress isn't computed from uploads.
- Shots `03f7b6e8…`, `bae3d3df…` and `f2c0d0e5…` are uploads attached to session `3338e9ec…` from before DEC-055, and they're counted in the score (3/20). Write the reset script (score, tiers, achievements, notifications for Shayne's user), but **don't run it on live**. Put it under "Needs Shayne".

## F. iOS: design 3.7
Build from `02_DESIGN/dev_build_v0/` (don't edit that folder). Report any screen that differs.
- **Status mapping:** one mapping, used everywhere. `Theme.swift MetricStatus` and `Models.swift` disagree today, so merge them. `best_effort`/`low_confidence`/`calibrated_estimate` → BEST EFFORT with rounded value and ± band; anything else → UNAVAILABLE with "—" and the reason, never a number.
- **Shot card (5 / 5a):** render the Next Shot card from insights `state` (the five 5a states). Show the camera-spot banner when `capture_quality.far_lane == "limited"`. Use "boards", never "ft". Use the upload footer, and no Score or achievement block, on uploads. Round achievement progress (no "359.359").
- **Pickers:** BallPicker (3a) from Setup and Session "Change"; OilPicker (3b) from Setup; SensorPicker (5b) from "Yes · pick sensor".
- **Failures (4c):** Mac unreachable at pre-flight (Try again / Record anyway, with local queueing); queued row in Session; lost connection mid-job; unsupported clip (HDR, 30 fps, exported copy); duplicate upload.
- **SessionReview (6a):** ended sessions open read-only (no Record / End). Notes stay editable.
- **Under13 (18a):** DOB under 13 blocks onboarding and saves nothing.
- **Fixes:** remove "Lane 14" (Summary, Feedback), the HIT MARK badge (Session), and purple and orange on Form timing chips (use attention yellow). Analyzing copy: "Usually 1–3 min today". Measure real end-to-end time on 5 shots and report it.

## G. Profile photo (Profile.dc.html "Add photo (optional)")
- Migration 015: `profiles.avatar_path`, plus a **private** Storage bucket `avatars` (`<user_id>/avatar.jpg`).
- Add `PUT`, `GET` and `DELETE /me/avatar`. Accept HEIC, JPEG and PNG; center-crop square; 512 px JPEG; strip EXIF/GPS; max 10 MB in. The phone talks only to the API.
- Support both MemoryStore and PgStore. `GET /me/profile` returns `has_avatar` and `avatar_updated_at`. Account deletion removes the avatar.
- iOS: an 84 pt circle on Profile with PhotosPicker and camera, upload progress and Remove. The header Profile button shows the photo when one is set.
- Fix the bug where `PUT /me/profile` silently drops `location` (no column). Add it in 015 or remove the field, and report which.

## H. Docs
- Update `HANDOFF.md` (API rows for `/shots/{id}/pins` and `/me/avatar`), `openapi.json`, `00_CONTEXT/CURRENT_STATE.md`, and the shot review's Status line. Bump Version and Last Updated on every doc you change.

## Final report (one message)
- Per workstream: what changed, commits, test count.
- Before/after on the regression clip and on IMG_8751–8754 vs Ruby.
- Measured analysis time.
- Screens that differ from 3.7.
- **Needs Shayne:**
  - apply migration 015;
  - run the score reset;
  - push when ready;
  - anything else irreversible.
