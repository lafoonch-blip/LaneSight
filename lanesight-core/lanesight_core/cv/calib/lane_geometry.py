"""Canonical ten-pin lane geometry — the single, cited source of truth for physical coordinates.

Handoff §4: "Do not put nominal sports geometry into code as unreviewed magic constants." So every landmark
carries a world coordinate AND a provenance (`source` + `citation`). A coordinate we do not actually know
is `None` with `source='tbd'` and a reason — never a fabricated number (CLAUDE.md: no mock/placeholder
numbers). The solver only consumes landmarks whose world coordinate is fully known.

Coordinate convention (matches `cv/metrics.py` so the ablation is comparable to production):
  X : inches from the LEFT lane edge (0 .. lane_width_in).
  Z : feet from the foul line, increasing toward the pins.
  board_from_left(X) = X / lane_width_in * boards + 0.5   (≈0.5 at left edge .. ≈39.5 at right edge)
  Absolute board numbering (what the app reports): board 1 = RIGHT gutter (see metrics.to_abs). The
  `board` field below is stored as board_from_left; convert at report time, not here.

Open decision #4 (CV_REARCHITECTURE_RESPONSE): confirm the USBC Equipment Specifications edition and fill
the arrow longitudinal stagger. Until then arrow Z is `None`/'tbd' — present in the structure, absent in value.
"""
from __future__ import annotations
from dataclasses import dataclass, field, asdict
from typing import Optional

# --- constants we are confident are standard (still cite the governing spec edition) ---
LANE_LENGTH_FT = 60.0          # foul line to the head-pin spot (pin #1 center)
LANE_WIDTH_IN = 41.5           # nominal playing-surface width
BOARDS = 39                    # 39 boards across the lane
BOARD_PITCH_IN = LANE_WIDTH_IN / BOARDS      # ≈ 1.0641 in center-to-center
PIN_SPACING_IN = 12.0          # pin spots on 12-inch centers (universal ten-pin spec)
BALL_DIAMETER_IN = 8.59        # legal ~8.5"–8.595"; matches cv/track.BALL_IN
# ball center at first head-pin contact = 60 ft - (ball_radius + pin_radius)/12
# (4.30 in ball radius + 2.38 in pin radius); kept as the value shipped in cv/metrics.Z_IMPACT.
Z_IMPACT_FT = round(LANE_LENGTH_FT - (4.30 + 2.38) / 12.0, 2)   # 59.44

# --- Ratified metric-reference conventions (DEC-064, 2026-10-26; CV_MEASUREMENT_DEFINITIONS D-1/D-2/D-3) ---
# D-1: canonical entry board is read at a FIXED 60.0 ft plane (foul -> head-pin spot); the other positions
# are named secondaries. D-2: canonical entry angle over a FIXED 52-55 ft window. These are the definitions;
# applying them to cv/metrics outputs is a deferred follow-up (production CV frozen, DEC-062).
ENTRY_REFERENCE_FT = 60.0                               # canonical entry_board plane
ENTRY_SECONDARY_FT = {"contact": Z_IMPACT_FT, "sensor": 55.0}   # kept as named secondary metrics
ENTRY_ANGLE_WINDOW_FT = (52.0, 55.0)                   # canonical entry_angle window

_SPEC = "USBC Equipment Specifications Manual (2026-03-26)"

# USBC 2026 permits RANGES, not a single universal marking position (Shayne, 2026-10-25). So arrows/dots are
# encoded as intervals (z_min, z_max), NOT exact points — they are calibration *constraints* / consistency
# checks, never exact anchors. Exact anchors are foul (Z=0) + pin spots (12-in centers). Where a center's
# actual measured positions are known, override with exact (x_in, z_ft) and source='measured'.
USBC_RANGES_FT = {
    "guide_dot": (6.0, 8.0),         # lane guide dots: 6-8 ft beyond the foul line
    "arrow": (12.0, 16.0),           # target arrows: 12-16 ft beyond the foul line
    "downlane_target": (33.0, 44.0), # downlane targets: 33-44 ft beyond the foul line
    "approach_guide": (-15.0, -2.0), # approach guides: several permitted distances BEHIND the foul line
}


