# CV Measurement Definitions — canonical conventions (DEC-062 Phase 1)
Version: 1.2
Last Updated: 2026-10-26
Status: D-1/2/3 RATIFIED (DEC-064); D-5 implemented (USBC 2026 ranges); D-4 open (needs Ruby docs). Canonical
reference for judging ablation accuracy. Grounds every metric in the real code
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

**Decision D-1 — RATIFIED (DEC-064, 2026-10-26): canonical `entry_board @ 60.0 ft`** (fixed
foul→head-pin-spot plane). Geometry-first: unambiguous, no ball/pin-radius coupling, matches "entry at the
pins". The other positions are kept as **separately named** secondary metrics, each carrying its Z:
`entry_board@59.44ft` (ball-center at first contact — the current production value) and `entry_board@55ft`
(sensor-style). **Every entry-board metric name carries its reference plane** — no bare "entry_board".

| Option | Z reference | Status |
|---|---|---|
| **A** | fixed **60.0 ft** (foul→head-pin spot) | **CANONICAL** |
| B | `59.44 ft` contact plane (current production) | kept as named secondary `entry_board@59.44ft` |
| C | fixed **55 ft** (sensor-style) | kept as named secondary `entry_board@55ft` |

## 3. Entry angle — declare the window

- `entry_angle_deg` (production headline): mean path angle over the **last ~1.5 ft of the tracked LOESS
  curve** — a *floating* window that depends on where the track ends. Fragile across clips.
- `entry_angle_52_55_deg`: mean angle over a **fixed 52–55 ft** span (Specto-compatible). Stable, comparable.

**Decision D-2 — RATIFIED (DEC-064, 2026-10-26): canonical `entry_angle @ 52–55 ft`** — a fixed window, NOT
the dynamic last-1.5-ft one. `atan(dX/dZ)` in degrees, sign convention **positive = toward the pocket**. The
floating last-1.5-ft version is demoted to an internal diagnostic. Report the derivative uncertainty (it
exceeds the position uncertainty).

## 4. Speed — match Ruby's definition or don't compare

Production speeds:
- `ball_speed` = **60 ft foul→pins average** (`mph(60/(t_impact−t_release))`). Needs the ball tracked to
  the pins; labeled "Ruby-comparable."
- `speed_release` = front-half **skid** speed (early 4–24 ft fit). Robust when the back half is lost, but a
  near-field homography Z-scale residual makes it read **~9% low** (noted in code, pending Specto).
- `speed_early` / `speed_late` = windowed fits; the plausibility gate uses `late > early` as a corruption flag.

Ruby provides `speed_mph` (e.g. IMG_8753 = 17.8). **Its exact location/time definition is unconfirmed**
(release-point? a fixed sensor location?). Most optical sensors report a near-release/early-lane speed.

**Decision D-3 — RATIFIED (DEC-064, 2026-10-26): keep four separately named speeds** — `ball_speed` (60 ft
foul→pins average; **canonical headline**), `speed_release` (front-half skid), `speed_early`, `speed_late`.
Do not collapse them. Speeds are **planar** `sqrt(dX²+dZ²)/dt` unless suffixed `_dz` (downlane `dZ/dt`); for
a near-straight line they're within rounding, but the convention is declared.

**Decision D-4 — STILL OPEN (needs Ruby docs):** do **NOT assume Ruby = full-lane average**. Treat Ruby as a
**secondary reference only** and **flag the measurement mismatch** in any comparison — never present a
Ruby-vs-LaneSight delta as accuracy until Ruby's exact location/averaging is confirmed.

## 5. Breakpoint, laydown, arrows

- **Laydown** = board at `Z=0` (foul line); only if the track starts within ~3 ft.
- **Arrows board** = board at `Z=15 ft`. ⚠ Nominal; see D-5 — the arrows are longitudinally **staggered**,
  so "board at 15 ft" is a lane-plane readout, not "the board the ball crossed the arrows on." Keep the name
  `board@15ft` to avoid implying a specific physical arrow.
- **Breakpoint** = lateral extreme (min board_from_left for a RH hook) over `15 < Z < 55 ft`, reported as
  `(breakpoint_board, breakpoint_ft)`. **Censor** (report unavailable) when the track doesn't bracket the
  turn — do not assert an exact point from an unobserved region (handoff §8). Note: our breakpoint is
  **geometric** (DEC-022); Ruby's `breakpoint_ft` is **rotational** (skid→hook) — NOT comparable.

## 6. Lane landmark coordinates (the geometry template) — USBC 2026 RANGES, not universal points

Single source: `cv/calib/lane_geometry.py` (`CANONICAL`). **Exact anchors** (the only features that
calibrate): foul corners (Z=0), lane width 41.5", 39 boards, pin spots on 12" centers (head pin board-20 @
60 ft). Citation: **USBC Equipment Specifications Manual (2026-03-26)**.

**D-5 resolved (Shayne, 2026-10-25):** the USBC manual permits **ranges**, not one universal marking
position — so arrows/dots/targets are encoded as **intervals**, never exact points, and are **consistency
constraints**, not anchors (`geometry.interval_landmarks()`, `solve.interval_consistency`):

| Landmark | USBC 2026 permitted Z | encoded as |
|---|---|---|
| Lane guide dots | **6–8 ft** past foul | `dot_*` interval |
| Target arrows | **12–16 ft** past foul (staggered) | `arrow_*` interval |
| Downlane targets | **33–44 ft** past foul | `downlane_target_*` interval |
| Approach guides | several permitted distances **behind** foul | `approach_dot_*` interval (negative Z) |

**Do not encode a single exact arrow/dot distance as universal ground truth.** Where a center's actual
positions are measured (e.g. from a verified calibration on these clips), override with exact (x,z) and
`source='measured'`. Otherwise the interval is used only to **check** a calibration solved from the exact
anchors (does a verified arrow map into its 12–16 ft band?).

---

## Summary — the four that can fake an error

| # | Thing | Status | Ratified value (DEC-064, 2026-10-26) |
|---|-------|--------|--------------------------------------|
| D-1 | Entry board | **RATIFIED** | canonical `entry_board@60.0ft`; `@59.44ft` + `@55ft` kept as named secondaries |
| D-2 | Entry angle | **RATIFIED** | canonical `entry_angle@52–55ft` (fixed window); floating version → diagnostic |
| D-3 | Speed | **RATIFIED** | keep `ball_speed`(60 ft avg, headline) + `speed_release`/`speed_early`/`speed_late`; planar unless `_dz` |
| D-4 | Ruby speed | **OPEN** | needs Ruby docs; secondary reference only, flag the mismatch |
| D-5 | Arrow/dot coords | **DONE** | USBC 2026 ranges (6–8 / 12–16 / 33–44 ft; approach behind foul) in `lane_geometry` |

D-1/2/3/5 are settled. D-4 waits on Ruby's published definition. **Implementation note:** the canonical
reference constants live in `cv/calib/lane_geometry` (`ENTRY_REFERENCE_FT`, `ENTRY_ANGLE_WINDOW_FT`,
`ENTRY_SECONDARY_FT`); applying them to the production `cv/metrics` outputs is a small follow-up, deferred
while production CV is frozen (DEC-062) — the definitions are fixed now so the later change is mechanical.
