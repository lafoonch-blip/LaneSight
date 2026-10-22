"""Ball catalog: out-of-box specs + a normalized expected reaction for recommendations (DEC-007, FEATURE_REVIEW §2.4).

Every catalog row keeps what the sources published (manufacturer specs, manufacturer ratings, bowling.com ratings)
untouched, and adds a LaneSight-normalized reaction on common 1-10 scales so balls from different brands can be
compared and ranked:

  ls_hook     1 = very little total hook ............ 10 = maximum hook / heavy-oil strength
  ls_length   1 = reads very early (rolls soon) ...... 10 = very long (skids far before it reads)
  ls_backend  1 = smooth / arcing ..................... 10 = sharp / angular change of direction
  ls_oil      dry | light | medium | medium_heavy | heavy   (center of the volume the ball is built for;
              ls_oil_min / ls_oil_max carry the manufacturer's stated range, ties round toward the lighter level)
  reaction_shape  straight | arc | continuous | angular | skid_flip

`reaction_basis` says where each normalized value came from, in priority order:
  'mfr_motion_chart' Brunswick Ball Motion Comparison Chart position (oil 1-16, shape 1-18) — one chart across the
                     seven Brunswick-family brands; tracks bowling.com hook labels (r=0.78) and stated oil (r=0.81)
  'retailer_rating'  bowling.com numeric rating, only when inside the page's own stated scale
  'mfr_rating_inferred_scale'  manufacturer numbers printed without a scale (Motiv chart, 0-100 bars)
  'mfr_rating'       the manufacturer's own published rating, mapped linearly from its stated scale
  'label'            a published word rating (e.g. "High", "Middle")
  'spec_estimate'    no published rating: estimated from cover type, RG, differential and box finish.
                     Always confidence 'low' — never shown as a published number (CLAUDE.md: label estimates).
A value that can't be derived at all is None, never a default.
"""
from __future__ import annotations
import re
from dataclasses import dataclass, asdict

CATALOG_VERSION = 'ball-catalog-1.0'
NORMALIZER_VERSION = 'ls-reaction-1.0'

OIL_LEVELS = ('dry', 'light', 'medium', 'medium_heavy', 'heavy')
SHAPES = ('straight', 'arc', 'continuous', 'angular', 'skid_flip')
TIERS = ('high', 'upper_mid', 'mid', 'entry', 'spare')

# bowling.com numeric ratings are used only when the value sits inside the page's own stated scale. Its pages are
# inconsistent (DV8 hook 325 with no scale; TZone hook shown on both 10-175 and 10-250; Kingpin 300 on "10-250"),
# so a number outside its scale, or with no scale, is ignored rather than clipped. Length: higher = longer.
def _in_scale(value, scale):
    v, rng = _num(value), parse_scale(scale)
    if v is None or rng is None or not rng[0] <= v <= rng[1]:
        return None
    return _lin(v, *rng)


# Manufacturer charts that print numbers without a scale. Motiv's reaction chart is 0-100 bars (its polyester
# spare reads Length 100 / Backend 0 / Hook 0). Values mapped with an inferred scale get basis 'mfr_rating_inferred_scale'.
UNSTATED_SCALES = {'Motiv': (0.0, 100.0)}
# Brunswick's Ball Motion Comparison Chart (one chart for Brunswick, DV8, Radical, Hammer, Ebonite, Track,
# Columbia 300): oil axis 1 (light) - 16 (heavy) ~ hook strength; shape axis 1 (smooth) - 18 (angular) ~ backend.
MOTION_OIL_RANGE = (1.0, 16.0)
MOTION_SHAPE_RANGE = (1.0, 18.0)

