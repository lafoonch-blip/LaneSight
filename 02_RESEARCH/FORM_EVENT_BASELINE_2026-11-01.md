# Form event baseline + remaining-gap root causes (2026-11-01)
Status: WORKING NOTES
Version: 1.5
Last Updated: 2026-11-02
Owner: Shayne (author: autonomous session)
Scope: DEC-118 Form MVP metrics measured against Shayne's form labels; DEC-120 slide-stop fix; and the
root causes of the three remaining gaps (step count, E2 ball-start, IMG_8826 mis-segmentation).

Ground truth: `lanesight-core/validation/form_labels.json` (6 clips: IMG_8824–26 side, IMG_8846–48 rear).
Harness: `lanesight-core/examples/form_baseline.py` (scores the Python engine vs the labels in frames).
All step counts are 5. The labels carry swing-event TIMES (E2/E4/E5/E7/E8) + the step COUNT (no per-step times).

## 1. Baseline + the shipped fix (DEC-120)
Before: swing events E2/E4/E7 nulled on all 6; E8 "slide stop" 23–86 frames late (median 56, 0/6 within ±2);
step count exact 0/6. Root cause of the nulls: E8 was `hold_start` (the posted-finish start, 0.4–1.0 s after
the real slide stop), so the event gate saw a false gap at release and dropped every event.

Fix (shipped): a slide-stop detector (slide foot settling after its slide peak, anchored on the bottom of the
swing arc E6), a release clamp, and the gate re-anchored on the corrected E8 (DEC-095 shadow flag retired).

After, vs labels (±2 frames = pass):

| Clip | View | E4 back | E7 release | E8 slide-stop | Steps (GT 5) |
|---|---|---|---|---|---|
| 8846 | rear | −1 ✓ | +1 ✓ | +1 ✓ | 3 |
| 8847 | rear | 0 ✓ | 0 ✓ | −2 ✓ | 4 |
| 8848 | rear | −2 ✓ | +1 ✓ | +1 ✓ | 4 |
| 8824 | side | −1 ✓ | +3 | −5 | 3 |
| 8825 | side | −2 ✓ | −1 ✓ | −1 ✓ | 4 |
| 8826 | side | null | null | +38 | 6 |

Swing events surface on 5/6 (was 0/6); rear E4/E7/E8 all within ±2 f; E8 median 56→2 f. E2 still null on all 6.

## 2. Remaining gaps — root causes (investigated, NOT fixed; a fix on 6 clips would overfit / regress honesty)

### 2a. Step count — 0/6 exact (under-counts)
Detector: `_foot_strikes` → `_local_minima` on the combined foot speed max(Rs,Ls); a plant = a trough (both
feet briefly slow). Two independent problems:
- **Window clips early steps (leading, fixable cause).** The step search starts at `b0−0.25` = approach-window
  start + 0.15, which lands AFTER the labeled ball start (E2) on all 6 clips, so the first 1–2 approach steps
  are outside the window. (Burst onset `b0` is detected late because the first step is gentle / below
  BURST_MOTION.)
- **The combined-speed signal is unreliable for counting on this data.** Extending the window does not give a
  clean 5 because: (i) on IMG_8825 the early steps register `comb≈0.0` — indistinguishable from standing still
  (small/far feet → near-zero pose foot velocity); (ii) IMG_8846 is 30 fps and shows only 4 troughs for 5 real
  steps; (iii) IMG_8824/8825 produce extra `comb=0` stance dips; (iv) IMG_8826 is mis-segmented (see 2c). A
  position-staircase counter (per-foot forward advance) was prototyped and merged steps (2–4), no better.
- **No per-step ground truth.** The labels have only the step COUNT, so any window/threshold tuned to hit 5 on
  these 6 clips cannot be distinguished from overfitting and would not be a real validation.

**Update 2026-11-01 (structural window fix SHIPPED):** cause (a) is now fixed — `_setup_hold_end` anchors the
step search at the end of the setup stance (where step 1 breaks the stillness) instead of `b0−0.25`, so steps
1–2 are no longer structurally excluded. Step counts after, vs GT 5: **8824 5 (EXACT, was 3)**, 8825 3, 8826 6,
8846 3, 8847 4, 8848 6 → **1/6 exact (was 0/6)**; swing events E4/E7/E8 unchanged. The residual over/under-counts
are cause (b) — the combined-foot-speed signal — which needs per-step truth to fix without overfitting.

