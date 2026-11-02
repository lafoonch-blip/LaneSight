# Form event baseline + remaining-gap root causes (2026-11-01)
Status: WORKING NOTES
Version: 1.0
Last Updated: 2026-11-01
Owner: Shayne (author: autonomous session)
Scope: DEC-118 Form MVP metrics measured against Shayne's form labels; DEC-120 slide-stop fix; and the
root causes of the three remaining gaps (step count, E2 ball-start, IMG_8826 mis-segmentation).

Ground truth: `lanesight-core/validation/form_labels.json` (6 clips: IMG_8824–26 side, IMG_8846–48 rear).
Harness: `lanesight-core/examples/form_baseline.py` (scores the Python engine vs the labels in frames).
All step counts are 5. The labels carry swing-event TIMES (E2/E4/E5/E7/E8) + the step COUNT (no per-step times).

## 1. Baseline + the shipped fix (DEC-120)
Before: swing events E2/E4/E7 nulled on all 6; E8 "slide stop" 23–86 frames late (median 56, 0/6 within ±2);
step count exact 0/6. Root cause of the nulls: E8 was `hold_start` (the posted-finish start, 0.4–1.0 s after
the real slide stop), so the event gate saw a false gap at release and dropped every event.

Fix (shipped): a slide-stop detector (slide foot settling after its slide peak, anchored on the bottom of the
swing arc E6), a release clamp, and the gate re-anchored on the corrected E8 (DEC-095 shadow flag retired).

After, vs labels (±2 frames = pass):

| Clip | View | E4 back | E7 release | E8 slide-stop | Steps (GT 5) |
|---|---|---|---|---|---|
| 8846 | rear | −1 ✓ | +1 ✓ | +1 ✓ | 3 |
| 8847 | rear | 0 ✓ | 0 ✓ | −2 ✓ | 4 |
| 8848 | rear | −2 ✓ | +1 ✓ | +1 ✓ | 4 |
| 8824 | side | −1 ✓ | +3 | −5 | 3 |
| 8825 | side | −2 ✓ | −1 ✓ | −1 ✓ | 4 |
| 8826 | side | null | null | +38 | 6 |

Swing events surface on 5/6 (was 0/6); rear E4/E7/E8 all within ±2 f; E8 median 56→2 f. E2 still null on all 6.

## 2. Remaining gaps — root causes (investigated, NOT fixed; a fix on 6 clips would overfit / regress honesty)

### 2a. Step count — 0/6 exact (under-counts)
Detector: `_foot_strikes` → `_local_minima` on the combined foot speed max(Rs,Ls); a plant = a trough (both
feet briefly slow). Two independent problems:
- **Window clips early steps (leading, fixable cause).** The step search starts at `b0−0.25` = approach-window
  start + 0.15, which lands AFTER the labeled ball start (E2) on all 6 clips, so the first 1–2 approach steps
  are outside the window. (Burst onset `b0` is detected late because the first step is gentle / below
  BURST_MOTION.)
- **The combined-speed signal is unreliable for counting on this data.** Extending the window does not give a
  clean 5 because: (i) on IMG_8825 the early steps register `comb≈0.0` — indistinguishable from standing still
  (small/far feet → near-zero pose foot velocity); (ii) IMG_8846 is 30 fps and shows only 4 troughs for 5 real
  steps; (iii) IMG_8824/8825 produce extra `comb=0` stance dips; (iv) IMG_8826 is mis-segmented (see 2c). A
  position-staircase counter (per-foot forward advance) was prototyped and merged steps (2–4), no better.
- **No per-step ground truth.** The labels have only the step COUNT, so any window/threshold tuned to hit 5 on
  these 6 clips cannot be distinguished from overfitting and would not be a real validation.
- **Fix path:** add per-step (or at least first-step) frame marks to the labeler `form_events` task, then build
  and validate a step counter against them. Likely a per-foot forward-position staircase (robust to the comb≈0
  velocity dropouts) + a window anchored [approach onset, slide_stop]. Validate held-out on IMG_8980.

### 2b. E2 ball start — null on all 6
- The bowling-wrist landmark (the current E2 cue) **does not move at the labeled pushaway onset** — its y is flat
  for 9–21 frames past E2 on every clip (the pushaway is a two-handed ball push the wrist landmark doesn't
  register). So E2 is a missing-signal problem, not a threshold tweak; and the gate's ball-start→release
  duration check then drops the late E2.
- **Ball-blob cue (tested, partially promising).** Tracking the ball blob from before E2 works on a CLEAN track
  (IMG_8847: motion onset −1 frame vs label) but the early ball association is jittery on the others, so a
  displacement-onset threshold fires 13–47 frames EARLY on blob noise (8824 −44, 8848 −47, 8846 −13, 8825 −23).
  Shipping it now would replace an honest `null` with a wrong-by-10-47-frame value (DEC-026/094 regression).
- **Fix path:** a robust setup-phase ball tracker (better seeding/association near the body) + a
  sustained-monotonic displacement onset (not a single threshold crossing), confidence-gated so it stays `null`
  when the track is not clean. Validate on more clips incl. IMG_8980.

### 2c. IMG_8826 mis-segmentation — events ~0.9–1.3 s late
- The wrist-y arc is low-amplitude and has a SECOND up-down hump at 17.9–18.9 s (post-release arm motion). The
  swing window runs to `hold_start+0.3 = 19.35 s` — ~1.8 s past the true release (17.57) — because the bowler
  isn't "both feet still" until 19.05 s. The `_swing_events` "deepest late minimum = follow-through" heuristic
  then anchors on the 18.9 s hump, cascading E4/E6/E7 late. (The true apex at 17.17 IS a local min — just not
  selected.) Same family as the old slide-stop bug: an over-wide post-release window confuses a downstream
  detector.
- **Fix path:** end the swing window near the delivery (e.g. at the slide-foot settle / first clear
  both-feet-slow after the backswing) rather than at `hold_start+0.3`; or constrain the backswing-apex→bottom
  sequence to a plausible downswing duration. Validate on more clips so a change doesn't regress the 5 clips
  that already work.

## 3. IMG_8980 (held-out)
Added to the labeler `form_events` task (side view), pending Shayne's labels — it was NOT used to tune anything.
Once labeled, `python examples/form_baseline.py` scores it automatically (the harness reads `form_labels.json`
and resolves the clip from `~/LaneSightData/.../11:1 Shots/`). Engine on 8980 today: side view, E4/E7/E8 surface,
E2 null, step count 14 (over-counts — multiple deliveries / walking in that clip; labels will confirm).