@dataclass
class Landmark:
    """A named physical landmark. (x_in, z_ft) is its exact world coordinate when known; otherwise a
    landmark may carry only a longitudinal INTERVAL (z_min..z_max) per the USBC range — usable as a
    consistency constraint but never as an exact calibration anchor."""
    name: str
    x_in: Optional[float]
    z_ft: Optional[float]
    source: str                      # 'spec' | 'derived' | 'measured' | 'usbc-range' | 'nominal' | 'tbd'
    citation: str = ""
    note: str = ""
    z_min: Optional[float] = None    # USBC permitted interval (longitudinal), when z_ft is not fixed
    z_max: Optional[float] = None

    @property
    def known(self) -> bool:
        """Exact point (usable as a calibration anchor)."""
        return self.x_in is not None and self.z_ft is not None

    @property
    def has_z_interval(self) -> bool:
        """X known + a permitted Z range, but no fixed Z (usable as a consistency constraint, not an anchor)."""
        return self.x_in is not None and self.z_ft is None and self.z_min is not None and self.z_max is not None

    def world(self):
        return (float(self.x_in), float(self.z_ft)) if self.known else None


def x_in_for_board(board_from_left: float) -> float:
    """Inverse of board_from_left(X); `board_from_left` counts from the LEFT edge (0.5 .. 39.5)."""
    return (board_from_left - 0.5) * LANE_WIDTH_IN / BOARDS


def board_from_left(x_in: float) -> float:
    return x_in / LANE_WIDTH_IN * BOARDS + 0.5


def _pin_spots():
    """The 10 pin spots from 12-inch centers on the standard triangle. Head pin (1) at board-20 center,
    Z = 60 ft. Rows recede by PIN_SPACING_IN*cos(30°); lateral offsets are multiples of PIN_SPACING_IN/2.
    Spacing is spec; absolute placement cited to the governing spec (edition TBD)."""
    import math
    row_dz_ft = PIN_SPACING_IN * math.cos(math.radians(30)) / 12.0     # ≈ 0.866 ft between rows
    half_in = PIN_SPACING_IN / 2.0
    center_x = LANE_WIDTH_IN / 2.0
    # (row index 0..3 from front, offsets in half-step units within the row)
    layout = {1: (0, [0]), 2: (1, [-1, 1]), 3: (2, [-2, 0, 2]), 4: (3, [-3, -1, 1, 3])}
    spots = []
    pin = 1
    for _, (row, offs) in sorted(layout.items()):
        z = LANE_LENGTH_FT + row * row_dz_ft
        for o in offs:
            spots.append(Landmark(f"pin_{pin}", round(center_x + o * half_in, 3), round(z, 3),
                                  source="spec", citation=_SPEC,
                                  note="12-in centers (spec); absolute placement pending edition confirm"))
            pin += 1
    return spots


@dataclass
class LaneGeometry:
    lane_length_ft: float = LANE_LENGTH_FT
    lane_width_in: float = LANE_WIDTH_IN
    boards: int = BOARDS
    board_pitch_in: float = BOARD_PITCH_IN
    z_impact_ft: float = Z_IMPACT_FT
    ball_diameter_in: float = BALL_DIAMETER_IN
    version: str = "2026-10-25.0"
    landmarks: dict = field(default_factory=dict)

    def known_landmarks(self):
        """Exact-point landmarks — the only ones usable as calibration anchors (foul + pin spots)."""
        return {k: v for k, v in self.landmarks.items() if v.known}

    def interval_landmarks(self):
        """X-known, Z-interval landmarks (arrows/dots/targets) — consistency constraints, not anchors.
        Returns {name: (x_in, z_min, z_max)}."""
        return {k: (v.x_in, v.z_min, v.z_max) for k, v in self.landmarks.items() if v.has_z_interval}

    def world_point(self, name: str):
        """Exact world coordinate for calibration; None for interval-only landmarks (by design)."""
        lm = self.landmarks.get(name)
        return lm.world() if lm else None

    def to_dict(self):
        d = {k: getattr(self, k) for k in
             ("lane_length_ft", "lane_width_in", "boards", "board_pitch_in",
              "z_impact_ft", "ball_diameter_in", "version")}
        d["landmarks"] = {k: asdict(v) for k, v in self.landmarks.items()}
        return d


