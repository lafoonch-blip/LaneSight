# Session handoff — 2026-10-25 (for the next Claude Code session)
Version: 1.0
Owner: Shayne

## Orient first (read order)
1. `CLAUDE.md` + `AGENTS.md` (rules, read order).
2. `00_CONTEXT/CURRENT_STATE.md` v1.29 (canonical state — the "Where things stand" top bullets are this work).
3. `00_CONTEXT/DECISIONS.md` (highest DEC number wins).
4. This file for what just happened + what's next.

## Working facts
- Repo: `~/Developer/LaneSight` (clone of GitHub `lafoonch-blip/LaneSight`). Branch **`dev-build-v0`**, pushed
  through commit **b405ee8** (origin up to date). `main` is older; we work on `dev-build-v0`.
- Backend code: `lanesight-core/` (pipeline `lanesight_core/`, API `lanesight_api/`, at-lane runner
  `lanesight_runner/`). Python venv: `cd lanesight-core && source .venv/bin/activate`. Tests:
  `python3 -m pytest` (**203 passing**). Run before every commit.
- iOS: `ios/LaneSight` (XcodeGen → `xcodegen generate` then xcodebuild; DEVELOPMENT_TEAM GK3N928748 pinned).
- Live Mac API: launchd `com.lanesight.api` via `lanesight_api/service.sh` (`restart`/`status`/`logs`), binds
  tailnet `100.84.190.82:8787`, served at `http://shaynes-macbook-pro.tail7fa640.ts.net:8787`. In-memory job
  queue (restart clears jobs). Supabase project ref `europwryibstnmipbvam` (MCP tools).
- Data on the Mac: `~/LaneSightData` (sessions, uploads, out, logs, models, `training_videos/`).

## Working style (IMPORTANT — memory: lanesight-no-permission-prompts)
- **Never ask permission / "want me to proceed?"** Just execute and report. Shayne has said this many times,
  emphatically. As of today this includes the previously-"gated" actions: **apply live migrations, run resets,
  restart/deploy the service, and push to GitHub** — do them as part of finishing work (prep, verify after,
  report). Only a genuinely destructive surprise outside the task warrants a heads-up.
- Non-negotiables: **no mock/placeholder/fallback numbers** (unmeasured = `unavailable` + reason); **accuracy
  over coverage**; no Ruby references in app screens; no pinfall in the dev build.
- Design source of truth = `02_DESIGN/dev_build_v0/*.dc.html` (Claude Chat edits these; Code builds from them,
  never edits them, flags drift). Repo is the one source of truth; re-read files before editing (concurrent
  sessions happen).

## What shipped this session (all committed + pushed; backend DEPLOYED to the live service)
GUARDRAILS 3.7 handoff A–H plus tonight's pale-lane work:
- **B** plausibility gate: `capture_quality.far_lane` + far-lane metrics flagged low_confidence/`best_effort`
  when implausible (speed rising downlane, lateral jumps, off-lane entry/breakpoint). Values unchanged.
- **C** rec-engine state machine: insights carry `state` (move | low_confidence_move | strike_repeat |
  execution_miss | pins_unknown | no_reliable_data) + confidence + note; single-shot move cap 2-and-1
  (3-and-2 needs 2+ agreeing shots); boards clamped 1–39.
- **API** `POST /shots/{id}/pins` (user reports leave when deck unreadable) + insights now recomputed with the
  thrown intent + session history (execution check + transition finally run on the API path).
- **D** pins: recover a clear settled deck frame; report the observed signal, not false "bowler stepped in".
- **E** upload dedupe by content hash (migration 016); score-reset script (`ops/reset_contaminated_score_2026-10-25.sql`).
- **F** iOS 3.7: shot card renders from `state` + camera banner, one status mapping, "boards" not "ft",
  SessionReview read-only, Under-13 block, Lane-X/HIT MARK removed. **Deferred (working equivalents exist):**
  dedicated Ball/Oil/Sensor pickers + a unified Failures screen.
- **G** profile photo `/me/avatar` (512px JPEG, EXIF-stripped, HEIC via sips) + fixed dropped `location`
  (migration 017). iOS avatar UI done.
- **H** docs: openapi regenerated, HANDOFF/CURRENT_STATE/shot-review updated.
- **Pale-lane + 17-clip work:** `find_lanes` retries saturation floors 105→70→50 (pale maple); far-lane gate
  drives insights state (B↔C agree); guarded two numpy crashes → clean errors.

### Deployed to live (Shayne authorized, done):
migrations 016 + 017 applied; reset run (3 pre-DEC-055 uploads detached from session 3338e9ec, derived
score/tier/achievement/finding/notification state cleared for user 551bc775…); service restarted (health ok,
mode live, new routes serving); pushed. **Nothing is pending on Shayne.**

## The OPEN problem (the main next work) — CV accuracy/coverage from any camera position
The 17 training clips (`~/Developer/LaneSight/10-25 training videos/`, pale maple, casual phone positions)
exposed that metrics are only reliable from a narrow framing. Final results: **3/17 analyzed, 6/17 flagged
implausible, 8/17 failed** (pin-impact-not-detected, foul-line-not-found, bad geometry). Root cause = the
**single two-point homography** (foul line + a far line synthesized from the vanishing point; no real downlane
references) + approach-vs-lane confusion + back-half ball loss + ball-above-plane parallax. Full analysis:
`02_RESEARCH/TRAINING_CLIPS_2026-10-25_pale_lanes.md`.

**Plan:** re-architect calibration to detect multiple **known lane fiducials** (arrows 15 ft, dots 7/12/15 ft,
pin spots 60 ft, gutters, foul line, edges) and solve full homography / camera pose (PnP) so the camera can be
anywhere. Shayne is getting an outside CV review — the self-contained brief + questions is
`03_ENGINEERING/CV_METRICS_REARCHITECTURE_BRIEF.md` (example frames in `10-25 training videos/_frames/`).
**Next session:** when Shayne brings back recommendations, vet them against our constraints and implement in
stages. This subsumes the old GUARDRAILS workstream **A** (far-lane calibration).

### Validation sets for any CV change (CLAUDE.md requires re-running these):
- `lanesight-core/validation/IMG_8751–8754` + `_ruby.json` (sensor ground truth; must not regress).
- Regression clip `~/LaneSightData/out/14b234c8…_trim.mov` (off-axis; expectations in
  `validation/14b234c8_regression.json`): entry should land 16–19.5, late speed < early.
- The 17 clips above (coverage target). The 3 that work (IMG_8899/8902/8904) + IMG_8753 are the no-regression set.

## Quick status check for the new session
```
cd ~/Developer/LaneSight && git log --oneline -3 && git status -sb
cd lanesight-core && source .venv/bin/activate && python3 -m pytest -q | tail -2
bash lanesight_api/service.sh status
```
