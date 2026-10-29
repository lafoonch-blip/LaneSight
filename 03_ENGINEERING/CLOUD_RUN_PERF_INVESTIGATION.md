# Cloud Run vs Mac latency — root-cause investigation (DEC-106 Phase 0)
Owner: Shayne · 2026-10-29 · Branch `feat/on-device-analysis`
Goal: explain the ~12–17× gap (Cloud Run ~186–280 s/shot vs the same code on a Mac ~16 s) **from measured runs**,
and recommend production config changes. **The production service was not changed for this investigation** — all
runs used separate `lanesight-api-bench` (4 vCPU) and `lanesight-api-bench8` (8 vCPU) services with no traffic.

## Headline
The gap is **dominated by the compute environment, measured — not inferred.** Capping threads to the vCPU count
removes a **~12%** oversubscription tax; the rest is **slow Cloud Run vCPUs (CV compute ~10–18× the Mac) plus
software video decode (~8.6×)**. More vCPUs barely help — **8 vCPU is only ~23% faster but ~53% more expensive**
(the pipeline doesn't parallelize past ~4 cores). **You cannot config Cloud Run near Apple-Silicon latency** — the
latency fix is the native on-device engine (DEC-106). This benchmark is Phase 0 of that decision.

## Environment facts (measured on the bench services via read-only `/debug/env` + `gcloud run describe`)
- **`os.cpu_count()` = 8, but only 4 vCPUs are allocated** on prod → everything that sizes threads off CPU count
  over-provisions 2×. (8-vCPU bench: `os.cpu_count()`=8 matches.)
- **OpenCV is NOT capped by `OMP_NUM_THREADS`** — `cv2.getNumThreads()` stayed 8 under the OMP env; it needs
  `cv2.setNumThreads()` (added, gated on `LANESIGHT_CV_WORKERS`/`LANESIGHT_CPU_THREADS`). Confirmed: with the gate
  set, `/debug/env` reports `cv2_num_threads: 4`.
- **Execution environment: gen1** (the default; no `--execution-environment gen2` set).
- **CPU is NOT always-allocated** — the default (CPU throttled to request processing). So scale-to-zero cold starts
  apply, and CPU isn't billed between requests.

## Config runs (same non-HDR clip, synchronous `/shots/analyze`; seconds)
| Run | vCPU | thread caps | **total** | analyze | decode (×9) | stabilize | blobs | pins |
|---|---|---|---|---|---|---|---|---|
| Prod default | 4 | none (all = os.cpu_count 8) | **186.6** | 170.7 | 34.5 | 112.1 | 25.5 | 11.2 |
| Capped (clean) | 4 | **all = 4 (incl. cv2)** | **164.6** | 150.5 | 28.9 | 97.7 | 22.3 | 10.5 |
| Capped (noisy re-run) | 4 | all = 4 | 201.2 | 187.0 | 35.4 | 127.8 | 30.2 | 8.8 |
| **8 vCPU** | 8 | all = 8 | **125.9** | 115.2 | 21.1 | 76.1 | 14.6 | 8.1 |
| **Mac (same code), non-HDR** | — | native, HW decode | **16.7** | ~20 | **3.37** | **9.8** | **1.2** | **2.3** |

**Run-to-run variance is large on Cloud Run** (shared infra): the *same* clip + config gave stabilize 97.7 s vs
127.8 s. The config deltas below are real but should be read as ±~15%; the stage *gaps* vs the Mac (8–18×) are far
bigger than the noise.

## Measured gap decomposition (non-HDR: Mac 16.7 s → Cloud Run 4-vCPU capped 164.6 s ≈ 9.9×)
Each contributor is a measured difference, not an estimate:

| Contributor | Measured | Δ added on Cloud Run | How measured |
|---|---|---|---|
| **CPU compute** (stabilize + blobs + pins) | CR 130.5 s vs Mac 13.3 s | **+117 s (~79% of the gap)** | per-stage step_timings, both platforms |
| — stabilize (ORB + warp) | 97.7 vs 9.8 s | ~10× | step_timings |
| — extract_blobs | 22.3 vs 1.2 s | ~18× | step_timings |
| — read_pins | 10.5 vs 2.3 s | ~4.6× | step_timings |
| **Video decode** (software FFmpeg vs HW VideoToolbox) | 28.9 vs 3.37 s | **+25.5 s (~17%), 8.6×** | `decode.seconds` (9 passes, 4001 frames both) |
| **Thread oversubscription** (8 threads on 4 vCPU) | 186.6 → 164.6 s | **−22 s (~12% tax), removed by capping** | prod-default vs capped run |
| **Cold start** (container boot + import) | ~4.9 s | **+4.9 s (first request only)** | Cloud Run logs: instance start 12:45:19.5 → "Application startup complete" 12:45:24.4 |
| **HDR convert** (tone-map, HLG clips only) | CR 26.6 s · Mac 41.6 s | platform-neutral; inflates HDR-clip latency | `convert_s` on an HLG clip, both platforms |

Reading it: **~79% of the gap is Cloud Run's CPUs being ~10× slower on the CV math; ~17% is software decode.**
Oversubscription is a separate ~12% tax that thread-capping removes. Cold start explains a few seconds of the
186→280 s spread. **HDR tone-mapping is CPU-bound on *both* platforms** (26.6 s CR vs 41.6 s Mac — Cloud Run was
actually faster here on a smaller clip), so it widens absolute latency for HDR inputs but is **not** a
Cloud-Run-specific penalty.

## 8 vCPU — measured, and it does NOT pay off (answers "faster at same cost?")
Doubling vCPUs (4→8, all caps = 8) made it only **~23% faster** (164.6 → 125.9 s), not ~2×, because the pipeline
is only partly parallel — the homography *solve*, pin read, and metric compute are sequential (Amdahl). Cost scales
with billed **vCPU-seconds = wall × allocated vCPU**:
- 4 vCPU: 164.6 s × 4 = **658 vCPU-s/shot**
- 8 vCPU: 125.9 s × 8 = **1,007 vCPU-s/shot**

So **8 vCPU costs ~53% more for ~23% less latency** — a poor trade (and 8 GiB memory doubles memory-seconds too).
My earlier "~cost-neutral, 2×" estimate was wrong; measuring corrected it. **Recommendation: do not move prod to
8 vCPU.** Keep 4 vCPU.

## Recommended production changes
### 1. Cap all thread pools to the vCPU count — **APPLYING NOW (approved)**, low-risk, reversible
Set on `lanesight-api` (4 vCPU): `OMP_NUM_THREADS / OPENBLAS_NUM_THREADS / MKL_NUM_THREADS / NUMEXPR_NUM_THREADS /
VECLIB_MAXIMUM_THREADS / LANESIGHT_CV_WORKERS = 4`, plus the committed `cv2.setNumThreads` cap (gated on
`LANESIGHT_CV_WORKERS`). **Measured gain: ~12% (186.6 → 164.6 s).** No cost increase (same vCPU, less wall time →
slightly *cheaper*: ~658 vs ~748 vCPU-s/shot). **Rollback:** remove the env vars (the cv2 cap self-disables when
`LANESIGHT_CV_WORKERS` is unset) and redeploy the prior revision `lanesight-api-00037-r6s`.

### 2. Decode-once (DEC-092 P1) — **PENDING a focused, gated effort; NOT deployed**
`cv/stabilize.py:frames()` re-decodes the whole clip on every call, and it is called **~9×** (4× inside stabilize,
plus track×2, pins, refine, rev). On this clip that's **~29 s of the 165 s**. Naive "decode once, keep all frames"
is **infeasible**: 4001 frames at full res ≈ 24 GB (the pipeline *streams* precisely to stay ~2 GB). A real
decode-once needs a **memory-bounded staged cache** (or fusing the passes that share a decode) **plus numeric
re-validation** — it can change stabilize/track/pin results. Because it touches the production CV path, it must
clear the **locked regression gate** (`ops/perf_benchmark.py` on the validation clips: every metric within DEC-034
tolerance, no new failures, peak RSS checked) and ship with a revision rollback **before** any deploy.
**Expected gain if it lands: ~20–26 s/shot. Status: designed, not implemented — recommend as the next focused task.**

### 3. 8 vCPU — **REJECTED** (measured above: +53% cost for −23% latency).

### Strategic (DEC-106)
~79% of the gap is environmental CPU speed and ~17% is software decode — neither is configurable away. Config
tuning caps out at ~12%. The real latency fix is the **native on-device engine** (hardware HEVC decode +
Apple-Silicon accelerators), which this benchmark confirms.

## Cost per 1,000 shots (DEC-043; compute only = vCPU-seconds × $0.000024)
| Config | wall | vCPU-s/shot | **$/1,000 shots** |
|---|---|---|---|
| Prod default (4 vCPU, uncapped) | 186.6 s | 746 | ~$17.9 |
| **4 vCPU, thread-capped (recommended)** | 164.6 s | 658 | **~$15.8** |
| 8 vCPU | 125.9 s | 1,007 | ~$24.2 |
(Plus memory-seconds + egress; see `ops.cost_rates` / the ops dashboard cost page.)

## Method notes / honest limits
- Per-stage from `analysis_attempt.step_timings`; env from `/debug/env` (read-only, no secrets) + `gcloud run
  describe`; cold start from Cloud Run instance logs; Mac baseline from `ops/perf_reports/od00_server_baseline.json`.
- n=1–2 per config on one clip; Cloud Run variance is ~±15% (shown above). Stage *ratios* vs the Mac are large
  enough to be unambiguous.
- The benchmark clip is a **no-trim** case (window found no sustained burst → full-clip analysis), so absolute
  decode/compute are on the order of a full training clip. Real at-lane shots trim to a short window and are
  cheaper in absolute terms; the *ratios* and the config conclusions hold.
- **CPU-seconds** reported = billed vCPU-seconds (wall × allocated vCPU), the cost-relevant figure. **Peak RSS**
  from the Mac baseline is ~1.82 GB for the same code (streaming); prod is on 4 GiB and has not OOM'd.
- Clean-up: delete the bench services when done — `gcloud run services delete lanesight-api-bench lanesight-api-bench8 --region us-east1`.
