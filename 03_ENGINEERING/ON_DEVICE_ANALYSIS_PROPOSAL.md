# LaneSight On-Device Analysis — Proposal
Status: DIRECTION ACCEPTED by Shayne 2026-10-28 (v0.3). The three DECs in §12 are accepted but **not yet numbered or entered in `DECISIONS.md`**. Claude Code enters them as the next free DEC numbers (see `HANDOFF_2026-10-28_ON_DEVICE_ANALYSIS.md`). Until they are entered, existing DECs govern.
Version: 0.3
Last Updated: 2026-10-28
Owner: Shayne
Checked against: DECISIONS.md v1.60 (latest DEC-099, branch `fix/ux-batch-2026-10-28`). The older v0.2 check was against `main` v1.44.

### Changes from v0.2
- **§11 resolved.**
  - **Advice uses Provisional / Low confidence / Ready states.** It is not blanket "provisional".
  - **Video follows DEC-099:**
    - LaneSight sets server retention.
    - Users choose only "Save recordings to my phone".
    - Using clips for model improvement is a separate disclosed consent.
- **Reconciled with DEC-086 and DEC-092…099** (§13).
  - The biggest change is to DEC-092. Its near-term rule, "optimize the server first; metric math stays on the server", stays in force until the device gates pass. On-device metric math becomes the **target** architecture rather than an excluded option.
  - `MeasurementEvidence` **is** DEC-092 P3's "timestamped observation interface" combined with DEC-094 §5's uncertainty contract. It is one interface, not a second one.
- **The phone already trims** (`VideoTrimmer.swift`). OD-04 is therefore "tighten and reuse the phone's trim window" (DEC-092 D5), not new work.

### Changes from v0.1
- **Latency claim corrected.** v0.1 said most of the 90–328 s per shot was upload and cold start. That claim was not supported. CURRENT_STATE's 328 s was the synchronous analyze step after the clip upload had already finished, so compute dominates. Whether an iPhone can do the same work fast enough is **unproven**.
- **Hybrid architecture.** Measurement runs on the device where the device and engine are validated. The server stays as the fallback and reference engine. Coaching, scoring, tiers and achievements stay authoritative on the server.
- **Measurement validity is separated from coaching policy** (DEC-046 boundary, §6.3).
- **New `MeasurementEvidence` contract** sits underneath `ShotRecord` (§6.4).
- **Port language decision deferred.** The choice between C++ and Swift waits for benchmarks in Phase 2.5. DEC-D is dropped for now.
- **Phase 1.5 added:** optimize the current pipeline in isolated, non-production benchmarks before porting anything.
- **Parity and ground truth are separate gates.**
- **Four new risks added:** trust in device-submitted results, local data lifecycle, engine-version migration, and sustained continuous capture.
- **DECs consolidated** from four drafts to three.
- Open items were listed in §11; they are now resolved.

---

## 1. Summary

The goal is an architecture of **capture → measurement → validation → bowling intelligence → coaching**, where each layer can change on its own. LaneSight's guiding principle carries through all of it: a believable but wrong measurement is worse than an unavailable one.

- **Measurement** of Shot and Form runs on the iPhone where the device's capability has been validated. It works offline. The cloud engine remains as the fallback for older phones and as the reference for validation and reprocessing.
- **Coaching intelligence** stays server-side and needs a connection. That covers next-shot moves, insights, form findings and drills, scoring, tiers and achievements. It is LaneSight's differentiator.
- **Losing the connection never blocks the rest of the app.**
- **The app becomes offline-first** with local persistence and reliable sync. This work can start now, independent of the CV freeze.

---

## 2. Competitive context: Bowlin (bowl-in.com)

**Basics.** Bowlin is a Korean app launched in July 2026 on iOS and Android, available in Korean, English and Japanese, with two KPBA pro advisers. It is built on YOLO and MediaPipe Pose.

