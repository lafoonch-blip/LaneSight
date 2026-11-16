# Claude Code handoff — CV accuracy architecture (DEC-094) · v1.1

Repo: lafoonch-blip/LaneSight, branch `dev-build-v0`. Work from the Mac copy; it's ahead of GitHub, so **don't pull**. Run straight through and report once. Stop only for a real blocker, a live migration or a deploy (list those as pending).

## 0. Record the decision (now)
- Add the DEC in the appendix to `00_CONTEXT/DECISIONS.md` as **DEC-094** and bump to v1.55.
- Add one line in `CURRENT_STATE.md` pointing to it and this handoff.
- Commit this handoff as `03_ENGINEERING/CV_ACCURACY_ARCHITECTURE_HANDOFF.md`.

## Gating
| Work | Can start |
|---|---|
| §1 dataset + labels, §2 evaluation harness | **Now** (DEC-093 landed) |
| §3 detector comparison, §4 tracker comparison, §5 speed-bias isolation | After Phase-2 camera validation reports |
| §6 uncertainty contract in coaching | **Now — do this first.** Safety rule, no new CV |

Nothing in §3–§5 replaces the production engine. Everything runs in shadow until promoted under the DEC's promotion rule.

## 1. Test dataset and labels
**Manifest** (`validation/cv_eval/manifest.json`, clips not committed). Each shot carries:
- id, path, session, bowler, center, lane number
- camera class: rear-centered / rear-oblique-multilane / low-approach / ball-return-POV / handheld / glasses
- orientation, fps, SDR/HDR, codec, resolution
- known occlusions
- split: `tune` / `test`

**Splits.** Hold out by **session and center**, not by shot. Never tune on `test`.

**Starting set.** All existing validation clips plus IMG_8929 and IMG_8930, with their manual ground truth from `CLAUDE_CODE_PROMPT_IMG8929_FIX.md`.
- Target 50–100 shots for the first comparison.
- Report which camera classes are thin, so Shayne knows what to film.

**Labels per shot:**
- Foul-line crossing time, first pin-contact time, release and touchdown times.
- Pins standing before and after.
- Ball **center** *and* ball **contact point** on frames sampled every ~0.1 s along the full roll. Mark a frame `occluded` when the ball isn't visible; never guess a position.
- Ruby speed and rev where available (validation only, DEC-070).
- Specto or tape-reference values when Phase-2 sessions provide them.

**Labeling tool.** Don't build a new one. Extend the existing `lanesight_core/cv/calib/label_tool.py` (cv2 HighGUI) and `label_server.py` (browser) with a per-frame **ball center / contact point / occluded** mode. Reuse their verified-vs-suggested safeguards. Labels go to JSON next to the manifest; Shayne labels.

## 2. Evaluation harness (extend `ops/perf_benchmark.py`, or a sibling `ops/cv_eval.py`)
One command runs a candidate pipeline over a split and writes JSON + a readable summary.

**Detection** (independent of tracking), per lane region **0–15 / 15–40 / 40–60 ft** and per camera class:
- **Recall:** labeled visible ball positions with a detection within 0.5 ball radius.
- **Positional error** (px and lane units).
- **False positives** per shot.
- **Observations per region.**

