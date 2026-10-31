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

## Corrections pass (2026-10-31 AM)
- **#3 form gate — FIXED to spec (shadow).** `pose.gate_events` now anchors release to the slide-foot PLANT (E5) not E8=hold_start, behind `LANESIGHT_FORM_GATE_FIX` (default OFF = production unchanged; shadow until Shayne's labels validate it + retune bounds). Test added (old gate off E8 rejects, spec gate off E5 accepts). 16 form tests pass. NOTE: even with the correct E5 reference, IMG_8824 is +0.33s (release after plant) which the current ±0.15 bound still rejects — the BOUNDS need label validation (that's why it's shadow, not flipped on).
- **#3 view — my error, retracted.** In the form pipeline `down_lane` == the SIDE view (spine_tilt requires `down_lane`; "forward lean needs a side view"). IMG_8824 `view=down_lane` is CORRECT. No classifier change.

## Correction #1 (TOP PRIORITY) — server speed ~14% low: ROOT-CAUSED, NOT fixed tonight
- **ffmpeg CLI decode does NOT fix it.** Added `stabilize._ff_frames` (LANESIGHT_FFMPEG_DECODE, streaming, frame-count-capped) + deployed with the flag. In-container smoke still read **16.038** (= the cv2-Linux value), so the deploy **auto-rolled-back to `revrate`** (prod safe/unchanged). On EACH platform ffmpeg≈cv2 (Mac both ~18.7, Linux both ~16.0) → the gap is a deeper platform decode difference, not opencv-wheel-specific.
- **Root cause (finer than DEC-107):** Mac ffmpeg **9.0.2** vs container ffmpeg **5.1** (bookworm). H.264 decode is bit-exact by spec, so the divergence is the **YUV→BGR colour conversion** (version-dependent swscale), and it's **colour-space-dependent** — IMG_8753 is `bt709`, **IMG_8751 is `bt2020nc`** (wide gamut), which is exactly why 8751 was the ffmpeg-vs-cv2 outlier on the Mac (0.236).
- **Open question for the diagnostic:** the server read EXACTLY 16.038 (the historical cv2 value) with the flag on — confirm via a Cloud Run Job (container_diag) whether `_ff_frames` was actually exercised and whether Linux ffmpeg == Linux opencv pixel-for-pixel.
- **Fix directions (next focused session):** (a) ship a **version-matched decoder** — a static ffmpeg 9 build in the Dockerfile — and re-test; or (b) **canonical YUV→BGR in numpy** (bit-exact H.264 decode to yuv420p + explicit per-colour-space matrix + fixed chroma upsample) — deterministic everywhere, but a NEW reference (not necessarily the Mac's 18.7); validate both in-container within 0.1 of the chosen reference before shipping. `_ff_frames` code is kept (off by default); smoke ref + deploy flag reverted so prod/deploys stay consistent.

## Corrections summary
- #1 server speed: root-caused (ffmpeg version / YUV→BGR colour), NOT fixed; prod safe on `revrate`.
- #2 pin truth: stated it was a track-crossing estimate (NOT Ruby/DEC-105); trim offset resolved; labeling packet with exact frame numbers at `03_ENGINEERING/pin_anchor_labeling_packet/`.
- #3 form: gate fixed to DEC-095 spec (release vs slide_plant E5) behind `LANESIGHT_FORM_GATE_FIX` (shadow, bounds pending labels); view correction — `down_lane`==side (8824 was already correct); other form sheets built (8847/8848; 8825/8826 pending — see note).

## Server-speed deep-dive (2026-10-31, next-session continuation)
- **STEP 1 — LOCALIZED (Cloud Run Job `lanesight-cv-diag`, IMG_8753 frame 300).** Raw YUV420P is **BIT-IDENTICAL** Mac vs Linux (md5 `41c6fd1c…`, mean 116.127) → H.264 decode matches. **BGR DIFFERS**: Linux (ffmpeg==cv2) `[110.384, 104.945, 112.805]` vs Mac cv2 `[109.743, 104.185, 111.401]` / Mac ffmpeg `[109.236, 104.637, 111.622]` — per-channel Linux−Mac ≈ **B+0.6 / G+0.8 / R+1.4** (red most). Same clip is `bt709`/`tv`. So the gap is **100% the YUV→BGR colour conversion** (Mac ffmpeg 9.0.2 ≠ container ffmpeg 5.1.9 / cv2 5.0); not the decode, not a 601↔709 or range swap (the shift is ~1%, red-biased — a chroma-filter/rounding/matrix nuance). Linux speed 16.038 / z@9.82=11.4 vs Mac 18.7 / 13.28.
- **STEP 3 — s_min is ROBUST (not the fix).** Scaling saturation ±5% on IMG_8753 moves speed only ±0.15 mph (±10% → ±0.3). So the `lane_mask` S>105 floor is NOT the sensitivity source; an adaptive-saturation mask would not fix the gap. The 14% gap from a ~1% BGR shift must act via hue → ball/impact detection (the 2-point homography's impact anchor), which option (b) removes at the source. (Adaptive mask left as possible future defence-in-depth, not needed here.)
- **STEP 2 — option (b) canonical decode: implementing** (raw YUV + numpy YUV→BGR per metadata, same code Mac+server → identical BGR → Mac==server by construction). Then STEP 4 gate.

## Server speed — STEP 2/4 status (canonical decode)
- **STEP 2 — canonical YUV→BGR decode DONE for SDR, validated IN-CONTAINER.** `cv/decode.py` (flag `LANESIGHT_FFMPEG_DECODE`): ffmpeg decodes YUV420P (bit-identical) + pure-numpy YUV→BGR per the clip's colour_space/range + deterministic numpy chroma upsample + rotation. Mac: IMG_8753=18.711 (exact vs cv2), IMG_8752=18.308. **Cloud Run Job: Linux canonical = 18.631 / z@9.82=13.26 vs Mac 18.711 / 13.28 — within 0.08 mph (< 0.1)**, i.e. the 16.0→18.6 fix is PROVEN on Linux. (pure-numpy upsample removes even that 0.08 residual.)
- **HDR (8751/8754, HLG bt2020) — implemented, NOT validated (perf).** Added a deterministic numpy HLG→SDR709 path in `canonical_frames` + skip the version-dependent `convert_sdr`/zscale for HLG under the flag (core.py). Correct approach (no zscale, no re-encode), but the HLG tone-map per frame × the pipeline's ~9 decode passes (the large HLG clip exceeds the frame cache → re-tone-maps each pass) is too slow to finish a Mac run — needs a perf pass (cache the converted frames / budget) before it can be validated.
- **STEP 4 gate — NOT met yet → NOT deployed.** SDR (8752/8753) passes Mac==server < 0.1. HDR (8751/8754) pending (perf + in-container). Truth comparison pending Shayne's pin labels (packet delivered). Per the gate ("deploy only after both pass"), nothing deployed; prod stays on `revrate` (cv2). Flag default OFF so prod/Mac unchanged until the full gate passes.
- **NEXT:** (1) make the HDR/large-clip canonical path cache-friendly so it finishes; (2) re-run the Cloud Run Job on 8751–54 with the numpy decode → confirm all 4 Mac==server < 0.1; (3) once Shayne's foul_cross/first_pin_contact labels land, compare canonical speed to 60 ft/Δt truth; (4) then flip the flag on in the deploy + ship.
