"""Oil-pattern library and a modeled top-down oil field for the lane view.

LaneSight cannot measure oil from video (video can't see oil; see RUNNER_V2_SPEC "Not in the runner"). What the
lane view shows is a REPRESENTATION of the oil pattern the bowler selected at session start — modeled from each
pattern's published spec (length, ratio, volume), NOT a scan of the actual lane. The library holds real published
specs; oil_field() turns a spec into a normalized board x distance grid for the heatmap.

The model: a cross-section across the boards (a crown whose steepness comes from the pattern's center:outside
ratio — steep for a house shot, nearly flat for a sport pattern; inverted for a reverse-block pattern like
Shark), times a longitudinal profile that runs full strength from the foul line and tapers to zero at the
pattern length. The grid is normalized per pattern so the heaviest area reads as full intensity.
"""
from __future__ import annotations


BOARDS = 39

# Real published specs (2025–2026 WSOB values for the PBA animals; the house shot is the typical recreational
# condition and varies by centre). ratio = centre:outside oil; reverse = edge-heavy (centre drier).
PATTERNS = [
    dict(id='house',     name='Typical house shot', length_ft=41, volume_ml=24.15, ratio=8.0,  category='house'),
    dict(id='cheetah',   name='PBA Cheetah',        length_ft=33, volume_ml=26.31, ratio=1.2,  category='sport'),
    dict(id='wolf',      name='PBA Wolf',           length_ft=34, volume_ml=31.8,  ratio=1.31, category='sport'),
    dict(id='viper',     name='PBA Viper',          length_ft=37, volume_ml=25.55, ratio=2.65, category='sport'),
    dict(id='bear',      name='PBA Bear',           length_ft=38, volume_ml=29.6,  ratio=2.01, category='sport'),
    dict(id='chameleon', name='PBA Chameleon',      length_ft=39, volume_ml=30.43, ratio=2.4,  category='sport'),
    dict(id='scorpion',  name='PBA Scorpion',       length_ft=42, volume_ml=28.9,  ratio=2.3,  category='sport'),
    dict(id='shark',     name='PBA Shark',          length_ft=48, volume_ml=29.2,  ratio=2.0,  category='sport', reverse=True),
]
_BY_ID = {p['id']: p for p in PATTERNS}


def find(name_or_id):
    """Match a session's pattern to a library entry by id or display name (case-insensitive, substring either
    way so 'House shot' resolves to 'Typical house shot'), or None."""
    if not name_or_id: return None
    key = str(name_or_id).strip().lower()
    if key in _BY_ID: return _BY_ID[key]
    for p in PATTERNS:
        nm = p['name'].lower()
        if key == nm or key == p['id'] or key in nm or nm in key: return p
    return None


def _oil_value(board, z, length, ratio, reverse, taper=8.0):
    """Relative oil at (board 1..39, z ft), shaped like a real Kegel pattern graph: a flat-topped plateau of
    heavy oil across the middle boards, steep shoulders down to a low non-zero baseline on the outside
    (baseline = 1/ratio, e.g. 1/8 for a house shot), running full strength from the foul line and tapering to
    zero over the last `taper` ft; the oiled WIDTH also narrows toward the pattern end (the reverse brush lifts
    off first). reverse = edge-heavy (centre drier), as on a Shark block."""
    if z >= length: return 0.0
    g = 1.0 if z <= length - taper else (length - z) / taper            # longitudinal strength
    baseline = 1.0 / ratio
    nz = length * 0.6                                                    # width narrows past ~60% of the length
    narrow = 1.0 if z <= nz else max(0.42, 1 - 0.58 * (z - nz) / (length - nz))
    plateau, shoulder = 0.40 * narrow, 0.22
    d = abs(board - 20) / 19.0                                          # 0 at centre board 20, 1 at the gutters
    if d <= plateau: v = 1.0
    elif d <= plateau + shoulder: v = 1 - (1 - baseline) * (d - plateau) / shoulder
    else: v = baseline
    if reverse: v = 1 + baseline - v
    return v * g


def oil_field(pattern, dz=2.0):
    """Normalized board x distance oil grid (0..1) for the heatmap. grid[z_index][board_index]; board index 0
    is board 1. Values are relative within the pattern (heaviest area = 1)."""
    length = pattern['length_ft']
    zs = [round(z, 1) for z in _frange(0.0, min(length + 4, 62.0), dz)]
    reverse = pattern.get('reverse', False)
    grid = [[_oil_value(b, z, length, pattern['ratio'], reverse) for b in range(1, BOARDS + 1)] for z in zs]
    mx = max((max(row) for row in grid), default=0.0) or 1.0
    grid = [[round(v / mx, 3) for v in row] for row in grid]
    return dict(
        grid=grid, boards=BOARDS, z_ft=zs, length_ft=length, name=pattern['name'],
        label=f"{pattern['name']} · {length} ft · {pattern['ratio']}:1 · {pattern['volume_ml']} mL",
        source='Modeled from the published pattern spec — a representation of the applied oil, not a scan of this lane.')


def _frange(a, b, step):
    out, v = [], a
    while v < b + 1e-9:
        out.append(v); v += step
    return out


def library():
    """Patterns for the session-start picker (no grid)."""
    return [dict(id=p['id'], name=p['name'], length_ft=p['length_ft'], category=p['category']) for p in PATTERNS]