**What it does:**
- Analysis runs on the device and works offline.
- Lane-calibrated trajectory with RPM, entry and exit speed, and breakpoint.
- Oil-pattern overlay.
- Tripod real-time mode that auto-detects throws.
- 8 pose metrics.
- Trends.
- Shareable overlay videos.
- An optional Pro tier with cloud backup and coach sharing.

**Added by the ChatGPT review from the App Store listing (not re-verified here):** cloud sync, pose comparison, handheld-camera improvements and ball comparison. Do not assume LaneSight has lasting differentiation on basic metrics or comparisons.

**Accuracy claims.** Bowlin claims ±3° for pose and ±5% of lane width for trajectory. These are vendor claims, not independent benchmarks.

**Where LaneSight differentiates:**
1. **Trusted measurement.** Validated accuracy across camera positions, devices and sensors.
2. **Bowling intelligence.** Explaining *why* the ball reacted the way it did, and separating execution errors from lane transition (DEC-005).
3. **Personalized coaching.** Built from shot history, form, the bowler's arsenal, lane conditions and coaching knowledge.

A competitor can copy a speed measurement much more easily than it can copy longitudinal data and coaching that bowlers trust.

---

## 3. Use case

**The at-lane loop (DEC-080):** record → Analyzing screen (blocking, keeps the screen awake; DEC-068) → shot details with result, metrics and next move → next shot. The bowler walks back in roughly 20–40 s.

**Where it fails today:**
- Analysis takes about 90 s on a trimmed clip and about 328 s on a full 26 s clip, on Cloud Run with 4 vCPU running synchronously.
- Upload adds time on top of that (27–43 MB clips over center Wi-Fi or cellular).
- Cold starts add time (the service scales to zero).
- With no connection, there is no analysis at all.

**Value of on-device measurement:**
1. **Independence from connectivity.** This has value even if analysis takes 20–30 s.
2. **Speed.** Only if measured (§7).
3. **Near-zero server compute per shot** (DEC-043 caps).

---

## 4. Current state (facts)

**Engine.** `lanesight-core` is Python, built on numpy, OpenCV and MediaPipe.
- `cv/` (about 90 KB) covers lanes, stabilize, track, refine, rev rate, pins, metrics, pipeline and `calib/` (pose geometry, DEC-065).
- `form/` (about 80 KB) covers pose, fundamentals and analyze.
- Shot-window trimming runs server-side.
- Beyond computation, the engine also holds calibration, physics, confidence and uncertainty, metric eligibility, and failure-reason logic. That is where the port risk lies.

**Hosting.** Cloud Run us-east1:
- 4 vCPU / 4 GiB, concurrency 1, max 1 instance.
- Scale-to-zero, synchronous analysis, about 1.8 GB peak memory.
- Clips go through the Supabase Storage `shot-clips` bucket and are deleted after analysis.

**App.** SwiftUI with AVFoundation, targeting 120 fps with real per-frame timestamps. `ShotRecord` v1 is the contract between app and service.

**Constraints that bind this work:**

| DEC | Constraint |
|---|---|
| DEC-026/027/061 | Honest unavailable states; never fabricate a value. |
| DEC-034/065 | Accuracy gates; far-lane metrics stay gated. |
| DEC-043 | Cost caps; on-device CV needs a measured benefit. |
| DEC-046 | Owner-only rules never ship to clients. |
| DEC-055 | Uploads never feed Stats or the score. |
| DEC-059 | Retained feedback store. |
| DEC-062 | Production CV is frozen. |
| DEC-068/080 | Blocking Analyzing screen, then shot details. |
| DEC-029/033 | Server-side analysis. These are the DECs this proposal would amend. |

---

## 5. Product behavior

### 5.1 Operating modes (hybrid)

| Device and connection | Measurement | Coaching / score |
|---|---|---|
| Supported iPhone, online | Device | Server |
| Supported iPhone, offline | Device | Deferred until reconnect |
| Unsupported or older iPhone, online | Server fallback (video upload disclosed) | Server |
| Unsupported or older iPhone, offline | Deferred ("Analysis pending") | Deferred |
| Validation and reprocessing | Reference server engine | Server |

