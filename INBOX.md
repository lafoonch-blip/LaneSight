# INBOX — decisions/requests from claude.ai chats not yet folded into the repo

Claude Code sessions: at start, act on every OPEN item addressed to you (record any DEC in DECISIONS.md
on your branch, do the work), then mark it DONE with your commit hash and update STATUS.md.
claude.ai chats: append new items at the bottom (date, OPEN, who it's for, the decision/request).

## 2026-11-23 — OPEN — ALL SESSIONS — DECISIONS (record as the next free DECs; these OVERRIDE conflicting items below)
Shayne, 2026-11-23 11:41, after reviewing an outside assessment ("visual observation reliability + capture-pipeline integrity, not physics,
is the bottleneck"):
1. FEATURE FREEZE: no new measurement features/metrics until Shot and Form each show repeatable accuracy AND coverage on UNSEEN clips.
   This pauses capture workstream item D (engine at 120/240/4K) and any new metric. Bug fixes, detection reliability, input-pipeline
   integrity, and the usability fixes below continue.
2. DONE = VERIFIED ON THE PHONE: nothing counts as done until it is compiled, installed, run on Shayne's iPhone, and graded against the
   labeled clips. Uncompiled branches (incl. the claude.ai ones below) are drafts until then. Report numbers, not intentions.
3. PINS ARE IN EVERY CLIP: Shayne states the pins are visible in every video he has uploaded. A missed pin contact / deck is a DETECTION
   failure, not a capture-position limit. REVERSE the DEC-118 "unsupported framing" classification of the ~13 behind-ball-return / off-axis
   clips (02_RESEARCH/UNCOVERED_CLIPS_CLASSIFICATION_2026-11-18.md): they are detection failures to fix and count against coverage.
   Do NOT add capture-position enforcement as a substitute for detection. (Centered behind the ball return must be supported.)
4. SHAYNE WILL LABEL: supersedes "Shayne doesn't label". He will label clips when it measurably helps. Use the existing LaneSight Labeler
   (double-click `LaneSight Labeler.command`; tasks in lanesight-core/validation/label_tasks/*.json). Sessions prepare the label tasks
   (which clips, which moments/boxes, with hints pre-filled so he only confirms/adjusts) and tell Shayne in one line when a batch is ready
   and roughly how long it takes. Priorities: (a) shot: foul-line crossing frame, first pin contact frame, ball center on a few frames,
   pin-deck box — across ALL his clips incl. the 13; (b) form: E2 ball start, E3 pushaway, E4 top of swing, E7 release, E8 slide stop.
   Keep a held-out UNSEEN set (never tuned on) for the gate in #1.
5. Measure detection quality separately from metric quality: lane landmarks, ball-detection recall, track continuity, pin-contact timing
   error vs labels — reported per stage, before speed/boards.

## 2026-11-23 — IN PROGRESS (foundational pass `bcca484` on feat/capture-any-video) — Capture workstream (owned by the FORM session): on-device only, any video in, capture default + override
NOTE: item D (engine 120/240/4K) is PAUSED by the feature freeze above; B ("any video in" input integrity) continues.
**Progress:** A (foundational) done + pushed — DEC-133, SERVER_MEASUREMENT_RETIREMENT.md, `CaptureProbe`, capture-floor copy, CAPTURE_TEST_PLAN. Remaining A (doc sweep) → B (any video in: probe wired into record+upload, HDR→SDR, below-floor reasons) → D (engine 120/240/4K). C picker = Figma-gated; E retirement = gates+Shayne; F benchmark/clips = Shayne. Not fully DONE (epic) — leaving OPEN with this hash.
Full handoff: `handoffs/HANDOFF_2026-11-23_ON_DEVICE_ONLY_ANY_VIDEO.md` on this branch (`git show origin/context:handoffs/HANDOFF_2026-11-23_ON_DEVICE_ONLY_ANY_VIDEO.md`).
Amendments that override it:
1. Use the next free DEC number in the repo (likely DEC-133), not DEC-126. Ignore the mirror's "v1.81 / DEC-125" notes.
2. "Stop server CV work" = no server-only measurement work. The Python reference engine stays the dev/validation
   harness: algorithms may be developed and graded there first, then ported (DEC-106). Session 1's coverage work continues.
3. Keep the in-app default at 1080p120 SDR (Form floor 60) until the device benchmark + DEC-118 gates pass at a higher
   format; promote it in a separate commit with the numbers.
4. Own worktree/branch feat/capture-any-video; CaptureView edits minimal and additive (the Form session also edits it).
5. Re-confirm the DEC number right before writing it (git fetch; highest DEC across all remotes); parallel sessions may have taken 133.
6. Carve-out: Session 1's DEC-132 coverage work (on-device stabilization, developed on the Python reference then ported) is on-device work, NOT "server-only CV". Do not withdraw or touch it under §3.2 item 5.
7. On-device frame stabilization is owned by Session 1 (its next item). The capture session reuses it for the high-fps/4K engine-load work (§3.5); don't build a second one. Coordinate via STATUS.md.
8. One iPhone, shared CaptureView: serialize device builds/benchmarks with Session 1 and the Form session (check STATUS.md for who's on the device); keep CaptureView changes minimal and additive.

## 2026-11-23 — DONE (info) — claude.ai capture chat: Vercel preview deploys turned off for lanesight-ops
Shayne approved. The `lanesight-ops` Vercel project now has preview deployments disabled (previewDeploymentsDisabled=true),
because every push to `context` (no `ops-dashboard/` folder) and `main` failed the preview build and emailed him.
Production still deploys from `dev-build-v0` (unchanged). Feature-branch dashboard previews no longer build; if one is ever
needed, deploy it manually with the Vercel CLI. No repo change required. Record in STATUS.md infra notes.

## 2026-11-23 — OPEN — Consolidated plan (both sessions)
- FORM session owns the capture workstream (it already drafted DEC-133, CaptureProbe, floor reasons, S1–S5 plan).
  Order: A push the draft to feat/capture-any-video (branch from its current HEAD) + doc sweep → B "any video in"
  (probe wired into record + upload, HDR→SDR on device, per-metric below-floor reasons) → D engine at 120/240/4K (PAUSED — freeze).
  C (Recording picker) waits on Figma frames; E (server retirement) waits on gates + Shayne; F waits on Shayne's recordings.
- SESSION 1 (shots): 1) 8969 far deck signal; 2) 8754 / 8976 pin deck + lane at distance; 3) the ~13 reclassified clips (now detection
  failures, see DECISIONS #3); owns on-device stabilization. Python reference first, then port; 22-clip gate after every CV change;
  zero plausible-but-wrong. Rev rate + early-lane speed stay best_effort until real truth exists. Sole deployer.
- Device: one iPhone; sessions take turns (note in STATUS when using it).

## 2026-11-23 — OPEN — Form session (capture workstream, item C unblocked): Figma designs for recording quality are ready
Figma file k6F8iHTtl2ZHvnXlHmYPnd, page "01 — Home & Foundation", section "Target state – v3.7":
- NEW `822:4216` Settings › Recording quality · v3.7 — Shot (1080p60 / 1080p120 Recommended ✓ / 1080p240 / 4K60) and Form
  (1080p60 / 1080p120 Recommended ✓ / 1080p240) option lists with trade-off lines; HDR-off note; "Form never below 60"; Dark-lanes note.
- NEW `822:4081` Sheet · Recording quality (from Setup) · v3.7 — same Shot options as a bottom sheet, "Use this format".
- NEW `822:4354` Upload video · lower-quality clip (30 fps HDR) · v3.7 — amber capture badge + "Lower-quality clip" note with tip.
- CHANGED `434:6174` Settings: Capture row value "1080p · 120 fps", footnote "Shots record at 1080p, 120 fps by default. Form never goes below 60 fps."
- CHANGED `411:3491` Setup · Shot: pre-flight Camera row "1080p · 120 fps ›" (taps open the sheet).
- CHANGED `422:5069` Upload video: "Results in about 15 seconds, analyzed on your iPhone."
Add APP_DESIGN_CHANGES.md entries (NOT BUILT → build) with these node IDs; only list formats the device actually supports (hide 4K/240 rows when unavailable).

## 2026-11-23 — OPEN — SESSION 1 (shots, sole deployer): merge + build + install the Active Session usability fix (TOP PRIORITY)
Branch `fix/active-session-usability` (4 commits on top of `eaca061`, pushed by claude.ai chat; NOT compiled — no Xcode there).
Shayne's device test: lane diagram unreadable, ball/oil not changeable, Skip on end-survey didn't end, session could never be ended.
Root cause of "stuck": never-closed server sessions; ending one made the app adopt the next (Shayne's account is 551bc775; the 62 open
sessions were on test account 0e5e25a7). DATA FIX DONE 2026-11-23 (Shayne approved): ALL 73 open sessions across all accounts were closed
in Supabase with ended_at = last shot time (or started_at when no shots) — 0 open sessions remain.
Changes: SessionView.swift (Ball/Oil tiles at top, full-width lane + Pins/Pocket/Target tiles, pinned Record/End, end runs after the
feedback sheet dismisses, ending overlay + error/Try again, Summary Done → Home), new Session/QuickPickerSheets.swift (one-tap ball/oil),
AppModel.swift (End closes all other open sessions; resume adopts newest open session and closes older ones). APP_DESIGN_CHANGES 2026-11-23-A (DIFFERS from Figma 413:3804).
NOTE: closeStaleOpenSessions calls POST /sessions/{id}/end, which stamps ended_at = now() → such rows would show multi-week durations
(Home now hides durations > 12 h). Better: have the server close stale sessions at their last shot time (or started_at) — please adjust.
2nd commit (APP_DESIGN_CHANGES 2026-11-23-C, Shayne's shot upload 762be1be: lane ok, track sparse, metrics failed — TRACK_TOO_SPARSE_FOR_SPEED,
PIN_IMPACT_NOT_DETECTED, rev spin period not clean → zero numbers): new Result/NoReadCard.swift replaces the 3D lane + empty gauges when every
metric is unavailable; "What worked" now lists on-device `track`/`metrics` stages (were hidden). Also please stop server coach.py:164
"Move the tripod…" when nothing was measured / on uploads (deploy). NoReadCard's filming tip must not blame camera position for missed
pins (DECISIONS #3) — reword to a neutral tip.
3rd commit `ab1a7ad` — Home "Recent activity" always failed: GET /me/activity returned the raw Postgres timestamptz (ISO string) for
`created_at`; iOS ActivityItem decodes it as Double → whole list fails → "Couldn't load this". Server fix: store.list_activity converts
created_at with _ts_epoch (needs a Cloud Run DEPLOY). App fix: ActivityItem decodes created_at leniently. Home session rows omit durations > 12 h.
Pytest not run in the chat — run it.
4th commit `2454798` — ops/simulated/ (see the simulated-data item below).
To do: merge into feat/ios-lane-parity, xcodegen + fix any compile errors, run pytest, DEPLOY the server (activity fix), Release install on the
phone, verify: Home Recent activity loads; open session → change ball + oil → End → Skip → summary → Done → Home with no banner.
Not fixed here: FormSessionView "End session" still uses try? with no feedback/summary — same pattern; Form session to align it.

## 2026-11-23 — OPEN — FORM session: merge + build + install the Form result fix, then fix swing-moment detection on Shayne's 2 clips
Branch `fix/form-result-usability` (off `feat/form-ondevice` 558260d, pushed by claude.ai chat; NOT compiled). APP_DESIGN_CHANGES 2026-11-23-B.
Shayne's uploads today: rear `0caad150` (events E4 9.34 / E7 9.52 / first_step 9.14 / E8 9.61 → whole approach in 0.47 s; approach 0.38 s
flagged implausible but "Early" checkpoints + pendulum still shown), side `be86b1db` (E2/E3/E4/E7 null; rejected 0.05 s downswing still shown
as Pendulum; backswing_height −5.75 shown → installed build lacks the backswing band). No stills on either; server key_frames [] for both.
Branch changes: engine withholds swing events + swing-derived metrics when a core timing is implausible and rebuilds positions after the
gate; stills read via AVAssetReader on the engine's PTS clock + persisted per shot (FormStillStore); FormCardView shows only measured
items, one "Not measured on this clip" card with plain reasons, "couldn't time this delivery" lead, tips collapsed, no version text.
To do: 1) merge into feat/form-ondevice, compile, run OnDeviceFormGateTests (the mis-segmentation rule may change gate outcomes — report),
Release install. 2) Pull both clips off the phone into ~/LaneSightData and root-cause why the delivery window is wrong (rear) / empty (side);
fix on the Python reference first, then port; re-run the form gate. Zero plausible-but-wrong. 3) Confirm stills now appear on the rear clip.
4) Prepare a Labeler task for form events (DECISIONS #4) on all form clips incl. these two.

## 2026-11-23 — DONE (`6e71dda`, DEC-134 on feat/ios-lane-parity) — SESSION 1: keep speed strict
Recorded as **DEC-134** (speed reported only when timed foul→detected pin contact; no early-lane/rev fallback; unavailable+reason).
**DEC-134 is TAKEN** — DOCS session: use **DEC-135** for the coaching-eligibility + headline "Avg speed" decision. Enforcement
(coaching/rec server+on-device + Active Session rings + shot-card "Avg speed" headline) pending on Session 1 after the 8754/coverage pass.
(original item:)
## 2026-11-23 — OPEN — SESSION 1 (shots): DECISION — keep speed strict (record as next free DEC)
Shayne chose (2026-11-23, after upload 762be1be produced zero numbers): keep speed strict. Speed is reported ONLY when timed foul line →
detected pin contact. Do NOT fall back to an early-lane / front-lane speed (or rev) estimate when pin contact isn't detected — show
unavailable + reason (the NoReadCard on `fix/active-session-usability` handles the zero-number case). Empty results are accepted until
on-device coverage improves; coverage work vs ground truth (pin contact / deck signal / far-small ball+pins) stays the priority.
Also: the Active Session rings currently show a session mean speed/rev labeled "best effort" (16.6 mph / 359 rpm seen today) — check where
that value comes from and make it follow this rule (strict speed only; no unvalidated estimate shown as a number).

## 2026-11-23 — INFO (all sessions) — SIMULATED history staged on Shayne's REAL account (his explicit request; overrides "real account = real data only" for this case)
Account 551bc775 (Shayne Lafoon) now carries simulated history so he can see Home with tiers/score: 14 practice sessions (Sep 27 → Nov 22),
227 shots, 1,816 measurements, 15 score snapshots (14 session-end 560 → 678 + one carried-forward "now" copy of 678 so Home's latest-snapshot
read shows it), Gold tier (tier_state gold/678), 8 achievement unlocks (Dialed In, Silver/Gold Status, Rising Star, Level Up, Line Locked,
Data Driven, Century Climber) + 22 activity items. Generated by running the REAL engines (score L-dev-0, tiers, achievements) through PgStore
against an emulated PostgREST — `lanesight-core/ops/simulated/`.
NOT staged: notifications (no popup flood), personal_baseline / findings (real coaching "normal" left untouched), feedback, uploads.
TAGS (exclude these from any accuracy/coverage/feasibility analysis!): shots.algorithm_version='simulated' + record.simulated=true;
score_snapshot.inputs.simulated; activity_item.payload.simulated; user_achievement_unlock/progress.evidence_ref.simulated.
Removal: `lanesight-core/ops/simulated/CLEANUP_shayne_simulated_2026-11-23.sql` (on fix/active-session-usability).
Note: Home Recent activity still shows "Couldn't load this" until the activity fix above is deployed/installed.

## 2026-11-23 — DONE (`4f7e4c7` on docs/consolidation-2026-11) — Docs consolidation pass
Doc-only consolidation (no code / no engine, threshold or product-decision changes). Done:
- AGENTS.md + CLAUDE.md now agree: **STATUS.md (this branch) is the live truth**; CURRENT_STATE.md is the
  architecture/history record (not the task board); **one push rule** (push own branch when tests+gates pass +
  verify ls-remote; never push/merge to main; only Session 1 deploys). CURRENT_STATE.md got a top pointer saying the same.
- Replaced `01_PRODUCT/METRIC_CAPABILITIES.md` with a **metric contract**: every MVP metric × {status
  (measured/best_effort/unavailable/disabled) · evidence · display-eligible · coaching-eligible}, **fail-closed**
  (no documented validation evidence or ambiguous → NOT coaching-eligible; "implemented" ≠ "validated"). **"Guaranteed"
  retired** across active docs (FEATURE_REVIEW, LOCAL_RUNNER_SPEC, VALIDATION_PLAN; one vocabulary everywhere + design README).
- Supersession one-liners on MASTER_CONTEXT §4/§18, ENGINE_ARCHITECTURE_DECISION, MVP_READINESS_PLAN, FEATURE_REVIEW
  (→ on-device DEC-106/126/127/130; DEC-133 noted as the capture-branch capstone — it is not yet in this branch's DECISIONS.md).
- APP_DESIGN_CHANGES "How this works" + design README: **honesty/accuracy/privacy outrank design parity** (deferrals
  allowed with a reason); **coaching acts only on coaching-eligible metrics**; **lane path drawn only where the ball
  was observed**. Design README: blocking "Analyzing" replaced with the DEC-127 **Complete/Offline** result flow.
- DECISIONS.md left as-is (history). DECISIONS.md lines 172–173 ("Guaranteed/Best effort/Sensor/Unavailable" per tier,
  DEC-023) and line 909 (blocking Analyzing, DEC-068) are historical and intentionally untouched; `dev_build_v0/HANDOFF.md`
  (frozen) still carries the old push line and was left frozen. All flagged in my report, none are live guidance.

## 2026-11-23 — DECIDED by Shayne (see item below) — Coaching-eligibility conflicts surfaced by the metric contract
The new fail-closed metric contract (`01_PRODUCT/METRIC_CAPABILITIES.md`) marks some metrics **not** coaching-eligible that
current coaching/Accuracy/Score logic already acts on. These are product calls, left undecided (docs-only pass):
1. **Rev rate** — contract: not coaching-eligible (REV_SENSOR_FACTOR=1.12 fitted on 4 shots, blind validation pending,
   DEC-027/028). But the shot-card coach matrix (APP_DESIGN_CHANGES 2026-10-27-A) uses revs as a *throw* classification
   input. Decide: blind-validate rev before it drives coaching, OR document the coach's rev use as relative-to-own-baseline only.
2. **Near-lane boards (arrows/laydown)** — contract: not coaching-eligible until the Specto board-accuracy gate (DEC-034)
   passes. But Accuracy `A` (DEC-031) and the lane-move coach already act on the arrows board, and DEC-127 makes measured
   on-device boards Score-eligible. Decide how to reconcile DEC-127 (measured = Score-eligible) with the fail-closed coaching bar.
3. **Headline speed definition** — DEC-030 (release) vs DEC-064 (60 ft foul→pins average) is still open (also tracked in
   METRIC_AND_SCORING_LOGIC / CURRENT_STATE). Phase-2 Specto settles it; noted in the contract's Open-conflicts section.

## 2026-11-23 — OPEN — Shayne decisions on coaching eligibility + headline speed (record as next free DEC)
Decided by Shayne 2026-11-23 (resolves the metric-contract conflicts above):
1. Rev rate: display-eligible (best_effort), NOT coaching-eligible until validated against independent truth
   (240 fps marked-ball clips or Specto). The coach matrix must not use revs as a throw signal until then.
2. Near-lane boards (laydown, arrows, 7 ft): coaching may use them for DIRECTION only ("missing left/right of your
   target"), never exact board-move prescriptions, until validated. Exact moves unlock once boards pass validation.
3. Headline speed = 60-ft average (foul line → first pin contact), labeled "Avg speed" — the validated metric and what
   center displays show. Release speed is secondary detail. Resolves DEC-030 vs DEC-064.
Tasks:
- DOCS session: record this as the next free DEC (fetch first) on docs/consolidation-2026-11; update METRIC_CAPABILITIES
  (metric contract) coaching-eligibility columns + the design README; push; mark this DONE.
- SESSION 1 (after 8754): enforce 1–2 in the coaching/rec code (server + on-device) and make the shot card headline
  "Avg speed" = speed_avg_foul_to_pins. Then validate near-lane boards: on the 22 labeled clips, read the true board at the arrows/foul line from frames
  (visible arrows/dots as the ruler; per DECISIONS #4 you may add a short board-check Labeler batch for Shayne instead), audit
  with contact sheets, grade laydown/arrows vs that truth, and report. If they pass a ±1 board gate, propose unlocking
  exact board moves.

## 2026-11-23 — OPEN — SESSION 1: next shot-coverage work after the Active Session fix ships
From Session 1's 8754/8969/8976 report (engine v17 unchanged, 5/22, 0 wrong). Per DECISIONS #3 these stay detection failures to fix, not accepted withholds.
1. Port the reference's phase-correlation frame de-jitter (on-device stabilization, already Session 1's item) — likely cause of 8754's ~0.67 s late deck contact
   on the untrimmed clip and of 8969's noisy pre-contact deck baseline. Then a safer shot-window isolation so 8754 isn't clipped. Python reference first,
   port, 22-clip gate after each change, zero plausible-but-wrong.
2. Prepare the shot Labeler batch (DECISIONS #4): foul-cross frame, first pin contact frame, a few ball centers, pin-deck box, on ALL shot clips incl. the 13,
   hints pre-filled; hold out an unseen set. One line to Shayne when ready + how long it takes.
3. Report detection quality per stage (DECISIONS #5) alongside the 22-clip table.
