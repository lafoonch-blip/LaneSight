# CV Re-architecture — Claude Code response (Phase 0 deliverable)
Version: 1.1
Last Updated: 2026-10-25
Status: DEC-062 ACCEPTED. Gap analysis + plan; the additive Phase-1 harness (`cv/calib/`) has landed
(production path untouched). Responds to `~/Downloads/LaneSight_CV_Architecture_Claude_Code_Handoff.md`
(ChatGPT, v1.0) and subsumes the outbound brief `CV_METRICS_REARCHITECTURE_BRIEF.md`.

> Scope note (per CLAUDE.md "accuracy over coverage" and the handoff's own "DO NOW: analysis/design
> only"): this is the gap analysis, file-by-file stage map, Phase-1 plan, test plan, and first-PR
> scope the handoff asks for. It touches no `lanesight_core/cv/` code. The 203-test suite is green as
> of this writing; nothing here has been merged.

---

## 0. TL;DR for Shayne

The outside review is good and we should adopt its spine: **geometry-first calibration decoupled from
the ball, metric-level (not shot-level) gates with real uncertainty, and a staged ablation that proves
geometry before we spend a dollar on ML.** Grounding it in our actual 1,346-line `cv/` module changes
three things about *how* we take it:

1. **We're already ahead of two of its "root defects."** It assumes we project the ball *centroid* onto
   the lane plane — we don't; we use ball-top + expected-diameter → contact row (`track.contact_row`).
   And it recommends building an "independent pin-impact event detector" — we already have one
   (`track.detect_impact`, pin-motion based). So those line items are *refinements*, not rebuilds.
2. **The real single lever is the one thing we do entirely missing:** we detect **zero** downlane
   fiducials (no arrows, dots, or pin spots). Our homography is literally 4 points — the two foul-line
   corners plus a **synthetic far line placed through the ball's extrapolated impact position.** That is
   the circular dependency the review names, and it is the whole ballgame for the elevated/foreshortened
   failures. Phase 1 is: detect real downlane fiducials and solve a properly-constrained calibration,
   then measure (ablation B/C) whether correct geometry alone makes the failing clips measurable.
3. **Phase 1 needs ~1 day of your time for ground truth, not ML.** The gating experiment (Run C) needs
   hand-labeled landmarks + hand-labeled ball centers on the 17 clips. No model training until B/C say
   geometry is the fix. That's the stop/go the review (correctly) insists on.

Recommendation: ratify the plan as **DEC-062** and let me build the Phase-1 geometry-proof harness
(manual-landmark calibration + ablation runner + diagnostics) as the first PR. No production path
changes until the ablation reports.

---

## 1. File-by-file stage map (the handoff's assignment #2)

Current pipeline, with exact locations of the five things the review asks us to pin down. Orchestration
is `cv/pipeline.py::analyze`.

| # | Stage | File / symbol | What it does |
|---|-------|---------------|--------------|
| A | Decode + stabilize | `cv/stabilize.py::stabilize` | ORB+RANSAC per-frame homography to a chosen reference frame; builds a temporal-median empty-lane plate (`bg`). Returns `Hs` (per-frame warps), `ts`, `ref`, `bg`, `shift`. |
| B | Lane geometry | `cv/lanes.py::find_lanes` | HSV **saturated-wood** mask (`lane_mask`, s_min 105→70→50), per-row runs linked into edges, shared vanishing point; **gutter-edge RANSAC fallback** (`_gutter_fallback`) for pale lanes. Foul line = **near boundary of the wood mask** (`_foul`). |
| C | "Calibration" | `cv/metrics.py::lane_homography` | **4-point** `cv2.getPerspectiveTransform`: foul-line corners + a **synthetic far cross-line through the ball's extrapolated impact pixel** (`impact_anchor`). No intrinsics, no distortion, no real downlane anchor. |
| D | Ball detection | `cv/track.py::extract_blobs`,`candidates` | Background-difference + connected components in the warped ROI; size-gated by expected diameter at depth (`exp_diam`). Pure classical; no learned detector. |
| E | Association + impact | `cv/track.py::link`,`extend_back`,`extend_forward`,`detect_impact`,`touchdown` | RANSAC track in `u=1/(row−vp_y)`; back/forward extension for loft + far-lane recovery; **independent pin-motion impact detector**. |
| F | 3D-ish reconstruction | `cv/metrics.py::compute`, `cv/refine.py::refine` | Maps contact rows → lane plane via the homography; LOESS lateral path (`cv/smooth.py`); colour-model re-measurement of each point. |
| G | Metrics + gates | `cv/pipeline.py::analyze` + `far_lane_quality` | Builds `ShotRecord` metrics with per-metric `confidence`/`status`/`uncertainty`; **plausibility gate** (speed-rising / >3-board jump / off-lane) flags `capture_quality.far_lane="limited"`; hard `>30 mph` and `impact=None` failures. |

**The five pins the handoff asked for:**
- **Synthetic far-line calibration:** `metrics.py:15-26` (`lane_homography`, `Z_IMPACT=59.44`), seeded by
  `metrics.py:33-51` (`impact_anchor`) and `metrics.py:59-60`; a second copy for pins at `pipeline.py:109-111`.
- **HSV lane detection:** `lanes.py:6-11` (`lane_mask`) + `lanes.py:69-99`; foul line `lanes.py:208-231` (`_foul`).
- **Impact coupling:** detector `track.py:146-194` (`detect_impact`, independent/pin-motion — good); the
  coupling is that its **time+position feed the homography scale** (`pipeline.py:85-93`) and that
  `analyze` **hard-fails** when it returns `None` (`pipeline.py:86`).
- **Ball-height assumption:** `track.py:12-15` (`contact_row` = top + expected-diameter, **not** centroid-on-plane).
- **Metric gates:** `pipeline.py:25-49` (`far_lane_quality`), `pipeline.py:100-105` (>30 mph), per-metric
  status mutation `pipeline.py:159-163`.

---

## 2. Claim-by-claim vetting of the handoff

CONFIRMED = accurate for our code. NUANCE = partly right / our framing differs. ALREADY = we already do it.

| Handoff claim (§2 defects / recs) | Verdict | Grounding |
|---|---|---|
| Synthetic far anchor → circular calibration + scale bias | **CONFIRMED (top priority)** | `lane_homography` far line runs through `impact_px`; the 59.44 ft scale is literally the ball's own extrapolated endpoint. If the ball is lost early, the scale stretches — exactly the >30 mph / off-lane failures. |
| Near wood-mask boundary mistaken for foul line when approach wood present | **CONFIRMED** | `lanes.py` line 2 comment *assumes* "approach wood is paler, so the foul line is the mask's near boundary." IMG_8900/8908 break this (bare approach wood contiguous with lane) → "foul line not found / off bottom." |
| Sparse depth anchors leave projective distortion unconstrained | **CONFIRMED** | 2 distinct depths only (foul ≈ 0 ft, synthetic ≈ 59.44 ft). Zero mid-lane anchors. Elevated cameras (IMG_8893) crush 60 ft into a few hundred px → entry board 45. |
| Ball **centroid** treated as a point on the lane plane | **NUANCE — we're already better** | We use `contact_row(top)` = ball-top + expected diameter, and exclude airborne frames. It's still *image-space* (linear-D heuristic), not a calibrated ray–plane intersection at `Y=radius`, so §6 still applies — but it is not the naive centroid bug described. |
| Difference-based detection loses the far/blurred/dark ball | **CONFIRMED** | `extract_blobs` is bg-diff + CC. `extend_forward` is a band-aid (extrapolate + reattach). Learned detector (P1) targets exactly this. |
| Hard plausibility gates catch consequences, not causes | **CONFIRMED** | `far_lane_quality` + >30 mph fire *after* a bad homography. They prevent garbage advice (good) but can't produce a correct number. |
| "No dependence on pin impact to establish calibration" | **NUANCE — reframe the task** | Our impact *detector* is already independent (pin motion). The problem is narrower: impact **position** seeds the far anchor, and `analyze` **hard-fails** without impact. Fix = decouple scale from impact + make impact optional, **not** build a new detector. |
| Every metric needs provenance + uncertainty + independent gate | **NUANCE — partially ALREADY** | We carry per-metric `confidence`/`status`/`uncertainty`, but confidence is heuristic (e.g. `0.9 if release_source==...`), not a propagated 95% interval with empirical coverage. §8 upgrade is real. |
| Determinism / seeds / stable ordering (§12) | **ALREADY (partial)** | RANSAC is seeded (`np.random.default_rng(0)`, `seed=0`); per-stage pickles cache `stab`/`blobs`. Missing: the full per-shot audit artifact set + numeric tolerance spec. |
| Use real camera intrinsics / lens metadata (§5.2.1) | **CONFIRMED — we use none** | `getPerspectiveTransform` on 4 points; no K, no distortion. **Risk:** our on-device trim (`ios/.../VideoTrimmer`, passthrough) + stabilization warps may already strip/alter EXIF and bake per-frame pose into a 2D warp — must verify before planning PnP (open decision #2). |

**Net:** the review's architecture is right. Two of its six "root defects" are already mitigated in our
code, which means Phase 1 is *smaller* than the handoff implies — it concentrates almost entirely on
**downlane fiducial detection + properly-constrained calibration**, which is the one thing we do not do
at all.

---

## 3. Answers to the handoff's "open decisions" (§14) we can already close

1. **Is 59.4 ft a plane or an assumption?** Both, confusingly — and the handoff's §4 warning applies to us
   today. `Z_IMPACT=59.44` in `metrics.py` is defined as "60 ft − (4.30+2.38)/12" = the **ball center at
   first head-pin contact** (a predicted-contact reference). `entry_board` is reported there. But
   `entry_angle_52_55` uses a **fixed 52–55 ft plane**. So we already ship two different entry conventions;
   the geometry module must name them explicitly (`entry_board@contact` vs `entry_angle@52-55ft-plane`).
2. **Camera-motion definition (the "~14,000 px" clip):** `stabilize` computes, per frame,
   `shift_i = ‖ H_i·c − c ‖` for image center `c=(540,960)`, where `H_i` warps frame i → reference;
   `camera_motion_px = max_i shift_i`. **14,414 px on a 1080×1920 frame is not literal translation** — it
   is the **chained-fallback homography diverging** (`Hs[-1] @ Hp` compounding when ORB match count drops,
   the `inl<0` path). So IMG_8901 is a *stabilization failure*, not merely "a lot of motion"; treat it as a
   calibration-input-invalid case, not a motion threshold.
3. **Determinism:** already seeded; we can commit to fixed `cv2.setNumThreads` in the deterministic config
   and document decoder/GPU tolerance caveats (§12) — low cost.

Still genuinely open (need Shayne / data): iPhone intrinsic+distortion availability post-trim (#2);
authoritative arrow/dot/pin-spot coordinate template (#4, USBC spec edition); Ruby time/location
definitions for speed/rev (#5, see §6 below); storage/retention for raw frames+overlays (#8).

---

## 4. Phase 1 — Geometry proof (the only thing to build next)

**Goal (the review's Phase-1 gate):** prove whether *correct geometry alone* makes the 17 failing clips
physically measurable, and quantify far-lane coordinate sensitivity — **before** any model training.

New code, all **additive and off the production path** (new package `cv/calib/`, new CLI; existing
`analyze` untouched until the ablation reports):

1. **`cv/calib/lane_geometry.py` — canonical geometry module (handoff §4).** One versioned source of truth
   for lane length/width/board pitch, **individual arrow coordinates (longitudinally staggered — not a
   single Z=15 cross-line)**, dot rows, pin-spot coordinates, foul line, gutter edges, with units, a stated
   board-numbering + handedness convention, tolerances, and USBC citations. Pure data + tests; **no magic
   constants in algorithm code** (this replaces the scattered `LANE_IN/BOARDS/Z_IMPACT` literals).
2. **`cv/calib/landmarks.py` — manual landmark schema + overlay.** A typed schema for hand-labeled image
   points/lines per clip (`foul_l`, `foul_r`, `arrow_k`, `dot_k`, `pin_spot_k`, `gutter_l/r`), plus a
   render-overlay (observed vs reprojected). This is the input to Runs B/C and the eventual training target.
3. **`cv/calib/solve.py` — point+line robust calibration (handoff §5.2).** `findHomography(..., USAC...)`
   for the lane plane from ≥6 constraints over ≥3 longitudinal zones; where intrinsics are available,
   PnP/IPPE planar pose + `scipy.optimize.least_squares` point+line refinement with uncertainty-weighted
   residuals; **homography-only fallback when intrinsics are unknown** (do not free-optimize focal +
   distortion + pose from one flat frame — §5.2.6). Emits `calibration_diagnostics` (reprojection +
   held-out residuals, longitudinal/lateral spread, per-region Δboard/Δft sensitivity under ±1 px).
4. **`cv/calib/ablation.py` — the A/B/C/D runner (handoff §10), the actual deliverable.**
   - **A** existing auto geometry + existing auto track (baseline — already have it, see §5).
   - **B** manual landmarks + existing auto track → *how much does geometry alone fix?*
   - **C** manual landmarks + **manual ball centers** → *is this shot physically observable from this camera?*
   - **D** new auto geometry + auto track (later; only if B/C justify it).
   Each run emits the per-metric table vs Ruby/landmark truth + the sensitivity map, by camera class
   (near-level / elevated / off-axis) and longitudinal region.

**Phase-1 stop/go (lifted from the handoff, made concrete):** if **Run C** can't hit ~±0.75 board entry /
±0.5 mph on the near-level clips with *perfect* geometry and *perfect* ball centers, the limit is
resolution/identifiability, not ML — we then change *capture guidance / eligibility*, not models. If C
works but A/D fail, perception+calibration automation is the priority (Phases 2–3).

---

## 5. Test & validation plan

**No-regression set (must not move — CLAUDE.md requires re-running):**
- `lanesight-core/validation/IMG_8751–8754` + `_ruby.json` (sensor ground truth). IMG_8753 is the reference
  (entry 16.6, strike) and must stay byte-stable.
- Regression clip `~/LaneSightData/out/14b234c8…_trim.mov` (`validation/14b234c8_regression.json`): entry
  16–19.5, late speed < early.
- The 3 working pale clips (IMG_8899/8902/8904).

**Coverage target:** the 17-clip cohort (`~/Developer/LaneSight/10-25 training videos/`, IMG_8893–8910, no
8906). Current **Run-A baseline is already captured** in `02_RESEARCH/TRAINING_CLIPS_2026-10-25_pale_lanes.md`
(3 analyze, 6 flagged, 8 hard-fail) — that *is* the handoff's Phase-0 baseline table; I'll fold it into the
ablation runner's `A` column verbatim so B/C/D compare like-for-like.

**Guarantees:** `python -m pytest` green before every commit; `cv/calib/*` ships with unit tests
(geometry constants, solver on a synthetic known-pose scene, landmark schema round-trip); the ablation
runner is deterministic (seeded) and writes the per-shot audit artifacts (handoff §12) so results are
reproducible and inspectable.

---

## 6. Data / asset requests (genuinely blocking, not nice-to-have)

1. **~1 day of hand-labeling** (me-assisted via the overlay tool from PR1): landmark points on all 17 clips
   + ball centers on enough frames of the ~8 that currently fail. Without this there is no Run B/C and no
   honest Phase-1 gate. This is the critical path.
2. **Authoritative fiducial coordinates (open decision #4):** confirm the USBC Equipment Specs edition for
   arrow/dot/pin-spot longitudinal positions so `lane_geometry.py` cites a real source, not nominal folklore.
3. **iPhone intrinsics reality check (open decision #2):** one clip's raw capture metadata **before**
   `VideoTrimmer` runs, to confirm whether lens/distortion/true-timestamps survive the passthrough trim. This
   decides PnP-with-intrinsics vs homography-only in `solve.py`.
4. **Ruby definitions (open decision #5):** exact location/time definition of Ruby `speed_mph` (release vs
   full-lane) and `rev_rate_rpm` so comparisons in the ablation are definition-matched (the review is right
   that comparing release speed to a 60-ft average is a silent bug). Our `IMG_875x_ruby.json` have the
   values; we need the conventions.

---

## 7. First PR scope (small, reviewable, additive)

**PR1 — "Phase-1 geometry harness (no production path change)":**
- `cv/calib/lane_geometry.py` (+ tests) — canonical constants with citations, replacing literals *only by
  re-export* so existing code is untouched this PR.
- `cv/calib/landmarks.py` (+ schema tests) and an overlay renderer.
- `cv/calib/ablation.py` runner with the **A** column wired to the existing pipeline and a stub for B/C.
- Fixture: landmark JSON for IMG_8753 (the reference) + one failing clip (IMG_8893, elevated) to exercise
  B end-to-end.
- Docs: this file linked from `CURRENT_STATE.md`; a `DEC-062` entry proposing the geometry-first direction.

Explicitly **out of PR1:** any change to `analyze`, `lane_homography`, detection, or gates; any model
training. Those wait for the ablation to report (Phase-1 gate).

---

## 8. Proposed decision to ratify

**DEC-062 (ACCEPTED 2026-10-25):** Adopt geometry-first camera calibration decoupled from the ball,
metric-level gating with propagated uncertainty, and the A/B/C/D ablation as the mandatory Phase-1 gate
before any ML investment. Supersedes the far-lane-calibration workstream (old GUARDRAILS A). Production CV
path is frozen until the ablation reports; `accuracy over coverage` remains the tie-breaker. Ratified by
Shayne; recorded in `00_CONTEXT/DECISIONS.md`. **PR1 harness has landed** (`lanesight_core/cv/calib/`,
additive/off-path, 7 tests, 210 total green); plates + unlabeled templates generated for 13/17 clips under
`10-25 training videos/calib_landmarks/`. Next: ground-truth labeling → run B/C.
