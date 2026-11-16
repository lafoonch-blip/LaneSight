# DEC-130 progress — learned detection front-end

Status doc for the autonomous build (DEC-130). Resume from here. Updated at each milestone, committed + pushed.
**Last updated:** 2026-11-15 (DEC-131: audio REMOVED, no mic; building the visual pin-contact classifier — see v5).

## v7 (2026-11-16) — production dual-engine + iOS changepoint; on-device parity gap found
**Server production path** (`ops/production_engine.py`): classical `analyze_clip` + learned `analyze_learned`
(CoreML ball/lane + pins + changepoint) reconciled — agree → classical; disagree >0.5 mph → **ENGINE_DISAGREE**
(unavailable, never pick one); only one → use it. `analyze_learned` also exposes `speed_besteffort` (classifier >
motion > geom) used only for the disagreement cross-check, so a clip the learned headline withholds (IMG_8968) is
still caught. **Production grade on 22: within ±0.5 10/22, coverage 10/22, MAE 0.146, held-out 6/6, landscape 2/2,
`wrong=[]` — ZERO plausible-but-wrong.** Committed `eb714b3`. MC pins exported to CoreML (3 ms, 0 px parity).

**iOS changepoint** (`OnDeviceTracker.contactChangepoint`, parity port) + arrival-agreement guard. On-device Release
validated: IMG_8751 18.08 (+0.21, 4.4 s), IMG_8966 16.95 (−0.29, 10.9 s **via the changepoint**), IMG_8967 (−0.15) —
parity with the server within ~0.3 mph, all HIT, all <30 s.

**On-device parity GAP (key finding).** Full 22-clip on-device Release gate: **within ±0.5 only 4/22**, 7
plausible-but-wrong (IMG_8963 −7.5, 8970 −7.7, 8974 −5.4…), ~10 `BALL_TRACK_NOT_FOUND`/`TRACK_TOO_SPARSE`. The gap is
NOT the changepoint (it HITs where the track is good, and the guard confirmed the wrongs survive without it) — it is
that the **on-device CLASSICAL engine is much weaker than the server's**: it fails to track the ball on the hard
portrait clips the server handled, and with only one on-device engine there is no ENGINE_DISAGREE to catch the
resulting wrong speeds. Closing this needs the **learned CoreML ball/pins engine ported on-device** (rescue the failed
tracks + provide the second estimate for an on-device ENGINE_DISAGREE) — a large Swift/CoreML port (the DEC-130 learned
detection pipeline was never built on-device; on-device is classical-only). Models are exported + bundled
(`ios/LaneSight/Models/Ball{Lane,Pins}Detector.mlpackage`, gitignored) as the foundation. This is the remaining work
for on-device parity → deploy → install.

## v6 (2026-11-15) — DEC-131 visual pin-contact classifier BUILT + graded
`ops/pin_contact.py`: `deck_motion_series` (foul-anchored window over the target-lane deck, bodies-above-bases,
per-frame phase-correlation re-align) + `detect_contact` (changepoint = largest step into the sustained scatter →
walk back to the rise start → subtract the one calibrated offset, ~3 frames) + NOISY/WEAK guards. `PinContactDetector`
wired into `analyze_learned` (authoritative: when it withholds, speed is unavailable — never the perspective-limited
motion/geom fallback that produced wrong values).

**Pin-contact accuracy (harvested labeled decks):** fires 5/13, **median 1.9 frames, worst 2.6, all within ±4**
(held-out 8751 +0.1, 8752 +2.1, 8754 +1.9). The other 8 are NOISY (handheld camera-motion residual) or WEAK (far/small
decks) → unavailable. Signal quality, not model capacity, caps coverage (a CNN over the same jittery crops wouldn't
help) — so the "classifier" is a deterministic frame-diff changepoint (one learned offset), not a CNN → the iOS port
is a Swift/Accelerate algorithm, not a CoreML model.

