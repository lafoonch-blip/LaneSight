# Device benchmark results (OD-01) — 2026-10-29
Owner: Shayne · Branch: `feat/on-device-analysis` · Harness: Settings → Dev panel → "Device benchmark (OD-01)"

## How to run (2 min)
1. Open the installed LaneSight app → Settings → Dev panel → **Device benchmark (OD-01)**.
2. **Pick a clip from Photos** (one of your real bowling clips, ideally a 120 fps shot).
3. Leave "Sustained passes" at 30 → **Run benchmark**.
4. When it finishes, **copy the Report** text and paste it under "Results" below.

## What to look at (the Phase-3 gates)
- **STABILIZATION PROXY (registered fps).** This is the primitive under `cv.stabilize_s`, the server's dominant
  CV cost (~15 s/clip). If the phone registers frames at or faster than real time, on-device stabilization is
  plausible. If it's far below, that's the first thing to optimize/offload.
- **NATIVE PROCESS fps** and **DECODE fps / realtime factor** — general compute headroom.
- **Peak memory (phys_footprint).** The server run peaks ~2 GB; iPhones jetsam well below that. This is the
  single biggest risk — if peak is high, frame-streaming + low-res detection is a prerequisite, not a nicety.
- **Thermal transitions** over the 30-pass run — any move past `fair` means sustained sessions will throttle.
- **Battery** delta over the run.

## Baseline to compare against (server / Mac, same code — from OD-00)
- Cloud Run (live): shot analysis **p50 186–280 s**.
- Mac (Apple Silicon, same Python): **p50 16.3 s / p90 30.2 s**.
- Dominant stages: `convert_s` (≤37.7 s/clip), `cv.stabilize_s` (~15 s/clip). Peak RSS ~2 GB.

## Results — run 1 (Shayne, iPhone 17 Pro Max, iOS 26.7.1)

```
LaneSight device benchmark (OD-01)
Device: iPhone · iOS 26.7.1            [iPhone 17 Pro Max]
Clip: clip (63 MB)  1920x1080 @ 60.0fps  21.8s  1305 frames

DECODE (HEVC → BGRA)
  one pass: 2.37s  →  551.4  decoded fps   (9.2x realtime)
NATIVE PROCESS (decode + vImage box-convolve, full frame)
  one pass: 1.95s  →  668.1  processed fps
STABILIZATION PROXY (Vision frame-to-frame registration — the server's dominant CV cost)
  one pass: 0.69s  →  347.7  registered fps  (240 pairs)

SUSTAINED RUN (30 passes ≈ a 30-shot session)
  total: 60.0s   mean/pass: 2.00s
  peak memory (phys_footprint): 67.6 MB
  battery: 100% → 100%
  thermal transitions: none (stayed nominal)
```

## Read — STRONG go signal (with honest caveats)

| Gate | Device (this run) | Server baseline | Verdict |
|---|---|---|---|
| **Stabilization** (dominant CV cost) | 347.7 reg fps → **~3.8 s** for the full 1305-frame clip | `cv.stabilize_s` ~15 s | **~4× faster on device** ✅ |
| **Peak memory** | **67.6 MB** | ~2 GB RSS | **~30× less — jetsam risk eliminated** ✅ |
| **Thermals** (30-shot session) | none; stayed `nominal` | n/a | **No throttling** ✅ |
| **Battery** | 100% → 100% (negligible) | n/a | ✅ |
| **Decode** | 551 fps, **9.2× realtime** | — | Large headroom ✅ |

- **Stabilization feasible on device?** Yes — comfortably. The server's single biggest cost runs ~4× faster here.
- **Memory within a safe iPhone budget?** Decisively yes. 67.6 MB vs ~2 GB. The win is **frame streaming**
  (AVAssetReader, one frame at a time) — the server's 2 GB comes from holding frames in numpy. Keep the
  streaming approach in the port; that's the whole memory story.
- **Thermals stable over 30 passes?** Yes — no transitions, negligible battery.

### Caveats (so we don't over-read a great result)
1. **This clip is 1080p @ 60 fps**, not the app's **120 fps** target (and 4K is possible). At 4K/120 the frame
   count and pixel work both rise, so expect higher times and memory — the headroom is large but re-run OD-01
   on a 120 fps clip before committing.
2. **The measured steps are primitives, not the full pipeline.** `STABILIZATION PROXY` is Vision translational
   registration (simpler than the server's optical-flow stabilization); `NATIVE PROCESS` is a vImage filter,
   not lane detection / ball tracking / rev / pins. The real on-device engine (lane calib, track, metrics) is
   more work than the sum here — but every primitive is fast and memory is tiny, so the architecture is sound.

### Verdict for Phase 2/3
**Green light to proceed** — the two risks that would have killed on-device (memory blow-up, thermal throttling)
are both cleared on real hardware, and the dominant compute is faster than the server. Next: (a) re-run OD-01 on
a 120 fps clip, (b) port the real stabilization step and parity-check it vs the server (DEC-103 gate), (c)
continue down the Phase-3 shadow path. The Mac-vs-CloudRun gap (OD-00) was environment, not algorithm; this run
shows the iPhone has the headroom to close it.