HOOK_LABELS = {  # word ratings -> 1-10
    'very low': 1.5, 'low': 2.5, 'low-medium': 3.5, 'medium-low': 3.5, 'low medium': 3.5,
    'medium': 5.0, 'moderate': 5.0, 'medium-high': 6.5, 'medium high': 6.5, 'high-medium': 6.5,
    'high': 8.0, 'very high': 9.0, 'extreme': 9.5, 'maximum': 9.5,
}
LENGTH_LABELS = {
    'very early': 1.5, 'early': 3.0, 'medium-early': 4.0, 'early-middle': 4.0, 'early-mid': 4.0,
    'middle': 5.5, 'medium': 5.5, 'mid': 5.5, 'middle-late': 7.0, 'medium-late': 7.0, 'mid-late': 7.0,
    'late': 8.0, 'long': 8.5, 'very long': 9.5, 'very late': 9.5,
}
SHAPE_WORDS = [  # first match wins
    (r'skid.?/?.?flip|skid flip|flip', 'skid_flip'),
    (r'angular|sharp|snap|aggressive backend|strong backend', 'angular'),
    (r'continu|controll?able backend|strong midlane|midlane', 'continuous'),
    (r'arc|smooth|even|predictable|benchmark', 'arc'),
    (r'straight|spare', 'straight'),
]
OIL_WORDS = [
    (r'heavy|high volume|high-volume|oily|fresh', None),  # resolved below with medium detection
]


@dataclass
class Reaction:
    ls_hook: float | None
    ls_length: float | None
    ls_backend: float | None
    ls_oil: str | None
    ls_oil_min: str | None
    ls_oil_max: str | None
    reaction_shape: str | None
    reaction_basis: dict          # per-field basis: {'hook': 'retailer_rating', ...}
    reaction_confidence: str      # high | medium | low
    normalizer_version: str = NORMALIZER_VERSION

    def to_dict(self):
        return asdict(self)


def _clamp(v, lo=1.0, hi=10.0):
    return round(max(lo, min(hi, v)), 1)


def _lin(v, lo, hi):
    return _clamp(1 + 9 * (float(v) - lo) / (hi - lo))


def parse_scale(scale) -> tuple[float, float] | None:
    """'10-250', 'scale: 25 - 235', '1 to 300' -> (lo, hi)."""
    if not scale:
        return None
    m = re.search(r'(-?\d+(?:\.\d+)?)\s*(?:-|–|to)\s*(\d+(?:\.\d+)?)', str(scale))
    if not m:
        return None
    lo, hi = float(m.group(1)), float(m.group(2))
    return (lo, hi) if hi > lo else None


def _num(v):
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    m = re.search(r'-?\d+(?:\.\d+)?', str(v))
    return float(m.group(0)) if m else None


def _canon(s: str) -> str:
    s = re.sub(r'\s+', ' ', s.strip().lower().replace('–', '-'))
    s = re.sub(r'\(.*?\)', '', s).strip()
    s = re.sub(r'mid[- ]?lane', 'middle', s)          # Storm charts: "Early-Mid-Lane", "Mid-lane-Late"
    s = re.sub(r'\bmid\b', 'middle', s)
    return s


def _one_label(s: str, table):
    if s in table:
        return table[s]
    hyph = s.replace(' ', '-')
    if hyph in table:
        return table[hyph]
    parts = [p for p in re.split(r'-| ', s) if p]
    vals = [table[p] for p in parts if p in table]    # "early-middle-late" style compounds -> mean of words
    if vals:
        return round(sum(vals) / len(vals), 1)
    return None


def _rating_num(v):
    """Published rating that may be a range: 6 -> 6.0, '3-4' -> 3.5, '10-11' -> 10.5, 'High' -> None."""
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    m = re.fullmatch(r'\s*(\d+(?:\.\d+)?)\s*(?:-|–|to)\s*(\d+(?:\.\d+)?)\s*', str(v))
    if m:
        return (float(m.group(1)) + float(m.group(2))) / 2
    m = re.fullmatch(r'\s*(\d+(?:\.\d+)?)\s*', str(v))
    return float(m.group(1)) if m else None


def _label(v, table):
    """Word rating -> 1-10. Ranges ('Medium to High', 'Early-Mid-Lane / Mid-lane') average their ends."""
    if not v or not isinstance(v, str):
        return None
    s = _canon(v)
    whole = _one_label(s, table) if s in table or s.replace(' ', '-') in table else None
    if whole is not None:
        return whole
    segs = [x.strip() for x in re.split(r'/|\bto\b|,', s) if x.strip()]
    vals = [x for x in (_one_label(seg, table) for seg in segs) if x is not None]
    return round(sum(vals) / len(vals), 1) if vals else None


