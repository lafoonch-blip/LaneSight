# Overnight run — 2026-10-30/31 (autonomous)

Started 2026-10-30 23:29 EDT. Live rev at start: `lanesight-api-revrate`. Next free DEC: 112. DECISIONS v1.69.

Goal by morning: upload a clip in the app → see speed + rev + form, all honest; pin anchor validated or clearly reported not-ready.

## Progress log (newest at bottom)

- **Setup** — created this file; latest DEC=111 (next 112); live rev `lanesight-api-revrate`.
- **1a DONE (finding: pose solver NOT usable here).** Wired DEC-065 pose solver into `pins_anchor.pin_pose_anchor` (detect 7 pin body centroids → foul+pins LandmarkSet → fit_focal → plane_homography). Result: ILL-CONDITIONED on IMG_8751-54 — reproj 3.6–6.4 px (gate 4), focal 2155–2935 (should be a constant), pin_height 0–20 in (should be ~15), head depth 67–126 ft (worse than planar). Cause: foul+pins near-coplanar + far (pose.py's documented planar-PnP ambiguity). **Planar `detect_pin_anchor` retained** (head depth, impact frame): 8751=61.3, 8752=58.4, 8753=62.7, 8754=61.7 ft (vs impact's 60). The ≤2.7 ft disagreement is adjudicated by ground truth → 1b. Pose code kept as a documented harness. 396 tests pass.

## Queue status
1a. Pin anchor + DEC-065 pose solver — IN PROGRESS
1b. Ground truth labels (foul_cross, first_pin_contact) on IMG_8751-54 — pending
1c. Compare both anchors vs truth; promote pin if ties/beats on all 4 — pending
2.  Upload → results in app (shot + form) — pending
3.  Form deferred fixes + labeling packet — pending
4.  Durable-jobs reliability tests vs live — pending
5.  Back-half ball tracking shadow (if time) — pending

## Morning report
(filled at end)