The app picks the mode from **measured device capability**, not from the model name.

An older phone must never produce lower-quality or estimated metrics just to keep the offline promise.

### 5.2 Availability

| Feature | Offline | Online |
|---|---|---|
| Record shot or delivery; pick a clip | ✅ | ✅ |
| Shot and Form metrics with status and uncertainty | ✅ on supported devices | ✅ |
| Strike / not strike (DEC-066) | ✅ on supported devices | ✅ |
| Form key-position thumbnails and skeleton (DEC-082) | ✅ on supported devices | ✅ |
| Target vs actual and execution miss (geometry only) | ✅ | ✅ |
| Session in progress, shot list, notes, end session | ✅ | ✅ |
| Session summary stats and early-vs-late trends | ✅ computed locally | ✅ |
| Next-shot move, insights, form findings and drills | ⏳ deferred | ✅ server |
| LaneSight Score, tiers, achievements | ⏳ last stored score shown, marked "latest session not yet included" | ✅ server |
| Feedback | ✅ queued | ✅ |
| Profile, arsenal, oil library (cached) | ✅ editable, synced later | ✅ |
| Sign-in / account creation | ❌ (an existing session stays signed in) | ✅ |

### 5.3 Late advice (review recommendation)

When a shot that was analyzed offline syncs:
- The server generates advice using the context that existed **at that shot**, and attaches it to that shot.
- That evidence then feeds future coaching.
- A late move is **never** presented as advice for the current throw. It does not pop up or interrupt the bowler.

### 5.4 Advice labeling (resolved, §11 item 1)
Every move, insight and form finding carries a server-decided state:
- **Provisional**: not enough evidence, or awaiting confirmation.
- **Low confidence**: limited but useful evidence.
- **Ready**: well supported.

Ready advice is still guidance, not a guarantee. The state comes from DEC-061 plus DEC-094 §5. Advice is not labeled provisional across the board.

### 5.5 Offline session end

The session summary shows immediately with every locally computable stat. The score popup (DEC-072) shows the stored score with "latest session not yet included".

**No unofficial score is ever calculated on the device.** Tier and achievement celebrations fire only after the server finalizes them (DEC-039/051).

---

## 6. Architecture

### 6.1 Layers

```
Capture → MeasurementEvidence → Validated metrics (ShotRecord) → Bowling intelligence → Coaching → Score
 device       device | server         device | server               server              server     server
```

### 6.2 Port strategy (deferred to Phase 2.5)

Benchmark **the same validated module**, for example lane detection, three ways:

| Approach | Effort | Performance potential | Maintenance |
|---|---|---|---|
| Optimized Python on the server | Low | Medium–High | Excellent |
| Swift + Accelerate / Vision | Medium | High | Good |
| Shared C++ (pybind11 for the server, interop for iOS) | High | High | Good once built |

**Rejected:** embedding Python on iOS.

**Decision criteria:**
- measured speed on the device
- parity with the reference engine
- binary size
- build and debugging complexity
- regression risk

**Ball detection** stays geometry-first and classical (DEC-062). A learned detector is added only when the data justifies it, and it runs in shadow first.

### 6.3 DEC-046 boundary

| Device: measurement validity | Server: coaching intelligence (owner-only) |
|---|---|
| Ball-detection reliability | Coaching benchmarks (L0–L3) |
| Lane calibration validity | Delivery-style expectations |
| Observational sufficiency | Lane-transition and move rules (DEC-061 moves) |
| Physical plausibility | Personal baselines |
| Metric eligibility and unavailable reasons | Recommendations, drills, form findings and timing windows (DEC-057) |
| Uncertainty bands | LaneSight Score formulas, tiers, achievement qualification |

