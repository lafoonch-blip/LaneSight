"""Configured reaction: what THIS bowler's ball should do, given how it was drilled and its surface right now.

The catalog's normalized reaction (catalog.normalize) describes the ball out of the box with a benchmark layout.
A user ball differs in two ways the bowler records in their profile (DEC-007):
  - the layout it was drilled with (ball_configurations, versioned), and
  - its current surface (surface_events, append-only; the bowler can re-sand or polish at any time).

configured_reaction() starts from the box reaction and applies one adjustment per recorded variable, each with
a reason, so the app can say *why* this Phaze II reads earlier than the catalog says.

Directions follow manufacturer layout and surface guides (sources in ADJUSTMENT_SOURCES). None of them publish
magnitudes, so the size of each adjustment is a provisional estimate: results are status 'best_effort', and the
adjusted axes are marked in `basis`. Once LaneSight has measured shots for a configuration+surface (breakpoint,
entry angle on known patterns), those measurements should replace these estimates — not implemented yet.

Adjustments are relative to a reference layout (no change when the ball is drilled at the reference):
  Dual Angle  45° drill angle × 4" pin-to-PAP × 45° VAL angle
  VLS         4" pin-to-PAP × 4" PSA-to-PAP × 2" pin buffer
and relative to the catalog's box finish for surface.
"""
from __future__ import annotations
import math
import re
from dataclasses import dataclass, field, asdict

from .catalog import finish_grit, _num, _clamp

CONFIGURED_VERSION = 'ls-configured-0.1-provisional'

ADJUSTMENT_SOURCES = {
    'pin_to_pap': 'Storm, "Drilling Layouts Explained: VLS"; MDM Coaching via BowlersMart, "Dual Angle Layouts Explained"',
    'psa_to_pap': 'Storm, "Drilling Layouts Explained: VLS"; Storm, "Pin Buffer Layout System: PSA to PAP"',
    'pin_buffer': 'Storm, "Drilling Layouts Explained: VLS"',
    'drill_angle': 'MDM Coaching via BowlersMart, "Dual Angle Layouts Explained"',
    'val_angle': 'MDM Coaching via BowlersMart, "Dual Angle Layouts Explained"',
    'pin_position': 'Storm, "Mastering Layouts: Pin Up vs. Pin Down"',
    'surface': 'bowling.com Knowledge Hub, "Using Surface to Fix Your Bowling Ball"',
}

REF_PIN_TO_PAP, REF_DRILL, REF_VAL, REF_PSA, REF_BUFFER = 4.0, 45.0, 45.0, 4.0, 2.0
AXIS_CAP = 2.5            # max total change per axis from layout, and separately from surface (1-10 points)


@dataclass
class Adjustment:
    variable: str             # pin_to_pap | drill_angle | val_angle | psa_to_pap | pin_buffer | pin_position | surface
    value: str                # what the bowler entered, as shown back to them
    d_hook: float = 0.0
    d_length: float = 0.0
    d_backend: float = 0.0
    reason: str = ''


@dataclass
class ConfiguredReaction:
    ls_hook: float | None
    ls_length: float | None
    ls_backend: float | None
    reaction_shape: str | None
    box: dict                  # the catalog reaction it started from
    adjustments: list[Adjustment] = field(default_factory=list)
    basis: dict = field(default_factory=dict)
    surface_grit: int | None = None
    surface_polished: bool | None = None
    surface_source: str | None = None        # 'surface_event' | 'box_finish' | None
    layout_used: dict | None = None
    bowler_used: dict | None = None           # bowler-level grip + PAP that informed this reaction (DEC-074/087)
    status: str = 'best_effort'
    notes: list[str] = field(default_factory=list)
    version: str = CONFIGURED_VERSION

    def to_dict(self):
        return asdict(self)


# ---------- bowler-level drilling inputs (DEC-074/087) ----------
# Grip (middle-finger pitch, span) and PAP (over, up) live on the BOWLER, not the ball — the same hand drills
# every ball — so they flow into configured_reaction() as `bowler`, not the per-ball config.
#
# WHERE EACH PLUGS IN (honest status — no fabricated reaction numbers, per the project rule):
#   • PAP (over/up): the layout a driller records (Dual-Angle / VLS) is ALREADY measured relative to this
#     bowler's PAP — `pin_to_pap_in` et al. bake it in — so PAP is NOT re-applied here. It becomes load-bearing
#     only for a layout entered pin-relative (pin distance from grip center), where pin-to-PAP must be derived
#     from PAP; that derivation is the single plug-in point marked `# PAP-DERIVE` in layout_values().
#   • Grip (pitch/span): affects fit/leverage, not the ball's published reaction axes; there is no sourced
#     model mapping pitch/span → hook/length/backend yet, so it is stored and surfaced (bowler_used) but not
#     turned into a numeric adjustment. When a cited model exists it plugs into layout_adjustments().
def bowler_values(bowler: dict | None) -> dict:
    if not bowler:
        return {}
    out = {}
    for k in ('grip_middle_pitch_in', 'grip_span_in', 'pap_over_in', 'pap_up_in'):
        v = _num(bowler.get(k))
        if v is not None:
            out[k] = v
    return out


