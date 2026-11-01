---
title: Metric lane-plane solve — ball-independent depth scale (findings)
status: prototype complete (Python reference)
date: 2026-11-01
decision: DEC-117 (CV-review item 1)
code: lanesight-core/ops/metric_lane_plane.py (solver + synthetic self-test)
---

# Ball-independent metric lane-plane solve — findings

**Goal (CV review, item 1):** replace the fragile impact anchor with a geometry that needs no ball and no
pin-impact: camera intrinsics (AVFoundation / `AVCameraCalibrationData` on device, EXIF/known on the clips) +
lane edges + foul line + known lane width (41.5 in) → a metric lane plane. A maxdiff-2 colour change swung the
impact-anchored speed 18.7 → 15.6; a ball-independent plane removes that failure mode.

## Method
Known `K` (focal `f`, principal point = image centre) + lane-direction VP `vpL` (lane edges) + a cross-lane
direction VP `vpC` + width 41.5 in → the plane. Any pixel → lane coords (Z ft down-lane, X in across); speed =
slope of metric-Z(t), **no impact anchor**. Two ways to get `vpC`:
- **(A) two cross-lines** (foul line + a far cross-line — the 15 ft arrows, or the pin-deck row read off the
  lane edges at the detected head-pin row): `vpC = foul × far`. **Preferred.**
- **(B) single foul line + f** via orthogonality `(K⁻¹vpC)·(K⁻¹vpL)=0`: fragile, avoid.

## Validated (synthetic ground truth — `ops/metric_lane_plane.py` self-test)
Recovers known Z **exactly** (max error 0.000 ft) across focal 1100–2400 px and pitch 12–25°. The solver is
correct. Single-foul-line mode (B) shows sign flips / divide-by-zero → not usable.

## Real clips IMG_8751–54 (foul + detected pin-deck cross-lines; impact anchor + labels for reference)
| clip | truth avg | impact_v | metric early @ correct f | err vs truth | f*(pin-deck=60ft) |
|------|-----------|----------|--------------------------|--------------|-------------------|
| 8751 | 17.87 | 18.41 | 18.10 | +0.23 | 2897 |
| 8752 | 18.00 | 17.87 | 18.38 | +0.38 | 2904 |
| 8753 | 18.27 | 18.68 | 17.94 | −0.33 | 2261 |
| 8754 | 17.36 | 18.10 | 17.62 | +0.26 | 2899 |

**MAE vs truth ≈ 0.30 mph** when the focal is correct — comparable to the impact anchor, and ball-independent.

## Observability & sensitivity (the catch)
- **Ill-conditioned on this mounted down-lane POV.** The foul line and the far cross-line are *near-parallel in
  the image* (tiny vertical baseline), so their intersection `vpC` is far off and nearly collinear with the lane
  VP: `cos_img` = 0.71–0.98 (→1 is degenerate). The depth scale is therefore **poorly observable** and rides on
  the focal length.
- **Focal dominates:** ±15 % `f` → ±~16 % speed. An assumed `f` = 1594 px gives a 0.57–0.70× scale (badly wrong,
  ~10–12 mph). The self-consistent focal (pin deck reads 60 ft) is ≈2900 px for 3/4 clips (8753, the most
  ill-conditioned, wants 2261) — i.e. these clips are a narrow/tele down-lane framing.
- **Pixel-robust:** ±2 px on the foul/pin-deck rows → ≈0 change. So the risk is the focal, not line localisation.

## Implications for the iOS port (DEC-117 item 2)
1. Build on this geometry, but feed **AVFoundation's exact per-frame intrinsic matrix** (enable intrinsic-matrix
   delivery / `AVCameraCalibrationData`) — that removes the focal unknown that makes the Python prototype
   unreliable here.
2. Use **two cross-lines** (foul + pin-deck or 15 ft arrows) for `vpC`; never the single foul line or an assumed
   focal.
3. This POV is focal-dominated; a slightly **wider framing** (more vertical separation between the foul and the
   far line) materially improves conditioning — worth a capture-guidance note.
4. Keep the impact anchor as the **server shadow** reference; promote the metric plane only once on-device
   intrinsics + a far cross-line clear the DEC-117 gate (speed within 0.3 mph of truth).
