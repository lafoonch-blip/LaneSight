# iOS parity golden (DEC-117 Track A item 1)

Per-clip reference outputs from the VALIDATED Python impact-anchor pipeline (the path that matches Shayne's
truth at MAE 0.12). The Swift on-device port is checked stage-by-stage against these in
`ios/LaneSight/Tests/` (lane edges, foul line, VP, impact-anchor pixel, event frames, ball_speed, foul→pins avg,
per-frame ball track).

Provenance: generated from the geo caches of the 2026-10-30 validated runs + `metrics.compute` for event times
(scratchpad `golden_gen.py`). Geometry (lane/foul/VP) and the scalar metrics (ball_speed, foul→pins) + the
foul→impact INTERVAL are trim-independent, so they compare directly regardless of how a clip is trimmed. Absolute
frame indices are in the server's trim coordinates — compare intervals, not absolute frame numbers, across trims.

## Swift lane parity (DEC-117 Track A item 2, 2026-11-01)
`OnDeviceLaneDetector.swift` is a line-for-line port of `cv/lanes.py find_lanes` (HSV wood mask → morphology →
per-row run tracks → robust edge fit → common VP → `_foul` → `_refine_edges` → VP re-solve), run on the same
stabilized background plate `find_lanes(bg)` consumes. `parity_gen.py` (here) regenerates the test fixtures from
the geo pkls: per-clip `IMG_875x_plate.bgra` (raw BGRA plate), `IMG_875x_strict.u8` / `_loose.u8` (the exact
Python s105 / s60 masks), and `parity_intermediates.json` (per-stage reference). Fixtures land in
`ios/LaneSight/Tests/ParityFixtures/` (gitignored, large/binary); `OnDeviceLaneParityTests` SKIPs if absent.

`OnDeviceLaneParityTests` runs two paths vs this golden:
- **geometry** — `detect(strictMask:looseMask:)` on the Python masks (isolates the geometry port). Result:
  **dVP = 0.00 px, dFoul ≤ 0.01 px** on all 4 clips (bit-exact).
- **plate** — `detect(pixelBuffer:)` on the raw plate (also exercises the Swift HSV mask + vImage morphology).
  Result: **dVP ≤ 1.43 px, dFoul ≤ 1.02 px** (inside the 5 px VP / 2 px foul gate; residual is HSV rounding +
  vImage-vs-cv2 morphology — ~1 % fewer mask pixels).

NOT ported (no validation clip exercises them; `find_lanes` only falls back when the saturation pass finds
nothing): the pale-lane gutter fallback (`_gutter_fallback`/`_ransac_edge`) and `classify_capture_view`.
