# LaneSight — live status (single source of truth for every session)

Branch `context` holds only STATUS.md, INBOX.md and handoffs/ (full briefs), so it never conflicts with code branches.

## How to use this branch
- **Claude Code (Mac):** at session start `git -C ~/Developer/LaneSight fetch -q origin context`, then read
  `git show origin/context:STATUS.md`, `…:INBOX.md` and any `…:handoffs/<file>` an INBOX item points to.
  To update: use the worktree `~/Developer/LaneSight-context` (create once:
  `git -C ~/Developer/LaneSight worktree add ../LaneSight-context context`), `git pull`, edit only your own
  rows/sections, then `git commit --no-verify` (the repo's pre-commit hook expects the full codebase and
  silently fails on this 2-file branch) and `git push`; verify with `git ls-remote origin context`.
- **claude.ai chats:** read these via the GitHub connector (or 00_CONTEXT/STATUS.md in the Project).
  The website GitHub connector is READ-ONLY, so a chat can't push here. Put new decisions/requests in the
  Project doc `00_CONTEXT/INBOX.md` (append) and tell Shayne "INBOX updated" — the coordinator session copies
  Project INBOX items onto this branch. Full briefs go in the Project under claude/ AND get copied to handoffs/.
- Never put code on `context`. Never ask Shayne to paste context.

Last updated: 2026-11-23 (Session 1 / shots — v17 on-device PinContactDetector shipped; updated Accuracy + Session 1 rows)

## Live
- Server: Cloud Run lanesight-api-47dfd3b (lanesight-cv-0.7.2 classical + form fixes). Shadow/validation only.
- iPhone (Shayne's): Release from feat/ios-lane-parity, on-device primary ON (classical + changepoint
  + learned fallback with ENGINE_DISAGREE). Form on-device (MediaPipe) from feat/form-ondevice.
- Supabase: migrations through 038 applied (036 outcome tracking, 037 cohort/consent, 038 feedback insights).
- Results UX: one complete result screen (Complete / Offline), metrics-only server call for score + coaching.

## Accuracy — ON-DEVICE vs GROUND TRUTH only (22 labeled clips; truth = foul-cross -> first pin contact; gate ±0.5 mph)
The server engine is OBSOLETE and is NOT a benchmark (no ground-truth guarantee); do not compare on-device to server/Ruby. Grade on-device against Shayne's labels, zero plausible-but-wrong.
- iPhone (v17 `7f07302`): **5/22 within ±0.5 of truth, 0 plausible-but-wrong, MAE 0.166** (on-device engine: foul-anchored deck-motion pin-contact changepoint + VP guard + WEAK spanMin 0.45; measures 8963 correctly at +0.03).
- Withheld (cover only when the on-device signal is reliable enough to be accurate — else withhold with reason): 8754 (TRIPOD) = pins deck not located + sparse track; 8969 = far/small deck → weak scatter signal (span 0.22–0.32 vs 0.55–0.81 on the clips that time cleanly); 8976 = classical lane fails (nGood=0) + pins not located. NOT camera motion (clips near-static; stabilization tried + disproven; a de-jitter attempt this session hurt). Levers = deck-ROI/signal strength + far/small pins & ball detection.
- ~13 clips (behind-ball-return / off-axis) are the DEC-118 unsupported framing (classified `02_RESEARCH/UNCOVERED_CLIPS_CLASSIFICATION_2026-11-18.md`): pins/contact 7, track 5, foul 1 — a capture-position limit.
- Rev rate + early-lane speed: no ground truth (best_effort). Far-lane metrics (entry, breakpoint) off.
- Form: on-device, plausibility-bounded; step count best_effort; blind test set = next 60 fps clips (not recorded yet).

## Active sessions
| Session | Worktree · branch | Now |
|---|---|---|
| Session 1 (shots) | ~/Developer/LaneSight · feat/ios-lane-parity | DEC-132 DONE + pushed (`eaca061`): v15 ENGINE_DISAGREE wired + learned engine shipped; v17 ported server PinContactDetector on-device → 5/22, 0 wrong (recovered 8963); 8969 deck-changepoint done (withheld — weak/small deck signal, NOT camera motion); uncovered clips classified (DEC-118 capture limit). v17 Release installed on phone. NEXT (on-device accuracy vs ground truth; server is obsolete, not a benchmark): strengthen the deck-motion signal/ROI + far/small pins & ball detection so 8969/8976/8754 time accurately vs truth — else keep them withheld (zero plausible-but-wrong). NOT stabilization. Sole deployer. |
| Form | ~/Developer/LaneSight-form · feat/form-ondevice | All assigned items DONE + pushed (558260d): form card vs design (grouping/labels/footer + on-device stills), E5 slide-plant (−13f early case fixed; late-error clips documented), on-device default verified ON. Release installed on Shayne's phone. IDLE — waiting on Shayne's 2 form re-uploads to validate the device fixes. |
| Capture → owned by Form session | ~/Developer/LaneSight-capture · feat/capture-any-video | INBOX 2026-11-23: on-device only + any video in + capture picker (next free DEC, likely 133). |

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

## Infra notes
- Vercel `lanesight-ops`: preview deployments DISABLED (`previewDeploymentsDisabled=true`, Shayne approved 2026-11-23) — every push to `context`/`main` (no `ops-dashboard/`) failed the preview build + emailed Shayne. Production still deploys from `dev-build-v0` (unchanged). Need a feature-branch dashboard preview? Deploy manually via Vercel CLI. No repo change.

## Shayne to-do
- Re-upload the 2 form clips (b6cfd17c rear, ee17c156 side) on the installed build.
- Next bowling session: 10–15 Form deliveries at 60 fps (mostly side view, feet visible).
- F&F: App Store Connect steps (03_ENGINEERING/TESTFLIGHT_FF.md); ANTHROPIC_API_KEY + GitHub token for insights.
