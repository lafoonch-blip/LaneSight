# Event-based approach step detector — experiment (2026-11-02)
Status: EXPERIMENT (offline; not shipped). Stopped at the recall gate.
Version: 1.0
Last Updated: 2026-11-02
Owner: Shayne (author: autonomous session, branch `form/step-events`)
Scope: find individual leg-advancement (plant) EVENTS, not periodic peaks. Offline only — reads the existing
pose output; changes no production code path, the app, or the server. Builds on
`02_RESEARCH/FORM_EVENT_BASELINE_2026-11-01.md` (the earlier periodic-cue work is reference only; its
thresholds were not reused).

Code: `lanesight-core/experiments/step_events/` (`detector.py`, `evaluate.py`, `test_step_events.py`, `plots/`).

## Method
Per frame, from the existing pose landmarks, along a per-clip forward axis (net foot travel direction):
- each leg's **ankle advancement relative to the hip midpoint** (`adv = fwd(ankle) − fwd(hip_mid)`); the KNEE is
  used instead when ankles aren't visible,
- **hip forward translation**.

Candidate events = **alternating leg-advance maxima** (one leg maximally advanced = a plant), each confirmed by
**hip forward translation since the previous event** — this is the discriminator that rejects in-place weight
shifts, the backswing, and slide adjustments (they move a leg but not the hip down-lane). Restricted to the
setup→slide window (`setup_hold_end` → posted-finish start). Thresholds are physiological (step interval ≥0.22 s;
advance prominence ≥15% of range; hip advance ≥6% of total approach translation) and were **not tuned clip by
clip**.

Per-clip **visibility mode**: `feet` (mean ankle visibility ≥0.55), else `knees_only` (knee ≥0.55), else
`insufficient` → `step_count` unavailable with a reason. The detector never knows the expected count; it outputs
`steps[] = {frame, t_s, leg, evidence, confidence}`, `step_count = len(steps)`, `visibility_mode`, `confidence`.

## Results — DEV clips only (IMG_8980 held out, never opened)
HIT = a detected step within ±3 frames of a labeled plant.

| clip | mode | detected | labeled (visible / true) | event recall | precision | count=labeled | timing of hits (Δf) |
|---|---|---|---|---|---|---|---|
| IMG_8824 | feet | 5 | 4 / 5 | 25% | 20% | no | [−1] |
| IMG_8825 | feet | 4 | 5 / 5 | 20% | 25% | no | [−3] |
| IMG_8826 | feet | 5 | 5 / 5 | 20% | 20% | **yes** | [−2] |
| IMG_8846 | feet | 3 | 5 / 5 | 20% | 33% | no | [+3] |
| IMG_8847 | feet | 3 | 5 / 5 | 0% | 0% | no | — |
| IMG_8848 | feet | 3 | 5 / 5 | 0% | 0% | no | — |

**Overall: event recall 14% (4/29), precision 17% (4/23).** Exact count = labeled-visible on 1/6, = true 5 on
2/6. (The "timing of hits" column is only the 4 matched events, so it is small by construction; the misses are
the real signal.) Split by mode: all six clips resolved to `feet`; `knees_only` / `insufficient` did not occur on
the dev set. Timeline PNG per clip (signals + detected vs labeled) in `experiments/step_events/plots/`.

## Why it fails (three independent reasons — all inherent, not threshold tuning)
1. **Leg-advance peak ≠ labeled foot-contact, by a VARIABLE offset.** "Leg maximally advanced relative to the
   hip" occurs when the foot stops moving forward, which precedes the labeled contact by **1–37 frames** and the
   offset is not constant across steps or clips (e.g. IMG_8847 detected→nearest-label Δ = +3, −11, +37 f). A
   single global shift cannot fix a variable offset, and correcting it per clip is the forbidden clip-by-clip
   tuning.
2. **Rear-view far-leg occlusion.** On the rear clips the far (slide/left) leg is occluded behind the near leg,
   so `adv_L` has no clean maxima — the detector emits only `R` events (IMG_8846/8847 are all `R`), alternation
   collapses, and ~half the steps are never detected. This is a property of the single rear camera, not a tuning
   knob.
3. **Follow-through spurious events.** After the slide, a leg advances again (kick-up / walk-off) inside the
   window, producing a detected step 20–37 f past the last real plant (e.g. IMG_8846 @15.53 s, IMG_8826 @18.30 s).

The hip-translation gate works as designed (it rejects in-place motion — unit-tested), and visibility-mode gating
works, but they can't overcome a leg-advance EVENT that is mis-timed vs contact and half-missing on rear view.

## Decision
**Event recall 14% is far below the 90% gate after a reasonable, debugged attempt (window + visibility bugs
fixed). Per the stop rule, STOPPED — no clip-by-clip tuning.** Nothing shipped; production `step_count` stays
`best_effort` (DEC-121). This rules out "hip-relative leg-advancement maxima" as the plant event on single-camera
phone pose for this footage.

What this points to next (for after Shayne's new 60 fps clips land): the plant instant is a **ground-contact**
event, and leg-advancement geometry is a few frames early and occlusion-limited — so the viable paths are a
dedicated foot/ground-contact signal (not whole-body landmark geometry) and/or the better capture (fps + both
feet framed) that DEC-121 set up. Decide once the held-out clips exist.

## Reproduce
```
cd lanesight-core && source .venv/bin/activate
PYTHONPATH=$PWD python experiments/step_events/evaluate.py          # table + PNGs (dev clips only)
PYTHONPATH=$PWD python -m pytest experiments/step_events/test_step_events.py -q   # event-logic unit tests
```
IMG_8980 is held out — `evaluate.py`'s `DEV_CLIPS` deliberately excludes it; it is never read here.
