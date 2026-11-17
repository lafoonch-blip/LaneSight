# DEC-130 progress — learned detection front-end

Status doc for the autonomous build (DEC-130). Resume from here. Updated at each milestone, committed + pushed.
**Last updated:** 2026-11-16 (v12: DEC-132 Stage 4 withholding — on-device WRONG 9→2; remaining 2 need the pin-detector port — see v12).

## v12 (2026-11-16) — DEC-132 Stage 4 (withholding): on-device WRONG 9→2, 4 correct kept
**The gate blocker was WITHHOLDING discipline, and the fix is a single faithful change.** `speed()` fell back to
`tImpact = argmax(u)` (the ball's farthest tracked point) when the measured pin-motion impact (`track.impactT`) was
nil — fabricating an impact and emitting a plausible-but-wrong foul→pins speed on every clip the server withholds.
Replaced with a guard: **no measured impact → unavailable (PIN_IMPACT_NOT_DETECTED)**, exactly the server's rule
(`analyze_learned`: the classifier is the authority; the ball-following `detect_impact` is OFF by default because it
"produced plausible-but-wrong speeds"). One change, both engines (both go through `speed()`). Committed b657426.

**On-device, all 22 clips, vs ground truth (60 ft / (pin_f−foul_f)/fps):**
| | correct | withheld (server also withholds) | WRONG | MAE(reported) |
|---|---|---|---|---|
| before (v11) | 4 | — | 9 | 2.75 |
| **after Stage 4** | **4** (8751 .04, 8752 .64, 8966 .45, 8967 .31) | 8963 8964 8968 8970 8972 8974 8978 | **2** (8969 3.8, 8973 4.6) | — |

**The 2 remaining wrong (8969, 8973) need the on-device PIN DETECTOR (task #40).** Both have a *measured* impact that
OVERSHOOTS: the device anchors impact to the ball's farthest TRACKED point, but the ball rolls ~0.5 s PAST the pins
into the pit (8969 far.t 5.04 vs true contact ~4.38) → span too long → 14.5/13.3 mph for 18/18 mph balls. The server
avoids this with its DETECTED head-pin row (`t_geom` stops AT the pins) + the trained pin-contact classifier as the
authority — neither is on-device yet. No clean non-overfit guard separates 8969/8973 from the 4 correct clips using
the signals the device has now (checked arrival time, track-end, past-impact tail — none separate; ENGINE_DISAGREE
fails too, both engines agree-wrong). STABILISATION and linker robustness are NOT the issue (detector positions match
the golden to ~2 px; v11).

**NEXT (gate-closing): wire the on-device pin detector → head-pin row** (task #40) so impact anchors to the pins, not
the ball's farthest point — then re-run the 22-clip gate (target: 0 wrong), remove `LS_LEARNED_ONDEVICE`, install
Release, report the iPhone table. **DE-RISKED:** `ios/LaneSight/Models/BallPinsDetector.mlpackage` is already bundled
and is the SAME architecture as BallLaneDetector (image[1,3,512,512] → heatmap[1,**4**,128,128]/wh/offset/lane) — a
4-channel multi-class heatmap (ball/pins/dots/arrows). So this reuses the existing `detect()` letterbox+fp16-read
pipeline: load the second model, multi-peak-decode the PINS channel (several pins, not argmax), take the head-pin row
(nearest-camera pin row), and (a) stop `detectImpact`'s ROI AT that row and (b) reject an impact whose implied contact
sits past it. Determine the pins channel index from the mc label order (DEC-130 task #35). Commits this session: 97d27df (S1 detector parity), 7583249 (S3 linking), 84485a4
(stabilisation disproven), b657426 (S4 withholding). On feat/ios-lane-parity, local only (gate not yet passed → not
pushed).

## v11 (2026-11-16) — DEC-132 staged port: Stage 1 PASSED; gate root-caused to on-device stabilization

## v11 (2026-11-16) — DEC-132 staged port: Stage 1 PASSED; gate root-caused to on-device stabilization
Porting the server learned pipeline to on-device piece-by-piece, each validated vs the server golden JSON on the 22
clips (per-stage parity harness: `scratchpad/detector_parity.py` + `dump_server_golden.py`; golden in
`~/LaneSightData/dec130/golden/`).

**Stage 1 (detector input parity) — PASSED, committed 97d27df.** Ported the server offset-head sub-cell refinement
(`cx=(px+ox)*st/s`) into on-device `detect()` + `detectInCrop()`. Without it the bare stride-4 cell quantises ball
position to ~15 px. Parity harness (device `learned_dets` vs server golden, time-aligned per clip to absorb the
device/server trim offset): **median-of-medials 2.6 px over 16 aligned clips; 11 ≤10 px, 15 ≤25 px.** 8966 156
matched @2.9px, 8964 150 @1.0px, 8974 82 @1.1px. Only 8977 (moving camera) at 292px.

**Stage 3 (robust linking) — committed (faithful port), but does NOT move the gate.** Added static-artifact
rejection + lateral-fraction consistency + min-depth seed gate + segment trimming (server `link()` lines 120-173) to
`buildTrack`. Builds, links on 3 more clips. **But the reported `speed_avg_foul_to_pins` was byte-identical before
and after** → proof the metric is the CLASSICAL engine's; the learned engine never influences it (reconciliation is
fallback-only, classical always emits something).

**GROUND-TRUTH accuracy (true speed = 60 ft / (pin_f−foul_f)/fps, all 22 clips):**
| engine | n speeds | MAE | max err |
|---|---|---|---|
| server (learned path) | 5 | **0.27 mph** | 0.51 |
| on-device (reconciled = classical) | 12–13 | **2.75–2.89 mph** | **7.81** |

The device's extra numbers are **plausible-but-wrong**: 8970 says 9.6 mph for a 17.4 mph ball, 8963 10.3 for 17.9.

**ROOT CAUSE of the speed gate (numbers-backed):** every wrong clip is **handheld** (IMG_8963–8981); the accurate
ones are **tripod** (8751/8966/8967, err 0.04–0.45). The on-device detector + classical tracker run on **RAW frames**
— the server runs on **STABILIZED** frames. On handheld, camera motion corrupts the track: classical UNDER-estimates
(9–15 mph), learned OVER-estimates (23–30 mph) — opposite directions, so not a scale bug, it's event-timing drift
from camera motion. Tripod clips are correct because raw≈stabilized there.

**ENGINE_DISAGREE (Stage 5) alone cannot reach zero-wrong** (modeled from `learned_avg` vs classical): withholds the
2 worst (8963, 8970) but 6 wrong survive — 8969/8972/8973 **agree-wrong** (both engines ~14/15/13), and 8964/8974/8978
are classical-only (no cross-check) — and it wrongly kills good classical on 8752.

**STABILISATION TRIED AND DISPROVEN (2026-11-16).** Integrated per-frame `VNHomographicImageRegistrationRequest` into
`buildTrack` (register each rotated frame to the first, map the ball centre through the homography into reference
space) and re-ran all 22 on-device. Result: **learned speeds byte-identical** (8963 30.20 vs 30.21, 8970 25.52 vs
25.55) and detector parity slightly WORSE (2.6→3.1 px). Reason: the detector positions **already match the server
(stabilised) golden to ~1-2 px on RAW frames** (8963 0.8px) — these validation clips are near-static, so the camera
-motion theory was wrong. Reverted the stabilisation loop (it only adds Vision latency + registration noise); kept the
harmless `detectRotated` refactor. Camera motion is NOT the blocker.

**CORRECTED ROOT CAUSE = WITHHOLDING discipline (not positions, not stabilisation).** On 8963 the positions are perfect
(1px) yet the device emits 10.26 (classical) / 30.20 (learned) while the server **withholds** (PIN_IMPACT_NOT_DETECTED).
The error is in EVENT TIMING / the best-effort fallback: both on-device engines force a speed where the server returns
unavailable. The server's `detect_impact` returns None when pin motion isn't confidently detected; the device's
classical impact path + the learned "best_effort: trajectory anchors" fallback emit a number anyway.
**NEXT: port the server's withholding to BOTH on-device speed paths** — make the impact/changepoint confidence gate
return unavailable (no best-effort trajectory-anchor fallback) so the device withholds exactly where the server does.
Target: match the server's 5-speed / MAE-0.27 / zero-wrong profile. This is the gate lever; Stages 2-3 (detector,
linker) are done and correct but cannot move a classical-dominated, over-producing output.

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

## v10 (2026-11-16) — learned track→speed root-caused to track NOISE (needs Priority-2 robust linking)
Priority-1 tuning (robust bracket foul-cross + arrival-guarded changepoint) improved but did not fix the learned
speed (8966 24.9→20.7, still +3.4). Root cause, fully traced: the on-device learned track carries **spurious
far-down-lane detections** (a false positive — pin/reflection — at u higher than the real ball). That spurious point
becomes the max-u "far point", so (a) the arrival guard anchors the changepoint there and (b) the changepoint locks
onto a false early deck-motion event (8966 impact 10.36 vs true 11.54). The foul is separately noisy (global linear
u-fit skewed by sparse small-ball down-lane positions). Added: a learned-lane sanity guard (rejects the garbage VP
e.g. −141764), a bracket-interpolated foul-cross threaded into speed() + the changepoint, reconciliation set to
fallback-only. The real fix is **Priority 2**: tiled native-res crops along the lane ROI (accurate small/far-ball
positions) + **constant-acceleration linking** (reject spurious points, densify sparse tracks) — i.e. port the
server's `detect_in_crop` + a quadratic trajectory model. Then a reliable changepoint, then on-device ENGINE_DISAGREE.
On-device full-22 = 4/22 (vs server 10/22). Detector itself is solid (real tracks, 58–97 pts). Gated LS_LEARNED_ONDEVICE;
shipping = classical + changepoint (installed).

## v9 (2026-11-16) — PHASE 1 SHIPPED; on-device detector FIXED; learned track→speed tuning remains
**Phase 1 DONE.** Merged `origin/feat/form-ondevice` (shot-side DEC-131 renumbered → **DEC-132**; form keeps DEC-131),
pushed. **Deployed** `lanesight-api-47dfd3b` (golden gate 7/7 + smoke pass 18.675 vs 18.71±0.2; expected_rev bumped;
serving 100%). **Installed Release on Shayne's iPhone** — classical + changepoint, on-device primary default ON
(confirmed `AppModel.onDevicePrimary` returns true), learned fallback gated `LS_LEARNED_ONDEVICE`. NOTE: the deployed
server runs CLASSICAL analyze + the form fixes (production_engine is eval-wired, not in `app.py`; and the image is
torch-free) — the zero-wrong dual-engine is validated in eval + runs on-device once Phase 2 lands; activating it
server-side needs torch-in-image (a separate careful deploy).

**Phase 2 — on-device learned engine: DETECTOR NOW WORKS.** Root-caused the constant-peak bug: the CoreML model is
exported **FLOAT16**, but the heatmap/lane outputs were read as Float32 → garbage ~1e34 constant peak. Fixed with a
precision-aware reader. Plus the earlier fixes (normalised-zero letterbox border; vImage high-quality downsample;
3-frame stride for memory/latency). The detector now produces REAL moving ball tracks on device (IMG_8751 learned
18.57 / 58 pts, 8963 97 pts, 8966 67 pts).

**OPEN (the Phase-2 gate):** the learned track→**speed** is still noisy (8751 +0.69, 8966 24.9) and fails on most of
the classical-failure clips it should rescue (buildTrack/speed reject on the far portrait tracks); reconciliation is
currently **fallback-only** (learned used when classical has no speed) because cross-checking a noisy learned speed
withholds good classical clips. On-device full-22 = **4/22** (vs server 10/22). To reach the gate (iPhone↔server
parity per event + speed, zero plausible-but-wrong, 10/10 deterministic, <30 s): (1) make the learned track→speed
accurate on the detector tracks — foul-cross from a robust fit, changepoint impact with the learned deck, DEC-122-7b
handling; (2) a reliable on-device ENGINE_DISAGREE to catch the classical wrongs (8963/8970/… ship wrong today).
Shipping on-device engine stays classical + changepoint (installed) until this passes, then: remove the gate, install
again, report the iPhone 22-clip table.

## v8 (2026-11-16) — on-device learned engine: built, detector decode diagnosed (WIP, opt-in)
Built the on-device learned fallback end to end (`OnDeviceLearnedDetector`: CoreML ball/lane inference + RANSAC-linked
track + lane-from-head; `OnDeviceShadow` learned fallback + ENGINE_DISAGREE; `OnDeviceTracker.impactTime` changepoint
wrapper). Compiles + runs on device; fixed two real bugs found on device: (1) per-frame 3 MB MLMultiArray memory
pressure → crash, fixed by running the detector every 3rd frame; (2) the letterbox border was raw-0 instead of the
server's **(0−mean)/std** normalised zero — raw-0 is out-of-distribution and made the detector fire a constant border
peak.

**OPEN (the remaining on-device blocker):** after the padding fix the ball-peak response falls below the 0.30
threshold (`raw=0`). Root cause isolated: the server detector runs on the **stabilised** frame with a **bilinear**
letterbox resize, while the on-device port runs on the **raw** frame with a **nearest-neighbour** resize — which
weakens the small-ball heatmap below threshold. Fix is a focused CV-parity pass (stabilised input + bilinear/area
resize, confirm the heatmap is sigmoid-ed [0,1], re-tune the threshold) then finish the RANSAC-track → speed path.
Gated behind `LS_LEARNED_ONDEVICE=1` so the shipping on-device engine stays the validated **classical + changepoint**
path. Models compile on-device (`Models/Ball{Lane,Pins}Detector.mlpackage`).

**On-device status (classical + changepoint, shipping):** 4/22 within ±0.5 — the changepoint HITs where the classical
track is good (8751 +0.21, 8966 −0.29, 8967 −0.15, all <30 s); the rest are the weak on-device classical tracker,
which the learned fallback closes once the decode pass above lands. (Server engine: 10/22, zero-wrong.)

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

## FOLLOW-UP (deferred by Shayne, 2026-11-16) — run production_engine on the server shadow
The deployed `lanesight-api-47dfd3b` runs the CLASSICAL analyze path + the form fixes. To run the **zero-wrong dual
engine** (`ops/production_engine.py`: classical-first + learned + ENGINE_DISAGREE) on the server shadow, these changes
are needed (NOT done now — the server is the shadow, on-device is primary):
1. **Torch on the image.** The Dockerfile is deliberately classical/OpenCV, no GPU. The learned path needs
   `torch` + `torchvision` (CPU) in a pyproject extra, installed in the Dockerfile. Cloud Run is Linux → **CoreML
   (.mlpackage) cannot run there**; `production_engine._load_detectors` must load the **torch** ckpts
   (`ball_centernet.pt` + `detector_mc.pt`, 22 MB each) on non-Darwin, not the mlpackage.
2. **Bundle the ckpts.** Fetch them in the Dockerfile like the pose model (they live in
   `gs://project-fd28bc3f-…/dec130/`), set `LS_DEC130_DIR`.
3. **Wire into the API.** `lanesight_api/app.py` calls `analyze_clip` (classical) at :496/:1967; route it through
   `analyze_production` (which returns a dict, so adapt the `(rec, probe, timings)` unpacking) behind a flag that
   degrades to classical if the detectors are absent.
4. **Validate latency.** Both engines per request on CPU is slow (~2× classical); confirm within the 600 s sync
   timeout and that the post-deploy smoke stays green (risk: OOM / latency → auto-rollback).
Risk to the live API is real (torch image size, CPU latency), so this warrants its own careful, separately-gated
deploy rather than bundling into the form-fix deploy.

## Done bar (per camera group)
metrics on the large majority; speed within 0.5 mph of truth on labeled clips; zero plausible-but-wrong;
IMG_8751-54 not worse; deterministic; <30 s on device.
