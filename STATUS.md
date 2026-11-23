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

Last updated: 2026-11-23 (Capture/Form session — capture A+B+C-core done + pushed (aa63f3b); HDR device test deferred (iPhone busy))

## Live
- 📱 **DEVICE FREE (Form done).** Combined Release INSTALLED on the phone: `integration/capture-form` `45b5fb3` = feat/capture-any-video (DEC-133 capture/any-video/picker) + feat/form-ondevice (form-usability fix b7ec24a) + latest feat/ios-lane-parity (DEC-134 strict speed + Active Session fix bcabde1); build contains SessionView/QuickPickerSheets/NoReadCard (verified in the binary). **Shayne to confirm on-phone (UI, can't automate):** (1) re-upload the 2 form clips → honest card ("Not measured", no −5.75, stills on the rear clip); (2) Settings › Recording quality shows only supported formats; (3) HDR import works. Form gate (sim): delivery-window test PASSED; parity test shows IMG_8824 residual E7/E8/plant misses = the known sim-vs-device MediaPipe landmark diff, NOT the new mis-segmentation rule (which doesn't fire on the clean labeled clips) — authoritative gate needs an on-device run.
- ✅ **Active Session usability fix SHIPPED (Session 1)**: merged `fix/active-session-usability` → `feat/ios-lane-parity` (`bcabde1`, pushed), xcodegen+build 0 errors, pytest 465 passed. Server **DEPLOYED `lanesight-api-bcabde1`** (regression PASS + smoke PASS): Home activity epoch-timestamp fix (verified live: `/me/activity` created_at is float ✓) + `coach.py` neutral `not_read` tip (no tripod/camera blame, DECISIONS #3). Release installed on phone. **UI tap-through (session→ball/oil→End→Skip→summary→Done→Home no-banner) = Shayne to confirm** (physical-device UI, can't automate). Follow-up (not blocking; data already fixed, app hides >12h): server-side close stale sessions at last-shot time.
  - **Form QUEUED NEXT** (combined capture+form Release built in `~/Developer/LaneSight-install`, `integration/capture-form` c5f5d17; ready to install): form-usability fix install + HDR check (IMG_8751/8754/8831) + recording-picker verify + stills-on-rear-clip + OnDeviceFormGateTests. Ping when the device is free.
- Server: Cloud Run lanesight-api-bcabde1 (classical + form fixes + Home activity epoch fix + neutral coach not_read). Shadow/validation only.
- iPhone (Shayne's): Release from feat/ios-lane-parity, on-device primary ON (classical + changepoint
  + learned fallback with ENGINE_DISAGREE). Form on-device (MediaPipe) from feat/form-ondevice.
- Supabase: migrations through 038 applied (036 outcome tracking, 037 cohort/consent, 038 feedback insights).
- Results UX: one complete result screen (Complete / Offline), metrics-only server call for score + coaching.

## Accuracy — ON-DEVICE vs GROUND TRUTH only (22 labeled clips; truth = foul-cross -> first pin contact; gate ±0.5 mph)
The server engine is OBSOLETE and is NOT a benchmark (no ground-truth guarantee); do not compare on-device to server/Ruby. Grade on-device against Shayne's labels, zero plausible-but-wrong.
- iPhone (v17 `7f07302`): **5/22 within ±0.5 of truth, 0 plausible-but-wrong, MAE 0.166** (on-device engine: foul-anchored deck-motion pin-contact changepoint + VP guard + WEAK spanMin 0.45; measures 8963 correctly at +0.03).
- Withheld, root-caused on the Python dev harness (vs ground truth; NOT vs server): **8969** = deck pre-contact baseline NOISY (0.153 > 0.08 honesty gate) from the camera position — the reference ALSO withholds it; forcing it would risk a wrong number → stays withheld (correct). **8976** = ball untrackable (reference: 13 track pts, no pins, no foul-cross) → genuinely unmeasurable, withheld. **8754** (TRIPOD) = CLOSED, stays withheld: the trim clips the shot (NOTRIM recovers a 102-pt track) but the deck contact then fires ~0.67 s late → wrong 13.6 — so the trim's withholding is load-bearing for zero-wrong (widening it ships a wrong number). Box-ROI fix tried → didn't fix the timing + regressed the gate (8968 wrong, MAE→1.13) → reverted. Real coverage needs shot-isolation + a faithful deck-timing (phase-correlation) port. NOT camera motion.
- ~13 clips (behind-ball-return / off-axis) are the DEC-118 unsupported framing (classified `02_RESEARCH/UNCOVERED_CLIPS_CLASSIFICATION_2026-11-18.md`): pins/contact 7, track 5, foul 1 — a capture-position limit.
- Rev rate + early-lane speed: no ground truth (best_effort). Far-lane metrics (entry, breakpoint) off.
- Form: on-device, plausibility-bounded; step count best_effort; blind test set = next 60 fps clips (not recorded yet).

## Active sessions
| Session | Worktree · branch | Now |
|---|---|---|
| Session 1 (shots) | ~/Developer/LaneSight · feat/ios-lane-parity | DEC-132 DONE + pushed (`eaca061`): v15 ENGINE_DISAGREE wired + learned engine shipped; v17 ported server PinContactDetector on-device → 5/22, 0 wrong (recovered 8963); 8969 deck-changepoint done (withheld — weak/small deck signal, NOT camera motion); uncovered clips classified (DEC-118 capture limit). v17 Release installed on phone. Investigated 8969/8976/8754 on the Python harness vs truth: 8969 (NOISY deck baseline) + 8976 (untrackable ball) stay withheld (reference withholds them too; forcing = wrong). 8754 investigation CLOSED: NOTRIM confirms the trim clips the shot (track recovers 102 pts), but the deck contact then fires ~0.67 s late → **wrong 13.6** (the trim's withholding is load-bearing for zero-wrong — widening it ships a wrong number). A box-based deck-ROI fix was tried → did NOT fix 8754's timing AND regressed the 22-clip gate (8968 → plausible-but-wrong, MAE 0.166→1.13) → REVERTED. **Outcome: none of 8969/8976/8754 is safely coverable; all 3 correctly withheld; engine UNCHANGED at v17 (5/22, 0 wrong), reinstalled.** Open coverage frontier needs a safer shot-isolation + deck-timing approach (phase-correlation port), not a quick fix. Also owns on-device stabilization for Form's high-fps work (future). Sole deployer. |
| Form | ~/Developer/LaneSight-form · feat/form-ondevice | **Form-usability fix MERGED + pushed (`b7ec24a`): compiles.** fix/form-result-usability (withhold swing metrics when a core timing is implausible; rebuild positions after the gate; stills via AVAssetReader + FormStillStore; card shows only measured items + one "Not measured" card) merged into feat/form-ondevice. **Root-caused the 2 new uploads (clips pulled to ~/LaneSightData/form):** rear `0caad150` = early approach steps MISSED in rear view → Python finds 3 strikes/1.05s (real ~5 steps) = plausible-but-wrong step_count; side `be86b1db` = swing events E4/E6/E7 not detected → Python correctly WITHHOLDS all (FORM_DELIVERY_NOT_ISOLATED, zero plausible-but-wrong — the merge fixes the installed build's −5.75 display). **Detection fix (early rear steps) GATED on Shayne's labels** → Labeler batch ready (`form_events_newclips.json`, pushed `e766b67`). **Install + gate PENDING device** (queued behind Session 1; combined capture+form Release built). |
| Capture → owned by Form session | ~/Developer/LaneSight-capture · feat/capture-any-video | **A + B + C-core DONE + pushed (`aa63f3b`); iOS builds (0 errors).** A: DEC-133 + SERVER_MEASUREMENT_RETIREMENT.md + `CaptureProbe` + capture-floor copy + CAPTURE_TEST_PLAN + doc sweep. B (`0e3a33d`): HDR→SDR tone-map + probe at both on-device entries (engine only sees SDR, DEC-113); `capture_quality.capture` stored on every shot (client + server); below-floor → each metric unavailable + its reason. C (`aa63f3b`): recording-quality picker — `CaptureFormats` model + device-format enumeration + persistence (default 1080p120, Form floor 60), CameraController honors chosen res/fps, **Settings › Recording quality** (822:4216), **Upload** detected-capture + 'Lower-quality clip' badge (822:4354) + copy (422:5069). **Remaining C (small):** Setup quick sheet 822:4081 + Setup Camera row 411:3491. **HDR device test DEFERRED** — needs the iPhone (Session 1 holds it) + an on-device baseline; run IMG_8751/8754/8831 when free (amendment 8). **D (engine 120/240/4K) BLOCKED:** reuses Session 1's stabilization (amendment 7, not built) + high-fps clips + on-device validation. E = gates+Shayne; F = Shayne's recordings. |
| Docs consolidation | ~/Developer/LaneSight-docs · docs/consolidation-2026-11 | **DONE + pushed (`4f7e4c7`), verified ls-remote.** Doc-only (no code/engine/threshold/product changes). AGENTS.md+CLAUDE.md agree: STATUS.md=live truth, CURRENT_STATE=architecture/history, one push rule. `METRIC_CAPABILITIES.md` replaced by a fail-closed **metric contract** (status/evidence/display/coaching, "Guaranteed" retired everywhere). Supersession notices on MASTER_CONTEXT §4/§18, ENGINE_ARCHITECTURE_DECISION, MVP_READINESS_PLAN, FEATURE_REVIEW. APP_DESIGN_CHANGES+design README: honesty>parity, coaching only on coaching-eligible, lane path only where observed; blocking "Analyzing"→DEC-127 Complete/Offline. DECISIONS.md untouched. 2 OPEN coaching-eligibility conflicts logged to INBOX for Shayne (rev rate; near-lane boards vs DEC-034/DEC-127). IDLE. |

## Latest decisions (full text: 00_CONTEXT/DECISIONS.md on feat/ios-lane-parity)
- DEC-126 usability first, iPhone primary · DEC-127 on-device metrics + metrics-only server call, one result screen
- DEC-128 plausibility bounds / honest stage report · DEC-129 Form on-device (MediaPipe) · DEC-130 learned detection front-end
- DEC-131 Form plausibility + swing-anchored delivery selector · DEC-132 pin contact measured visually, NO audio
- DEC-133 one on-device measurement engine; any video in (detected capture drives availability); capture default 1080p120 SDR overridable; retire the server measurement path per metric as each passes its DEC-118 gate (on `feat/capture-any-video`)

## Standing rules
- No fabricated or plausible-but-wrong numbers; unavailable + reason. No audio-based measurement. No AGPL models.
- No user taps/labeling for calibration; Shayne doesn't label — sessions auto-label and self-audit.
- Push own branches when gates pass (verify ls-remote). Never merge to main. Only Session 1 deploys.
- Big artifacts under ~/LaneSightData, never /tmp. iPhone plugged in + unlocked for device runs.
- **One product engine = on-device (DEC-133): no new server-only measurement work; server stays auth/data/Score/coaching + Python dev harness.** Session 1's DEC-132 on-device coverage is on-device work, NOT withdrawn (amendment 6).
- **One iPhone — take turns (amendment 8):** note here when you start a device build/benchmark; don't run concurrent device work with Session 1 or Form.

## Infra notes
- Vercel `lanesight-ops`: preview deployments DISABLED (`previewDeploymentsDisabled=true`, Shayne approved 2026-11-23) — every push to `context`/`main` (no `ops-dashboard/`) failed the preview build + emailed Shayne. Production still deploys from `dev-build-v0` (unchanged). Need a feature-branch dashboard preview? Deploy manually via Vercel CLI. No repo change.

## Shayne to-do
- Re-upload the 2 form clips (b6cfd17c rear, ee17c156 side) on the installed build.
- Next bowling session: 10–15 Form deliveries at 60 fps (mostly side view, feet visible).
- F&F: App Store Connect steps (03_ENGINEERING/TESTFLIGHT_FF.md); ANTHROPIC_API_KEY + GitHub token for insights.
