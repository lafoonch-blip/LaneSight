# LaneSight Video Architecture & Cost Strategy — Claude Handoff
Status: WORKING CONTEXT (not an approved architecture decision)
Version: 1.0
Last Updated: 2026-10-19
Owner: Product
Applies to: video capture, analysis, storage, cost controls, and future sensor fusion

## Purpose
Summarize the October 2026 video architecture discussion for Claude to evaluate against **existing code and accepted decisions**. This is an input to technical specifications, **not** permission to replace existing designs or rewrite the implementation.

## Read these first
Follow root `AGENTS.md` reading order. In particular:
- `00_CONTEXT/DECISIONS.md` and `00_CONTEXT/CURRENT_STATE.md` win over this handoff if they conflict.
- `01_PRODUCT/BUILD_PLAN.md`, `01_PRODUCT/METRIC_CAPABILITIES.md`, `01_PRODUCT/METRIC_AND_SCORING_LOGIC.md` define committed scope, constraints, and metrics.
- `03_ENGINEERING/` and `lanesight-core/` contain the existing implementation; extend rather than rebuild.
- Do not edit historical DEC entries. Propose a *new* DEC for any material architecture change.

## Product goals
- Capture from different camera angles (behind, diagonal, side, front when useful), with stationary/tripod and moving/handheld recordings.
- Recover where defensible from temporary occlusions, bystanders, camera motion, inconsistent lighting, glare, and imperfect framing.
- Deliver honest shot and form metrics with **per-metric confidence, uncertainty, provenance, and explicit unavailable states**.
- Capture video once; retain a compact, durable performance record and optional relevant clips, rather than all raw footage.
- Support later video + Ruby/Storm/other sensors + authorized scoring feeds through source-agnostic contracts.
- Prioritize **low cost to launch, low recurring cost per shot, and incremental improvements** over expensive APIs, subscriptions, or GPUs.

## Existing project reality (verify latest before coding)
- Native iOS SwiftUI + AVFoundation and real frame timestamps; Python `lanesight-core` + FastAPI + Supabase backend are already accepted (DEC-029). First app iteration is capture/upload; on-device CV is an **optional later optimization**, not the committed v1 pipeline.
- Fixed-camera remains validation baseline, **but moving-camera measurement is already in MVP backend scope** (DEC-018). Do not incorrectly defer all moving-camera work post-MVP.
- Highest supported practical fps targeting **120 fps**, with capture-aware uncertainty, follows DEC-028; do not silently reset capture default to 60 fps. Preserve actual timestamps (variable fps possible).
- Existing pipeline already handles tripod/handheld to a degree, has local Mac runner, trim preprocessing, rev rate and pins confidence/unavailable gates, replay payload, Ruby comparisons. Review `CURRENT_STATE.md` and live code before suggesting replacements.
- Existing acceptance gates and validation against Ruby/Specto matter more than an aspirational feature chart. Historical decisions on headline ball speed have evolved; consult latest DEC entries rather than using an older definition.

## Recommended architecture boundaries (proposal, not mandatory vendor commitments)
1. **Capture adapter** — AVFoundation video, timestamps, camera/lens metadata, orientation, frame rate, possible motion/IMU; in future sensor/glasses capture adapters.
2. **Vision engine** — lane detection, camera calibration, lane-plane registration/perspective, stabilization, ball/bowler/pose/pin recognition, object tracking, occlusion flags, and shot-event windows.
3. **Measurement engine** — reusable calculations, source/provenance, per-metric uncertainty, quality and availability, video/sensor conflict checks.
4. **Data engine** — versioned `ShotRecord`, session/shot metadata, compressed time-indexed tracking observations, metric results, analysis version, optional video pointers, and deletion/retention controls.
5. **Recommendation engine** — deterministic/rules-based insight initially; generative coaching only if it later justifies its cost.

Keep algorithms, codecs, and object-storage providers behind interchangeable modules; avoid per-shot external API lock-in.

## Robustness requirements
- Calibrate each camera relative to visible fixed lane landmarks: boundaries, foul line, arrows/dots, pins and/or additional reference features. Record calibration quality.
- For camera motion: register lane plane per frame/segment and estimate drift; distinguish camera motion from actual ball/bowler motion. For large turns, rolling shutter, or unobservable lane, mark dependent metrics unavailable.
- For temporary obstacles: record observed vs predicted/interpolated trajectory segments separately; reacquire ball after occlusion; reduce relevant metric confidence; do not hallucinate occluded pin leaves/rev rate/axis.
- Pose analysis depends on angle and visibility; behind-camera footage cannot guarantee full-body mechanics, while side footage may not yield reliable board crossings.
- Metric fidelity is capture- and view-dependent. Video rev/axis/PAP are conditional; sensor telemetry remains an optional complementary source. Do not claim full metric coverage from arbitrary video.
- Pin leave unreadable when deck blocked; rev unavailable when pattern cannot be resolved, per existing decisions.