# ---------- layout parsing ----------
def parse_layout(system: str | None, layout: str | None) -> dict:
    """'50 x 4.5 x 40' (Dual Angle: drill angle × pin-to-PAP × VAL) or '4 x 4 x 2' (VLS: pin-to-PAP × PSA-to-PAP ×
    pin buffer). Fractions like '3 3/8' and '3⅜' are accepted. Unknown systems parse to {}."""
    if not layout or not system:
        return {}
    s = layout.replace('⅛', ' 1/8').replace('¼', ' 1/4').replace('⅜', ' 3/8').replace('½', ' 1/2') \
              .replace('⅝', ' 5/8').replace('¾', ' 3/4').replace('⅞', ' 7/8').replace('"', '').replace('°', '')
    parts = re.split(r'\s*[x×X*]\s*', s.strip())
    vals = []
    for p in parts:
        m = re.fullmatch(r'\s*(\d+(?:\.\d+)?)(?:\s+(\d+)/(\d+))?\s*', p)
        if not m:
            return {}
        v = float(m.group(1)) + (float(m.group(2)) / float(m.group(3)) if m.group(2) else 0.0)
        vals.append(v)
    if len(vals) != 3:
        return {}
    sysl = system.lower().replace(' ', '').replace('_', '')
    if 'dual' in sysl:
        return {'drill_angle_deg': vals[0], 'pin_to_pap_in': vals[1], 'val_angle_deg': vals[2]}
    if 'vls' in sysl or 'vector' in sysl:
        return {'pin_to_pap_in': vals[0], 'psa_to_pap_in': vals[1], 'pin_buffer_in': vals[2]}
    return {}


def layout_values(config: dict | None) -> dict:
    """Structured columns win; the layout string fills anything left blank."""
    if not config:
        return {}
    parsed = parse_layout(config.get('layout_system'), config.get('layout'))
    out = {}
    for k in ('pin_to_pap_in', 'psa_to_pap_in', 'pin_buffer_in', 'drill_angle_deg', 'val_angle_deg'):
        v = _num(config.get(k))
        out[k] = v if v is not None else parsed.get(k)
    out['pin_position'] = config.get('pin_position')
    # PAP-DERIVE: if a future layout form gives pin distance from the grip center (not pin-to-PAP), derive
    # pin_to_pap_in here from the bowler's PAP (over/up). No such layout form exists yet, so nothing to do.
    return {k: v for k, v in out.items() if v is not None}


# ---------- surface parsing ----------
def surface_state(event: dict | None) -> tuple[int | None, bool | None]:
    """surface_events row -> (effective grit, polished?). Accepts grit_value / polished columns or free text
    ('500 Abralon', '1500 + Royal Compound', 'Polished')."""
    if not event:
        return None, None
    grit = _num(event.get('grit_value'))
    pol = event.get('polished')
    text = ' '.join(str(event.get(k) or '') for k in ('grit', 'polish', 'product')).lower()
    if grit is None:
        gs = [int(g) for g in re.findall(r'(\d{3,5})', text) if 180 <= int(g) <= 30000]
        grit = max(gs) if gs else None
    if pol is None and text.strip():
        pol = bool(re.search(r'polish|compound|shine|gloss', text))
    return (int(grit) if grit is not None else None), pol


def _surface_index(grit: int | None, polished: bool | None) -> float | None:
    """log2(grit / 2000): 500 -> -2, 1000 -> -1, 2000 -> 0, 4000 -> +1. Polish adds 1.5 (skids like a much higher grit)."""
    if grit is None and not polished:
        return None
    base = math.log2((grit or 2000) / 2000.0)
    return base + (1.5 if polished else 0.0)


def _box_surface(rec: dict) -> tuple[int | None, bool]:
    f = (rec.get('factory_finish') or '').lower()
    polished = bool(re.search(r'polish|compound|gloss|shine', f))
    grits = [int(g) for g in re.findall(r'(\d{3,5})', f.replace(',', '')) if 180 <= int(g) <= 30000]
    return (max(grits) if grits else None), polished


# ---------- adjustments ----------
def _flare(p: float) -> float:
    """Relative flare vs pin-to-PAP: peaks around 3.75" (the 3⅜-5" 'strong' band), falls off toward 1" and 6¾"."""
    return 1 - ((p - 3.75) / 2.75) ** 2


