# Form event labeling — ~10 min (for Shayne)

Built overnight 2026-10-31. These labels unblock the form delivery gate (DEC-095) + the numeric-bar form validation.

## Why
Every form upload currently fails `FORM_DELIVERY_NOT_ISOLATED`. Root cause (found tonight): the gate compares
**release** to **hold_start** (the posted-finish start, when both feet go still) instead of **slide_plant**
(when the slide foot stops) — a ~0.7–0.9 s false gap that rejects every clip. Example (IMG_8824): detected
release 4.44 s, slide_plant 4.11 s (gap +0.33 s, physically fine), hold_start 5.33 s (gap −0.89 s → gate
fails). Fixing the gate reference AND retuning its bounds needs your true event times — hence this packet.
(Also: IMG_8824 — a side clip — is misclassified `view=down_lane`; I'll fix the view classifier after labels.)

## How to label
Open each `*_contactsheet.png` (frames every ~0.13 s, timestamp printed on each). For each clip, write the
timestamp (seconds, to ~0.05 s) of these 5 events — pick the closest frame:

| Event | What to look for |
|---|---|
| `ball_start` (E2) | the ball first moves out of your setup hold (pushaway begins) |
| `backswing_top` (E4) | the ball reaches the top of the backswing (highest point) |
| `release` (E7) | the ball leaves your hand at the bottom of the swing |
| `slide_stop` | your slide foot stops sliding / plants |
| `finish_hold_end` | you come out of the posted finish |

Put them in `form_event_labels.json` next to this file, e.g.:
```json
{
  "IMG_8824": {"view":"side","ball_start":null,"backswing_top":null,"release":null,"slide_stop":null,"finish_hold_end":null},
  "IMG_8846": {"view":"rear","ball_start":null,"backswing_top":null,"release":null,"slide_stop":null,"finish_hold_end":null}
}
```
Label only what's clearly visible; `null` is fine. These are the ground truth for the DEC-095 gate fix +
the numeric-bar form validation (both deferred until they're in).

Sheets included: **IMG_8824 (side)**, **IMG_8846 (rear)**. If you want the others labeled too (8825/8826 side,
8847/8848 rear), say so and I'll extract their sheets the same way.
