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
