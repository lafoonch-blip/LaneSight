# On-device speed chain — status + blockers (DEC-117 Track A, 2026-11-01)
Status: WORKING NOTE
Owner: Shayne

Where the Swift on-device engine (`ios/LaneSight/Sources/OnDevice`) stands against DEC-117's
"iPhone is the primary engine for speed + rev" goal, after the lane-geometry parity work landed.

## DONE — lane geometry parity (the explicit gate)
`OnDeviceLaneDetector` is a line-for-line port of `cv/lanes.py find_lanes`, now complete through the
tail (`_foul` → `_refine_edges` → VP re-solve), Double-precision. `OnDeviceLaneParityTests` asserts
VP within 5 px / foul within 2 px vs `ios_parity_golden`, on the stabilized background plate the
Python reference consumes:
- geometry path (Python masks): **dVP 0.00 px, dFoul ≤0.01 px** — bit-exact, all 4 clips.
- plate path (Swift HSV + vImage morph): **dVP ≤1.43 px, dFoul ≤1.02 px** — within gate, all 4.
The detector is correct. See `03_ENGINEERING/ios_parity_golden/README.md`.

## NOT DONE — end-to-end speed (track → events → speed within 0.3 mph, Release)
Ran `OnDeviceGateTests` (the full shadow chain: referenceFrame → detect → track → speed → rev) on
all 4 validation clips, **on the iOS Simulator** (Debug). No clip produces a valid ball_speed yet.
Three distinct blockers, NONE of them the lane geometry:

| clip | rot | detect | track | speed | rev | first_failing_stage |
|---|---|---|---|---|---|---|
| IMG_8751 | −90 | degenerate (VP y=−32069, thin band y585–725) | 0 pts | — | — | track |
| IMG_8752 | 0 | OK — VP (940,561) vs golden (947,557) ≈6px | 108 pts, impact@27.81s | FAIL: foul→impact 9.31 s implausible | **386 rpm ±41 ✓** | speed |
| IMG_8753 | 0 | 6 lanes, none VP-consistent → no geometry | empty | — | — | track |
| IMG_8754 | −90 | degenerate (VP y=53934, thin band y581–727) | 0 pts | — | — | track |

### Blocker 1 — orientation not applied (IMG_8751, IMG_8754)
The on-device decode path (`OnDeviceLaneDetector.referenceFrame`, `OnDeviceTracker.buildBackground`
/`forEachLuma`/`detectImpact`) reads BGRA via `AVAssetReaderTrackOutput`, which does **not** apply the
track's `preferredTransform`. IMG_8751/8754 are `rotation −90` (stored 1920×1080, display portrait
1080×1920), so the detector gets a landscape frame → near-parallel edges → garbage VP. The server
applies this in `cv/decode.py _apply_rotation` (and `cv/stabilize.py` honours the rotation flag).
**Fix:** rotate each decoded CVPixelBuffer by the track's display rotation (vImageRotate90 for ±90/180),
matching `_apply_rotation`'s clockwise convention, before detect/track. Device-independent; verify on the
sim (8751/8754 should then detect like the plate).

### Blocker 2 — single raw reference frame ≠ the stabilized plate (IMG_8753, general)
The chain detects on ONE raw frame (`referenceFrame at: 30`). The golden/parity geometry comes from the
stabilized **background plate** (temporal median, bowler/ball removed). On a raw frame IMG_8753 detects
6 candidate lanes and none agree on a VP (vs a clean single lane on the plate). **Fix:** build a background
plate on device (the tracker already medians sampled frames in `buildBackground` — reuse that plate, at
full res, as the detector input) or pick a robust static pre-roll frame; do NOT detect on a lone frame.
No detector change needed — it's the input.

### Blocker 3 — impact / foul→impact anchoring (IMG_8752)
8752 has good geometry + a 108-point track + working rev, but speed fails: foul→impact = 9.31 s (truth
≈ 2.3 s; golden interval gives 17.86 mph). `detectImpact` returned t=27.81 s — a late/ wrong pin-deck
spike — and/or `speed()`'s foul-cross extrapolation is off. **Fix:** align the on-device impact anchor to
the validated impact-anchor logic (`cv/metrics.impact_anchor` + the 59.44 ft foul→pins interval); the
pin-deck motion detector is picking a non-shot spike.

## Per-stage timing (NEW instrumentation) — sim/Debug, illustrative only
`perf.stage_ms` now breaks latency into reference_frame / detect / track / speed / rev. On the sim (Debug),
`track` dominates (IMG_8752: detect 0.9 s, **track 159 s**, rev 6 s, total 166 s; IMG_8751 track 375 s as it
scans 2095 frames and finds nothing). Per-clip total latency (sim Debug): 8751 375.9 s, 8752 166.1 s,
8753 1.4 s (bailed at the geometry guard), 8754 371.8 s; peak mem ~120–123 MB; thermal nominal throughout
(the sim doesn't model device thermals). Whole 4-clip gate: 915 s. These are NOT the device Release
numbers — Task 1's real Debug-vs-Release device timing is pending (see below).

## Task 1 — device Release timing: PENDING (device coordination)
`OnDeviceGateTests` + `GateClips/` (4 clips symlinked locally) are wired and build clean for the device.
Run (Release) when the phone is free:
```
xcodebuild test -scheme LaneSight -configuration Release \
  -destination 'id=00008150-000651C10138401C' \
  -only-testing:LaneSightTests/OnDeviceGateTests
```
Grep `ONDEV_GATE_ROW` for per-clip `latency_s` + `stage_ms` + `peak_mem_mb` + thermal, vs the ~132 s
Debug baseline (DEC-117). NOTE: until Blocker 1 is fixed the 8751/8754 timings won't reflect real work
(track bails on garbage geometry), so fix orientation first for a meaningful device timing on all 4.

## Suggested order
1. Blocker 1 (orientation) — small, unblocks 8751/8754, verify on sim.
2. Blocker 2 (plate as detector input) — unblocks 8753 and makes 8751/8754/8752 robust.
3. Blocker 3 (impact anchor) — the last mile to a real speed; then the 0.3 mph gate on device Release.
No detector rewrite / no new geometry needed for any of these — they are decode/IO + tracker/anchor fixes.