The new DEC must state this boundary explicitly.

**Ambiguous case to review:** owner-editable form timing windows (DEC-057) are coaching policy and stay on the server. The device reports raw timings, and the server issues the early / on time / late verdict.

### 6.4 Contracts

**`MeasurementEvidence` (new, versioned).** This is the observations layer:
- timestamped ball observations, with **observed vs predicted kept separate**; predicted positions never count as observed
- lane geometry and calibration provenance (DEC-065 pose, focal source)
- coordinate-system definition
- pose landmarks with confidence
- capture conditions (fps, timestamps, camera motion)
- sensor observations, when present
- eligibility and uncertainty

No observation-coverage field may be assumed to exist. Any such field must be explicitly introduced and implemented.

**`ShotRecord` v1.** The application-facing result: metrics with status, confidence, uncertainty and reason codes. Every record adds `engine.platform` (`ios` | `server`), `engine.version` and `engine.build`.

The evidence layer also prepares for sensor fusion and smart-glasses capture without coupling them to CV internals.

### 6.5 Validation gates (separate)

1. **Ground truth.** The device engine meets the applicable DEC-034 accuracy gates against Ruby and Specto references. This is the OD-07A harness.
2. **Parity.** Device and server differences stay within **metric-specific numerical tolerances** set by the parity harness. Disagreements on status or unavailable state get an explicit review. Reason codes must be semantically equivalent, not identical.

Both gates must pass before device results become authoritative.

### 6.6 Local data and sync
- The local store is encrypted where appropriate and **scoped per account**. Behavior on account switch, logout, account deletion, a full disk and app upgrade must be defined.
- The outbox uses client UUIDs and idempotency keys. It survives the app being killed, retries with backoff and never duplicates.
- **Conflict rules:**
  - Session and measurement records are immutable or revisioned.
  - Arsenal and ball-setup changes are revisioned, so history is never overwritten (DEC-007 / DEC-044 surface history).
  - Last-write-wins applies only to simple profile fields.
- **The server validates every device submission** before it feeds Stats or the score: auth, ownership, schema, plausibility, and an accepted engine version. A client-reported engine id is used for tracing, not as proof.

### 6.7 Engine-version migration

The server keeps a compatibility policy covering:
- which engine versions are supported
- deprecated metric definitions
- recalculation (only where evidence or clips were retained)
- historical comparability
- quarantine of results from outdated or rejected engines

The goal is that statistics never quietly mix incompatible measurements.

### 6.8 Video (resolved, §11 item 2)
- **Required for:** server-fallback analysis only. The upload is disclosed before processing.
- **Not required for:** local metrics on a supported device.
- **Retention (DEC-099):**
  - LaneSight sets how long video stays on its servers, and this will be plan-based.
  - The bowler chooses only "Save recordings to my phone".
  - Using clips for validation and model improvement needs separately disclosed consent, never silent collection.
  - Legal and privacy check needed before Beta.

---

## 7. Performance targets (engineering targets, not launch promises)

| Metric | Target |
|---|---|
| Shot analysis p50 / p95 | ≤10 s / ≤20 s |
| Form analysis p50 | ≤10 s |
| Sustained 30-shot session | No unacceptable thermal degradation |
| Battery | Measured and reported |
| Memory | Frames streamed; within limits of supported devices |
| Accuracy | No regression vs the validated reference |
| Unavailable metrics | Never replaced by estimates |

Each speed gain must be demonstrated by measurement, not assumed. On-device analysis stays valuable at 20–30 s because it removes the dependence on connectivity.

Continuous capture (DEC-014, DEC-060 multi-bowler) is a heavier workload that must be benchmarked separately later.

---

## 8. Phased plan

