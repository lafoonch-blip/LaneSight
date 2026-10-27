"""Parse bowwwl.com ball pages into RECORD_SPEC records for retired Storm, Roto Grip, 900 Global and Motiv balls.

    python data/ball_catalog/backfill/bowwwl.py <pages_dir> <raw_dir> <out_dir>      (needs beautifulsoup4 + lxml)

Why bowwwl: Storm Products deletes a ball's page when it's retired (its product search lists only the current
lineup), and Motiv blocks bulk downloads, so for these four brands there is no manufacturer page to read. Shayne chose
bowwwl.com (fan-run database: release month, per-weight RG/diff/mass-bias, discontinued flag) on 2026-10-27, with
every record labelled as coming from it. No photo: bowwwl hosts its own copies, so image_url stays null.

<pages_dir> holds `<brand-slug>__<ball-slug>.html` (bowwwl.com/bowling-ball-database/<brand-slug>/<ball-slug>).
A ball is written only when it is NOT in the brand's current lineup (raw/<brand>.json, status current); it gets
status 'discontinued'. Only balls bowwwl flags 'Discontinued' are added: unflagged ones missing from the current
lineup turned out to be current balls under another name, or overseas releases that may still be sold.
"""
from __future__ import annotations
import json, re, sys
from pathlib import Path
from bs4 import BeautifulSoup

BRANDS = {  # bowwwl slug -> (manufacturer, parent, raw file)
    'storm': ('Storm', 'Storm Products', 'storm.json'),
    'roto-grip': ('Roto Grip', 'Storm Products', 'rotogrip.json'),
    '900-global': ('900 Global', 'Storm Products', '900global.json'),
    'motiv': ('Motiv', 'Motiv', 'motiv.json'),
}
MONTHS = {m: i for i, m in enumerate(['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov',
                                      'dec'], 1)}


def norm(name: str) -> str:
    s = name.lower().replace('!q', 'iq').replace('&', 'and')
    return re.sub(r'[^a-z0-9]', '', s)


def text(el, sep=' | '):
    return el.get_text(sep, strip=True) if el else ''


def field(s, name):
    return s.select_one(f'.field--name-field-{name}')


def value_of(el) -> str | None:
    """Value of a 'Label | value' field."""
    if not el:
        return None
    items = el.select('.field__item')
    v = text(items[-1]) if items else ''
    return v or None


def cover_type(t: str | None) -> str | None:
    if not t:
        return None
    s = t.lower()
    for k, words in (('urethane', ('urethane',)), ('polyester', ('polyester', 'plastic')), ('hybrid', ('hybrid',)),
                     ('pearl', ('pearl',)), ('solid', ('solid',))):
        if any(w in s for w in words):
            return k
    return None



def in_range(rg, diff, idiff, notes, where):
    """A published number outside what a bowling ball can be (RG 2.40-2.80, diff 0-0.080, int diff 0-0.040) is a
    typo on the source page: keep the ball, drop that value, say what was printed."""
    out = []
    for lab, v, lo, hi in (('RG', rg, 2.40, 2.80), ('diff', diff, 0.0, 0.080), ('int diff', idiff, 0.0, 0.040)):
        if v is not None and not lo <= v <= hi:
            notes.append(f'{where} prints 15 lb {lab} {v}, outside {lo}-{hi} (likely a typo); left null.')
            v = None
        out.append(v)
    return tuple(out)

def num(v):
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    return round(x, 3)


