# Phase-2 far-lane validation — field checklist (book from this)
Version: 1.0 · 2026-10-29 · one-page companion to `CV_PHASE2_CAMERA_VALIDATION_PROTOCOL.md` (full method).
Goal: get the ground truth that unblocks the DEC-065 far-lane gate (entry board/angle, breakpoint, board-at-distance) and settles the headline-speed definition (60 ft average vs release). One bowler, one ball, one lane, one oil, one session.

## Bring
- **Tape measure** (≥ 50 ft) + **removable floor tape / dots** in 2 colors (boards vs distance marks). Painter's tape lifts clean.
- **Phones/cameras** for 4 simultaneous positions if possible (else one, repositioned back-to-back). Tripods reaching **2 ft up to 6 ft**. Chargers / power bank, empty storage (120 fps eats space).
- **Specto unit** + laptop for its export; a short **clap/flash at the start of each shot** to sync Specto ↔ video timestamps.
- Notebook (or a notes app) for the shot log: position tag, shot #, ball/oil, anything odd.

## Lay out the lane (once, before shooting)
- From the **foul line**, tape marks at **boards 10 / 20 / 30**, at **15 ft and 40 ft** down lane (8 marks). Measure each with the tape; write the exact board+distance on the tape. These are the camera-independent board(Z) truth.
- Record a **5-second empty-lane framing from each camera position** (so the marks are visible per position).

## Camera positions (centered, square, whole lane foul-line→pins in frame)
| Pos | Height | Where | Why |
|-----|--------|-------|-----|
| **A** | 2–3 ft | behind lane, centered, square | best-case baseline (the reference) |
| **B** | 4–5 ft | behind lane, centered, square | everyday practical height |
| **C** | 5–6 ft | behind lane, centered, square | elevation floor test |
| **D** | elevated, **off-axis** (ball return / settee) | negative control (= today's clips) |

**All cameras identical:** 1080p, **120 fps** (60 min), **HDR OFF (SDR)**, lock exposure/focus if available, phone dead stable. Keep the **original files** (no AirDrop re-encode). Filename = position + shot: `POS_A_shot01.mov` …

## How many shots
- **~5 shots per position** (20 total if repositioning; fewer clips if all 4 capture each delivery **simultaneously** — preferred, since then the only variable is the camera).
- Same bowler / ball / lane / oil throughout. Mix a few different lines (e.g. 2 pocket, 1 light, 1 high, 1 across) so entry/breakpoint span a range.

## Specto data to export (per shot, CSV/JSON)
- **Speed — and WHERE it's measured.** Export speed at **release / off-the-hand (front of lane)** AND at **the pins / impact** if Specto reports both. This is the key item: it validates `speed_release` vs the 60 ft foul→pins average (`ball_speed`) and settles the headline definition (the TV/PBA vs alley-monitor question). If Specto gives one number, note exactly where it's measured.
- **Rev rate**, **axis rotation**, **axis tilt** (cross-check vs Ruby; definition-matched).
- **Any down-lane position / trajectory data** Specto provides: board at distances, **breakpoint board + distance**, entry board/angle, launch angle. This is the far-lane truth Ruby can't give — export it even if it looks redundant.
- **Per-shot timestamp / shot index** so each Specto row maps to its video (use the clap/flash + the shot log).
- Raw export preferred over a summary PDF (we need the numbers machine-readable).

## After the session (Claude Code does this)
1. Clips → `~/LaneSightData/phase2/POS_*`; Specto export → `.../specto.csv`; tape truth → `.../tape_marks.json`.
2. Label foul + pins + tape marks per position (`label_server.py`).
3. `python -m lanesight_core.cv.calib.phase2 ~/LaneSightData/phase2` → per-position 🟢/🟡/🔴 + the comparison table.
4. Confirm **A 🟢 / D 🔴** and locate the **B/C elevation floor** → the capture-guidance height.
5. If A clears its reference checks (reprojection < 0.5 board on held-out tape, speed within ±0.5 mph of Specto), **flip `FAR_LANE_VALIDATED` and lift the DEC-065 gate** for the validated metrics; otherwise report what's still short.

## Acceptance targets (what "good" looks like — validate, don't assume)
speed ±0.5 mph · board@distance ±0.75 · entry board ±0.75 · entry angle ±0.5° · breakpoint ±1 board/±2 ft · ball tracked to ≥55 ft on ≥4/5 shots. Full targets + method: the protocol doc §3–4.
