# iOS parity golden (DEC-117 Track A item 1)

Per-clip reference outputs from the VALIDATED Python impact-anchor pipeline (the path that matches Shayne's
truth at MAE 0.12). The Swift on-device port is checked stage-by-stage against these in
`ios/LaneSight/Tests/` (lane edges, foul line, VP, impact-anchor pixel, event frames, ball_speed, foul→pins avg,
per-frame ball track).

Provenance: generated from the geo caches of the 2026-10-30 validated runs + `metrics.compute` for event times
(scratchpad `golden_gen.py`). Geometry (lane/foul/VP) and the scalar metrics (ball_speed, foul→pins) + the
foul→impact INTERVAL are trim-independent, so they compare directly regardless of how a clip is trimmed. Absolute
frame indices are in the server's trim coordinates — compare intervals, not absolute frame numbers, across trims.