def parse(brand: str, slug: str, raw: str) -> dict | None:
    manufacturer, parent, _ = BRANDS[brand]
    url = f'https://www.bowwwl.com/bowling-ball-database/{brand}/{slug}'
    s = BeautifulSoup(raw, 'lxml')
    h1 = s.select_one('h1')
    name = re.sub(r'\s+', ' ', text(h1, ' ')).strip() if h1 else None
    if not name or not field(s, 'core-specs') and not field(s, 'coverstock'):
        return None
    notes = ['Retired ball. Specs from bowwwl.com (fan-run database), not the manufacturer: '
             f'{manufacturer} no longer publishes a page for it (backfill 2026-10-27).']
    disc = bool(text(field(s, 'discontinued')))
    intl = bool(text(field(s, 'international')))
    if not disc:
        # Unflagged balls missing from the current lineup were mostly current balls under another name
        # (bowwwl 'Hustle M-M' = Roto Grip 'Hustle M+M', 'Global Onyx Clear' = 'Onyx Clear') or overseas releases
        # that may still be sold. Only balls bowwwl itself marks discontinued are added.
        return {'_skip': 'not flagged discontinued on bowwwl' + (' (international release)' if intl else '')}
    if intl:
        notes.append('bowwwl lists it as an overseas/international release.')
    rel = None
    if (rv := value_of(field(s, 'release-date'))):
        m = re.match(r'([A-Za-z]{3})[a-z]* (\d{4})', rv)
        if m and m.group(1).lower() in MONTHS:
            rel = f'{m.group(2)}-{MONTHS[m.group(1).lower()]:02d}'
        elif re.fullmatch(r'\d{4}', rv):
            rel = rv
    cov = field(s, 'coverstock')
    cov_name = None
    if cov:
        first = cov.find(string=True, recursive=True)
        parts = [p for p in text(cov).split(' | ') if p]
        cov_name = parts[0] if parts and parts[0] not in ('Type',) else None
        if cov_name:
            cov_name = re.sub(r'\s+Coverstock$', '', cov_name).strip() or None
    cov_type_txt = value_of(field(s, 'coverstock-type'))
    ctype = cover_type(cov_type_txt) or cover_type(cov_name)
    if ctype and not cover_type(cov_type_txt):
        notes.append(f"cover_type from the coverstock name '{cov_name}'.")
    core = field(s, 'core')
    core_name = None
    if core:
        parts = [p for p in text(core).split(' | ') if p]
        core_name = parts[0] if parts and parts[0] not in ('Core Type',) else None
    core_t = (value_of(field(s, 'core-type')) or '').lower()
    core_type = 'asymmetric' if 'asym' in core_t else 'symmetric' if 'sym' in core_t else (
        'pancake' if 'pancake' in core_t else None)
    rg = diff = mb = None
    for card in s.select('.paragraph--type--core-specs'):
        title = text(card.select_one('.card-title'), ' ')
        if re.match(r'15 (pounds|lbs?)\b', title):
            rg = num(value_of(card.select_one('.field--name-field-rg')))
            diff = num(value_of(card.select_one('.field--name-field-differential')))
            mb = num(value_of(card.select_one('.field--name-field-mass-bias-differential')))
    if rg is None and diff is None:
        others = [text(c.select_one('.card-title'), ' ') for c in s.select('.paragraph--type--core-specs')
                  if c.select_one('.field--name-field-rg')]
        if others:
            notes.append(f"bowwwl gives core numbers only for {', '.join(others)}; 15 lb fields left null.")
    rg, diff, mb = in_range(rg, diff, mb, notes, 'bowwwl')
    finish = value_of(field(s, 'factory-finish'))
    rec = {
        'manufacturer': manufacturer, 'parent_company': parent, 'name': name,
        'product_line': None, 'performance_tier': None, 'release_date': rel,
        'colors': None, 'coverstock_name': cov_name, 'cover_type': ctype or 'other',
        'core_name': core_name, 'core_type': core_type,
        'rg_15': rg, 'diff_15': diff, 'int_diff_15': mb,
        'factory_finish': finish, 'recommended_oil': None,
        'mfr_ratings': None, 'retailer_ratings': None, 'motion_chart': None, 'reaction_description': None,
        'image_url': None, 'image_source': None,
        'product_url': url, 'spec_source_urls': [url],
        'status': 'discontinued',
        'notes': ' '.join(notes),
    }
    if mb is not None:
        rec['notes'] += ' int_diff_15 = bowwwl "MB Diff" (mass-bias / intermediate differential, 15 lb).'
    rec['missing'] = [k for k in ('product_line', 'performance_tier', 'release_date', 'colors', 'coverstock_name',
                                  'core_name', 'core_type', 'rg_15', 'diff_15', 'int_diff_15', 'factory_finish',
                                  'recommended_oil', 'image_url') if rec.get(k) is None]
    rec['missing'] += ['mfr_ratings', 'retailer_ratings', 'motion_chart', 'reaction_description']
    if not ctype:
        rec['missing'].append('cover_type')
    return rec


def main(pages: Path, raw_dir: Path, out: Path):
    out.mkdir(parents=True, exist_ok=True)
    for brand, (manufacturer, _, raw_file) in BRANDS.items():
        current = {norm(r['name']) for r in json.loads((raw_dir / raw_file).read_text())
                   if (r.get('status') or 'current') == 'current'}
        recs, skipped, seen = [], [], set()
        for f in sorted(pages.glob(f'{brand}__*.html')):
            slug = f.stem.split('__', 1)[1]
            rec = parse(brand, slug, f.read_text(errors='replace'))
            if not rec:
                skipped.append((slug, 'no ball data on page'))
                continue
            if '_skip' in rec:
                skipped.append((slug, rec['_skip']))
                continue
            k = norm(rec['name'])
            if k in current:
                skipped.append((slug, 'in current lineup'))
                continue
            if k in seen:
                skipped.append((slug, 'duplicate name'))
                continue
            seen.add(k)
            recs.append(rec)
        (out / raw_file).write_text(json.dumps(recs, indent=1, ensure_ascii=False))
        print(manufacturer, len(recs), 'written;', len(skipped), 'skipped', file=sys.stderr)
        (out / (raw_file + '.skipped.json')).write_text(json.dumps(skipped, indent=1))


if __name__ == '__main__':
    main(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
