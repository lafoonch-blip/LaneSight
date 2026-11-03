# DEC-128 real-clip parity findings (on-device vs server)

Status: ACTIVE · Last Updated: 2026-11-03 · Owner: Shayne

Method: `ops/parity_fetch.py` downloaded the retained clips from the `shot-clips` bucket (Shayne's accounts),
matched each to its shot by `content_hash` (or upload-time proximity for the hashless on-device shots), and
recorded the SERVER `analysis_metric_outcome` rows. `OnDeviceGateTests` ran the iPhone engine on each clip
(trimmed to the 5 s shot window, like the live path) on the simulator; `ops/parity_report.py` joined the two.

Of 24 matched retained clips, only three carry a server metric reference (the rest the server also left
unmeasured): **80ae104f** and **7936cc3f** (server measured everything) and **6ecfcfee** (the device-test
wrong-lane case). Those three are the parity-critical set.

## Per-clip parity table (the three clips with a server reference)

| clip | metric | server | iPhone | verdict |
|---|---|---|---|---|
| **7936cc3f** | ball_speed | 17.5 | 17.7 best_effort | MATCH |
| | speed_avg_foul_to_pins | 18.0 | 18.1 best_effort | MATCH |
| | laydown_board | 13.3 | 13.4 ok | MATCH |
| | board_at_7ft | 9.5 | 9.9 ok | MATCH |
| | arrows_board | 6.4 | 6.9 ok | MATCH |
| | rev_rate | 390 | unavailable · `SPIN_NOT_RESOLVED` | honest miss |
| | loft | 0.9 | unavailable · `NOT_MEASURED_FROM_VIDEO` | honest miss |
| **80ae104f** | all | 17.6 / 15.7 / 15.1 / 14.5 / 370 … | unavailable · `BALL_TRACK_NOT_FOUND` | honest fail |
| **6ecfcfee** | (server measured nothing) | — | boards unavailable; speed 8.6 best_effort; **no implausible values** | consistent |

Tolerances: speed ±1.5 mph, boards ±2, rev ±75 rpm.

## Gate verdict

The gate — *on every clip where the server measures a metric, the iPhone measures it within tolerance or returns
`unavailable` with a reason; zero implausible values* — **passes**:
- **Zero implausible values.** 6ecfcfee's old impossible `board_at_7ft 50.6` / `arrows 37.1` are now `unavailable`
  (item-1 bounds + the near-lane-corruption drop: the near-lane boards ride one homography, so if any is off-lane
  all are dropped and the path is suppressed).
- **7936cc3f matches** the server on every board + speed; rev/loft are honestly `unavailable` with a reason.
- **80ae104f** returns `unavailable` with a reason on every cell (previously the cells had no `reason_code`; now
  the stage cause is stamped per metric).

## Open item — 80ae104f coverage (iPhone fails where the server succeeds)

Root cause, confirmed: the on-device ball **detector/linker** finds too few candidate frames to form a track —
14 of ~358 frames trimmed, **31 of ~497 untrimmed** — and RANSAC links **0** track points. The server tracks the
same clip fine. It is **not** the trim window, the untrimmed 15 s path, or lane selection (lane detection succeeds;
the untrimmed run still fails at `track`).

Fixing it means loosening the on-device foreground threshold (`diffThr`/diameter gate) and/or the RANSAC link —
the exact levers that can regress the validated IMG_8751-54 golden clips, so it requires the full on-device
validation loop (re-run `OnDeviceGateTests` on the golden set + 7936cc3f/6ecfcfee) and may not succeed if the ball
is genuinely hard to segment on-device. Flagged as a follow-up rather than shipped speculative, per
"accuracy beats coverage."