- **Next (item 3, gated on labels):** the `form_steps` labeler task (per-plant times for the 6 clips + IMG_8980,
  with detector hints) is now in `validation/label_tasks/form_steps.json` → exports `form_steps_labels.json`.
  Once labeled, fix the foot-strike detector against per-plant truth (gate: every plant ±2 frames, count exact),
  likely a per-foot forward-position staircase (robust to the comb≈0 dropouts). Hold out IMG_8980 + future clips.

**Update 2026-11-01 (per-plant labels landed; detector investigated, NOT yet at gate).** Shayne labeled every
plant (`validation/form_steps_labels.json`): ALL approaches are 5 steps (no 6-step data); some early plants are
off-frame → `null` (not scored), so the visible-plant count per clip is 8824:4, 8825:5, 8826:5, 8846:5, 8847:5,
8848:5, 8980(held-out):3. Scoring harness: `examples/form_steps_baseline.py`.
- **Root cause of the old detector found:** `_foot_strikes` used minima of the COMBINED `max(Rs,Ls)` — the
  double-support moments BETWEEN plants, offset ~5 f early — not per-foot plants. A plant is one foot's own
  speed dipping (foot at rest) while the other swings; plants alternate L,R,L,R,L. Direct inspection of 8847
  confirms each labeled plant sits at a per-foot swing→stance transition.
- **Three detectors tried vs per-plant truth** (combined-min; per-foot speed minima; per-foot position
  staircase). Best was per-foot speed minima, but it still lands **2–9 frames off on multiple plants** and the
  count is unstable (spurious dips split/merge steps): within ±2 f ≈ 0–3 of 5 per clip; held-out 8980 1/3.
- **Why it's hard:** on this footage the MediaPipe foot landmarks jitter ±3–6 frames and the labeled contact
  instant doesn't crisply align with any single feature (speed-min lands after contact; plateau-start before;
  the offset isn't constant across clips). Side-view / far / small feet and 30 fps (8846) are worst.
- **NOT shipped:** a detector still 5–9 f off on half the plants would not meet the ±2 f gate and could regress
  the current counts — shipping it would violate accuracy-over-coverage. Kept the structural window fix only.
- **Recommended path:** (1) higher-fidelity foot localization — crop each foot region and refine the contact
  frame (sub-landmark), or a dedicated foot-contact signal — then re-fit the per-foot model; (2) or accept a
  realistic ±3–4 f plant gate for phone pose and re-score; (3) more clips (incl. IMG_8980 held out) before
  committing a change. The per-plant labels + harness are in the repo so this continues cleanly next session.

**Update 2026-11-01 (per-foot STANCE detector built + the bottleneck pinned to landmark confidence).** Built the
correct model — per-foot forward-position STANCE (plateau) detection: each foot advances then holds; a plant =
the hold onset; plants alternate; the last plant ≈ slide_stop (already detected ±2 f). Scored vs per-plant truth
(`plant_v3`, tuned on the 6, IMG_8980 held out): still only **1–3 of 5 plants within ±2 f**, count off by ±1–2,
errors 2–9 f (worst on the first plant at the setup→approach boundary and on side view). Held-out 8980: 1/3.
- **Bottleneck = foot-landmark confidence, measured:** during the approach the MediaPipe foot landmarks
  (ankle/heel/foot, both feet) average **rear ≈0.80, side 8824 ≈0.84 (min 0.19), side 8825 ≈0.53 with 43% of
  frames <0.5 (min 0.01)**. The side-view / far / small feet jitter ±3–6 f, so no per-foot feature (speed-min,
  plateau-onset) aligns to the labeled contact within ±2 f consistently — and the offset isn't constant, so it
  can't be calibrated out. Four models (combined-min, per-foot-min, position-staircase, per-foot-stance) all
  plateau here → it's a signal floor, not an algorithm choice.
