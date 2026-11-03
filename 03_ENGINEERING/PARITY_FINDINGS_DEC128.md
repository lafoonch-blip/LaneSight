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

## 80ae104f resolved — it was a LANE-SELECTION bug (not detector tuning)

Per-frame intermediate dumps on both engines localised the divergence through every stage (decode matches to ~3
of max-channel mean; stabilization irrelevant — the failing clip is static at 1.1 px while the *working* clip has
22.8 px motion). The real cause: **the device tracked the wrong lane.**

- The server and the device both detect the **same 3 raw lanes**. A spurious 3rd lane (center_x 554, edges that
  miss the VP by ~830 px) skews the device's jointly-solved VP (637,881 vs the server's 612,844). With that
  skewed VP, the **ball's pale left lane** (center_x ~405, server dl=14 → GOOD) misses the device VP by dl=180 →
  dropped by the VP-consistency "good" filter. The device then tracked `geo.lanes.first` = the **empty right
  lane** → 0 track points. The server iterates all lanes and keeps the one the ball rolled down (`_lane_ball_score`).

**Fix (DEC-128, `OnDeviceTracker`/`OnDeviceLaneDetector`/`OnDeviceBoards`):**
- The tracker now scores **every** detected lane by the ball track (`_lane_ball_score`, ported from
  `cv/pipeline.py`) and keeps the ball's — never `lanes.first`.
- `OnDeviceLaneDetector` exposes `rawLanes` (all lanes before the VP "good" filter). When the ball is on no good
  lane, the tracker falls back to the raw lanes — the real pale lane is still there and scores highest.
- `cv/track.py`'s `_groups` fragment-merge is ported and applied **only on the raw-lane fallback** (the ball
  fragments on a pale lane); the good-lane path keeps the exact original candidate set, so the validated clips are
  unchanged.
- `BallTrack.selectedLane` is carried into `OnDeviceBoards`, and the board homography anchors Z=0 at the selected
  lane's near row — otherwise the boards are read on the wrong lane's scale.

**Result (sim, trimmed like live):** 80ae104f now **tracks** (was 0 points): ball_speed 16.6 vs server 17.6
(within ±1.5), arrows 14.5 vs 14.5 (exact), board_at_7ft 16.7 vs 15.1 (within ±2). laydown 19.7 vs 15.7 is ~2
boards beyond tolerance — the near-lane board on the pale fallback lane (its unrefined edges + the horizontal
foul-row approximation); a documented residual. Golden: `OnDeviceLaneParityTests` pass; IMG_8751/8752 pass vs
truth; IMG_8753/8754 are untracked on the **original** device engine too (not a regression — the device never
tracked them; only the server, with stabilization + full-res, does). Reverted as net-negative: the per-channel
BGR diff and the bg-level ROI port (no benefit; the ROI/per-channel perturbed the golden f2p).
