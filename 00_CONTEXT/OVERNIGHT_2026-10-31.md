# Overnight run — 2026-10-30/31 (autonomous)

Started 2026-10-30 23:29 EDT. Live rev at start: `lanesight-api-revrate`. Next free DEC: 112. DECISIONS v1.69.

Goal by morning: upload a clip in the app → see speed + rev + form, all honest; pin anchor validated or clearly reported not-ready.

## Progress log (newest at bottom)

- **Setup** — created this file; latest DEC=111 (next 112); live rev `lanesight-api-revrate`.
- **1a DONE (finding: pose solver NOT usable here).** Wired DEC-065 pose solver into `pins_anchor.pin_pose_anchor` (detect 7 pin body centroids → foul+pins LandmarkSet → fit_focal → plane_homography). Result: ILL-CONDITIONED on IMG_8751-54 — reproj 3.6–6.4 px (gate 4), focal 2155–2935 (should be a constant), pin_height 0–20 in (should be ~15), head depth 67–126 ft (worse than planar). Cause: foul+pins near-coplanar + far (pose.py's documented planar-PnP ambiguity). **Planar `detect_pin_anchor` retained** (head depth, impact frame): 8751=61.3, 8752=58.4, 8753=62.7, 8754=61.7 ft (vs impact's 60). The ≤2.7 ft disagreement is adjudicated by ground truth → 1b. Pose code kept as a documented harness. 396 tests pass.

- **1b/1c DONE (pin NOT promoted; labels BLOCKED).** Ground-truth 60 ft via track image-crossings (offset-invariant Δt): TRUTH 18.03/18.24/18.17/17.54. Anchor errors vs truth — impact 0.03/0.47/0.15/0.07, pin 0.17/0.10/0.15/0.14. Pin ties/beats on 2/4 (8752,8753), impact better on 8751/8754 → fails the "all 4" gate → NOT promoted (DEC-112). VISUAL labeling BLOCKED: trim/stabilization shifts track time off original clip time (at track t_imp the original still shows standing pins), so I can't map events to original frames autonomously → foul_cross/first_pin_contact labels need Shayne (or a pins-scatter frame-diff pass). DEC-112 recorded, v1.70. Pin anchor stays shadow; nothing deployed.

- **2a/2c BALL shot DONE.** App builds + installed on sim. Uploaded IMG_8753 to live API (shot 5ff7a596…) → previewed the shot card via the DEBUG harness: renders **Release speed 16.0 mph**, **Rev rate 412 rpm**, Accuracy "Set a target", LANE & PINS all "Not read", far-lane banner, no fabricated numbers. Matches design `shot_card_state_far_lane_not_read.png` (diffs are data-state only). Marked APP_DESIGN_CHANGES 2026-10-29-A **BUILT** (C verify done). FORM shot (IMG_8846) FAILED `FORM_DELIVERY_NOT_ISOLATED` (DEC-095 gate) — friendly copy exists ("We couldn't find your whole delivery"). Sweeping other form clips to find one that isolates → 2b.

## Queue status
1a/1b/1c. Pin anchor — DONE (shadow, not promoted; labels blocked on Shayne). See DEC-112.
- **2b/3a form root cause (found; fix deferred pending labels).** All form clips fail DEC-095 because the gate (`pose.py:586`, `RELEASE_VS_STOP`) compares release (E7) to **E8=hold_start** (posted-finish start, ~5.33s) while the code comment + physics say release ≈ **slide_plant** (~4.11s). The 0.67-0.88s false gap drops every event. Candidate fix: gate release vs slide_plant — BUT it's a user-facing form gate, so NOT changed without ground truth. Also 8824 (side) misclassified view=down_lane. Both need Shayne's event labels → packet (3b). Form RESULTS stay blocked; in-app shows the honest reason. Did NOT loosen the gate (honesty/DEC-094).

2a. Ball upload→card — DONE (verified). Form — fails DEC-095 isolation on all tested clips (8846 rear, 8824 side): E2 ball-start / E7 release NOT located, swing_time 1.035s < 1.3s gate → FORM_DELIVERY_NOT_ISOLATED (friendly reason shows in-app). 8847/8848 too big for direct multipart (413; app uses Storage upload). Minimum bar (clear reason) MET; form RESULTS blocked on the pose event detection → investigating (item 3a). Note: 8824 (side) detected view=down_lane (view-label issue, item 3a).
2.  Upload → results in app (shot + form) — pending
3.  Form deferred fixes + labeling packet — pending
4.  Durable-jobs reliability tests vs live — pending
5.  Back-half ball tracking shadow (if time) — pending

## Morning report
(filled at end)