- **Decision: NOT shipped.** A detector 2–9 f off on half the plants fails its own ±2 f gate and would regress
  the current counts (accuracy-over-coverage, DEC-026/094). The step-count structural window fix (DEC-120) is
  the only shipped change. Concrete next step for Shayne to choose: (a) invest in foot-region crop+refine to
  raise landmark confidence (the only path to a true ±2 f gate on side view), or (b) adopt a ±3–4 f plant gate +
  rear-view-only step count for MVP. Either way, hold out IMG_8980 + new clips.

**Update 2026-11-02 (option 1 — foot-crop refine — BUILT, TESTED; confidence up, accuracy flat → not shipped).**
Re-ran pose on an upscaled person-bbox crop (original full-res frame) over the approach window, mapped the
refined foot landmarks back, and re-scored per-foot stance plants. Harness: `examples/foot_refine.py`. Per clip,
foot-landmark confidence (approach window) BEFORE → AFTER, and plants within ±3 f BEFORE → AFTER:

| clip | view | conf before→after | ±3f before→after | count det vs visible |
|---|---|---|---|---|
| 8824 | side | 0.77 → 0.86 | 2/4 → 2/4 | 6 vs 4 |
| 8825 | side | 0.72 → 0.82 | 2/5 → 2/5 | 4 vs 5 |
| 8826 | side | 0.74 → 0.84 | 3/5 → 3/5 | 5 vs 5 |
| 8846 | rear | 0.82 → 0.85 | 2/5 → 2/5 | 4 vs 5 |
| 8847 | rear | 0.81 → 0.84 | 3/5 → 3/5 | 5 vs 5 |
| 8848 | rear | 0.85 → 0.89 | 3/5 → 3/5 | 6 vs 5 |
| 8980 | side, **HELD OUT** | 0.46 → 0.61 | 1/3 → 1/3 | 4 vs 3 |

**Confidence rose on every clip (incl. side view and held-out 8980) but ±3 f accuracy and count did NOT move.**
So landmark confidence was NOT the bottleneck — the labeled foot-contact instant is not recoverable from the
foot position/velocity trace regardless of landmark quality (plateau-onset vs contact offset, genuine blur
ambiguity). Crop-refine is therefore **not shipped** (runtime cost of a second pose pass, no metric gain).
- **Gates recorded as DEC-121** (amends DEC-118): step COUNT exact; swing events ±2 f; per-plant timing ±3 f
  (approach-duration/tempo only). **Step count shipped `best_effort`** (not `ok`) with a reason — it is ±1–2 and
  not yet validated to exact on either view (DEC-026/094: no false-confident number).
- **Capture (DEC-121):** Form recording floored at 60 fps (120 when supported at ≥1080p) + an on-screen "keep
  both feet in frame" tip, so a future attempt has the frame rate and framing it needs. iOS needs an Xcode build.
- **The real fix is a different foot-contact signal** (not whole-frame pose landmarks), validated per-plant with
  IMG_8980 + new clips held out — not more tuning of the pose-landmark detector.

### 2b. E2 ball start — null on all 6
- The bowling-wrist landmark (the current E2 cue) **does not move at the labeled pushaway onset** — its y is flat
  for 9–21 frames past E2 on every clip (the pushaway is a two-handed ball push the wrist landmark doesn't
  register). So E2 is a missing-signal problem, not a threshold tweak; and the gate's ball-start→release
  duration check then drops the late E2.
- **Ball-blob cue (tested, partially promising).** Tracking the ball blob from before E2 works on a CLEAN track
  (IMG_8847: motion onset −1 frame vs label) but the early ball association is jittery on the others, so a
  displacement-onset threshold fires 13–47 frames EARLY on blob noise (8824 −44, 8848 −47, 8846 −13, 8825 −23).
  Shipping it now would replace an honest `null` with a wrong-by-10-47-frame value (DEC-026/094 regression).
- **Fix path:** a robust setup-phase ball tracker (better seeding/association near the body) + a
  sustained-monotonic displacement onset (not a single threshold crossing), confidence-gated so it stays `null`
  when the track is not clean. Validate on more clips incl. IMG_8980.

