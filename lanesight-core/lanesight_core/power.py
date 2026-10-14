"""Power (proposed DEC-024): impact energy at pocket speed, scaled 0-100 against a fixed elite reference.

E = 1/2 m v^2 + 1/2 (m RG^2) w^2
  v = speed at the pocket (late speed), w = rev rate, m = ball weight, RG = ball radius of gyration.
Power = 100 * E / E_REF, capped at 100. E_REF = 16 lb, 18 mph at the pocket, 450 rpm, RG 2.50 in (~267 J).
Absolute scale on purpose: a bowler's number never drifts as the user base grows.
Power is NOT a carry score. Show it next to pocket position and entry angle, never as "more power = more strikes".
"""
from __future__ import annotations
import math

LB_KG, MPH_MS, IN_M = 0.45359237, 0.44704, 0.0254
DEFAULT_RG_IN = 2.50

def impact_energy_j(weight_lb: float, speed_mph: float, rev_rpm: float, rg_in: float = DEFAULT_RG_IN) -> dict:
    m = weight_lb * LB_KG; v = speed_mph * MPH_MS; w = rev_rpm * 2 * math.pi / 60; rg = rg_in * IN_M
    trans = 0.5 * m * v * v; rot = 0.5 * m * rg * rg * w * w
    return dict(translational_j=trans, rotational_j=rot, total_j=trans + rot)

E_REF_J = impact_energy_j(16, 18, 450)['total_j']

def power(weight_lb, speed_mph, rev_rpm, rg_in=None) -> dict:
    """Returns {'value', 'energy_j', 'status', 'why', ...}. value is None whenever an input is missing: no guessed inputs."""
    missing = [n for n, v in (('ball weight', weight_lb), ('speed at the pocket', speed_mph), ('rev rate', rev_rpm)) if v is None]
    if missing:
        return dict(value=None, energy_j=None, status='unavailable', why='needs ' + ', '.join(missing))
    rg_default = rg_in is None
    e = impact_energy_j(weight_lb, speed_mph, rev_rpm, DEFAULT_RG_IN if rg_default else rg_in)
    return dict(value=round(min(100.0, 100 * e['total_j'] / E_REF_J)), energy_j=round(e['total_j']),
                translational_j=round(e['translational_j']), rotational_j=round(e['rotational_j']),
                status='best_effort', definition='proposed DEC-024',
                why='estimate: pocket speed and rev rate are Best effort' + ('; RG assumed 2.50 in' if rg_default else ''))