**Trajectory:**
- Lateral error in boards and down-lane error in ft against labels.
- Observed vs. predicted fraction per region. Predicted points never count as detections.
- Add **`observed_fraction`** as a **new additive** per-metric field (it doesn't exist yet). Until then, the rule binds to `Measurement.status` / `confidence` plus the far-lane plausibility gate.

**Metrics** vs. ground truth, for speed (each definition), arrows/laydown/breakpoint/entry board, entry angle, loft and pins:
- MAE, median, p90, bias.

**Coverage:** share of shots where each metric is available.

**Plausible-but-wrong rate:** a metric shown as measured/ok whose error exceeds its tolerance. Report it separately from unavailable. It's the most important number in the report.

**Tolerances** (initial, in their own config file, `validation/cv_eval/tolerances.json`). This is accuracy vs. ground truth. Keep it **separate** from DEC-092's don't-regress tolerances in `ops/perf_benchmark.py`.
- speed ±0.5 mph
- boards ±1.0
- entry angle ±1.0°
- loft ±1 ft
- pins exact

**Runtime:** wall time, CPU-seconds, peak memory, cost per 1,000 shots (DEC-043 basis).

**Diagnostics per shot:**
- A frame-strip / overlay image showing labels vs. detections vs. track.
- Per-region tables.
- Failure code.

## 3. Correct lane, then detector comparison (shadow)
**3a — first.** Multi-lane correct-lane detection and stable foul-line geometry.
- On IMG_8929, `find_lanes` stops at the first saturation floor and finds only the ball-return lane; lane 9 is never detected, and its foul-line fit is degenerate even when forced. Fix that before detector work can show anything on this clip class.
- Report lane-detection rate per camera class.

**3b — detectors.**
| ID | Candidate |
|---|---|
| D0 | Current OpenCV motion/blob detector (baseline) |
| D1 | Improved classical detector: per-shot ball appearance model (color/texture from the first confident near-lane detections) + search restricted to the lane polygon / predicted region at native resolution |
| D2 | Small learned detector, fine-tuned on LaneSight labels |

**D2 requirements:**
- **License:** Apache-2.0, MIT or BSD only, for both code and weights. Verify from the actual LICENSE files and record them in the report.
  - Candidates to check: YOLOX, NanoDet, RTMDet / MMDetection, RT-DETR.
  - For RT-DETR, use the lyuwenyu / PaddleDetection / Hugging Face implementations, **not Ultralytics' (AGPL)**. No Ultralytics code or weights at all.
- **Input:** tiles or crops from the lane region at native resolution. A far-lane ball is ~8–15 px and disappears if the full frame is downscaled to 640 px.
- **Data:** train only on `tune`. Report data size alongside results.
- **Runtime:** CPU inference on the Cloud Run class of machine (DEC-045 basis), unless the report shows GPU is the only way to meet the cost caps.

## 4. Tracker comparison (shadow, on the best detector)
| ID | Candidate |
|---|---|
| T0 | Current link / extend / far-lane recovery |
| T1 | Physics-constrained state estimator in lane coordinates |

**T1 details:**
- Kalman filter first; IMM / multiple regimes (skid, hook, roll) only if Kalman leaves clear errors.
- Gate candidates by predicted position and uncertainty, and keep lower-confidence detections that match the prediction.
- Widen the search when detections are lost.
- Predictions are stored as predicted, never measured, and don't count toward `observed_fraction` (the new field from §2).

**Report T0 vs T1** on trajectory error, metric error, coverage, plausible-but-wrong rate and runtime, per region.

**Promotion** may be partial: per region or per metric, with fixed routing, each part meeting the DEC's conditions on its own, and the plausible-but-wrong rate not rising in any region.

## 5. Release-speed bias isolation
Test each candidate cause **one at a time** on the same labeled shots, against Ruby speed and labeled event times, matching definitions exactly:
1. **Contact point vs. visible center.** Project the contact point (ball radius ~4.3 in) instead of the center.
2. **Longitudinal calibration.** Use extra down-lane landmarks (approach dots, 7 ft dots, arrows) per DEC-065.
3. **Event timing.** Release vs. foul-line crossing vs. ball-center crossing; first pin contact vs. impact detection.

Report how much of the bias each explains, alone and combined. **No universal multiplier.**

Also run a blind validation of the **×1.12 rev factor** on the 120 fps Ruby set. Recommend keep, recalibrate or remove, with the evidence.

## 6. Uncertainty contract in coaching (start now — first)
- Every coaching adjustment (target move, speed change, ball change, etc.) declares the metrics it depends on and the uncertainty it needs. Keep these in one editable table, owner-visible / user-hidden (same pattern as the fundamentals rules).
- Insights, recommendations and the coach takeaway check `status` / `uncertainty` before using a metric:
  - **If it falls short:** suppress the adjustment and attach a reason that the shot card shows ("Not enough lane data to suggest a move this shot").
  - **Never** use predicted / estimated values unless that metric is approved for estimates.
- Add tests: an uncertain arrows board suppresses a 1-board move; an unavailable entry board suppresses entry-based advice.
- Schema changes are **additive only.**

## 7. Report back
- **Dataset:** shot counts by camera class and split, and gaps for Shayne to film.
- **Harness:** output on the current engine. This is the baseline, including the current plausible-but-wrong rate.
- **When §3–§5 run:** comparison tables plus a promote / don't-promote recommendation per candidate under the DEC's promotion rule.
- **Licenses** verified for any model used.
- **Pending items:** migrations, deploys.
- **Docs changed,** for the Project re-sync.

---
## Appendix — DEC-094 text to commit

# DEC-094 — CV accuracy architecture: detection first, shadow tracking, uncertainty contract
Status: ACCEPTED (Shayne, 2026-10-28) · v1.1 (Claude Code review corrections folded in)

**Decision (Shayne, 2026-10-28):**

**1. Development order**
1. **Done — DEC-093:** speed honesty gate, SVD / least-squares crash guard, chosen lane recorded on the shot.
2. **Phase-2 camera validation** (`CV_PHASE2_CAMERA_VALIDATION_PROTOCOL`) plus a labeled test set covering more camera positions, lighting and lanes.
3. **Correct-lane detection and density.**
   - **3a. Correct-lane detection + stable foul-line geometry in multi-lane views.** On IMG_8929, `find_lanes` stops at the first saturation floor and finds only the lane by the ball return; the bowler's lane 9 is never detected, and its foul-line fit is numerically degenerate even when forced. Density work can't help until this is solved.
   - **3b. Detection density:** detect more real ball positions, especially from 40 to 60 ft.
4. **Physics-constrained tracking,** as a shadow experiment on top of the better detection.
5. **Isolate the release-speed bias** (see item 4).
6. **DEC-092 latency work,** in its existing order.

Steps 3–5 are gated behind Phase-2. The dataset, labels, evaluation harness and the coaching uncertainty contract (item 5) can start now: Phase-2 needs the first three, and item 5 needs no new CV.

**2. Detection is evaluated independently of tracking**
- Report for every detector:
  - ball-detection recall
  - positional error
  - false positives
  - observations per lane region (**0–15, 15–40, 40–60 ft**)
- Predicted or interpolated positions never count as detections or as measured positions.
- **`observed_fraction` does not exist yet.** It is a **new, additive** per-metric field: the share of the metric's span that was observed rather than predicted.
- Until it exists, the rule binds to what does exist: `Measurement.status` / `confidence` plus the far-lane plausibility gate.

**3. Promotion rule: accuracy, coverage and runtime are measured separately**
- A new detector or tracker runs in **shadow** against the current engine on a locked test split.
- It is promoted only when **all** of these hold:
  - metric accuracy is no worse on any metric, beyond the stated tolerances
  - coverage (share of shots with each metric available) is no worse, and better where it's claimed
  - the **plausible-but-wrong rate** does not rise. This is a metric shown as measured/ok whose error exceeds its tolerance against ground truth.
  - runtime and cost per shot stay within DEC-043's caps
- Finding more points is not enough: if the extra detections make the trajectory less accurate, the change is rejected.
- **Partial promotion is allowed** per lane region or per metric (e.g., use the new detector from 40 to 60 ft and keep the baseline elsewhere). Conditions:
  - the routing is fixed by region or metric, not chosen per shot
  - each promoted region or metric meets every condition above on its own
  - the plausible-but-wrong rate does not rise in **any** region
- **Two tolerance sets stay separate:** accuracy vs. ground truth (this DEC's harness) and don't-regress-the-current-engine (DEC-092 `ops/perf_benchmark.py`). Each lives in its own config.

**4. No unvalidated correction factors**
- The release-speed bias (~9% low) is isolated experimentally across three candidate causes, each tested one at a time against the same reference:
  - ball contact point vs. visible center
  - longitudinal (down-lane) calibration
  - event timing definitions
- No universal multiplier is added.
- The existing ×1.12 rev-rate factor gets the same treatment: blind validation against independent reference data, or it is removed and rev is reported unavailable where it isn't supported.

**5. Uncertainty is a shared contract between measurement and coaching**
- Each metric's `status`, `source` and `uncertainty` drive every downstream calculation: Score inputs, insights, recommendations and the coach takeaway.
- Each coaching adjustment declares the measurement tolerance it needs (e.g., a 1-board target move needs arrows-board uncertainty ≤0.5 board). If the measurement doesn't meet it, the adjustment is suppressed and the shot card explains why.
- Shown statuses map to **Measured / Estimated (only where approved for that metric, labeled) / Unavailable with a reason**. Sensor source is parked under DEC-070.

**6. ML models must be license-safe**
- Only permissively licensed models and weights (Apache-2.0, MIT, BSD) are used, and the license is verified from the actual repo and weights.
- AGPL models (e.g., Ultralytics YOLO, including Ultralytics' RT-DETR implementation) are excluded unless a later DEC approves a commercial license.
- Apache-2.0 implementations (e.g., RT-DETR from lyuwenyu/PaddleDetection or Hugging Face transformers) are eligible after their LICENSE files are checked.

**Preserved:**
- DEC-062/065: geometry first; far-lane metrics stay unavailable until Phase-2 passes.
- DEC-070: Ruby is a validation instrument only; no sensor features in MVP.
- DEC-092: latency order.
- DEC-043: cost caps.
- DEC-093: lane selection is recorded on the shot.
- The existing measurement schema: changes are additive only (`observed_fraction` is one such addition).

**Why:**
- Far-lane failures are a detection problem first. On IMG_8929 the bowler's lane isn't detected at all, and the ball gets only 3–11 observations on the lane that is. A tracker can bridge occasional misses but can't rebuild a far-lane path from that few observations without large uncertainty.
- A believable wrong number hurts coaching more than an honest "unavailable."
- Correction factors hide calibration errors that vary by camera setup.

**Date:** 2026-10-28 · **Status:** ACCEPTED on commit · **Supersedes:** none