def _response(rec: dict) -> tuple[float, float, list[str]]:
    """How much a layout can change this ball: scales with total diff (flare potential) and, for PSA, int. diff."""
    notes = []
    diff, idiff = _num(rec.get('diff_15')), _num(rec.get('int_diff_15'))
    if rec.get('cover_type') == 'polyester':
        return 0.15, 0.0, ['polyester spare ball: layout barely changes its path']
    if diff is None:
        k = 0.8
        notes.append('no published differential: layout effect sized for a typical reactive ball')
    else:
        k = max(0.3, min(1.3, diff / 0.045))
    if rec.get('core_type') == 'asymmetric' and idiff is not None:
        ka = max(0.2, min(1.4, idiff / 0.015))
    elif rec.get('core_type') == 'asymmetric':
        ka = 0.8
        notes.append('asymmetric core without a published intermediate differential')
    else:
        ka = 0.0
    return k, ka, notes


def layout_adjustments(rec: dict, lv: dict) -> tuple[list[Adjustment], list[str]]:
    adj, notes = [], []
    if not lv:
        return adj, notes
    k, ka, rnotes = _response(rec)
    notes += rnotes
    p = lv.get('pin_to_pap_in')
    if p is not None:
        d = _flare(p) - _flare(REF_PIN_TO_PAP)
        adj.append(Adjustment('pin_to_pap', f'{p:g}"',
                              d_hook=1.5 * d * k, d_length=0.4 * (p - REF_PIN_TO_PAP) * k,
                              d_backend=0.4 * (p - REF_PIN_TO_PAP) * k,
                              reason=('near maximum flare: more total hook' if d > 0.05 else
                                      'short pin-to-PAP: low flare, smooth early hook' if p < REF_PIN_TO_PAP else
                                      'long pin-to-PAP: more length and a stronger downlane move')))
    da = lv.get('drill_angle_deg')
    if da is not None:
        x = (da - REF_DRILL) / 45.0
        adj.append(Adjustment('drill_angle', f'{da:g}°', d_length=1.2 * x * k, d_backend=0.5 * x * k,
                              reason='larger drill angle: later roll' if da > REF_DRILL else
                                     'smaller drill angle: earlier roll' if da < REF_DRILL else 'reference drill angle'))
    va = lv.get('val_angle_deg')
    if va is not None:
        x = (va - REF_VAL) / 45.0
        adj.append(Adjustment('val_angle', f'{va:g}°', d_hook=-0.4 * x * k, d_backend=-1.5 * x * k,
                              reason='small VAL angle (pin up): faster, snappier transition' if va < REF_VAL else
                                     'large VAL angle (pin down): smoother transition' if va > REF_VAL else
                                     'reference VAL angle'))
    s = lv.get('psa_to_pap_in')
    if s is not None and ka > 0:
        adj.append(Adjustment('psa_to_pap', f'{s:g}"', d_hook=-0.3 * abs(s - REF_PSA) * ka,
                              d_length=0.3 * (s - REF_PSA) * ka, d_backend=0.35 * (s - REF_PSA) * ka,
                              reason='short PSA-to-PAP: earlier, smoother change of direction' if s < REF_PSA else
                                     'long PSA-to-PAP: later, sharper (and weaker past 4")' if s > REF_PSA else
                                     'reference PSA-to-PAP (most flare)'))
    elif s is not None:
        notes.append('PSA-to-PAP ignored: symmetric core')
    b = lv.get('pin_buffer_in')
    if b is not None:
        adj.append(Adjustment('pin_buffer', f'{b:g}"', d_backend=-0.35 * (b - REF_BUFFER) * k,
                              reason='short pin buffer: quicker skid-hook-roll transition' if b < REF_BUFFER else
                                     'long pin buffer: slower, smoother transition' if b > REF_BUFFER else
                                     'reference pin buffer'))
    pos = lv.get('pin_position')
    if pos and va is None and b is None:       # VAL angle / pin buffer already encode the pin's position
        sign = {'above_fingers': 1, 'below_fingers': -1}.get(pos, 0)
        if sign:
            adj.append(Adjustment('pin_position', pos.replace('_', ' '), d_hook=0.4 * sign * k,
                                  d_backend=0.8 * sign * k,
                                  reason='pin up: more flare, stronger backend recovery' if sign > 0 else
                                         'pin down: less flare, smoother and more controlled'))
    return adj, notes