**Shipping-config grade (classical-first, classifier fallback, NO audio) on 22 labeled:**
| group | within ±0.5 | coverage | MAE | plausible-but-wrong |
|---|---|---|---|---|
| ALL 22 | **10/22** | 11/22 | **0.198** | IMG_8968 only |
| Held-out 6 | **6/6** | 6/6 | 0.164 | none |
| Landscape | 2/2 | 2/2 | 0.047 | none |
| Portrait | 8/20 | 9/20 | 0.232 | IMG_8968 |
vs the audio config (10/22, MAE 0.52, 3 wrong): same hit count, MAE down to 0.198, **wrongs 3→1**. The one remaining
(IMG_8968 −0.72) is CLASSICAL's own marginal miss (0.22 over the gate), not the classifier. 8966 (a classical miss) is
now a frame-accurate classifier HIT. **Still NOT deployed** pending the iOS port + deploy sequence.

## v5 (2026-11-15) — DEC-131: no audio; visual pin-contact classifier
Shayne's decision: no audio-based measurement, app must not request the mic. The audio work below (v4) proved pin
contact is a frame-accurate event (20/22 within ±4 frames) but is **removed** (`ops/audio_contact.py`, the audio block
in `learned_analyze`, and all iOS mic code). Replacement = a visual temporal "pins start moving" classifier on the
trained pin-deck crop of the bowler's (target) lane; train on classical-`detect_impact`-reliable clips + Shayne's 22
labeled contact frames (session split, hold out 6); goal ≤4 frames median. Foul-row / false-track guards kept.
`analyze_learned` now takes `pin_contact_detector`; `.contact_time(...)` supplies t_pins. Rollout per DEC-131: wire →
iOS CoreML → deploy (merge feat/form-ondevice) → install on-device-primary ON → 22-clip iPhone-engine table.

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

## v1 end-to-end result (2026-11-14) — HONEST NEGATIVE, drove the hybrid fix
Learned-only (detector lane + detector ball) on all 118 clips vs baseline vs foul->pins truth:
- speed coverage 24/101 (baseline 50/101) — WORSE; speed MAE 3.75 mph (baseline 0.24); within ±0.5: 1/22 (baseline 8/22).
- Diagnosis: detector tracks the ball well, but the lane-geometry regression head (~48px on foul/VP) corrupts the
  depth scale -> speeds wrong (IMG_8752 28.4 vs 18.0) or withheld. Table: `~/LaneSightData/dec130/eval/DONE_BAR_TABLE.md`.
- FIX (no retrain): HYBRID geometry — classical find_lanes (sub-pixel when it succeeds) for metric-grade depth +
  learned ball detection to fill tracking gaps; learned lane only when classical lane fails. Implemented in
  LearnedDetector.geometry. Re-eval in progress.

## v2 result (2026-11-14) — event-timing reformulation (Shayne's redirect): still below bar, cleaner diagnosis
Implemented `ops/learned_analyze.py`: headline speed = 59.44 ft / (t_pins - t_foul), time-based, NO depth.
  t_foul = ball ground-contact row crosses the foul-line row (row-based, geometry-tolerant).
  t_pins = detect_impact (ball-following) OR a brightness-located pin-deck motion box (fallback).
  boards = lateral interpolation of the ball center between lane edges on the same row.
