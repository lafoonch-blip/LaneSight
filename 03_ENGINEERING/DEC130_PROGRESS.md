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
1. [RUNNING] Harvest auto (68 clips) + zeroshot (49 clips) -> `~/LaneSightData/dec130/dataset/`.
2. make_dataset -> splits (holdout = IMG_8751-54, 8964, 8981).
3. Train unified ball+lane v3 -> `~/LaneSightData/dec130/models/` (+ backup + manifest).
4. Export CoreML (+ backup + manifest); verify <15 ms + lane geometry.
5. Integration end-to-end (server reference `analyze_learned`), verify honest metrics on failing clips.
6. iOS Swift port + bundle CoreML model.
7. Full eval vs the Done bar on all 118 clips (speed truth = foul-cross->pin-contact, 22 labeled clips).
8. Deploy (server shadow), install Release, ONE report (coverage/accuracy table + screenshots).

## Done bar (per camera group)
metrics on the large majority; speed within 0.5 mph of truth on labeled clips; zero plausible-but-wrong;
IMG_8751-54 not worse; deterministic; <30 s on device.
