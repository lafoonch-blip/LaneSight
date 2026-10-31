# Pin-anchor ground-truth labeling — foul_cross & first_pin_contact (for Shayne)

Built 2026-10-31. Confirms the pin-anchor vs impact-anchor decision with REAL ground truth.

## What "truth" I used in the overnight report (correction #2)
The 60-ft "truth" in the overnight pin-anchor table was **NOT Ruby** (DEC-105 — Ruby is just another guess, discarded). It was a **track-crossing estimate**: the ball's detected image positions crossing the foul-line image row → the head-pin image row, truth = 60 ft / Δt. That Δt is offset-invariant (a time difference), so the speed is valid, but it is **not a visually-confirmed frame label** and it partly uses my own pin detector's head-pin row. This packet replaces it with YOUR frame labels.

## Trim offset resolved
The analysis trims each clip to the shot window, so track-time ≠ original-clip time. I recovered the window start `t0` (`detect_window`): original_time ≈ track_time + t0. Verified on IMG_8751 (ball hits pins at ~29.0 s in the original; computed 28.96 s — within ~3 frames).

## Confirm these frames (60 fps)
Open each `*_foul.png` / `*_pin.png` sheet (frame # printed on each tile) and write the exact frame for:
- **foul_cross** — the ball crosses the foul line (nearest the camera)
- **first_pin_contact** — the ball first touches the head pin

| Clip | foul_cross (my estimate) | first_pin_contact (my estimate) |
|---|---|---|
| IMG_8751 | ~26.69 s / frame ~1601 | ~28.96 s / frame ~1737 (looks ~29.0 / f1740 by eye) |
| IMG_8752 | ~18.57 s / frame ~1114 | ~20.82 s / frame ~1249 |
| IMG_8753 | ~9.29 s / frame ~557 (no trim on this clip) | ~11.54 s / frame ~692 |
| IMG_8754 | ~25.72 s / frame ~1543 | ~28.05 s / frame ~1683 |

Put the confirmed values in `pin_anchor_labels.json`:
```json
{ "IMG_8751": {"foul_cross_frame": null, "first_pin_contact_frame": null, "fps": 60}, ... }
```
Truth = 60 ft / ((pin_frame − foul_frame)/fps). With these, I'll recompute both anchors' 60-ft speed vs YOUR truth and decide pin-anchor promotion (DEC-112) — no Ruby involved.