def finish_grit(finish: str | None) -> int | None:
    """Box finish -> effective grit. '500/1500 SiaAir' -> 1500, '3000 Abralon' -> 3000, polished -> 4000+."""
    if not finish:
        return None
    s = finish.lower()
    grits = [int(g) for g in re.findall(r'(\d{3,5})', s.replace(',', '')) if 180 <= int(g) <= 30000]
    g = max(grits) if grits else None
    if 'polish' in s or 'compound' in s or 'factory finish' in s:
        g = max(g or 0, 4000)
    return g


OIL_TOKENS = {'dry': 0.0, 'light': 1.0, 'light-medium': 1.5, 'medium-light': 1.5, 'medium': 2.0,
              'medium-heavy': 3.0, 'heavy-medium': 3.0, 'heavy': 4.0}


def oil_range(text: str | None) -> tuple[str, str, str] | None:
    """Manufacturer condition text -> (min, center, max) oil levels.
    'Medium, Medium-Heavy' -> (medium, medium_heavy, medium_heavy); 'Light to medium oil' -> (light, ...);
    'Any' / 'All' / unparseable -> None (fall back to hook)."""
    if not text:
        return None
    s = text.lower().replace('–', '-')
    s = re.sub(r'\b(light|medium|heavy)/(light|medium|heavy)\b', r'\1-\2', s)   # 'Medium/Heavy' = medium-heavy
    s = re.sub(r'\b(oil|oils|volume|conditions?|patterns?|spares?|lanes?)\b', ' ', s)
    s = re.sub(r'\(.*?\)', ' ', s)
    vals = []
    for seg in re.split(r',|/|\bto\b|\band\b|&', s):
        seg = re.sub(r'\s*-\s*', '-', seg.strip())
        if seg in OIL_TOKENS:
            vals.append(OIL_TOKENS[seg])
        elif seg:
            words = [OIL_TOKENS[w] for w in re.split(r'[\s-]+', seg) if w in OIL_TOKENS]
            if words:
                vals.append(sum(words) / len(words))
    if not vals:
        return None
    import math
    def lvl(v):
        return OIL_LEVELS[int(min(4, max(0, v)))]
    lo, hi, mid = min(vals), max(vals), sum(vals) / len(vals)
    # a half level ('light-medium') widens the range: floor at the low end, ceil at the high end
    return lvl(math.floor(lo)), lvl(math.ceil(mid - 0.5)), lvl(math.ceil(hi))


def oil_from_text(text: str | None) -> str | None:
    r = oil_range(text)
    return r[1] if r else None


def shape_from_text(*texts) -> str | None:
    for t in texts:
        if not t:
            continue
        s = str(t).lower()
        for pat, shape in SHAPE_WORDS:
            if re.search(pat, s):
                return shape
    return None


# ---------- spec-based estimate (used only when nothing was published) ----------
COVER_HOOK = {'solid': 3.0, 'hybrid': 2.4, 'pearl': 1.8, 'urethane': 0.6, 'polyester': 0.0, 'other': 1.0}


def _spec_hook(rec) -> float | None:
    ct = rec.get('cover_type')
    if ct not in COVER_HOOK:
        return None
    if ct == 'polyester':
        return 1.0
    score = 2.0 + COVER_HOOK[ct]
    diff, rg = _num(rec.get('diff_15')), _num(rec.get('rg_15'))
    if diff is not None:                      # .010 -> 0, .060 -> +3
        score += max(0.0, min(3.0, (diff - 0.010) / 0.050 * 3.0))
    if rg is not None:                        # 2.58 -> 0, 2.46 -> +1
        score += max(0.0, min(1.0, (2.58 - rg) / 0.12))
    g = finish_grit(rec.get('factory_finish'))
    if g is not None:                         # dull adds read, polish removes it
        score += 0.8 if g <= 1000 else 0.4 if g <= 2000 else 0.0 if g <= 3000 else -0.6
    if rec.get('core_type') == 'asymmetric':
        score += 0.4
    return _clamp(score)


def _spec_length(rec) -> float | None:
    ct = rec.get('cover_type')
    g = finish_grit(rec.get('factory_finish'))
    if ct is None and g is None:
        return None
    score = 5.0 + {'pearl': 1.5, 'hybrid': 0.3, 'solid': -1.0, 'urethane': -1.5, 'polyester': 3.0}.get(ct, 0.0)
    if g is not None:
        score += -1.0 if g <= 1000 else -0.4 if g <= 2000 else 0.3 if g <= 3000 else 1.2
    rg = _num(rec.get('rg_15'))
    if rg is not None:                        # higher RG revs up later
        score += max(-0.8, min(0.8, (rg - 2.52) / 0.06 * 0.8))
    return _clamp(score)