def _canonical() -> LaneGeometry:
    lms: dict = {}

    def add(lm: Landmark):
        lms[lm.name] = lm

    # Foul line corners (Z=0) — known exactly from the lane width.
    add(Landmark("foul_l", 0.0, 0.0, "spec", _SPEC, "left foul-line corner"))
    add(Landmark("foul_r", LANE_WIDTH_IN, 0.0, "spec", _SPEC, "right foul-line corner"))
    # Gutter / edge lines run the length of the lane at X=0 and X=lane_width (structural cue, not foul).
    add(Landmark("gutter_l", 0.0, None, "spec", _SPEC, "left edge line (X known, any Z)"))
    add(Landmark("gutter_r", LANE_WIDTH_IN, None, "spec", _SPEC, "right edge line (X known, any Z)"))

    # Target arrows at boards 5..35. X known; Z is a permitted INTERVAL (12-16 ft), not a universal point —
    # USBC allows a range and the arrows are longitudinally staggered. Interval constraint, never an anchor.
    amn, amx = USBC_RANGES_FT["arrow"]
    for b in (5, 10, 15, 20, 25, 30, 35):
        add(Landmark(f"arrow_{b}", round(x_in_for_board(b), 3), None, "usbc-range", _SPEC,
                     "arrow X known; Z in the USBC 12-16 ft range (staggered; measure center-specific for exact)",
                     z_min=amn, z_max=amx))
    # Guide dots: 6-8 ft PAST the foul line (USBC range). X known; Z interval.
    gmn, gmx = USBC_RANGES_FT["guide_dot"]
    for b in (5, 10, 15, 20, 25, 30, 35):
        add(Landmark(f"dot_{b}", round(x_in_for_board(b), 3), None, "usbc-range", _SPEC,
                     "guide-dot X known; Z in the USBC 6-8 ft range", z_min=gmn, z_max=gmx))
    # Downlane targets: 33-44 ft past the foul line (USBC range) — in the breakpoint region, if visible.
    dmn, dmx = USBC_RANGES_FT["downlane_target"]
    for b in (5, 10, 15, 20, 25, 30, 35):
        add(Landmark(f"downlane_target_{b}", round(x_in_for_board(b), 3), None, "usbc-range", _SPEC,
                     "downlane-target X known; Z in the USBC 33-44 ft range", z_min=dmn, z_max=dmx))
    # Approach dots BEHIND the foul line (negative Z); USBC permits several distances. Modeled separately
    # (handoff §4) and first-class here — the best-resolved fiducials in the ball-return framing this cohort
    # uses (CV_PHASE1_VALIDATION_REPORT). X known; Z interval (behind foul). Measure center-specific for exact.
    rmn, rmx = USBC_RANGES_FT["approach_guide"]
    for b in (5, 10, 15, 20, 25, 30, 35):
        add(Landmark(f"approach_dot_{b}", round(x_in_for_board(b), 3), None, "usbc-range", _SPEC,
                     "approach-dot X known; Z negative (behind foul), several USBC-permitted distances",
                     z_min=rmn, z_max=rmx))

    for lm in _pin_spots():
        add(lm)

    return LaneGeometry(landmarks=lms)


CANONICAL = _canonical()
