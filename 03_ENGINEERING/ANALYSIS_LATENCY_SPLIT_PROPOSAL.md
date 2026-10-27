# Analysis latency: phone vs server split
Status: ACCEPTED as DEC-092 (execution order §6). §3 items not listed in §6 remain proposals.
Version: 1.2 (§6 agreed order + benchmark/regression rules; adds §5 ChatGPT reconciliation) · Last Updated: 2026-10-27 · Owner: Shayne
Merge note: no prior copy of this proposal existed in the repo (the earlier v1.1 lived only in the claude.ai Project), so v1.2 is written from the accepted v0.3 text; every DEC-090 reference is DEC-092. Not to be confused with `PERFORMANCE_RELIABILITY_SLO_PROPOSAL.md` (SLA targets, DEC-043) — a separate doc.
Against: DECISIONS v1.53 (DEC-092), CURRENT_STATE (Cloud Run rev 00023), `dev-build-v0`
Builds on: `03_ENGINEERING/VIDEO_ARCHITECTURE_COST_REVIEW.md` (§6, §13, §14 — S1–S9, P1–P8)

## 1. Bottom line
- **The server, not the upload, is most of the wait.** Today's live shot: **280 s of server analysis** (4 vCPU Cloud Run). A failed clip today ran **140 s before failing** with `FOUL_LINE_NOT_IN_VIEW`.
- **Why it's slow:** the CV pipeline software-decodes the full-resolution 120 fps HEVC clip about **9 times** (`frames()` is called from stabilize ×4, track ×2, refine, pins, revrate). Earlier profiling put ~80% of "analyze" in decode, not math.
- **Rule for the split:** the phone does what its hardware makes cheap and what removes bytes or wasted server work (framing, warm-up, trimming, hints). **Metric math stays on the server**: one validated implementation, production CV frozen behind the ablation gate (DEC-062/065). Porting the CV to Swift now would create a second implementation to validate and keep in sync.
- **Biggest single lever is server-side:** decode once instead of ~9 times. The biggest phone-side levers are a framing check before recording (kills the failed-clip case at the source) and a tighter on-device trim.
- **Estimated end state** (needs Phase 0 numbers to confirm): ~5 min per shot → ~3.5 min after the quick wins → ~1–1.5 min after decode-once.

## 2. Where the time goes today
The shot flow is fully serial (`AppModel.runPipeline`): trim on phone → get signed URL → PUT to Supabase Storage → `POST /shots/analyze` (synchronous) → fetch shot + score.

| Step | Where | Today | Source |
|---|---|---|---|
| Motion pre-pass + passthrough trim | Phone | Not measured. ~400 random seeks into a 120 fps HEVC clip (`AVAssetImageGenerator` at 20 Hz) | `VideoTrimmer.swift` |
| Upload | Phone → Supabase | Not measured. 1080p120 HEVC ≈ 3 MB per second of clip; capped at 48 MB | `VideoTrimmer.maxUploadBytes` |
| Cold start + download | Cloud Run | Not measured. Scale-to-zero, `--max-instances 1` | DEPLOY_CLOUDRUN |
| Re-window + trim | Server | Repeats the phone's window search | `runner/core.analyze_once` |
| HDR → SDR | Server | ~40 s **if** the clip is HDR. The app doesn't pin an 8-bit format, so unverified | `CameraController.bestFormat` |
| CV analyze | Server | **280 s** (successful shot, 2026-10-27); **140 s** to a framing failure | `analysis_attempt` |

Gap (now closed by P0): `analysis_attempt.step_timings` stored only the total. The per-stage timings the runner collects (`window_s`, `convert_s`, `analyze_s`, `cv.*`) now persist; decode passes/time and a cold-start flag are added.

## 3. Recommended split

### Phase 0 — Measure first (½ day)
| ID | Change |
|---|---|
| M1 | Phone records trim, upload (bytes, seconds), request wait and fetch times; sends them with the analyze request |
| M2 | Server persists all step timings + clip facts (fps, codec, 8/10-bit, HDR, bytes, duration, cold start yes/no) on `analysis_attempt` |
| M3 | One report: median and p90 per stage over the last N shots |

