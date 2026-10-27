# MVP Capture Guidance — where to put the phone (post-Phase-1)
Status: DRAFT — recommendation pending Shayne's field validation · Version: 0.1 · Last Updated: 2026-10-26
Owner: Shayne · Addresses: MVP review C1. Grounded in `CV_PHASE1_VALIDATION_REPORT.md` §0/§0.1 (findings),
`FORM_ANALYSIS_SPEC.md` §5 (Form views), `CAPTURE_TEST_PLAN_v1.md` (full scenario matrix). This is the crisp
"do this at the lane" card + the gate that proves it worked. Not new findings — a distillation + a test.

## Why this matters (one line)
Every validation clip so far was shot from the **back settee / ball-return, held high, across many lanes**.
That vantage compresses the lane's 60 ft into a thin upper band, so the pipeline **correctly gates far-lane
metrics (entry board/angle, breakpoint, late speed) to UNAVAILABLE**. The Shot card's headline result and the
score's performance pillar depend on exactly those. So *where the phone sits* decides whether the MVP shows
insight or "move your camera."

## Shot capture — recommended position (to validate)
Change the vantage so the near-to-mid fiducials the solver needs are resolvable:
- **Square up behind one lane**, not across many (lane direction runs straight up the frame).
- **Lower the phone** (tripod/clamp ~waist–chest height), not held overhead on the settee.
- **Put the foul line in frame** with a little approach — foul line (0 ft) + approach dots are the best-resolved
  anchors; arrows/dots mid-lane are marginal from the old angle (Phase-1 §0).
- **1080p 120 fps, HDR OFF** (sharper ball, real timestamps; rev/loft need ≥120).
- Keep the **pin deck in frame** at the top — a well-anchored pin end is what *might* recover entry board.

**Honest limit:** far-lane board precision stays gated until the **Phase-2 mid-lane reference** exists — a
better position maximizes the *near-to-mid* metrics (laydown, arrows, early speed, launch) and *may* recover
entry board if the pin deck anchors well, but it is not guaranteed to unlock breakpoint/entry on its own. The
test below tells us which.

## Form capture — recommended position (from FORM_ANALYSIS_SPEC §5.1)
- **Side view, default.** Perpendicular to the approach, **1.5–2.5 lanes away**, lens at **hip height (~1 m)**,
  centered on the **last two steps + foul line**, landscape.
- **Bowler ≥ 40% of frame height** (the pilot failed pose at ~8–13%), locked tripod, **120 fps**, HDR off.
- Rear view is the alternative (drift, swing plane) but can't see true backswing apex / knee.

## Validation gate (what proves the position is right)
A short, controlled A/B the next lane session — record the SAME shots two ways:
1. **Old vantage** (elevated ball-return) × ~6 shots.
2. **New vantage** (squared, lowered, foul line in frame) × ~6 shots, same ball + target.
Then compare (the API already returns per-metric status + reasons; use `GET /sessions/{id}/export.csv`):
- **% MEASURED vs UNAVAILABLE** per metric, old vs new — especially entry board, entry angle, breakpoint.
- **Foul-line detection rate** (old vantage fails it — IMG_8900/8908).
- Ball-speed error vs Ruby where available (sanity, not the gate).

**Acceptance:** the new position moves the far-lane metrics (entry board/angle at minimum) from UNAVAILABLE to
MEASURED on a majority of clean shots. If it does **not**, that confirms capture position alone is insufficient
and the Phase-2 mid-lane reference is the real unblock — a useful negative result either way.

## Decisions this needs from Shayne
- Approve the recommended Shot vantage to test (above), or propose an alternative placement to A/B.
- Whether to run this A/B on the next bowling-center trip before wider friend testing (recommended — it gates
  whether the headline UI has data).
