# Cloud Run vs Mac latency — root-cause investigation (DEC-106 Phase 0)
Owner: Shayne · 2026-10-29 · Branch `feat/on-device-analysis`
Goal: explain the ~12–17× gap (Cloud Run ~186 s/shot vs the same code on a Mac ~16 s) and recommend a config
change. **No production service was changed** — all runs used a separate `lanesight-api-bench` service.

## Headline
The gap is **dominated by the compute environment, not a fixable config bug.** Thread oversubscription is real
but small (~12%); the rest is **fundamentally slower Cloud Run vCPUs + fewer cores + software video decode**
vs Apple Silicon's fast cores + hardware decoder. **You cannot config Cloud Run to match the phone** — which is
exactly why the production engine is going native (DEC-106).

## What was measured
Clip: IMG_8753 (the validation clip), via `/shots/analyze` (synchronous). Mac per-stage from the OD-00
baseline (`ops/perf_reports/od00_server_baseline.json`).

### Config runs (Cloud Run, 4 vCPU / 4 GiB, startup-cpu-boost on)
| Run | Config | Total | analyze_s | decode_s (×passes) | stabilize_s |
|---|---|---|---|---|---|
| Prod (no limits) | numpy/OpenCV/workers all default (= os.cpu_count) | **186.6 s** | 170.7 | 34.5 (×9) | 112.1 |
| Bench A | numpy/BLAS + worker pool capped to 4 (OpenCV still 8) | 176.9 s | 158.5 | 30.5 (×9) | 103.6 |
| Bench B | **all capped to 4** (numpy + BLAS + workers + **OpenCV**) | **164.6 s** | 150.5 | 28.9 (×9) | 97.7 |
| **Mac (same code)** | native, hardware decode | **~16 s** | ~20 | **~3.5 (×9)** | **~15** |

Capping every thread pool to the allocated vCPUs → only **~12% faster** (186.6 → 164.6 s). If oversubscription
were the main cause, it would have ~halved.

### The oversubscription fact (confirmed via a read-only `/debug/env`)
- **`os.cpu_count()` returns 8, but only 4 vCPUs are allocated.** Everything that sizes threads off CPU count
  over-provisions 2×.
- **OpenCV is NOT controlled by `OMP_NUM_THREADS`/`OPENBLAS_NUM_THREADS`** — `cv2.getNumThreads()` stayed 8 even
  with those env vars set. It needs `cv2.setNumThreads()` (added, gated on `LANESIGHT_CV_WORKERS`/`LANESIGHT_CPU_THREADS`).
- Our worker pool sizes off `min(os.cpu_count(), 12)` = 8 on prod → 8 workers on 4 vCPUs.

## Gap decomposition (per stage, prod → capped → Mac)
| Stage | Prod (8 thr) | Capped to 4 | Mac | Capped-vs-Mac | Cause |
|---|---|---|---|---|---|
| stabilize (ORB + warp, OpenCV) | 112 s | 97.7 s | ~15 s | **6.5×** | slower vCPUs + fewer cores |
| decode (9 passes) | 34.5 s | 28.9 s | ~3.5 s | **8.3×** | **software FFmpeg vs hardware VideoToolbox** |
| extract_blobs | 25.5 s | 22.3 s | ~1.2 s | ~18× | slower vCPUs + numpy |
| read_pins | 11.2 s | 10.5 s | ~1 s | ~10× | slower vCPUs |

Breakdown of the total gap:
- **~12% — thread oversubscription** (8 threads on 4 vCPUs). Removable by capping (above). Affects every stage.
- **~6–7× — fundamental compute**: Cloud Run's 4 shared/throttled vCPUs are much slower per-core, and fewer,
  than the Mac's performance cores. This is the bulk of the CV-stage gap and is not configurable away.
- **~8× — video decode**: Cloud Run has no hardware HEVC decoder (software FFmpeg); the Mac uses VideoToolbox.
- **Cold start** adds to wall-clock on the first request (not in the per-stage compute numbers above).
- **9 decode passes** (the clip is decoded 9×) multiplies the decode cost — the DEC-092 P1 "decode-once" target.

## Recommended production config change (PENDING — Shayne approves; not applied)
Ranked by value; none applied to the live service.

1. **Cap all thread pools to the vCPU count** (correctness + ~12%). Set on the service:
   `OMP_NUM_THREADS / OPENBLAS_NUM_THREADS / MKL_NUM_THREADS / NUMEXPR_NUM_THREADS / VECLIB_MAXIMUM_THREADS / LANESIGHT_CV_WORKERS = <vCPUs>`, and the committed `cv2.setNumThreads` cap (gated on `LANESIGHT_CV_WORKERS`)
   handles OpenCV. Low-risk; removes oversubscription. **Expected: ~12% faster, no cost change.**
2. **Decode once (DEC-092 P1).** 9 passes × ~3.2 s = ~29 s today; decode-once ≈ ~3 s → **saves ~25 s/shot**.
   Already on the DEC-092 roadmap; biggest single server win. Code change, not config.
3. **Consider 8 vCPU** (`--cpu 8`, matching `os.cpu_count`=8). Roughly 2× the parallel compute → ~halves the
   parallelizable stages. Cost: 2× per-second but ~½ the duration → **~cost-neutral per shot, ~2× faster
   wall-clock** (verify against DEC-043 caps before shipping).
4. **Strategic (DEC-106):** the dominant cost is environmental (slow vCPUs + software decode). Config tuning
   caps out around a modest improvement; the real latency fix is the **on-device native engine** (hardware
   decode + Apple-Silicon cores) — which this benchmark confirms.

### Cost per 1,000 shots (DEC-043), compute only (vCPU-seconds × $0.000024)
- Today: ~187 s × 4 vCPU ≈ 748 vCPU-s → **~$18/1,000 shots**.
- Thread-capped: ~165 s × 4 ≈ 660 vCPU-s → **~$15.8/1,000**.
- 8 vCPU (if ~halved duration): ~82 s × 8 ≈ 656 vCPU-s → **~$15.8/1,000** (≈ same cost, ~2× faster).
(Plus memory-seconds + egress; see `ops.cost_rates` / the ops dashboard /cost page.)

## Method notes / honest limits
- Confirmed via `/debug/env` on the bench service (read-only, no auth, no secrets).
- Runs were single-shot (n=1) on one clip; stabilize varies ±20% run-to-run, so the config deltas (~12%) are
  indicative, not tight. The *fundamental* 6–10× stage gaps are large enough to be unambiguous.
- Not run (optional, the conclusion is already clear): CV_WORKERS 2/1 sweep, a pure decode-only isolation, and
  an H.264-input comparison. Add these if a tighter decode/compute split is wanted.
- **Benchmark service `lanesight-api-bench` is still deployed** (scale-to-zero, ~$0 idle). Delete it when done:
  `gcloud run services delete lanesight-api-bench --region us-east1`.
