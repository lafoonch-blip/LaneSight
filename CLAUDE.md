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

## Design source of truth (DEC-091 — Figma target state; one app)
- The app is built to the **Figma "Target state – v3.7"** designs (file `k6F8iHTtl2ZHvnXlHmYPnd`, page "01 — Home & Foundation"). Guide and changelog: `02_DESIGN/target_state/README.md`.
- **Your build queue is `03_ENGINEERING/APP_DESIGN_CHANGES.md`.** Before any UI work, read it and build every entry marked **NOT BUILT**, in order: match the PNGs in `02_DESIGN/target_state/screens/<date>/` and the written spec. Then set the entry to **BUILT (commit)**. If you must differ, add **DIFFERS:** with the reason. Never defer an entry to a "later version".
- If you have Figma access (Dev Mode / Figma MCP), use the node IDs in each entry for exact values. Otherwise, the PNGs plus the spec are the reference.
- `02_DESIGN/dev_build_v0/` is **frozen** (last synced 2026-10-26). Don't build new UI from it; Figma and APP_DESIGN_CHANGES.md win where they differ.
- Don't edit design files. If a code change makes a screen differ from its design, list the screen and the difference in your report.
- Visual standards come from the Figma "01 - Design Standards" page (tokens in the design README); logos and icons come from `02_DESIGN/brand/`. Lane view reference: `02_DESIGN/target_state/lane_render/`.