| Phase | Focus | Timing | Status |
|---|---|---|---|
| 0 | Instrument and benchmark the current pipeline and the device | Now | Recommended: approve |
| 1 | Offline-first app: local persistence, reliable sync, offline UX | Now (independent of CV freeze) | Recommended: approve |
| 1.5 | Optimize the current pipeline in isolated, non-production benchmarks (decode once, low-res detection with full-res measurement crops, remove redundant passes) | Parallel | Recommended: approve as experiments only |
| 2 | On-device pose and Form Analysis | After reference validation | Conditional |
| 2.5 | Compare Swift vs shared C++ on the same module | After Phase 0/1.5 benchmarks | Conditional |
| 3 | On-device Shot Analysis: shadow first, then switch | After the DEC-062 freeze lifts and DEC-065 Phase-2 validates | Conditional |
| 4 | Hybrid production: device primary, server fallback and reference | After both gates pass | Conditional |

Phase 1 must **keep DEC-068/080** (the blocking Analyzing screen, then shot details). It must not silently turn analysis into a background task.

On-device shot-window trimming is its own gated task (OD-04), not part of Phase 1.

---

## 9. Tasks for Claude Code

**Approve now:**

| ID | Task | Acceptance |
|---|---|---|
| OD-00 | Per-stage timing instrumentation in `lanesight_api` / `core.analyze_clip` (upload, cold start, download, decode, trim, geometry, stabilize, track, rev, pins, pose, metrics, insights, DB) | Breakdown for ≥20 real clips, written to `02_RESEARCH/` |
| OD-00A | Audit the Python pipeline for repeated decoding, redundant passes and staged-measurement opportunities, with **no production changes** | Ranked findings with estimated savings |
| OD-00B | Define the versioned `MeasurementEvidence` interface and the device-validity vs server-coaching boundary (§6.3–6.4) | Spec doc reviewed by Shayne |
| OD-01 | iOS device benchmark: 120 fps decode, one native processing step, memory, sustained 30-clip thermal and battery run | Numbers from Shayne's iPhone |
| OD-02 | Local store and outbox sync, with account-scoped, revisioned records per §6.6 | Works end to end in airplane mode; survives the app being killed; no duplicates |
| OD-02A | Tests for offline-to-online recovery, account isolation, conflicts and engine-version compatibility | Test suite green |
| OD-03 | Offline UX states ("Analysis pending", "Advice when you're back online", "Latest session not yet included"), keeping DEC-068/080 | No blocked screens offline; Figma and dev build updated |
| OD-07A | Ground-truth validation gate, independent of parity | Runs the locked validation set against Ruby (and Specto when available) |

**Held behind technical and DEC approval** (isolated, non-production experiments allowed):
- OD-04: on-device trim and spot check
- OD-05: metrics-only advice API
- OD-06: engine provenance in the schema
- OD-07: device-vs-server parity harness
- OD-08: on-device pose
- OD-09: Swift vs C++ spike
- OD-10: full shot engine on device

**Rules for the implementer:**
- Reconcile the Mac branch first.
- Don't touch branches you didn't create.
- No production CV changes while DEC-062 stands.
- Never fabricate a metric to fill an offline or device gap.

---

## 10. Risks
1. Two engines drift apart. Mitigation: the parity harness, and possibly a shared core.
2. Porting a moving target. Mitigation: port only after the freeze lifts and the pipeline is optimized.
3. Device speed, heat and battery are unproven. Mitigation: Phase 0 benchmarks and the targets in §7.
4. Device fragmentation. Mitigation: capability-based modes with a server fallback.
5. **Device-submitted results can't be blindly trusted.** Mitigation: server validation; never treat engine ids as proof. This matters more once achievements or competitive features exist.
6. **Local data lifecycle** (account switch, deletion, storage, upgrades). Mitigation: §6.6.
7. **Mixed engine versions** in long-term stats. Mitigation: §6.7.
8. **Continuous capture** load isn't covered by single-clip benchmarks.
9. Rules leakage. Mitigation: the §6.3 boundary.
10. Loss of validation data if video stays on the device. Mitigation: the §6.8 policy.
11. App size growth from OpenCV and pose models.

