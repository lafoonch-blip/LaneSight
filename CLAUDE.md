# Claude Code instructions (LaneSight)
Read `AGENTS.md` first and follow its read order and rules. Short version: `DECISIONS.md` and `CURRENT_STATE.md` win; never use `99_ARCHIVE/` as a source; bump `Version` / `Last Updated` on any doc you change.

## Local workflow (Shayne's Mac)
- Code: `lanesight-core/` (pipeline `lanesight_core/`, at-lane runner `lanesight_runner/`). Setup and use: `lanesight-core/README.md`.
- Python: `lanesight-core/.venv` (Python 3.12). Activate before anything: `cd lanesight-core && source .venv/bin/activate`.
- Real clips and runner data live in `~/LaneSightData` (`sessions/<id>/shot_NNN.mov`, `lanesight_runner.db`). Training/validation clips: `~/LaneSightData/training_videos`. Never copy videos into the repo.
- Validation reference: `lanesight-core/validation/` (pipeline outputs + Ruby values for IMG_8751–8754). Any change to `lanesight_core/cv/` must be re-run on real clips and compared against these before committing. Report the numbers.
- Run `python3 -m pytest` before every commit; all tests must pass.
- Commit locally. **Push to GitHub only when Shayne says so.**

## Rules
- **Work continuously.** Never pause between steps to ask whether to continue or to report progress. Run the whole task to the end, committing locally as you go, and give one report when finished. Stop only if a test fails and you can't fix it, you're truly blocked, or the next action is irreversible outside the repo (applying a migration to live Supabase, pushing to GitHub).
- No mock, placeholder or fallback numbers. A metric that can't be measured is `unavailable` with a reason. Estimates are labeled (status `best_effort` / low confidence) and say how they were derived.
- Accuracy beats coverage when the number drives a recommendation (e.g. entry board decides pocket/light/high: a 2-board error flips the advice).
- If something fails, show the exact error before changing code.

## Design source of truth (DEC-089 — one app, one design set)
- `02_DESIGN/dev_build_v0/` is the **only** source for the app's screen designs — the v3.7 designs the app is built to. Build the iOS UI from it; read its `README.md` first. (The folder keeps its `dev_build_v0` name for now; there is **no** separate "target state (later)" app — that split was retired in DEC-089.)
- **Do not edit files in that folder.** Shayne changes designs in the claude.ai Claude Design canvas, and Claude (claude.ai) syncs the approved files here.
- If a code change makes a screen differ from its design, list the screen and the difference in your report. Don't silently diverge.
- When design files change (check `git diff 02_DESIGN/`), update the matching SwiftUI screens and report what changed. A newly-synced design is built into the app now — it is never deferred to a "later version."
- Visual standards come from the Figma "01 - Design Standards" page (tokens are listed in the design README); logos and icons come from `02_DESIGN/brand/`. `02_DESIGN/target_state/` holds forward design-system notes + `lane_render`, not a second app.