### 2c. IMG_8826 mis-segmentation — events ~0.9–1.3 s late
- The wrist-y arc is low-amplitude and has a SECOND up-down hump at 17.9–18.9 s (post-release arm motion). The
  swing window runs to `hold_start+0.3 = 19.35 s` — ~1.8 s past the true release (17.57) — because the bowler
  isn't "both feet still" until 19.05 s. The `_swing_events` "deepest late minimum = follow-through" heuristic
  then anchors on the 18.9 s hump, cascading E4/E6/E7 late. (The true apex at 17.17 IS a local min — just not
  selected.) Same family as the old slide-stop bug: an over-wide post-release window confuses a downstream
  detector.
- **Fix path:** end the swing window near the delivery (e.g. at the slide-foot settle / first clear
  both-feet-slow after the backswing) rather than at `hold_start+0.3`; or constrain the backswing-apex→bottom
  sequence to a plausible downswing duration. Validate on more clips so a change doesn't regress the 5 clips
  that already work.

## 3. IMG_8980 (held-out)
Added to the labeler `form_events` task (side view), pending Shayne's labels — it was NOT used to tune anything.
Once labeled, `python examples/form_baseline.py` scores it automatically (the harness reads `form_labels.json`
and resolves the clip from `~/LaneSightData/.../11:1 Shots/`). Engine on 8980 today: side view, E4/E7/E8 surface,
E2 null, step count 14 (over-counts — multiple deliveries / walking in that clip; labels will confirm).

## 4. Periodic whole-body step COUNT — tried (hip / knee / thigh), does NOT pass; Form work paused (2026-11-02)
Per Shayne's direction, prototyped step COUNT from a periodic whole-body cue counted between setup-hold-end and
slide-stop (`examples/form_step_count_cues.py`), instead of locating individual foot plants. Cues tried: pelvis
(hip) vertical bounce, knee vertical bounce, knee forward-swing (thigh), and thigh angle (hip→knee), plus
shoulder as a cross-check. Shayne's note that the thigh moves more than the hips and stays visible when the foot
doesn't is correct — but it didn't rescue the count.

Counts vs GT 5 (IMG_8980 held out):

| clip | hip-y | knee-y | knee-fwd | thigh-angle (L+R) |
|---|---|---|---|---|
| 8824 | 5 | 4 | 4 | 8 |
| 8825 | 3 | 3 | 3 | 5 |
| 8826 | 3 | 4 | 4 | 5 |
| 8846 | 4 | 4 | 3 | 7 |
| 8847 | 4 | 4 | 4 | 7 |
| 8848 | 6 | 6 | 6 | 8 |
| 8980* | 4 | 2 | 2 | 8 |

**No cue gives exactly 5 on all 7 (counts range 2–8).** Why: a bowling approach is NOT steady-state periodic
gait — it is 4–5 ACCELERATING steps ending in a glide/slide. The early steps glide with sub-1-cycle-per-step
vertical bounce (hip oscillates ~0.6–0.8 cycle/step: on 8847 only ~3 hip-high minima across 5 steps), the slide
adds no clean bounce, and phone-pose lower-body landmarks are noisy. The thigh angle has more amplitude but is
noisy per leg (each leg should swing 3/2 times for an L-start 5-step; it over-counts). So periodic counting
over/under-shoots per clip.

**Decision: NOT shipped (gate not met), and per Shayne, STOP here.** Step count stays `best_effort` (DEC-121);
no periodic-cue detector added. `examples/form_step_count_cues.py` keeps the negative result reproducible.

**Form work is PAUSED** pending **10–15 new 60 fps form deliveries (side + rear)** from Shayne. Those plus
IMG_8980 are the held-out validation set; nothing gets tuned on them until they exist. The likely real fix needs
either higher-fps, better-framed capture (so the gait signal is cleaner) or a dedicated foot-contact signal —
decided after the new clips are in hand.

**iOS capture change needs a device build (Session 1 TODO).** DEC-121's Form capture defaults — floor Form
recording at 60 fps (120 if supported at ≥1080p) and the "keep both feet in frame through your whole approach"
tip — are code-complete in `ios/LaneSight/Sources/Capture/CaptureView.swift` but were written here without an
Xcode build. They must be built + verified on a device before relying on them (and before the new-clip capture).
