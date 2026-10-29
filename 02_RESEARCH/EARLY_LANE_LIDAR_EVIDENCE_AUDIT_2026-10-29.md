# Early-lane measurement zone + LiDAR — evidence audit / blocked evaluation
Status: RESEARCH ONLY — INCOMPLETE, NO METRIC PROMOTION, NO DEC APPROVED
Version: 0.1
Date: 2026-10-29
Branch: dev-build-v0
Owner: Shayne
Source: GitHub branch artifacts inspected remotely; NOT an execution of the production container.

## Decision and blocker
**No change to the headline speed or rev-rate logic is justified yet.** The requested three-way (a/b/c) comparison cannot be run from this environment: the private clips and original-frame contact labels are not in GitHub (explicitly excluded by `validation/cv_eval/README.md`), and the production container image, running service environment, and iPhone hardware are not accessible. Do not represent saved JSON artifacts as a new production-container evaluation.

**DEC conflict to resolve before interpreting accuracy:** accepted DEC-105 removes Ruby from validation ground truth. The new request asks for accuracy versus Ruby, including the ×1.12 rev adjustment. Ruby may be shown as historical/exploratory context, **not used to promote a metric or establish accuracy** without a new approved decision. Specto or independently measured reference values are required for accuracy promotion; ensure early-speed truth matches the near-lane measurement definition (not a full-lane average).

## What the checked-in artifacts actually show
- `lanesight-core/ops/perf_reports/cv_eval_server_2026-10-29.json` contains 12 rows, 8 with analyzed status and 4 missing/failed, and time/depth samples for some analyzed clips. It is a historical saved artifact, not a new run. Its `gt_metrics` labels include historic Ruby-derived values and are not accepted speed ground truth under DEC-105.
- `lanesight-core/validation/cv_eval/README.md`: clips are in `~/LaneSightData/training_videos`, labels are not committed.
- `lanesight-core/ops/perf_reports/gate_speedgate_svd.json`: local report for IMG_8753 gives ball_speed 17.838 mph, elapsed 24.43 s in that run. This is **not** the asserted 15.98 mph server run; isolate the run identities, container digests, inputs, HDR conversion, and stage settings before attributing the difference.

### Illustrative diagnostic only — NOT proposed (b)
An exploratory ordinary-least-squares fit over *saved reported lane-depth trajectory positions* in 0–24 ft (not original-frame contact-point projections, no explicit touchdown cutoff, no observation-versus-prediction filtering, no production container run) produces:

| Clip | Reported (a) mph | Existing (c) mph | Diagnostic 0–24 ft slope mph | Positions used |
|---|---:|---:|---:|---:|
| IMG_8753 | 17.838 | 18.711 | 17.90 | 26 |
| IMG_8754 | 16.975 | 18.210 | 18.18 | 52 |
| IMG_8808 | 17.297 | 15.465 | 15.47 | 29 |
| IMG_8815 | 21.044 | unavailable | 21.00 | 24 |
| IMG_8819 | 18.652 | unavailable | 16.74 | 50 |

These are **not** equivalent speed definitions. In particular, IMG_8753 has only 7 original reported observations in 0–15 ft (and IMG_8754 has more), so near-zone density is a real constraint; using all 0–24 ft points can hide a large early-region gap. The other observed trajectories contain gaps and anomalous scale, with no independent reference confirmation. These numbers cannot establish that (b) wins. No MAE, bias, p90 or plausible-but-wrong rate is asserted.

