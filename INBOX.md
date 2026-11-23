# INBOX — decisions/requests from claude.ai chats not yet folded into the repo

Claude Code sessions: at start, act on every OPEN item addressed to you (record any DEC in DECISIONS.md
on your branch, do the work), then mark it DONE with your commit hash and update STATUS.md.
claude.ai chats: append new items at the bottom (date, OPEN, who it's for, the decision/request).

## 2026-11-23 — OPEN — Capture session: on-device only, any video in, capture default + override
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
