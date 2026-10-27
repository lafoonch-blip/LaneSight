# Training-clip analysis — 2026-10-25 pale-lane set (IMG_8893–8910)
Version: 1.0
Last Updated: 2026-10-25
Status: Findings + fixes made (pale-lane detection, crash guards, honest flagging). Detection robustness for
awkward framings is the remaining work.

## Set
17 clips (IMG_8893–8910, no 8906), 1080×1920 portrait, 60 fps, bt709 **SDR** (not HDR), ~26 s each. Pale/blonde
maple lanes (mid-lane saturation ≈ S60, below the S105 detector floor). Various framings: some near lane-level
behind/beside the lane, some elevated on the ball return looking down, one with large camera motion.

## What was fixed this session (committed, 203 tests pass)
- **Pale-lane detection:** `find_lanes` retries the saturation pass at 105 → 70 → 50 before the gutter
  fallback. s_min=105 runs first, so well-saturated lanes (IMG_8751–8754) detect byte-identically
  (IMG_8753 verified unchanged: entry 16.6, strike). This alone took the set from **0/17 → 3/17** analysing.
- **Honest geometry flagging:** an off-lane entry/breakpoint (not 0–40) now marks `capture_quality.far_lane =
  limited`, and that verdict drives the insights `state` to `no_reliable_data` (B and C share one verdict) —
  no confident move on a broken homography (IMG_8893 entry 45.6 was shown as a move; now no move).
- **Crash guards → clean errors:** empty mid-lane breakpoint (IMG_8896) and degenerate/empty lane ROI
  (IMG_8909) raised bare numpy errors (500s); both now return clear "reshoot square to the lane" messages.

## Results (with the fixes)
**Analyses well (3):**
| clip | entry | speeds (early→late) | result |
|---|---|---|---|
| IMG_8899 | 14.2 | 17.6 → 15.9 ✓ | strike |
| IMG_8902 | 18.7 | 19.9 → 16.9 ✓ | strike |
| IMG_8904 | 20.0 | 18.9 → 15.9 ✓ | move (slightly high) |

**Flagged honestly → no_reliable_data, no garbage advice (6):** IMG_8893 (entry off-lane 45.6),
IMG_8895/8903 (off-lane-ish entry + low speed), IMG_8896 (too-slow/short track), IMG_8901 (camera motion
14,414 px), IMG_8907 (impossible 34 mph).

**Fail with a clear error (8):** IMG_8894/8897/8898/8910 "pin impact not detected"; IMG_8900/8908 "foul line
not found — lane runs off the bottom"; IMG_8905 "no VP-consistent edges"; IMG_8909 "lane geometry unusable".

## Why the failures happen (root cause)
The geometry detector assumes the **foul line is the near boundary of the lane** and the lane isn't extremely
foreshortened. The failing clips break one of these:
- **Camera on/behind the approach looking down** (IMG_8900/8908): bare approach wood is contiguous with the
  lane wood, so the foul line is "below the frame" and the near boundary is wrong.
- **Elevated camera** (IMG_8893): 60 ft of lane is crushed into a small vertical band → far-lane depth
  resolution collapses → entry board lands off the lane (45).
- **Pins in too few pixels / ball fades before the deck** (the "pin impact not detected" group): back-half
  ball tracking is the known frontier.
Camera *height / foreshortening* matters more than left/right: IMG_8902 worked as a close side view (bowler
prominent) because it was near lane-level; IMG_8893 failed from straight-behind because it was elevated.

## Remaining work (detection robustness — the real fix for coverage)
1. **Foul line from the gutters, not the wood mask.** The playing lane is flanked by dark gutters; the approach
   is not. Use the near end of the gutters as the foul line so approach wood no longer defeats detection.
2. **Reject/annotate extreme foreshortening** (lane vertical span too small) rather than emitting an off-lane
   entry; or fit far references (pin deck) to pin the depth scale (the original workstream A).
3. **Back-half ball tracking** to recover impact on foreshortened decks (the long-standing frontier).
These need per-clip ground truth to validate accuracy; the 3 good clips + IMG_8751–8754 are the no-regression set.

## Guidance that makes it work now
Shoot **near lane-level** (not elevated/looking down), with the **foul line visible as the lane's near edge**
(minimal bare approach wood below it), the **whole lane to the pins in frame**, and a **stable** phone. The
3 clips that met this analysed correctly; the detector is solid there (IMG_8753 is the reference).
