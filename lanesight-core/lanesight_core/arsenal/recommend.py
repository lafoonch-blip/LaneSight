"""Ball recommendations from the catalog's normalized reaction (catalog.normalize).

Two questions the app asks:
  1. rank_for_condition  — "which ball (mine or from the catalog) fits this pattern for my game?"
  2. arsenal_gaps        — "which catalog ball covers ground my arsenal doesn't?"

STATUS: provisional heuristics (best_effort). The target formulas and weights below are starting values that
need review by a pro-shop operator / certified coach before beta (BUILD_PLAN M4-08), and later calibration from
observed shots (a ball's measured breakpoint/entry on known patterns beats its catalog rating). Every result
carries `basis` and `confidence` so the UI can say how sure it is, and balls whose reaction is only a
spec_estimate are flagged rather than hidden.
"""
from __future__ import annotations
import math
from dataclasses import dataclass, field

from .catalog import OIL_LEVELS

RECOMMENDER_VERSION = 'ls-recommend-0.1-provisional'


@dataclass
class Condition:
    pattern_length_ft: float | None = None   # oil_patterns.length_ft
    volume_ml: float | None = None           # oil_patterns.volume_ml
    oil_level: str | None = None             # overrides volume when the user picks it (house shot = 'medium')
    speed_mph: float | None = None           # bowler baseline (60 ft average speed, DEC-022/036)
    rev_rate_rpm: float | None = None        # bowler baseline


@dataclass
class Target:
    hook: float
    length: float
    oil_level: str
    reasons: list[str] = field(default_factory=list)


def oil_level_from_volume(ml: float | None) -> str | None:
    if ml is None:
        return None
    return 'light' if ml < 19 else 'medium' if ml < 24 else 'medium_heavy' if ml < 28 else 'heavy'


def target_for(cond: Condition) -> Target:
    reasons = []
    oil = cond.oil_level or oil_level_from_volume(cond.volume_ml) or 'medium'
    if not (cond.oil_level or cond.volume_ml):
        reasons.append('no oil volume given: assuming a medium (house) volume')
    hook = {'dry': 2.5, 'light': 4.0, 'medium': 5.5, 'medium_heavy': 7.0, 'heavy': 8.5}[oil]
    length = 5.5
    if cond.pattern_length_ft is not None:
        # longer patterns -> ball that reads earlier; shorter -> cleaner through the front
        length += (40 - cond.pattern_length_ft) * 0.15
        reasons.append(f'{cond.pattern_length_ft:.0f} ft pattern')
    if cond.rev_rate_rpm is not None:
        # more revs = more hook from any ball, so ask less of the equipment (per 100 rpm vs a 350 rpm midpoint)
        hook -= (cond.rev_rate_rpm - 350) / 100
        reasons.append(f'{cond.rev_rate_rpm:.0f} rpm')
    if cond.speed_mph is not None:
        # faster speed needs a stronger, earlier ball; slower speed needs more length
        hook += (cond.speed_mph - 17.0) * 0.4
        length -= (cond.speed_mph - 17.0) * 0.4
        reasons.append(f'{cond.speed_mph:.1f} mph')
    return Target(round(max(1, min(10, hook)), 1), round(max(1, min(10, length)), 1), oil, reasons)


def _fit(ball: dict, t: Target) -> tuple[float | None, list[str]]:
    h, ln = ball.get('ls_hook'), ball.get('ls_length')
    if h is None or ln is None:
        return None, ['no reaction data']
    notes = []
    score = 100 - 12 * abs(h - t.hook) - 8 * abs(ln - t.length)
    lo, hi = ball.get('ls_oil_min') or ball.get('ls_oil'), ball.get('ls_oil_max') or ball.get('ls_oil')
    if lo in OIL_LEVELS and hi in OIL_LEVELS:
        want = OIL_LEVELS.index(t.oil_level)
        gap = max(OIL_LEVELS.index(lo) - want, want - OIL_LEVELS.index(hi), 0)   # 0 when inside the stated range
        if gap >= 1:
            score -= 15 * gap
            span = lo if lo == hi else f'{lo}-{hi}'
            notes.append(f"built for {span.replace('_', '-')} oil")
    if h - t.hook > 1.5:
        notes.append('stronger than needed: likely to hook early')
    elif t.hook - h > 1.5:
        notes.append('weaker than needed: may skid through the pocket')
    if ln - t.length > 1.5:
        notes.append('longer than ideal')
    elif t.length - ln > 1.5:
        notes.append('reads earlier than ideal')
    return round(max(0.0, min(100.0, score)), 1), notes


def rank_for_condition(balls: list[dict], cond: Condition, top: int = 5) -> dict:
    """balls: catalog rows (or user balls joined to their catalog row) carrying ls_* fields.
    Returns the target and the best-fitting balls, each with its fit score and the reaction basis."""
    t = target_for(cond)
    ranked = []
    for b in balls:
        s, notes = _fit(b, t)
        if s is None:
            continue
        ranked.append({
            'manufacturer': b.get('manufacturer'), 'name': b.get('name'), 'id': b.get('id'),
            'fit': s, 'notes': notes,
            'reaction_confidence': b.get('reaction_confidence'),
            'estimated': (b.get('reaction_basis') or {}).get('hook') == 'spec_estimate',
        })
    ranked.sort(key=lambda r: (-r['fit'], r['estimated']))
    return {'target': t.__dict__, 'results': ranked[:top], 'status': 'best_effort',
            'version': RECOMMENDER_VERSION}


def arsenal_gaps(owned: list[dict], catalog: list[dict], top: int = 5, min_gap: float = 1.5) -> dict:
    """Catalog balls farthest (in hook × length × backend space) from everything the bowler owns.
    Spare/polyester balls are skipped as candidates; owned balls without reaction data are ignored."""
    def pt(b):
        if b.get('ls_hook') is None or b.get('ls_length') is None:
            return None
        return (b['ls_hook'], b['ls_length'], b.get('ls_backend') or 5.0)

    have = [p for p in (pt(b) for b in owned) if p]
    owned_keys = {(b.get('manufacturer'), b.get('name')) for b in owned}
    out = []
    for c in catalog:
        if c.get('cover_type') == 'polyester' or (c.get('manufacturer'), c.get('name')) in owned_keys:
            continue
        p = pt(c)
        if not p:
            continue
        d = min((math.dist(p, q) for q in have), default=float('inf'))
        if d >= min_gap:
            out.append({'manufacturer': c.get('manufacturer'), 'name': c.get('name'), 'id': c.get('id'),
                        'distance': round(d, 2) if d != float('inf') else None,
                        'ls_hook': c['ls_hook'], 'ls_length': c['ls_length'],
                        'reaction_shape': c.get('reaction_shape'),
                        'estimated': (c.get('reaction_basis') or {}).get('hook') == 'spec_estimate'})
    out.sort(key=lambda r: (r['estimated'], -(r['distance'] or 99)))
    return {'owned_points': len(have), 'results': out[:top], 'status': 'best_effort',
            'version': RECOMMENDER_VERSION}
