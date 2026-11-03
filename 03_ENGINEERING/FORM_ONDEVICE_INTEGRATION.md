# Form on-device integration (DEC-129)

Status: ACTIVE · Version: 2.0 · Last Updated: 2026-11-03 · Owner: Shayne
Decision: DEC-129 (Form analysis runs on-device, matching the DEC-126/127 shot architecture).

## Update 2026-11-03 (device-build session) — what's now DONE vs device-pending
Done on Shayne's Mac (Xcode 27.1): **§A** MediaPipe vendored via `Vendor/fetch_mediapipe.sh` (MediaPipeTasksVision +
MediaPipeTasksCommon 1.0.0 xcframeworks + the force-loaded `graph_libraries/*.a` + the pose model → Models/); the
`project.yml` dependency + sdk-conditional `-force_load`/`-ObjC` are live; **Release builds SUCCEED for device
(generic/platform=iOS, signed)**, and MediaPipe loads + runs (the TFLite XNNPACK delegate initializes). The Swift
form engine compiled clean after 3 small fixes (a `let`→`var status`, a no-op line, and marking the pure-compute
types `nonisolated` so they run off the main actor). **§B is now WIRED (not just spec'd):** `AppModel` has
`measureOnDeviceFormPrimary` + `showOnDeviceFirstFormResult` + `buildFormResultFromCard`/`offlineFormResult`, and
the capture pipeline routes `capture_mode=form` through the on-device-first path (gated by `ls.ondevice_primary`,
default OFF — ships dark). `APIClient.scoreFromMetrics` gained additive form params (events/view/measured_positions/
form_version). It all compiles + links for device Release.

**The gate RAN on device (2026-11-03) and does NOT pass yet (7 failures)** — full per-clip table + analysis in
`02_RESEARCH/FORM_ONDEVICE_DEVICE_GATE_2026-11-03.md`. Headline: determinism 10/10 on all clips; the port is
faithful (reproduces the server reference tightly where the two MediaPipe runtimes agree); E7/E8 parity-match
within ~0–2 f; the gaps are the iOS-vs-Python MediaPipe landmark difference (step count + the 8825 window) and
runtime >30 s on long untrimmed 60 fps clips. The Release build is installed on the iPhone.

**Still device-pending:** one **end-to-end form upload** — flip `ls.ondevice_primary` on (Dev Panel), record a
Form delivery (a short live clip stays under the 30 s cap), confirm on-device metrics → `/shots/metrics` form
branch → one Complete/Offline form result. The **Complete (coaching) path needs the `/shots/metrics` form branch
deployed to the live API** (server deploy = Shayne's call); until then the metrics call hits the old server and
the card shows the Offline (measured-only) state.

This is the hand-off for wiring the on-device Form **engine** (built, parts 1–3 below) into the **app flow**
(part 4). The engine, the Python parity golden, the gate test, and the **server** form branches are done and
pytest-green. The iOS app wiring is specified here because it is coupled to the DEC-119 ↔ DEC-127 capture-pipeline
reconciliation that Session 1 / Shayne own (see "AppModel" below) — it needs a device build to verify.

## What is DONE (committed on `feat/form-ondevice`, 447 pytest pass)

1. **On-device Form engine** — `ios/LaneSight/Sources/OnDevice/Form/` (a faithful 1:1 port of
   `lanesight_core/form/pose.py` + `fundamentals.py`):
   - `FormPoseLandmarker.swift` — MediaPipe **Pose Landmarker (heavy, VIDEO mode)**, 33 BlazePose landmarks incl.
     feet (ankle/heel/foot_index), per-frame container PTS, display-orientation (reuses `OnDeviceDecode.rotated`).
     `#if canImport(MediaPipeTasksVision)` so the file compiles before the pod is added (throws
     `.mediaPipeUnavailable`). NOT Apple Vision (no feet) — supersedes `OnDeviceFormShadow`.
   - `FormSignal.swift` — numpy primitives (`gradient` non-uniform, `smooth`, `point`, `torso`, `speed`,
     `localMinima`/`localExtrema`, `interp`, `searchsorted`, `median`).
   - `FormEngine.swift` — delivery segmentation (`findDelivery`/`looksSlowmo`/`setupHoldEnd`), foot strikes,
     slide foot + stop, swing events (E2–E8 via wrist arc), slo-mo, `gateEvents` honesty gates, view classify.
   - `FormResult.swift` — `FormMeasurement` + `FormAnalysis` (FORM_P1 metrics, events, measured positions, stage
     report) with `metricsJSONObject` / `eventsJSONObject` / `stageReportJSONObject` for the server contract.
   - `OnDeviceFormEngine.swift` — `analyze(clipURL:handed:) -> FormAnalysis` orchestrator (= `pose.analyze` +
     `analyze_form_clip`), partial results + DEC-122 stage report.
   - `FormFundamentals.swift` — M1–M7 measured positions + view gating.
   - `FormBallTrack.swift` — documented no-op hook (the reference ball-confirm never moved E7 on the labeled set,
     so the wrist arc is parity-exact; a faithful OpenCV port is a future item if a clip needs it).
2. **Python parity golden** — `examples/form_ondevice_golden.py` → `validation/form_ondevice_golden.json`
   (the Python reference on all 7 labeled clips; the on-device parity target).
3. **Gate test** — `ios/LaneSight/Tests/OnDeviceFormGateTests.swift` (determinism + engine-parity-vs-server
   ±2 frames + step-count exact; reports DEC-121 ground-truth deltas + runtime; SKIPs without bundled clips/model).
4. **Server** — `lanesight_api/app.py`:
   - `POST /shots/metrics` `capture_mode=form` → `_form_shot_from_metrics(...)` builds the form record from the
     device `metrics`+`events`+`view` and runs `engines.after_form_analyzed` (timing checkpoints T1–T4,
     swing_timing vs baseline, measured-position enrichment, coaching cues, focus) — the SAME pure fundamentals
     the video path runs, no video. Writes DEC-122 outcome rows (mode `form`, engine `iphone`). Returns the form
     card. Tests: `tests/test_metrics_endpoint.py::test_form_metrics_*`.
   - `POST /shots/{id}/shadow_video` now runs the FORM video shadow (`analyze_form_clip`, platform `server`) — was
     "not supported". So a live form delivery ends with BOTH an `ios` and a `server` attempt + outcome rows.

## PENDING Shayne / Session 1 (needs Xcode + a device)

### A. MediaPipe dependency + model + clips (`project.yml`)
- Add `MediaPipeTasksVision.xcframework` as a vendored framework on the app target:
  `dependencies: - framework: Vendor/MediaPipeTasksVision.xcframework` with `embed: true`. (No `packages:` section
  exists; this is additive. Git LFS is not configured — either init LFS for the xcframework or fetch it via a
  documented script, like the model below.)
- Bundle the pose model as a resource: `pose_landmarker_heavy.task` under e.g. `ios/LaneSight/Models/` added to the
  app target `sources:` as a resource (like `Resources/Fonts/*` and the `LaneRender/three` folder reference).
  **Do not commit the 30 MB model** — gitignore it and copy it from `~/LaneSightData/models/` before building
  (same pattern as `Tests/GateClips`). `FormPoseLandmarker.resolveModelPath` finds it in the bundle or via
  `$LANESIGHT_POSE_MODEL`.
- Gate fixtures: drop the labeled clips in `ios/LaneSight/Tests/FormGateClips/` (gitignored) + add
  `validation/form_labels.json` and `validation/form_ondevice_golden.json` as test resources, and declare both
  `Tests/FormGateClips` and those JSONs as `buildPhase: resources, optional: true` (mirror `Tests/GateClips`).

### B. iOS on-device-first FORM wiring (`AppModel.swift` + result builders)
This is coupled to the capture-pipeline reconciliation (see AppModel below). Once the on-device-first path exists
for shots, add the form branch:
1. **Measure:** where shots call `measureOnDevicePrimary(... mode:"shot")` running `OnDeviceShadow.run`, add a form
   path that runs `OnDeviceFormEngine.analyze(clipURL:handed:)` (full clip, no window trim — DEC-101) under the
   same 30 s cap + `Task.isCancelled` handling.
2. **Serialize:** build the `POST /shots/metrics` body from `FormAnalysis`:
   `metrics = analysis.metricsJSONObject`, `events = analysis.eventsJSONObject`,
   `measured_positions` from `analysis.measuredPositions` (each `.dict`), `view = analysis.view`,
   `status = analysis.status`, `form_version = analysis.formVersion`,
   `stage_report = analysis.stageReportJSONObject`, `capture_mode = "form"`, `algorithm_version =
   OnDeviceFormEngine.backendVersion`. Post via a form variant of `client.scoreFromMetrics` / `postMetricsRaw`.
3. **Render once:** on success build a form `ShotResult` from the response (`isForm = true`, attach
   `FormCardView` via `attachFormFundamentals`); on timeout/offline show an **Offline** form card from the
   on-device metrics (coaching pending) and enqueue the metrics body like the shot path.
4. **Background:** reuse `backgroundUploadAndShadow` (Wi-Fi only by default) and call `shadowVideo` for the form
   server shadow.

### C. AppModel capture-pipeline reconciliation — DONE by Session 1 (f638c02)
Session 1 reconciled the two capture pipelines on `feat/ios-lane-parity` (commit f638c02 "Merge dev-build-v0 into
feat/ios-lane-parity (DEC-119 durability + PR #6 F&F/feedback + DEC-127/128)"). Its `AppModel.swift` now carries
**all** of: the DEC-127 on-device-first path (`runPipeline`/`measureOnDevicePrimary`/`/shots/metrics`/
`backgroundUploadAndShadow`), the DEC-119 durable-upload + active-session/resume lifecycle, and the DEC-124/125
ff-feedback members. The re-merge (2026-11-03) **took that reconciled `AppModel.swift` (`--theirs`)** — so the
on-device-first scaffolding now exists on `feat/form-ondevice` and all kept files resolve against it. The only
remaining AppModel work is **B** below (add the FORM branch to the on-device-first path) — no longer a pipeline
design decision, just the additive form wiring. It is left as this spec (not committed) because it is
unverifiable without an Xcode/device build and `AppModel.swift` is Session 1's actively-changing file; applying B
with a compiler is a few-minute change.

## Verification status
- **Verified (this session):** 463 pytest pass incl. the form metrics-endpoint tests; the Python parity golden ran
  on all 7 labeled clips; the IMG_8751–54 CV regression passes (no CV touched).
- **Unverified (needs Shayne's Xcode + iPhone):** the iOS build after the MediaPipe dependency is added; the
  on-device parity gate (`OnDeviceFormGateTests`) on real MediaPipe landmarks; per-clip runtime <30 s on device;
  determinism across 10 runs on device. The gate is authoritative only on a device (MediaPipe-iOS landmarks differ
  slightly from the Python/XNNPACK reference, which is exactly what the ±2-frame tolerance + on-device run cover).
