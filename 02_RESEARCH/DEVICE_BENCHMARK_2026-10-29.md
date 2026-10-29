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

## Results
_(paste the harness Report here)_

```
<paste>
```

## Read (fill after pasting)
- Stabilization feasible on device? ___
- Memory within a safe iPhone budget? ___
- Thermals stable over 30 passes? ___
- Verdict for Phase 2/3 go/no-go: ___