def _spec_backend(rec) -> float | None:
    ct = rec.get('cover_type')
    if ct is None:
        return None
    score = {'pearl': 7.0, 'hybrid': 5.5, 'solid': 4.0, 'urethane': 2.0, 'polyester': 1.0}.get(ct, 4.5)
    diff = _num(rec.get('diff_15'))
    if diff is not None and ct not in ('urethane', 'polyester'):
        score += max(-1.0, min(1.5, (diff - 0.035) / 0.020))
    g = finish_grit(rec.get('factory_finish'))
    if g is not None and g >= 3000:
        score += 0.8
    return _clamp(score)


def _shape_from_numbers(rec, hook, length, backend) -> str | None:
    ct = rec.get('cover_type')
    if ct == 'polyester':
        return 'straight'
    if ct == 'urethane':
        return 'arc'
    if backend is None:
        return None
    if length is not None and length >= 7 and backend >= 7:
        return 'skid_flip'
    if backend >= 6.5:
        return 'angular'
    if backend <= 4.0:
        return 'arc'
    return 'continuous'


def _oil_from_hook(hook) -> str | None:
    if hook is None:
        return None
    return 'heavy' if hook >= 8.5 else 'medium_heavy' if hook >= 7 else 'medium' if hook >= 5 else 'light' if hook >= 3 else 'dry'


def normalize(rec: dict) -> Reaction:
    """Derive the LaneSight reaction for one catalog record. Pure: never mutates `rec`."""
    rr = rec.get('retailer_ratings') or {}
    mr = rec.get('mfr_ratings') or {}
    mc = rec.get('motion_chart') or {}
    basis: dict[str, str] = {}

    # hook
    hook = None
    if _num(mc.get('oil')) is not None:
        hook, basis['hook'] = _lin(_num(mc['oil']), *MOTION_OIL_RANGE), 'mfr_motion_chart'
    elif (v := _in_scale(rr.get('hook_potential'), rr.get('hook_potential_scale'))) is not None:
        hook, basis['hook'] = v, 'retailer_rating'
    elif _rating_num(mr.get('hook')) is not None and parse_scale(mr.get('hook_scale')):
        hook, basis['hook'] = _lin(_rating_num(mr['hook']), *parse_scale(mr['hook_scale'])), 'mfr_rating'
    elif _rating_num(mr.get('hook')) is not None and rec.get('manufacturer') in UNSTATED_SCALES:
        hook, basis['hook'] = _lin(_rating_num(mr['hook']), *UNSTATED_SCALES[rec['manufacturer']]), 'mfr_rating_inferred_scale'
    elif _label(mr.get('hook'), HOOK_LABELS) is not None:
        hook, basis['hook'] = _label(mr['hook'], HOOK_LABELS), 'label'
    elif _label(rr.get('hook_potential_label'), HOOK_LABELS) is not None:
        hook, basis['hook'] = _label(rr['hook_potential_label'], HOOK_LABELS), 'label'
    elif (h := _spec_hook(rec)) is not None:
        hook, basis['hook'] = h, 'spec_estimate'

    # length (higher = longer)
    length = None
    if (v := _in_scale(rr.get('length'), rr.get('length_scale'))) is not None:
        length, basis['length'] = v, 'retailer_rating'
    elif _rating_num(mr.get('length')) is not None and parse_scale(mr.get('length_scale')):
        length, basis['length'] = _lin(_rating_num(mr['length']), *parse_scale(mr['length_scale'])), 'mfr_rating'
    elif _rating_num(mr.get('length')) is not None and rec.get('manufacturer') in UNSTATED_SCALES:
        length, basis['length'] = _lin(_rating_num(mr['length']), *UNSTATED_SCALES[rec['manufacturer']]), 'mfr_rating_inferred_scale'
    elif _label(mr.get('length'), LENGTH_LABELS) is not None:
        length, basis['length'] = _label(mr['length'], LENGTH_LABELS), 'label'
    elif _label(rr.get('length_label'), LENGTH_LABELS) is not None:
        length, basis['length'] = _label(rr['length_label'], LENGTH_LABELS), 'label'
    elif (ln := _spec_length(rec)) is not None:
        length, basis['length'] = ln, 'spec_estimate'

    # backend
    backend = None
    if _num(mc.get('shape')) is not None:
        backend, basis['backend'] = _lin(_num(mc['shape']), *MOTION_SHAPE_RANGE), 'mfr_motion_chart'
    elif _rating_num(mr.get('backend')) is not None and parse_scale(mr.get('backend_scale')):
        backend, basis['backend'] = _lin(_rating_num(mr['backend']), *parse_scale(mr['backend_scale'])), 'mfr_rating'
    elif _rating_num(mr.get('backend')) is not None and rec.get('manufacturer') in UNSTATED_SCALES:
        backend, basis['backend'] = _lin(_rating_num(mr['backend']), *UNSTATED_SCALES[rec['manufacturer']]), 'mfr_rating_inferred_scale'
    elif (b := _spec_backend(rec)) is not None:
        backend, basis['backend'] = b, 'spec_estimate'

    # shape: published words first, then numbers
    shape = shape_from_text(mr.get('reaction_shape'), rr.get('reaction_label'))
    if shape:
        basis['shape'] = 'mfr_rating' if shape_from_text(mr.get('reaction_shape')) else 'retailer_rating'
    elif rec.get('cover_type') == 'polyester':
        shape, basis['shape'] = 'straight', 'spec_estimate'
    else:
        shape = _shape_from_numbers(rec, hook, length, backend)
        if shape:
            basis['shape'] = 'spec_estimate'

    # oil volume: manufacturer's stated condition first
    rng = oil_range(rec.get('recommended_oil'))
    oil_min = oil_max = None
    if rng:
        oil_min, oil, oil_max = rng
        basis['oil'] = 'mfr_rating'
    elif (o := _oil_from_hook(hook)) is not None:
        oil, basis['oil'] = o, 'derived_from_hook'
    else:
        oil = None

    published = {'retailer_rating', 'mfr_rating', 'mfr_motion_chart', 'mfr_rating_inferred_scale'}
    core = [basis.get('hook'), basis.get('length')]
    if all(b in published for b in core):
        conf = 'high'
    elif any(b in published | {'label'} for b in core):
        conf = 'medium'
    else:
        conf = 'low'
    return Reaction(hook, length, backend, oil, oil_min, oil_max, shape, basis, conf)