## Required reproducible Part 1 experiment (pending local/container access)
1. Record image digest, commit, environment, engine version, detection and calibration flags, timestamped source clip metadata, and fixed clip-list manifest. Evaluate **inside the production container image** with the same source files used by the server. Production service and migrations must not be touched.
2. Preserve existing (a) headline ball_speed and (c) speed_release unchanged as baselines.
3. Build shadow candidate (b) from **observed contact positions**, starting at independently labeled touchdown and ending at 20–25 ft (multiple predefined windows including 4–24 ft). Use PTS, weighted robust regression, inspect temporal spacing, track gaps, and report position depth-scale uncertainty. Predicted/interpolated positions cannot inflate observed coverage. Require enough positions AND depth span; reject otherwise. Do not fit a 0–24 ft center track and call it (b).
4. Separately localize speed error using held-out depth labels: contact-vs-center, focal/longitudinal geometry, touchdown event error, temporal gaps. No correction multipliers.
5. Output per shot fps, camera class, ground-truth source and **definition**, (a)/(b)/(c) speed, speed error where comparable, eligibility + exact unavailable reason; show duration/span/sample count. Aggregate coverage, MAE, signed bias, p90 absolute error and plausible-but-wrong rate with explicit denominators, and splits by camera class/fps. Report where no valid reference exists as **not evaluable**, never zero error.
6. Rev rate: near-zone surface-pattern observations only, measured coverage and comparator-specific error; compare raw lane RPM with historical ×1.12 transformed RPM as diagnostic, but **no Ruby-based tuning/promotion under DEC-105**. Use Specto reference where definition-matched; otherwise state reference unavailable.
7. Runtime: benchmark actual full-resolution near + reduced-resolution downlane processing, preserve lane-calibration provenance and DEC-065 far-lane gating, compare identical clips/stages. Do not claim estimated CPU savings as measured.
8. Do not change DEC-036 headline until Shayne accepts a new DEC, with speed names explicit and evidence meeting DEC-034/094/106.

## P0 order
1. Diagnose IMG_8753 **15.98 server / 17.84 local** difference with identical input+image digest+code/config and stage logs (existing checked-in 17.838 report is not evidence of the 15.98 run).
2. Fix Form reference event timing, view label, crops and step count, with regression tests.
3. Complete controlled production-container Part 1 candidate analysis and reference-matched evaluation.

## Part 2 — LiDAR ball/lane: experiment design only; NOT implemented
Dev/owner-only feature flag `experiment.lidar_lane_setup` default off; do not modify production. When local iPhone is available, acquire a short setup-only depth sequence, infer floor plane/camera height and foul-line distance within sensor's effective range, then return to normal 60/120 fps video capture. Compare video-only and depth-assisted scale on the *same taped shots* and camera positions; report board error, distance-scale error, near-speed error versus matched independent ground truth, setup failure rate and calibration latency. Keep video-only as universal fallback; zero raw depth retention. This is a feasibility protocol, not a claim of improved accuracy.

## Part 3 — LiDAR Form: experiment design only; NOT implemented
Owner/dev-only flag `experiment.lidar_form_setup`, default off. Test setup depth for floor-plane scale and step/slide/drift measured against physical floor-tape marks; video alone supplies event timing. Optionally compare synchronized video+depth mode separately, rejecting it if it degrades video timing/fps. Require view-specific results and confidence/unavailable states per DEC-076 and Form gates. Depth maps stay device-local and are discarded; persist only provenance and consent-reviewed derived results. Privacy-policy and App Store label review before any rollout. Do not capture while Form P0 event/crop/step fixes are outstanding.

**Measured LiDAR-format FPS: unavailable.** Only the actual iPhone's AVCaptureDevice activeFormat and supported depth formats/frame-rate ranges can establish this; do not report an assumed 30 fps as measured. No device experiment was run.

## Pending (no deployment or live migration performed)
- Access to local uncommitted videos and labeled contact points, production image digest/runner, and matching independent ground truth.
- IMG_8753 server/local speed divergence P0 and Form reference P0 corrections.
- Production-container per-shot comparison tables + stratified summary and runtime benchmark.
- iPhone LiDAR format query and paired taped shot captures (Parts 2/3 deferred).
- Shayne approval of an evidence-backed DEC if (b) wins; DEC-105 must be expressly reconciled before using Ruby as accuracy reference.
