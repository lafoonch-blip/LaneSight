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

- **3b DONE.** Form labeling packet at `03_ENGINEERING/form_labeling_packet/` (contact sheets for IMG_8824 side + IMG_8846 rear + README). Verified form-clip times map to original frames (no form trim) + 8824 is clearly a SIDE view (classifier wrong). ~10 min for Shayne to label → unblocks the gate fix + numeric form validation.
- **4 DONE (no regressions).** Durable jobs verified LIVE on `revrate`: analysis_job has 7 done + 9 failed rows from tonight's uploads; cross-instance `GET /jobs/:id` resolves (job 8aab7a0d → done, correct shot_id). 396 unit tests pass incl. durable-job cross-instance/failure-durability/best-effort-persist + resume. Client background/kill-relaunch resume is unit-tested + builds; a live UI kill/relaunch test needs automation (not done autonomously), but the server durability that enables recovery is confirmed.
- **5 DONE (characterization, report-only — no build/promote).** Ran the mounted down-lane POV reference clips: IMG_8929 → `TRACK_TOO_SPARSE_FOR_SPEED` with **on_lane_pts=1, track_first=last=56.29 ft** (the ball is detected at ONE point, near the pins; the whole release→~56 ft roll is missed). IMG_8930 → `BALL_TRACK_NOT_FOUND`. **Reframe:** the frontier here is NOT back-half tracking — it's early/mid-lane ball ISOLATION on this POV (the detector/window locks onto the bowler + ball return; the rolling ball isn't isolated from release through ~56 ft). Next-session direction: improve near/mid-lane ball detection/isolation on the mounted POV (then the existing linker can connect it), DEC-094 shadow. Nothing changed/promoted.

## Morning report

**Live:** `lanesight-api-revrate` (unchanged — no server deploy needed tonight; all new code is shadow-gated or docs/tests). dev-build-v0 pushed through commit at wrap.

**What changed tonight:**
- Pin anchor: wired the DEC-065 pose solver (finding: ill-conditioned on this POV; planar retained) + shadow harness; **DEC-112** records it's shadow-only, not promoted.
- Ball upload→shot card verified end-to-end in the app (Release speed 16.0 + Rev 412 + honest unavailable states); APP_DESIGN 2026-10-29-A marked BUILT (C verify).
- Form root-caused (DEC-095 gate bug) + a labeling packet built. View-classifier bug noted.
- Durable jobs re-verified live; no regressions.

**Pin anchor vs 60 ft truth (both anchors, per clip)** — truth = track-crossing 60 ft/Δt (offset-invariant; NOT visually frame-confirmed, see below):
| Clip | Truth | impact err | pin err |
|---|---|---|---|
| 8751 | 18.03 | 0.03 | 0.17 |
| 8752 | 18.24 | 0.47 | 0.10 |
| 8753 | 18.17 | 0.15 | 0.15 |
| 8754 | 17.54 | 0.07 | 0.14 |
Pin ties/beats on 2/4 (8752, 8753) → fails the "all 4" gate → NOT promoted. Pose solver worse (ill-conditioned).

**What I need from you (shortest first):**
1. **Form event labels (~10 min):** `03_ENGINEERING/form_labeling_packet/` — mark ball_start/backswing_top/release/slide_stop/finish_hold_end on the 2 contact sheets → unblocks the form gate fix + form results.
2. **Pin anchor truth labels:** confirm foul_cross/first_pin_contact on IMG_8751–54 (I'm blocked by the trim/stabilization time offset) → decides pin-anchor promotion.
3. **Decision:** want the other 4 form clips' sheets too? And should I fix the view classifier (8824 side→down_lane misread) now or after labels?

**Known not-done:** form RESULTS in-app (blocked on the gate fix, which needs #1). Item 5 (back-half tracking) was characterized not built — and it's really an early/mid-lane ball-isolation problem on the mounted POV (IMG_8929: 1 ball point at 56 ft; the whole roll is missed), a focused next-session CV experiment.

**Morning-goal status:** Upload → **speed ✓ + rev ✓** (ball shot verified in the app: Release speed 16.0 mph, Rev rate 412 rpm, honest unavailable states) + **form = honest reason, not results yet** (gate bug root-caused; results unblock once you label — #1). Pin anchor: validated and **clearly reported not-ready** (shadow, DEC-112). Nothing unvalidated reached baselines/score/coaching; live rev unchanged (`revrate`).