## Cost-first technology options
| Need | Low-cost starting point | Caveats |
|---|---|---|
| iOS video capture | AVFoundation / native camera + native HEVC/H.264 encoding | Device support, licensing and frame/timing tests |
| Computer vision and lane geometry | Existing OpenCV-based Python pipeline | Open source; engineering, evaluation, and optimization still cost time |
| Form/pose | Apple Vision or MediaPipe evaluated experimentally | Model/weights license, deployment and performance review required |
| Video trimming | Existing shot-window pre-pass; FFmpeg or native encoding | Preserve approach, release, trajectory, settled pin deck; current trim may still be long |
| Ball tracking/occlusion | Existing models + conventional tracking/filters | Custom training only when evidence warrants it |
| Back-end metrics | Existing `lanesight-core`, FastAPI, Postgres | Reuse current implementation |
| Structured cloud data | Supabase already chosen | Free/paid tier quotas, RLS, bandwidth |
| Video blobs | Evaluate Supabase Storage vs Cloudflare R2 | R2 is **candidate**, not a chosen migration. Include operational overhead, requests, auth, egress, lifecycle |
| Recommendations | Existing deterministic logic | Avoid LLM API call per shot |
| Development inference | Existing local Mac runner and affordable CPU workers | No automatic always-on GPU subscription |
| Mobile on-device inference | Apple Vision/Core ML eventually | Profile latency, device battery, thermal impact, app complexity before migrating |

**Key tradeoff:** On-device inference may reduce marginal cloud compute but **cost more to build and debug**. Preserve DEC-029's local-Mac→service→cloud sequence unless a measured cost/latency benefit supports a new decision. Prototype models on existing hardware first.

## Capture, retention, and storage
- Continuous session recording should become **event-driven shot windows**. The app/device should avoid uploading idle minutes whenever feasible.
- Store video and metric data separately. Video: encrypted object storage and expiring references; data: shot/session records and appropriately compressed observations.
- Suggested initial retention policy **for evaluation, not approval**: raw full-session video device-only or short-lived; temporary raw uploads ~24–72 h; analyzed shot clips ~7–30 days; explicitly saved highlights user-controlled; structured performance history for account lifetime, subject to deletion/privacy law.
- Preserve raw/high-quality frames until required CV processing finishes. Aggressive compression or low frame rate may destroy rotational cues; optionally retain diagnostic frames where consented.
- Use native efficient codecs (HEVC where supported; H.264 fallback), MP4-compatible delivery, resumable upload, and adaptive playback. Evaluate AV1 for future delivery only; avoid unnecessary transcoding.
- Audio off by default. Minimize bystander capture/retention, especially League Mode; provide user controls and deletion paths.
- Never assert tracking summaries can reconstruct image details required by future models. Historical reprocessing only possible if sufficient original pixels/observations were retained.

## Cost guardrails / economics
- Target planning envelope: roughly **<$100/month early infrastructure** if usage is low and compute remains local/on-device or very selectively cloud-run. This is a target, not a validated forecast or committed SLA.
- Do not infer true per-shot costs from storage alone. Model **peak concurrent sessions, bytes uploaded per shot, raw-to-trim ratio, video retention days, object-storage request counts, analysis CPU/GPU seconds, bandwidth, DB load, observability, support, and inference retry rates**.
- Illustrative only: at 10 MB/clip, 100,000 retained clips ≈1 TB; retention strongly determines steady-state cost. Storage pricing and free tiers change; recheck before selection.
- Use quotas, retries with budgets, backpressure, TTL/lifecycle deletions, and per-user fair-use policies.
- Track cost per analyzed shot, cost per monthly active bowler, clip bytes, processing duration, success/finish rate, and percentage requiring cloud reprocessing.
- Avoid paid per-shot vision/LLM services until independent quality and economics justify them.

## Phased path
**Now / MVP:** strengthen existing CV pipeline, shot segmentation, calibration and tracking; preserve current moving-camera MVP work; build native capture + service adapter + schema; keep video uploads clipped where feasible; use local/dev compute first; reliability/error transparency and validation come before paid inference.
**After validation:** evaluate optional on-device preprocessing/inference, pose modules, more sophisticated tracking/occlusion and multi-angle support. Introduce cloud workers only where justified and cost-metered.
**Revenue-supported expansion:** longer video retention, more expensive cloud reprocessing, advanced 3D/multi-camera form reconstruction, improved model training, smart-glasses/POV ecosystem and sensor fusion upgrades. Note: optional early sensor fusion remains in current scope; do not postpone existing Ruby integration.

## Validation before vendor upgrades
- Build/maintain a labeled cross-device, multi-angle, multi-center clip set with Ruby and eventually Specto or otherwise credible ground truth.
- Measure speed MAE/bias, trajectory/boards/entry error, pin precision and unreadable handling, rev uncertainty, event-timing error, calibration failure, shot-finish rate, occlusion recovery, moving-camera degradation, processing time, file size, and **cost per shot**.
- Compare open-source baseline with any proposed paid service on the same locked test set. Paid wins only with meaningful quantified gains.

## Requests for Claude
1. Compare this handoff with current `DECISIONS.md`, `CURRENT_STATE.md`, code, BUILD_PLAN and engineering specs. Identify contradictions explicitly.
2. Produce a **minimal-change** cost-optimized proposal that preserves accepted scope and uses the working pipeline.
3. Separate `already implemented`, `approved but not implemented`, `new proposal`, and `future option`.
4. Estimate realistic $/1k analyzed shots and monthly operating costs for beta, 1k, and 10k active bowlers under conservative/moderate/heavy usage assumptions; quote verified pricing and uncertainty.
5. Recommend whether video should stay in Supabase Storage at first or use R2, considering implementation/ops, not just price/GB.
6. Specify metric-level confidence, storage schema, retention policy and shot-clip boundaries without redefining existing metrics or historical decisions.
7. Suggest any **new DEC entries** required; never silently override accepted ones.
8. Do not implement a migration, choose vendors, or rewrite canonical docs until the proposals are reviewed.
