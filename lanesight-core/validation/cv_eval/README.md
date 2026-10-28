# CV accuracy evaluation set (DEC-094 §1/§2)

The locked dataset + ground-truth labels the detector/tracker/metric comparisons run against. **Clips and label
files are NOT committed** (videos live in `~/LaneSightData/training_videos`; labels are personal ground truth).
Only this README, `manifest.json` and `tolerances.json` are tracked.

Run the harness: `python -m ops.cv_eval --manifest validation/cv_eval/manifest.json` (see `ops/cv_eval.py`).

## manifest.json
`{"clips": [ <shot>, ... ]}` — one entry per shot. Fields:

| field | meaning |
|---|---|
| `id` | stable shot id (clip stem + optional suffix) |
| `clip` | video basename under `--clips-dir` (default `~/LaneSightData/training_videos`) |
| `session`, `bowler`, `center`, `lane` | provenance; **splits hold out by `session` + `center`, never by shot** |
| `camera_class` | `rear-centered` / `rear-oblique-multilane` / `low-approach` / `ball-return-POV` / `handheld` / `glasses` |
| `orientation` | `portrait` / `landscape` |
| `fps`, `codec`, `resolution`, `dynamic_range` (`sdr`/`hdr`) | capture technicals |
| `occlusions` | list of known occlusion notes (free text) |
| `split` | `tune` or `test` — **never tune on `test`** |
| `ground_truth` | inline manual truth where known (e.g. IMG_8929); else labels come from `labels/<id>.json` |

## labels/&lt;id&gt;.json  (written by the ball-labeling tool; not committed)
Ground truth for one shot. Coordinates are **original-frame pixels** (never scaled-preview), matching the
landmark tool's safeguard. A position is recorded only when the ball is actually visible — an unseen ball is
`occluded`, never guessed.

```json
{
  "clip": "IMG_8929.MOV",
  "fps": 60.0,
  "events": { "foul_cross_s": 17.08, "first_pin_contact_s": 19.73, "release_s": 17.0, "touchdown_s": 17.2 },
  "pins_before": [1,2,3,4,5,6,7,8,9,10],
  "pins_after": [10],
  "balls": [
    { "t": 17.1, "center": [412.0, 1300.0], "contact": [412.0, 1316.0], "occluded": false },
    { "t": 17.2, "center": null, "contact": null, "occluded": true }
  ],
  "ruby":      { "speed_mph": 15.5, "rev_rpm": null },
  "reference": null
}
```
- `balls` are sampled ~every 0.1 s along the full roll (foul line → pins).
- `ruby` / `reference` are validation-only (DEC-070); present only where a sensor/tape value exists.

## Lane regions (reported separately everywhere)
Down-lane distance from the foul line, in feet: **0–15 / 15–40 / 40–60 ft**. A far-lane (40–60 ft) ball is
~8–15 px, so detection is scored at native resolution.

## Two tolerance sets — do not conflate
- `tolerances.json` here = **accuracy vs. ground truth** (drives MAE / plausible-but-wrong).
- `ops/perf_benchmark.py` `TOL` = **don't-regress-the-current-engine** (tighter; a stability gate).
