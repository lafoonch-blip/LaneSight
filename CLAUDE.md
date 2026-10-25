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
- No mock, placeholder or fallback numbers. A metric that can't be measured is `unavailable` with a reason. Estimates are labeled (status `best_effort` / low confidence) and say how they were derived.
- Accuracy beats coverage when the number drives a recommendation (e.g. entry board decides pocket/light/high: a 2-board error flips the advice).
- If something fails, show the exact error before changing code.

## Design source of truth (Dev Build v0)
- `02_DESIGN/dev_build_v0/` is the **only** source for Dev Build v0 screen design. Build the iOS UI from it; read its `README.md` first.
- **Do not edit files in that folder.** Shayne changes designs in the claude.ai Claude Design canvas, and Claude (claude.ai) syncs the approved files here.
- If a code change makes a screen differ from its design, list the screen and the difference in your report. Don't silently diverge.
- When design files change (check `git diff 02_DESIGN/`), update the matching SwiftUI screens and report what changed.
- Visual standards come from the Figma "01 - Design Standards" page (tokens are listed in the design README); logos and icons come from `02_DESIGN/brand/`. Figma screen designs are **target state** for later versions; don't build Dev Build v0 screens from them.