def surface_adjustment(rec: dict, event: dict | None) -> tuple[Adjustment | None, int | None, bool | None, str | None]:
    box_g, box_p = _box_surface(rec)
    cur_g, cur_p = surface_state(event)
    if cur_g is None and cur_p is None:
        return None, box_g, box_p, ('box_finish' if box_g or box_p else None)
    if cur_g is None:
        cur_g = box_g
    b, c = _surface_index(box_g, box_p), _surface_index(cur_g, cur_p)
    if b is None or c is None:
        return None, cur_g, cur_p, 'surface_event'
    d = c - b
    label = f"{cur_g or ''}{' polished' if cur_p else ''}".strip() or 'polished'
    if abs(d) < 0.05:
        return Adjustment('surface', label, reason='same surface as out of the box'), cur_g, cur_p, 'surface_event'
    return (Adjustment('surface', label, d_hook=-0.5 * d, d_length=1.0 * d, d_backend=0.7 * d,
                       reason=('shinier than the box finish: more length, sharper backend, less read in oil' if d > 0
                               else 'duller than the box finish: reads earlier, smoother, more hook in oil')),
            cur_g, cur_p, 'surface_event')


def _sum_capped(adjs, attr):
    return max(-AXIS_CAP, min(AXIS_CAP, sum(getattr(a, attr) for a in adjs)))


def _shape(cover_type, hook, length, backend) -> str | None:
    if cover_type == 'polyester':
        return 'straight'
    if backend is None:
        return None
    if length is not None and length >= 7 and backend >= 7:
        return 'skid_flip'
    return 'angular' if backend >= 6.5 else 'arc' if backend <= 4.0 else 'continuous'


def configured_reaction(rec: dict, config: dict | None = None, surface_event: dict | None = None,
                        bowler: dict | None = None) -> ConfiguredReaction:
    """rec: catalog row with ls_* fields. config: the ball's current ball_configurations row (or None).
    surface_event: its latest surface_events row (or None = still the box finish). bowler: the owner's
    profile grip + PAP (DEC-074/087) — the same hand drills every ball, so it's bowler-level, not per-ball.
    See `bowler_values` for exactly how/where PAP and grip plug in (and why they're not fabricated here)."""
    box = {k: rec.get(k) for k in ('ls_hook', 'ls_length', 'ls_backend', 'reaction_shape', 'reaction_confidence')}
    lv = layout_values(config)
    bv = bowler_values(bowler)
    lay, notes = layout_adjustments(rec, lv)
    if bv and lv.get('pin_to_pap_in') is not None and ('pap_over_in' in bv or 'pap_up_in' in bv):
        notes.append('PAP on file; this layout already encodes pin-to-PAP, so PAP is not re-applied')
    if bv.get('grip_middle_pitch_in') is not None or bv.get('grip_span_in') is not None:
        notes.append('grip (pitch/span) recorded; no validated pitch/span→reaction model yet, so it is stored not applied')
    surf, grit, pol, ssrc = surface_adjustment(rec, surface_event)
    basis = {}

    def apply(axis, attr):
        v = rec.get(axis)
        if v is None:
            return None
        dl, ds = _sum_capped(lay, attr), (getattr(surf, attr) if surf else 0.0)
        if lay and abs(dl) >= 0.05:
            basis[axis] = 'catalog+layout' + ('+surface' if surf and abs(ds) >= 0.05 else '')
        elif surf and abs(ds) >= 0.05:
            basis[axis] = 'catalog+surface'
        else:
            basis[axis] = 'catalog'
        return _clamp(v + dl + max(-AXIS_CAP, min(AXIS_CAP, ds)))

    hook, length, backend = apply('ls_hook', 'd_hook'), apply('ls_length', 'd_length'), apply('ls_backend', 'd_backend')
    shape = rec.get('reaction_shape')
    if any(b != 'catalog' for b in basis.values()):
        shape = _shape(rec.get('cover_type'), hook, length, backend) or shape
    if config is None:
        notes.append('no drilling recorded: using the out-of-box reaction')
    elif not lv:
        notes.append('layout not entered in a recognised form: drilling not applied')
    if rec.get('reaction_confidence') == 'low':
        notes.append('catalog reaction is itself an estimate from specs')
    adjs = lay + ([surf] if surf else [])
    for a in adjs:
        a.d_hook, a.d_length, a.d_backend = round(a.d_hook, 2), round(a.d_length, 2), round(a.d_backend, 2)
    return ConfiguredReaction(hook, length, backend, shape, box, adjs, basis, grit, pol, ssrc, lv or None,
                              bowler_used=bv or None, notes=notes)


def as_rankable(rec: dict, cr: ConfiguredReaction, **extra) -> dict:
    """A row recommend.rank_for_condition / arsenal_gaps can use: the catalog row with the configured reaction."""
    row = dict(rec)
    row.update(ls_hook=cr.ls_hook, ls_length=cr.ls_length, ls_backend=cr.ls_backend, reaction_shape=cr.reaction_shape,
               configured=True, configured_basis=cr.basis, adjustments=[asdict(a) for a in cr.adjustments])
    row.update(extra)
    return row
