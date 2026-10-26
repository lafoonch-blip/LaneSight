# CV Measurement Definitions — canonical conventions (DEC-062 Phase 1)
Version: 1.0
Last Updated: 2026-10-25
Status: Proposed canonical reference for judging ablation accuracy. Grounds every metric in the real code
(`lanesight_core/cv/metrics.py`, `cv/calib/lane_geometry.py`) and the Ruby fields
(`validation/IMG_875x_ruby.json`). Flags the conflicts that can make a *perfectly calibrated* clip still
disagree with ground truth — resolve these BEFORE reading ablation errors (handoff §4; response §3).

> Why this exists: the response doc found we already ship **two different entry conventions** and a
> speed headline that is not definition-matched to Ruby. If we score the ablation against the wrong
> reference, we will "fail" geometry that is actually correct. One convention per metric, decided here.

---

## 1. Coordinate frame & board numbering (canonical)

- **X** = inches from the LEFT lane edge, `0 .. 41.5`. **Z** = feet from the foul line toward the pins.
- `board_from_left(X) = X / 41.5 * 39 + 0.5` → ≈0.5 at the left edge, ≈39.5 at the right edge.
- **Absolute board (what the app reports): board 1 = RIGHT gutter, board 39 = LEFT gutter.** Production
  flips board_from_left when the bowler is right-handed (`cv/metrics.py` `to_abs`). This handed flip is a
  *reporting* step — the ablation stores board_from_left internally and converts at the end, so a labeling
  error in handedness never corrupts the geometry comparison.
- Handedness is inferred from the late hook direction (cubic end-slope). For ablation ground truth, record
  the bowler's actual hand per clip so we never infer it from a short/sparse track.

**Decision D-1 (confirm):** board 1 = right gutter, right-hander's pocket ≈ board 17.5. This matches the
app and Ruby's `breakpoint_ft`/board intuition. ✅ proposed canonical.

## 2. Entry board — the conflict to kill first

Production today reports **`entry_board` at `Z_IMPACT = 59.44 ft`** = the ball **center at first head-pin
contact**, derived as `60 ft − (ball_radius 4.30" + pin_radius 2.38")/12`. This is a *predicted-contact*
reference, **not** a fixed plane. But `entry_angle_52_55` (below) uses a **fixed 52–55 ft** plane. So the
two "entry" numbers live at different Z — exactly the ambiguity the review warns about.

**Decision D-2 (choose one canonical entry reference):**
| Option | Z reference | Pro | Con |
|---|---|---|---|
| **A (recommended)** | fixed **60.0 ft plane** (foul→headpin spot) | unambiguous, matches "entry at the pins", geometry-only (no ball/pin radius coupling) | ~0.56 ft nearer than contact; tiny board delta |
| B | keep `59.44 ft` contact plane | current behavior; physically "where it hits" | couples to ball+pin radii; reads like a plane but isn't |
| C | fixed **55 ft** (common sensor "entry") | matches some sensors | not where the app says "entry" |

Recommend **A**: report `entry_board @ 60.0 ft` as a named, fixed plane; keep the 59.44 ft contact figure
only as an internal note. Whatever we pick, the metric name must carry the Z (`entry_board@60ft`).

## 3. Entry angle — declare the window

- `entry_angle_deg` (production headline): mean path angle over the **last ~1.5 ft of the tracked LOESS
  curve** — a *floating* window that depends on where the track ends. Fragile across clips.
- `entry_angle_52_55_deg`: mean angle over a **fixed 52–55 ft** span (Specto-compatible). Stable, comparable.

**Decision D-3 (recommended):** make **`entry_angle @ 52–55 ft`** the canonical reported angle (fixed
window, sensor-comparable); demote the floating last-1.5-ft version to a diagnostic. `atan(dX/dZ)`, degrees,
sign convention: positive = toward the pocket. Derivative uncertainty will exceed position uncertainty —
report it.

## 4. Speed — match Ruby's definition or don't compare

Production speeds:
- `ball_speed` = **60 ft foul→pins average** (`mph(60/(t_impact−t_release))`). Needs the ball tracked to
  the pins; labeled "Ruby-comparable."
- `speed_release` = front-half **skid** speed (early 4–24 ft fit). Robust when the back half is lost, but a
  near-field homography Z-scale residual makes it read **~9% low** (noted in code, pending Specto).
- `speed_early` / `speed_late` = windowed fits; the plausibility gate uses `late > early` as a corruption flag.

Ruby provides `speed_mph` (e.g. IMG_8753 = 17.8). **Its exact location/time definition is unconfirmed**
(release-point? a fixed sensor location?). Most optical sensors report a near-release/early-lane speed.

**Decision D-4 (needs Shayne / Ruby docs — open #5):** confirm whether Ruby `speed_mph` is release/early or
full-lane average. Then compare **like to like**: if Ruby = release → compare to `speed_release` (and
correct the known ~9% bias); if full-lane → compare to `ball_speed`. **Do not** compare Ruby release to our
60 ft average — that alone is a multi-% phantom error. Also distinguish downlane `dZ/dt` from planar
`sqrt(dX² + dZ²)` speed (handoff §4); for a nearly-straight line they're within rounding, but name it.

## 5. Breakpoint, laydown, arrows

- **Laydown** = board at `Z=0` (foul line); only if the track starts within ~3 ft.
- **Arrows board** = board at `Z=15 ft`. ⚠ Nominal; see D-5 — the arrows are longitudinally **staggered**,
  so "board at 15 ft" is a lane-plane readout, not "the board the ball crossed the arrows on." Keep the name
  `board@15ft` to avoid implying a specific physical arrow.
- **Breakpoint** = lateral extreme (min board_from_left for a RH hook) over `15 < Z < 55 ft`, reported as
  `(breakpoint_board, breakpoint_ft)`. **Censor** (report unavailable) when the track doesn't bracket the
  turn — do not assert an exact point from an unobserved region (handoff §8). Note: our breakpoint is
  **geometric** (DEC-022); Ruby's `breakpoint_ft` is **rotational** (skid→hook) — NOT comparable.

## 6. Lane landmark coordinates (the geometry template)

Single source: `cv/calib/lane_geometry.py` (`CANONICAL`). Known exactly: foul corners (Z=0), lane width
41.5", 39 boards, pin spots on 12" centers (head pin board-20 @ 60 ft). **TBD pending the USBC edition
(open #4):** arrow longitudinal stagger (X known, Z null), guide-dot Z (small positive), approach-dot Z
(negative, ~12–15 ft behind foul — first-class here per the framing finding). No fabricated coordinate ships;
a landmark we don't know is `None`/`tbd` with a reason.

**Decision D-5 (needs citation):** fill arrow/dot Z from the governing USBC spec edition, then lift their
`source` from `tbd` to `spec`. Until then the solver simply doesn't consume them.

---

## Summary — the four that can fake an error

| # | Thing | Current state | Canonical (proposed) |
|---|-------|---------------|----------------------|
| D-2 | Entry board reference | `entry_board@59.44ft` vs angle `@52-55ft` | `entry_board@60.0ft` (fixed plane) |
| D-3 | Entry angle window | floating last-1.5-ft headline | `entry_angle@52-55ft` (fixed) |
| D-4 | Speed vs Ruby | headline = 60 ft avg; Ruby def unconfirmed | match definitions; never Ruby-release vs 60 ft avg |
| D-5 | Arrow/dot coordinates | nominal/ambiguous | cite USBC edition; stagger encoded |

D-1/D-2/D-3 are ours to ratify now; D-4/D-5 need the Ruby docs + USBC edition. Resolve all five before the
ablation's B/C columns are read as accuracy.