**Grade on the 22 labeled clips:** coverage 5/22, within +/-0.5 mph **1/22**, MAE 2.44. Best: IMG_8968 -0.40 (HIT),
IMG_8969 -0.54, IMG_8751 +0.79. Most: IMPLAUSIBLE (pin detector fires early -> Δt too small -> >30 mph),
PIN_IMPACT_NOT_DETECTED, or FOUL/BALL not found.
**Clean diagnosis (important):** the logs show classical find_lanes SUCCEEDS on the portrait clips (foul±1px), so
geometry is NOT the blocker and the reformulation is correct in principle (it works when timing is clean). The sole
remaining wall is **precise event-timing detection**: pin-contact (t_pins) to ~0.05 s on the detector's tracks, plus
reliably tracking the ball THROUGH to the pins. detect_impact (tuned for the classical tracker) fires early/misses on
the learned tracks; the brightness pin-deck fallback fires early.
**NOT met:** Done bar. **NOT deployed** (fails the bar; accuracy beats coverage). **No regression** on classical-
success clips (classical-first architecture; IMG_8754 learned==baseline).
**Recommended next step:** a PIN-DECK / PINS detection class (Shayne's own suggestion) so t_pins comes from a
precisely-located pin box + motion — the clean fix. Needs a retrain (ball+lane+pins). Alternatively more event-timing
CV. Both are substantial; surfaced for a steer rather than spending hours speculatively.

## v4 result (2026-11-15) — AUDIO t_pins: the metric is SOLVED on the labeled set
Shayne's redirect: before building a temporal pin-motion classifier, try audio (cheap + physically frame-accurate).
The pin impact is a sharp broadband transient; its onset times the contact far better than any position-based method
(near the deck the ball barely moves in pixels, so pin_geo is perspective-limited to ~8-22 frames).

Implemented `ops/audio_contact.py`: ffmpeg mono extract -> STFT spectral-flux onset envelope (HF-weighted) ->
strongest onset in a window -> subtract sound travel (60 ft + camera-behind, at 1125 ft/s) -> apply the measured
constant capture A/V offset. Integrated into `learned_analyze` speed block.

**Audio calibration vs 22 frame-level labels:** after a constant **+1.16-frame** (iphone A/V) offset, **20/22 within
±4 frames, MAD 0.71 frames** (sub-frame). Camera-distance assumption is negligible (0→25 ft shifts delay ~1.3 f,
absorbed in the empirical offset).
**Audio t_pins + labeled foul (isolates audio quality):** within ±0.5 mph **20/22**, MAE **0.28**, **held-out 6/6**
(MAE 0.13). vs the pins-retrain visual path (0/22). This clears the speed bar on the labeled set.
**The 2 misses** (8967, 8976, multi-lane views) = the loudest in-window onset is an earlier, LOUDER neighbour-lane
crash. Guard: the contact cannot precede the ball's last detected frame (sound can't arrive before the ball reaches
the deck) — drops the early crash; if no onset survives -> CONTACT_AMBIGUOUS (unavailable, never wrong). The unreliable
`detect_impact` headline fallback is now opt-in (`LS_IMPACT_FALLBACK=1`) so no plausible-but-wrong speed leaks.

**iOS (DEC-130):** shot clips were silent. Added the mic input gated to SHOT mode (`CameraController.includeAudio`,
set in `CaptureView`), mic-permission priming, and `NSMicrophoneUsageDescription`. Form stays video-only. Server does
the audio onset on the uploaded clip (shadow architecture); on-device onset is a later optimisation.

**SHIPPING-CONFIG grade (classical-first, learned+audio fallback) on 22 labeled clips:**
| group | within ±0.5 mph | coverage | MAE | plausible-but-wrong |
|---|---|---|---|---|
| ALL 22 | **10/22** | 13/22 | 0.516 | IMG_8963, 8968, 8975 |
| Held-out 6 | **6/6** | 6/6 | 0.164 | none |
| Landscape 1920×1080 | 2/2 | 2/2 | 0.047 | none |
| Portrait 1080×1920 | 8/20 | 11/20 | 0.601 | 3 |

Classical-first keeps classical's sub-pixel accuracy where it works; audio-fallback (analyze_learned) covers clips
classical can't. Every remaining miss is foul/track CV, NOT t_pins: IMG_8963 foul-row geometry (+12f), IMG_8968
classical foul −0.72, IMG_8975 false early-track selection. The 9 uncovered clips are far/small-ball track failures
on portrait (5 BALL_TRACK_NOT_FOUND) + foul-not-detected (4). **Done bar: not fully met** (needs a large majority +
zero-wrong); held-out 6/6 and landscape 2/2 are clean. **NOT deployed** (3 plausible-but-wrong remain).

**Wiring note:** audio lives in `analyze_learned`; `cv_eval.py --engine learned` fallback calls `pipeline.analyze`
(no audio). This grade routes classical→analyze_learned(audio) directly. Shipping audio in the real server path needs
`analyze_learned`'s audio block wired into that fallback.

**Next levers (ranked):** (1) foul-cross CV — foul-row geometry + reject false-track selection (fixes 8963/8975,
tightens 8968); (2) far/small-ball tiled detection (DEC-130 #3) to recover the 5 no-track + unlock foul on the
no-foul portrait clips; both raise coverage toward the large-majority bar.

## Done bar (per camera group)
metrics on the large majority; speed within 0.5 mph of truth on labeled clips; zero plausible-but-wrong;
IMG_8751-54 not worse; deterministic; <30 s on device.
