# Phase 3 — on-device engine build status (2026-10-29)
Owner: Shayne · Branch: `feat/on-device-analysis` · DEC-102/103 · SHADOW (nothing shown/counted until gates pass)

Greenlit by OD-01 (iPhone 17 Pro Max): stabilization ~4× faster than server, peak memory 67.6 MB (vs ~2 GB),
no thermal throttling. See `02_RESEARCH/DEVICE_BENCHMARK_2026-10-29.md`.

## Pipeline stages (server → device port order)
From `lanesight_core/cv/pipeline.py`, by cost (OD-00A) and dependency:

| # | Stage | Server module | Device status |
|---|-------|---------------|---------------|
| 1 | **Stabilization** (register frames → reference) | `cv/stabilize.py` | ✅ **built (shadow)** — `OnDeviceStabilizer.swift`, Vision homographic registration, streaming |
| 2 | Lane detection / calibration | `cv/` find_lanes + `calib/` | next |
| 3 | Ball detection + tracking | extract_blobs + link/extend | after 2 |
| 4 | Impact / refine | detect_impact + refine | after 3 |
| 5 | Metrics (speed, entry board, rev, angle) | `cv/metrics.py` | **accuracy-critical** — port last, with the DEC-034 gates |
| 6 | Pins | read_pins | parallel |

Run stage 1 on device: Settings → Dev panel → **On-device analysis (shadow)**.

## Parity gate (DEC-103) — the key architectural decision
**Parity is METRIC-level, not stage-level.** The device engine is Vision/Accelerate-native; the server is
OpenCV/Python. Their intermediate outputs will never bit-match (different algorithms, RNG, feature detectors).
Trying to force stage-by-stage equality is the wrong goal and a trap. What the DEC-103 gate actually checks:
the device's **final measurements** (ball speed, entry board, entry angle, rev rate, pins) agree with the
server's **within the DEC-034 tolerances** on the validation set, plus Specto where available (DEC-105: Ruby
removed from the validation process; the server is the reference engine).

Concretely, this reframes the port:
- Each device stage can use the **best native approach** (e.g. stage 1 uses Vision homographic registration
  with a first-frame reference) — it does **not** have to replicate `cv/stabilize.py`'s reference-frame picker
  (middle of the longest steady lane-visible stretch) or its homography chaining.
- The reference-frame choice still **matters** because it sets the coordinate frame lane calibration reads — so
  it must be *good enough* that the downstream boards/speed land in tolerance, not *identical* to the server.
- **Gate = end-to-end metrics**, run once the device pipeline produces measurements. There is no meaningful
  per-stage parity number before then; a stabilization-only "parity" would measure algorithm cosmetics, not trust.

Stage-level comparisons (e.g. residual lane jitter of the stabilized output) are useful **debugging cross-checks**,
not the gate.

## Immediate next steps
Build the device pipeline **end-to-end to at least one metric** before worrying about parity numbers, because
the gate is metric-level (above). Order:
1. **Stage 2 — lane detection + calibration on device** (Vision/Accelerate-native). This turns the stabilized
   frames into the lane coordinate frame every metric reads. Biggest unlock.
2. **Stage 3 — ball detection + tracking** → a track in lane coordinates.
3. **First metric — ball speed** (geometry over the track + frame timestamps): the simplest end-to-end metric,
   and enough to stand up the real parity gate (device speed vs server speed, within DEC-034 tol; Specto where available).
4. Extend to entry board / angle / rev / pins. Hold each until it clears ground-truth + parity on the
   validation set — accuracy beats coverage (a 2-board error flips the advice; CLAUDE.md).

`OnDeviceStabilizer` (stage 1) stands as-is; its first-frame reference is fine under metric-level parity and can
be refined later only if the metrics need it.

## Non-negotiables carried into the port
- No AGPL models (DEC-094 §6). Measurement-validity on device; coaching/thresholds stay server-side (DEC-046).
- Stream frames (never hold the clip — that's the 67.6 MB vs 2 GB win). No fabricated metric to fill a gap.
- Shadow only until the ground-truth (DEC-034) + parity gates pass; server stays authoritative (DEC-102).
