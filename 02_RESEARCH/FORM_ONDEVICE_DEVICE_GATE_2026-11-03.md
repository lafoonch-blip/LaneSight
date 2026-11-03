# On-device Form parity gate — device run (DEC-129)

Status: FINDING · Version: 1.0 · Last Updated: 2026-11-03 · Owner: Shayne
Device: iPhone 17 Pro Max (Release, signed), Xcode 27.1, MediaPipe Pose Landmarker heavy 1.0.0.
Harness: `OnDeviceFormGateTests.testOnDeviceFormParityOnLabeledClips` (7 labeled clips, 10× determinism loop).
**Verdict: TEST FAILED (7 assertion failures) — the gate does NOT pass yet.** 2163 s total.

## Per-clip results (device vs the labels and vs the Python server reference / golden)

| clip | view | det | wall | step dev/label(ref) | E4 dev\|ref | E7 dev\|ref | E8 dev\|ref |
|---|---|---|---|---|---|---|---|
| IMG_8824 | side | 10/10 | **7.5 s** | 5/5 (5) | −1.0\|−0.9 | +3.0\|+3.0 | −5.0\|−5.0 |
| IMG_8825 | side | 10/10 | 37.9 s | 2/5 (3) | null\|−2.0 | null\|−1.1 | +12.0\|−1.0 |
| IMG_8826 | side | 10/10 | 40.9 s | 4/5 (6) | null\|null | null\|null | +38.0\|+38.0 |
| IMG_8846 | rear | 10/10 | **15.9 s** | 6/5 (3) | −2.0\|−1.0 | +1.0\|+1.0 | +1.0\|+1.0 |
| IMG_8847 | rear | 10/10 | 37.2 s | 5/5 (4) | −4.0\|+0.0 | +1.0\|−0.0 | +2.0\|−2.0 |
| IMG_8848 | rear | 10/10 | 33.6 s | 6/5 (6) | −1.0\|−2.0 | +1.0\|+1.0 | +0.0\|−0.0 |
| IMG_8980 (held-out) | rear | 10/10 | 35.9 s | 5/5 (14) | +327\|+328 | +313\|+314 | +307\|+307 |

(`det` = determinism over 10 runs; `wall` = single-run on-device time; Δ in frames vs the label, and vs the
Python reference's Δ. `null` = the on-device engine dropped that event via the DEC-095 honesty gate.)

## What the device run establishes

1. **Determinism: 10/10 on every clip.** The on-device engine (MediaPipe pose + the Swift port) is byte-identical
   across 10 runs — the DEC-126 P0 non-determinism rule holds on device. ✅
2. **The Swift port logic is faithful to the Python reference.** Where the two MediaPipe runtimes agree, the port
   reproduces the reference tightly: IMG_8824 matches to ~0.1 frame on E4/E7/E8 + exact step count; IMG_8980
   reproduces the reference's (wrong) mis-segmentation to ~1 frame. So the ported event/metric math is correct.
3. **Swing events E7 (release) + E8 (slide stop) parity-match the server within ~0–2 frames on 5/6 non-held-out
   clips** (8824/8826/8846/8847/8848) — the back-half DEC-118 events transfer well to device.

## Why the gate FAILED — the two real gaps

- **iOS-vs-Python MediaPipe landmark gap** (the dominant cause). The iOS GPU-delegate pose and the Python
  XNNPACK-CPU pose produce slightly different landmarks. On the robust events (E7/E8) this stays within ±2 f, but:
  - **Step count** diverges from the reference (dev 2/4/6/5/6 vs ref 3/6/3/4/6) — the foot-plant signal is the
    known-weak best_effort metric (DEC-120/121); the landmark gap tips the foot-speed minima across the threshold.
  - **IMG_8825** — the on-device pose shifts the delivery-isolation window enough that E4/E7 drop (honesty gate)
    and E8 lands +12 f off; the reference had a clean read there. A marginal-window clip amplified by the gap.
  - **E4 (top of backswing)** wanders ±1–4 f (8847 is −4) — more landmark-sensitive than E7/E8.
- **Runtime > 30 s on long untrimmed 60 fps clips** (8825 37.9 / 8826 40.9 / 8847 37.2 / 8848 33.6 / 8980 35.9).
  The engine runs pose on EVERY frame; a full ~19–22 s 60 fps validation clip is ~1150–1320 frames. The short /
  lower-fps clips pass (8824 7.5 s, 8846 15.9 s). A REAL form capture (tap-record a single delivery, ~5–8 s) is
  ~300–500 frames and would land well under 30 s, but the gate's untrimmed clips do not. `measureOnDeviceFormPrimary`
  caps at 30 s and falls back to the server, so long clips are honest (server-analyzed), not wrong — but they are
  not measured on-device.

## Recommended next steps (not done here — each needs validation)
1. **Trim to the delivery before pose** (or a frame stride for the pre-approach stance) to bring long 60 fps clips
   under 30 s. Must re-check parity (fewer frames must not move the events).
2. **Close the step-count gap** — this is the same signal-floor DEC-121 flagged for the server; on device it is
   additionally offset by the iOS/Python landmark difference. Keep `step_count` best_effort; do not gate on it.
3. **Decide the gate's parity reference.** The DEC-129 gate currently asserts on-device == the *Python server*
   engine within ±2 f. Because the two MediaPipe runtimes differ, a fairer on-device gate may be on-device ==
   *labels* within tolerance (ground truth), with the server comparison kept as a reported shadow — the server
   itself only passes a subset of the labels (DEC-120/121). Shayne's call.

## What DID ship + is validated on device
MediaPipe vendored + the device Release build succeeds + the pose model loads and runs on device; the engine is
deterministic; the ported event math is faithful; `§B` on-device-first form wiring is built + installed (Release)
behind `ls.ondevice_primary` (default OFF). The gate failing is an accuracy/runtime finding about the iOS pose
runtime + the untrimmed clips — not a build or a port-logic failure.