# ---------- validation ----------
REQUIRED = ('manufacturer', 'name', 'cover_type', 'product_url')


def validate(rec: dict) -> list[str]:
    """Problems that block loading. Missing optional specs are fine (they stay null), wrong types are not."""
    errs = [f'missing {k}' for k in REQUIRED if not rec.get(k)]
    if rec.get('cover_type') and rec['cover_type'] not in ('solid', 'pearl', 'hybrid', 'urethane', 'polyester', 'other'):
        errs.append(f"bad cover_type {rec['cover_type']!r}")
    if rec.get('core_type') and rec['core_type'] not in ('symmetric', 'asymmetric', 'pancake', 'unknown'):
        errs.append(f"bad core_type {rec['core_type']!r}")
    if rec.get('performance_tier') and rec['performance_tier'] not in TIERS:
        errs.append(f"bad performance_tier {rec['performance_tier']!r}")
    rg, diff, idiff = _num(rec.get('rg_15')), _num(rec.get('diff_15')), _num(rec.get('int_diff_15'))
    if rg is not None and not 2.40 <= rg <= 2.80:
        errs.append(f'rg_15 {rg} outside 2.40-2.80')
    if diff is not None and not 0.0 <= diff <= 0.080:
        errs.append(f'diff_15 {diff} outside 0-0.080')
    if idiff is not None and not 0.0 <= idiff <= 0.040:
        errs.append(f'int_diff_15 {idiff} outside 0-0.040')
    for k in ('image_url', 'product_url'):
        if rec.get(k) and not str(rec[k]).startswith('https://'):
            errs.append(f'{k} not https')
    if not rec.get('spec_source_urls'):
        errs.append('no spec_source_urls')
    return errs


def catalog_key(rec: dict) -> tuple[str, str]:
    return (rec['manufacturer'].strip(), rec['name'].strip())