### Phase 1 — Phone-side quick wins
| ID | Change | Expected gain | Risk |
|---|---|---|---|
| D1 | **Framing check in the live preview** before/during recording, with "move the camera" guidance | Framing failures go from a 140 s wait to an instant prompt | Must not block clips the server could analyze — advisory first |
| D2 | **Pre-warm the server** (`GET /health`) when Setup/Record opens | Hides the cold start; $0 | None |
| D3 | **Pin 8-bit SDR capture** (choose a `420v/420f` format explicitly; HDR off) | ~40 s per shot if any clips are arriving HDR | Verify with M2 first |
| D4 | **Tighter, faster trim**: `AVAssetReader` sequential low-res read; cut to the server's window | Fewer upload bytes (est. 30–50%) and faster trimming | Passthrough cuts snap to keyframes, so pad to the prior keyframe |
| D5 | **Send the phone's window as a hint**; server skips its own window search when present | Removes one full decode pass | Server keeps fallback to its own search |
| D6 | **Overlap small steps**: request the signed URL while trimming | A few seconds | None |

### Phase 1 — Server-side quick wins
| ID | Change | Expected gain | Risk |
|---|---|---|---|
| S1 | **Fail-fast precheck** before stabilize (keyframes + `find_lanes`; prototype ran 1.4–1.6 s and matched the full pipeline's verdicts) | Failed clips: minutes → ~2 s | Must not reject clips the full pipeline passes — tune on the eval set |
| S2 | **Static-camera fast path**: when pass A shows a steady camera, skip per-frame ORB/RANSAC | Est. 30–50% of analyze on tripod clips | Accuracy gate |

### Phase 2 — Server-side structural
| ID | Change | Expected gain | Risk |
|---|---|---|---|
| S3 | **Decode once**: decode the trimmed clip one time into a shared working-resolution / lane-ROI frame cache used by stabilize, track, refine, pins and rev | Analyze est. 280 s → 60–100 s | Memory (1,200 full-res frames ≈ 7 GB; must be downscaled/ROI'd or streamed); regression-test every metric |
| S4 | **Staged results**: fast metrics (speed, boards, pins) first; rev rate second | Shot card opens sooner | Needs a DEC: DEC-080 currently waits for the full result |
| S5 | **More vCPU per job** (`--cpu 8`) once S3 removes the serial decode bottleneck | Wall time down at roughly the same CPU-seconds | Check against the DEC-043 cost caps |

### Validate before adopting (changes the server's input)
These shrink the upload but change pixels the CV sees. The cost review showed input changes alone moved entry board by up to 2.6 boards, so each one goes through the locked eval set first.
- Re-encode on the phone to a lane-ROI crop (hardware encoder, same fps).
- Lower upload bitrate (e.g. 25 → 12 Mbps HEVC) — watch rev rate, which needs ball texture.
- H.264 instead of HEVC — faster server decode, larger upload; mostly moot after S3.

### Not now
- **Full CV on the phone** (Core ML / Vision port). Large rewrite, a second implementation of a frozen, ablation-gated algorithm, and different results by device. Revisit after the geometry is validated and if server cost, not latency, becomes the constraint.
- **Form pose on the phone** (Apple Vision instead of MediaPipe) is the most plausible first on-device CV piece; only after it matches MediaPipe on the form fundamentals within tolerance.
- **Always-warm instance** (`min-instances 1`): ~4 vCPU idle all month breaks the ≤$100/month beta cap (DEC-043). D2 gets most of the benefit for free.

## 4. Suggested order
1. Phase 0 (M1–M3), then re-baseline.
2. D2, D3, D6, S1 — small, no metric risk.
3. D1, D4, D5 — phone work; D1 advisory first.
4. S2, then S3 behind the eval-set gate.
5. S4/S5 as DEC changes once S3 lands.

## 5. Reconciliation with the ChatGPT review (2026-10-27)
**Adopted from it:**
- **Observation-based engine interface.** The analysis engine accepts timestamped observations (frames, geometry, ball points, pose landmarks, model version, confidence), not only video. Then moving a step to the phone later doesn't mean rewriting the engine. Becomes a design rule for S3.
- **Low-res detection + full-res crops** inside decode-once (S3).
- **Adaptive phone work:** skip on-device extras when the phone is hot or low on battery (`ProcessInfo.thermalState`).
- **Full-resolution fallback** stays available whenever a phone-side reduction is in use.
- **Durable async jobs** (already a CURRENT_STATE follow-up). They fix dropped connections but don't make analysis faster.

**Corrected or not adopted:**
- *"Full video uploaded."* Not true today: the phone already trims (`VideoTrimmer`), and the 328 s figure was a server benchmark on an untrimmed clip. Today's real phone-trimmed shot still took 280 s, which is why server decode, not upload size, is the main lever.
- *Variable-rate frame selection on the phone* (5–240 fps by segment). Dropping frames from HEVC means re-encoding, which changes the pixels the CV reads, and speed/rev rely on even frame spacing. Server-side, a lower rate for stabilize-only passes can be tested inside S3, behind the eval gate.
- *Lane detection and camera calibration on the phone.* The phone does only an advisory framing check (D1). Calibration stays in the server's validated pose solver (DEC-065).
- *Uploads of 3–10 MB.* Only with the eval gate; rev rate depends on ball texture.
- *10–30 s cloud processing / 15–45 s total.* Not reachable without a CV rewrite. Decode-once is estimated at 60–100 s; confirm with Phase 0.
- *MVP <60 s / Beta <30 s goals.* Conflicts with DEC-043, which makes latency targets target-state rather than gates. Changing that needs a new DEC.
- *Its gaps:* no fail-fast precheck, server pre-warm, SDR check, window hint, or note that per-stage timings aren't persisted. Those are the cheapest wins here.

## 6. Agreed execution order (Shayne, 2026-10-27 → DEC-092)
Optimize the existing pipeline before moving more CV onto the iPhone.

| Priority | Item | Maps to | Objective |
|---|---|---|---|
| P0 | Persist per-stage timings (phone + server) | M1–M3 | Find the real bottlenecks |
| P0 | ~2 s precheck before the full pipeline | S1 | Reject unusable clips before expensive analysis |
| P0 | Wake Cloud Run when Record opens | D2 | Cut cold-start wait |
| P0 | Verify SDR capture (pin 8-bit only if clips are arriving HDR) | D3 | Avoid HDR conversion |
| P1 | Decode once | S3 | Remove repeated decoding — confirm it's the largest cost from P0 data first |
| P1 | Pass the phone's trim window to the server | D5 | Diagnostics; server may skip its own search, with fallback |
| P2 | Low-res detection + full-res measurement | §5 | Less CV work at the same accuracy |
| P3 | Timestamped observation interface | §5 | Lets work move between phone and cloud later |

**Added rules:**
- **Reproducible benchmark.** The same representative clip set runs after every optimization. Each run tracks total and per-stage time, peak memory, CPU use, failures, and metric values. Harness: `lanesight-core/ops/perf_benchmark.py` + manifest `ops/perf_manifest.json`.
- **Regression gate.** An optimization is kept only if it cuts time, holds every metric within tolerance of the reference run (speed ±0.2 mph, boards ±0.5, same pin read, same pass/fail), adds no new failures, and doesn't grow cost per shot out of line with the gain.
- **Two latency measures, reported separately:**
  - *Analysis time:* server CPU work per successful shot.
  - *User-perceived latency:* tap-stop to shot card, split for successful and failed shots.

  Wake-up and precheck improve the second, not the first.
- **No new speed requirement and no change to DEC-043.** Measured results inform that later.
- S2 (static-camera fast path), S4 (staged results), S5 (more vCPU), D1 (live framing check), D4 (faster phone trim) and the input-changing options stay parked until the P0 data is in.
