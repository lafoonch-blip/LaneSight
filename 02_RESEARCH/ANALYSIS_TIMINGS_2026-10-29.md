# Analysis latency baseline + audit (OD-00 / OD-00A) — 2026-10-29
Owner: Shayne · Branch: `feat/on-device-analysis` · Source data: `lanesight-core/ops/perf_reports/od00_server_baseline.json`
Harness: `ops/perf_benchmark.py` (reuses DEC-092 P0 per-stage timers) over 24 real clips (`ops/perf_manifest_od00.json`).

## How this was measured
`analyze_clip` was run on **this Mac (Apple Silicon)** over 24 real clips from `~/LaneSightData/training_videos`
— the **same Python/OpenCV/MediaPipe code** that runs on Cloud Run. This isolates *compute* (probe → window →
convert → decode → CV analyze), excluding upload and cold start. It is **not** the iPhone (see caveats); the
iPhone number is OD-01, which only Shayne can run.

## Headline
| Environment (identical code) | Shot-analysis compute |
|---|---|
| **Mac (Apple Silicon)** | **p50 16.3 s · p90 30.2 s · max 72.0 s · mean 20.7 s** (18/24 analyzed, 6 failed) |
| Cloud Run (4 vCPU, synchronous) | ~90 s trimmed, ~328 s full clip (CURRENT_STATE / proposal §3) |

The same pipeline is **~5–6× faster on Apple Silicon than on Cloud Run**. That strongly supports the proposal's
core premise: the latency is dominated by the **compute environment**, not by irreducible algorithm cost. An
iPhone uses the same CPU family — hence OD-01.

## Where the time goes (stage totals across the 24 clips)
| Stage | Total | Notes |
|---|---|---|
| `analyze_s` (CV) | **304.7 s** | dominated by `cv.stabilize_s` (~14.8 s on IMG_8751 alone) |
| `convert_s` | **83.2 s** | format/HDR normalization — up to **37.7 s on a single clip** |
| `window_s` | 38.5 s | shot-window trim |
| `probe_s` | 2.4 s | cheap |
| decode | ~3.5 s/clip total | **cheap** — `passes: 9` but only ~3.5 s; decode is NOT the bottleneck |

Correction to an earlier hunch: the "~9 decode passes" are cheap in wall time. The real costs are **`convert_s`**
and **`stabilize_s`**. Example (IMG_8751, 61.7 s): probe 0.1 · window 3.7 · **convert 37.7** · analyze 20.2
(of which **stabilize 14.8**, read_pins 2.3, extract_blobs 1.2).

## The iPhone caveats (why the Mac number is only a proxy)
- **Peak memory ~1.97 GB (p50), 2.14 GB (max).** This is the biggest risk for on-device: iPhones jetsam-kill
  apps well below the Mac's headroom (often ~2–3 GB per app). The pipeline as-is would likely be killed or
  need real memory work (frame streaming, lower-res detection with full-res crops) before it runs on a phone.
- **No active cooling.** Sustained 30-shot sessions will thermally throttle — OD-01 measures this directly.
- **Fewer performance cores** than the Mac.

## OD-00A — ranked optimization targets (no production CV change; DEC-062)
Estimated savings are from the stage totals above; each must be proven by the `perf_benchmark` regression gate
(DEC-092 tolerances) before adoption.

1. **`convert_s` (≈83 s total, up to 37.7 s/clip).** Likely HDR 10-bit → 8-bit / container normalization done
   in software. Target: hardware-accelerated decode/convert, or skip the full re-encode when the decoder can
   emit the needed pixel format directly. **Highest single win.**
2. **`cv.stabilize_s` (dominant CV op, ~15 s/clip).** Optical-flow stabilization. On device this is a strong
   candidate for Vision/Accelerate/Metal; on the server, cap iterations / downsample the stabilization pass
   (full-res only where measurement needs it).
3. **Memory (~2 GB peak).** Stream frames instead of holding the clip; run detection at low res and measure on
   full-res crops. This is a correctness prerequisite for iPhone, not just a speed win.
4. **Decode passes (9–10×).** Low wall-time cost today (~3.5 s) but still wasteful; decode once and reuse. Minor.

## Failures (6/24)
Failed clips still carry per-stage timings (DEC-092 reporting rule). They are in the JSON with their failure
codes; most are capture-quality cases (far-lane limited / pin-impact not detected), consistent with the DEC-101
trim findings. Not a regression — these are hard clips in the set.

## Next
- **OD-01 (Shayne):** run the device benchmark (Dev panel → "Device benchmark (OD-01)") on the iPhone with a
  real clip; paste the report into `02_RESEARCH/DEVICE_BENCHMARK_2026-10-29.md`. That turns the Mac proxy into
  a real device number and tests the memory/thermal risks above.
- The two gates (convert, stabilize) are where Phase 1.5 experiments should focus.
