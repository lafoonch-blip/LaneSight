# INBOX — decisions/requests from claude.ai chats not yet folded into the repo

Claude Code sessions: at start, act on every OPEN item addressed to you (record any DEC in DECISIONS.md
on your branch, do the work), then mark it DONE with your commit hash and update STATUS.md.
claude.ai chats: append new items at the bottom (date, OPEN, who it's for, the decision/request).

## 2026-11-23 — IN PROGRESS (foundational pass `bcca484` on feat/capture-any-video) — Capture workstream (owned by the FORM session): on-device only, any video in, capture default + override
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
  (probe wired into record + upload, HDR→SDR on device, per-metric below-floor reasons) → D engine at 120/240/4K.
  C (Recording picker) waits on Figma frames; E (server retirement) waits on gates + Shayne; F waits on Shayne's recordings.
  Form branch work is done; only Shayne's 2 form re-uploads remain to validate it.
- SESSION 1 (shots): 1) 8969 far deck signal; 2) 8754 / 8976 pin deck + lane at distance; owns on-device stabilization
  (shared with capture D). Python reference first, then port; 22-clip gate after every CV change; zero plausible-but-wrong.
  Rev rate + early-lane speed stay best_effort until real truth exists. Sole deployer.
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
  "Avg speed" = speed_avg_foul_to_pins. Then validate near-lane boards WITHOUT Shayne labeling: on the 22 labeled
  clips, read the true board at the arrows/foul line from frames yourself (visible arrows/dots as the ruler), audit
  with contact sheets, grade laydown/arrows vs that truth, and report. If they pass a ±1 board gate, propose unlocking
  exact board moves.
