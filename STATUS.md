# LaneSight — live status (single source of truth for every session)

Branch `context` holds ONLY this file and INBOX.md, so it never conflicts with code branches.
- Every Claude Code session reads STATUS.md + INBOX.md at start and updates STATUS.md when it
  finishes a task (commit + push to `context`).
- claude.ai chat sessions read both via GitHub at the start of any LaneSight conversation and
  append new decisions/requests to INBOX.md.

Last updated: 2026-11-23 (Form session, Claude Code — updated Form row)

## Live
- Server: Cloud Run lanesight-api-47dfd3b (lanesight-cv-0.7.2 classical + form fixes). Shadow/validation only.
- iPhone (Shayne's): Release from feat/ios-lane-parity, on-device primary ON (classical + changepoint
  + learned fallback with ENGINE_DISAGREE). Form on-device (MediaPipe) from feat/form-ondevice.
- Supabase: migrations through 038 applied (036 outcome tracking, 037 cohort/consent, 038 feedback insights).
- Results UX: one complete result screen (Complete / Offline), metrics-only server call for score + coaching.

## Accuracy (22 labeled clips; truth = foul-cross -> first pin contact; gate ±0.5 mph)
- iPhone: 4/22 within, 0 wrong. Server production engine: 8/22 within, 0 wrong.
- ~12 clips (mostly 11/1 behind-ball-return / portrait) get no speed on any engine. #1 open problem.
- Rev rate + early-lane speed: no ground truth (best_effort). Far-lane metrics (entry, breakpoint) off.
- Form: on-device, plausibility-bounded; step count best_effort; blind test set = next 60 fps clips (not recorded yet).

## Active sessions
| Session | Worktree · branch | Now |
|---|---|---|
| Session 1 (shots) | ~/Developer/LaneSight · feat/ios-lane-parity | DEC-132 coverage: on-device deck changepoint (8969), then the uncovered clips by first-failing stage (Python first, then port). Sole deployer. |
| Form | ~/Developer/LaneSight-form · feat/form-ondevice | All assigned items DONE + pushed (558260d): form card vs design (grouping/labels/footer + on-device stills), E5 slide-plant (−13f early case fixed; late-error clips documented), on-device default verified ON. Release installed on Shayne's phone. IDLE — waiting on Shayne's 2 form re-uploads to validate the device fixes. |
| Capture (to start) | ~/Developer/LaneSight-capture · feat/capture-any-video | INBOX 2026-11-23: on-device only + any video in + capture picker (next free DEC, likely 133). |

## Latest decisions (full text: 00_CONTEXT/DECISIONS.md on feat/ios-lane-parity)
- DEC-126 usability first, iPhone primary · DEC-127 on-device metrics + metrics-only server call, one result screen
- DEC-128 plausibility bounds / honest stage report · DEC-129 Form on-device (MediaPipe) · DEC-130 learned detection front-end
- DEC-131 Form plausibility + swing-anchored delivery selector · DEC-132 pin contact measured visually, NO audio
- Pending: on-device only / any video in / capture default (INBOX 2026-11-23)

## Standing rules
- No fabricated or plausible-but-wrong numbers; unavailable + reason. No audio-based measurement. No AGPL models.
- No user taps/labeling for calibration; Shayne doesn't label — sessions auto-label and self-audit.
- Push own branches when gates pass (verify ls-remote). Never merge to main. Only Session 1 deploys.
- Big artifacts under ~/LaneSightData, never /tmp. iPhone plugged in + unlocked for device runs.

## Shayne to-do
- Re-upload the 2 form clips (b6cfd17c rear, ee17c156 side) on the installed build.
- Next bowling session: 10–15 Form deliveries at 60 fps (mostly side view, feet visible).
- F&F: App Store Connect steps (03_ENGINEERING/TESTFLIGHT_FF.md); ANTHROPIC_API_KEY + GitHub token for insights.
