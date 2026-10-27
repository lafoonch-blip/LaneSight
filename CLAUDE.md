# Claude Code instructions (LaneSight)
Read `AGENTS.md` first and follow its read order and rules. Short version: `DECISIONS.md` and `CURRENT_STATE.md` win; never use `99_ARCHIVE/` as a source; bump `Version` / `Last Updated` on any doc you change.

## Where LaneSight lives (2026-10-27)
- **Source of truth:** GitHub `lafoonch-blip/LaneSight`, `main`. Start from `origin/main` (`git fetch`), not from a Mac or an old clone. LaneSight no longer depends on Shayne's Mac.
- **Backend:** Google Cloud Run `lanesight-api` (us-east1) + Supabase `europwryibstnmipbvam`. Deploys: `03_ENGINEERING/DEPLOY_CLOUDRUN.md`. Code that runs there must not rely on macOS tools (Keychain, `sips`, launchd).
- **Ball catalog:** reaches Supabase only from `main`, via the weekly refresh (`lanesight-core/data/ball_catalog/REFRESH.md`).

## Local development (optional, any machine)
- Code: `lanesight-core/` (pipeline `lanesight_core/`, at-lane runner `lanesight_runner/`). Setup and use: `lanesight-core/README.md`.
- Python 3.12: `cd lanesight-core && pip install -e '.[dev,api]'` (on the Mac: `source .venv/bin/activate`).
- On Shayne's Mac, real clips and runner data live in `~/LaneSightData` (`sessions/<id>/shot_NNN.mov`, `lanesight_runner.db`). Training/validation clips: `~/LaneSightData/training_videos`. Never copy videos into the repo.
- Validation reference: `lanesight-core/validation/` (pipeline outputs + Ruby values for IMG_8751–8754). Any change to `lanesight_core/cv/` must be re-run on real clips and compared against these before committing. Report the numbers.
- Run `python3 -m pytest` before every commit; all tests must pass.
- Commit on a feature branch. **Push to GitHub only when Shayne says so**, and never to `main` directly.

## Rules
- **Work continuously.** Never pause between steps to ask whether to continue or to report progress. Run the whole task to the end, committing locally as you go, and give one report when finished. Stop only if a test fails and you can't fix it, you're truly blocked, or the next action is irreversible outside the repo (applying a migration to live Supabase, pushing to GitHub).
- No mock, placeholder or fallback numbers. A metric that can't be measured is `unavailable` with a reason. Estimates are labeled (status `best_effort` / low confidence) and say how they were derived.
- Accuracy beats coverage when the number drives a recommendation (e.g. entry board decides pocket/light/high: a 2-board error flips the advice).
- If something fails, show the exact error before changing code.

## Design source of truth (Dev Build v0)
- `02_DESIGN/dev_build_v0/` is the **only** source for Dev Build v0 screen design. Build the iOS UI from it; read its `README.md` first.
- **Do not edit files in that folder.** Shayne changes designs in the claude.ai Claude Design canvas, and Claude (claude.ai) syncs the approved files here.
- If a code change makes a screen differ from its design, list the screen and the difference in your report. Don't silently diverge.
- When design files change (check `git diff 02_DESIGN/`), update the matching SwiftUI screens and report what changed.
- Visual standards come from the Figma "01 - Design Standards" page (tokens are listed in the design README); logos and icons come from `02_DESIGN/brand/`. Figma screen designs are **target state** for later versions; don't build Dev Build v0 screens from them.