---

## 11. Decisions (resolved 2026-10-28)
1. **Advice labeling.** Every move, insight and form finding carries one finalization state, decided by the server:
   - **Provisional**: not enough evidence yet, or awaiting confirmation.
   - **Low confidence**: limited but useful evidence (the existing DEC-061 "Maybe…" state).
   - **Ready**: enough validated evidence.

   Ready is still guidance, not a guarantee. The state is driven by DEC-094 §5's uncertainty contract.
2. **Video.** DEC-099 stands:
   - LaneSight sets server retention, which will be plan-based.
   - The bowler only chooses "Save recordings to my phone".
   - Using clips for **validation and model improvement** is a separately disclosed consent in the Privacy Policy, never silent. The default and opt-in vs opt-out wording need a legal and privacy check before Beta.
   - Server-fallback analysis discloses the upload before processing.
3. **Approved now:** Phase 0, Phase 1, Phase 1.5 experiments and the `MeasurementEvidence` design (OD-00/00A/00B/01/02/02A/03/07A).
4. **DEC-A/B/C accepted.** Claude Code enters them in `DECISIONS.md` under the next free numbers.

---

## 12. DECs (accepted 2026-10-28; numbers assigned on entry)

**DEC-A — Offline-first, hybrid measurement architecture**
- LaneSight adopts an offline-first app architecture.
- It targets on-device Shot and Form measurement where validated device capability permits.
- Cloud measurement stays as the fallback and reference engine.
- Coaching intelligence, scoring, tiers and achievements stay server-authoritative.
- Measurement-validity checks may run on the device; owner-only coaching policy stays on the server (DEC-046 intact, boundary per §6.3).
- Keeps DEC-055, DEC-068/080 and the honesty and accuracy rules.
- Amends DEC-029 and DEC-033.

**DEC-B — Measurement provenance, validation and sync**
- Every measurement carries:
  - engine provenance
  - versioned `MeasurementEvidence`
  - status, uncertainty and calibration info
- On-device engines must pass ground-truth gates and parity tests before they become authoritative.
- Offline records sync idempotently and are scoped per account.
- The server validates device submissions before they count toward stats or the score.
- An engine-version compatibility policy applies.

**DEC-C — Video transmission, contribution and retention**
- Video isn't required for measurement on supported devices.
- Server fallback may need an upload, which is disclosed first.
- Server retention is set by LaneSight (DEC-099).
- The bowler controls only saving clips to the phone.
- Using retained clips for validation and model improvement needs separately disclosed consent.
- Deletion schedules are defined with the retention policy.

**Deferred:** a shared C++ core, until the Phase 2.5 evidence is in.

---

## 13. Reconciliation with DEC-084…099 (entered after v0.2)

| DEC | Effect on this plan |
|---|---|
| DEC-086 (structured failures, `analysis_attempt`) | The device engine must emit the same `AnalysisFailure` codes and stages. Device attempts sync into `analysis_attempt` with `env`/`source` showing they ran on the device. |
| DEC-092 (optimize server first) | Its P0–P3 order **is** this plan's Phase 0/1.5. It is amended only in its long-term scope: on-device metric math is the target once the DEC-B gates pass. Until then, all metric math stays on the server. |
| DEC-093/094 (honesty gates, detection-first, uncertainty contract, license-safe ML) | The device engine reuses the same gates. `observed_fraction` stays the one additive field. **No AGPL models** (e.g. Ultralytics YOLO, including RT-DETR from Ultralytics) on the device or the server. |
| DEC-095 (form event gates) | The on-device pose path applies the same physiological gates before anything is shown. |
| DEC-096 (stay in the session; resume) | Offline sessions follow the same loop. "Analysis pending" shots sit in the session list like "Couldn't analyze" ones. Resume-after-relaunch must work from the local store. |
| DEC-099 (save to phone; server retention set by LaneSight) | Adopted for video (§11 item 2). |
