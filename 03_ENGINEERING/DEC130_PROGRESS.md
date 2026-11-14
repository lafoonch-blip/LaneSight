# DEC-130 progress — learned detection front-end

Status doc for the autonomous build (DEC-130). Resume from here. Updated at each milestone, committed + pushed.
**Last updated:** 2026-11-14 (regeneration run after the v1 scratchpad was cleared from /tmp).

## Persistence rule (this run)
Everything under `~/LaneSightData/dec130/` — NOT /tmp or scratchpad:
`dataset/` `models/` `coreml/` `eval/` `backup/` `logs/`. Each trained model + .mlpackage is copied to a 2nd
location (`backup/` + `gs://project-fd28bc3f-a844-43c2-a1c_cloudbuild/dec130/`) with sha256 in
`~/LaneSightData/dec130/ARTIFACTS.md` (also committed here as `03_ENGINEERING/DEC130_ARTIFACTS.md`).

## Done (code committed on feat/ios-lane-parity)
- DEC-130 decision (DECISIONS.md) + full 118-clip eval manifest (`validation/cv_eval/manifest_all.json`).
- Data pipeline: `ops/autolabel.py` (auto), `ops/zeroshot_label.py` (OWLv2+motion), `ops/harvest.py`, `ops/make_dataset.py`.
- Detector: `ops/train_detector.py` (unified ball + lane-geometry CenterNet, MobileNetV3-L, stride-4).
- Export: `ops/export_coreml.py`. Integration: `ops/detector_integrate.py`.
- Baseline grade (survived in repo): classical engine tracks **68/118**; split at `~/LaneSightData/dec130/baseline_full_split.json`.
- Previously validated (artifacts since lost, being regenerated): ball-only recall 0.957; CoreML ~4 ms/frame.

## Running / next
1. [DONE] Harvest auto (64 clips, 2460 fr) + zeroshot (43 clips, 604 fr) -> `~/LaneSightData/dec130/dataset/`.
2. [DONE] make_dataset -> splits (74 train clips/2803 fr, 10 val, 6 holdout = IMG_8751-54,8964,8981).
3. [RUNNING] Train unified ball+lane v3 -> `~/LaneSightData/dec130/models/v3` (log `logs/train_v3.log`).
   ep2 recall 0.940 lane_mae 0.059. ~240s/epoch, 30 epochs.
4. [DONE, uncommitted on disk] Integration: pipeline.analyze gains `detector=` (default-off, 463 pytest pass);
   LearnedDetector in ops/detector_integrate.py; cv_eval `--engine learned --ckpt/--mlpackage`.
5. [NEXT] Export CoreML (+ backup to `backup/` + gs cloudbuild bucket + sha256 in DEC130_ARTIFACTS.md).
6. [NEXT] Learned eval: cv_eval --engine learned on holdout then all 118; verify honest metrics on failing clips.
7. [NEXT] iOS Swift port (OnDeviceTracker) + bundle CoreML model.
8. [NEXT] Full eval vs Done bar (speed truth = foul-cross->pin-contact, 22 labeled); deploy (shadow); install; ONE report.

## OPERATIONAL NOTE (important)
The pre-commit hook runs the IMG_8751-54 golden regression = 4 parallel CV analyses that saturate all cores and
STARVE training's dataloader (training dropped to ~1% CPU, epochs stalled). **Do NOT git-commit while a training
run is active.** Hold commits; batch them after training finishes. Integration code is safe on the persistent repo
working tree meanwhile. Keep-awake = detached `caffeinate -dimsu` (survives session events; harness-tracked ones
get killed at turn boundaries).

## Done bar (per camera group)
metrics on the large majority; speed within 0.5 mph of truth on labeled clips; zero plausible-but-wrong;
IMG_8751-54 not worse; deterministic; <30 s on device.
