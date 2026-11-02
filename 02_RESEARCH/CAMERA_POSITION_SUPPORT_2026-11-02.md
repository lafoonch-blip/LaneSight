# Supported camera positions — the 11/1 speed-truth set (DEC-118)
Status: FINDING · Date: 2026-11-02 · Owner: Shayne · Engine: lanesight-cv-0.7.1 (live)

## CORRECTION (2026-11-02, DEC-122 stage evidence) — it is NOT "degenerate geometry"
The earlier verdict below blamed degenerate far-lane geometry **without stage evidence**. With the DEC-122
per-stage report, the real per-clip causes are now measured (`validation/speed_truth_1101_stage_diag_0.7.2.json`):
**lane + ball_track SUCCEED on 12 of 18 clips.** The failures are NOT geometry — they are:
- **IMPACT detection** (pin contact not found): IMG_8963, 8971, 8973, 8975 — lane ✓, ball_track ✓, impact ✗.
- **Speed-scale / compute** (IMPOSSIBLE_SPEED_SCALE): IMG_8965, 8966, 8967 — lane ✓, ball_track ✓, impact ✓,
  but the homography-scaled RELEASE speed is implausible (wrong-lane selection among the n=2 detected lanes, or
  the track stops short of the pins → stretched scale). The geometry-free foul→pins average (time-based) is NOT
  affected by this and should still be reported (step 7c).
- **Lane detection (genuine)**: only IMG_8974, 8977 (mounted POV, pale/no-wood) — LANE_NOT_DETECTED_NO_WOOD.
- **Completed with a measured speed**: IMG_8964, 8968, 8969, 8970, 8981 (+ 8972/8976/8978/8979 returned no-metrics).

Per-group FIRST failing stage: angled-side {impact:1}; behind-ball-return-offset {completed:2, compute:2, impact:1,
no-metrics:1}; mounted-POV {impact:2, lane:2, no-metrics:3}; lower/wider {compute:1, completed:3}. So
"centered behind the ball return" is **not** a geometry dead-end — 8973/8975 produced a lane + full ball track
(impact-detection is the miss), and 8974/8977 are a pale-lane wood-detection miss. This supports the plan: fix
lane-selection-from-the-ball + a geometry-free 60 ft average + impact robustness; do NOT write it off as geometry.
The sections below are the EARLIER (superseded) framing, kept for history.

---

Shayne labeled 18 shot clips recorded 2026-11-01 from FOUR deliberately-varied camera positions
(`validation/labels/speed_truth_1101.json` + `validation/speed_truth_1101_labels.json` for the group tags).
Truth speed = 59.44 ft / ((first_pin_contact_frame − foul_cross_frame) / fps). Ran the 0.7.1 engine
(engine-identical to live Cloud Run) on all 18; foul→pins average vs truth, per camera group:

| camera group | clips | measured | within 0.3 | MAE | bias | worst | verdict |
|---|---|---|---|---|---|---|---|
| **centered behind ball return (mounted POV)** | 7 | **0** | 0 | — | — | — | ❌ UNSUPPORTED |
| **behind ball return, offset right** | 6 | 3 | 1 | 4.67 | +4.64 | **+13.57** | ❌ UNSUPPORTED |
| **lower/wider, ball return lower-right** | 4 | 3 | 0 | 2.72 | +2.01 | **+7.09** | ❌ UNSUPPORTED |
| **angled from the side** | 1 | 0 | 0 | — | — | — | ❌ UNSUPPORTED |
| (reference) rear-centered, square, foul+pins in frame — IMG_8751–54 | 4 | 4 | 4 | ~0.12 | ~−0.1 | 0.28 | ✅ SUPPORTED |

**Overall: coverage 6/18 measured, accuracy 1/18 within 0.3 mph of truth.** None of the four new positions is
supported. The one accurate clip (IMG_8964, −0.05) sits in a group whose sibling IMG_8971 reads **+13.6 mph**
(plausible-but-wrong), so the position is not reliable even where one clip happens to land.

### Failure modes by position
- **centered behind ball return (mounted POV)** — 0/7. LANE_GEOMETRY_UNUSABLE ×3, LANE_NOT_DETECTED_NO_WOOD ×2,
  PIN_IMPACT_NOT_DETECTED ×1, and **IMG_8975 raised an uncaught `ValueError`** (robustness bug — must become a
  coded AnalysisFailure, not a crash; see below). This is the DEC-065 ill-conditioned mounted POV: the foul line
  and the far cross-lines are near-parallel in the image, so the lane plane is degenerate.
- **behind ball return, offset right** — 3/6 produce a number, but only IMG_8964 is accurate; IMG_8965
  IMPOSSIBLE_SPEED_SCALE, IMG_8972 LANE_GEOMETRY_UNUSABLE, IMG_8971 **+13.6** (the ball track is routed off the
  bowler's lane / mis-scaled).
- **lower/wider, ball return lower-right** — 3/4 measure but all read HIGH (bias +2.0), IMG_8970 **+7.1**.
- **angled from the side** — the single clip can't anchor impact (PIN_IMPACT_NOT_DETECTED).

### In-app "supported camera positions" guidance (DEC-118)
Only the validated framing is supported for ball-speed/lane metrics; the app should GUIDE the bowler to it and
warn/flag off it (the DEC-061 capture-quality gate already flags some of these):
- ✅ **Camera BEHIND the lane, roughly CENTERED on the bowler's lane, SQUARE to it, with BOTH the foul line and the
  pins in frame, held steady (tripod/stable).** (This is the IMG_8751–54 framing.)
- ❌ Do NOT shoot from **beside/over the ball return**, **offset to one side**, **mounted low behind the return
  (looking down the lane at a shallow angle)**, or **angled across from the side** — the far-lane geometry is
  degenerate from those positions, so speed is unavailable or wrong (often confidently wrong — e.g. +7 to +14 mph).

### Robustness bug to fix (separate)
IMG_8975 (mounted POV) raised a bare `ValueError` instead of a coded `AnalysisFailure`. Every pipeline raise
should be a coded failure the app can show (DEC-086). Track + fix; add IMG_8975 to the manifest as expected-failed
once coded.

### What landed in the gates (item 2)
Only the clips the engine measures within the Standard tol (0.5 mph of truth) were added as regression anchors —
IMG_8964 (−0.05), IMG_8969 (−0.35), IMG_8981 (+0.39) — so the Standard tier now gates **7** clips vs truth
(not 4), and the on-device `OnDeviceGateTests` carries the full 22-clip truth map + the 3 passers in GateClips.
The other 15 clips are NOT added (they fail or are plausible-but-wrong — adding them would require supporting the
camera positions, which is out of scope and contradicted by this data). "Judged on 22, not 4" in practice means
**the gate grew to 7 reliable anchors; the remaining 15 are documented here as unsupported framings.**
