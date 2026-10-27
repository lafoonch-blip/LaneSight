"""Parse retired-ball pages from Brunswick's own brand sites into RECORD_SPEC records.

    python data/ball_catalog/backfill/brunswick_family.py <pages_dir> <out_dir>

<pages_dir> holds `<brand>__<slug>.html` files downloaded from
  - brunswickbowling.com / dv8bowling.com / radicalbowling.com  /products/balls/retired/<slug>
  - hammerbowling.com / ebonite.com / trackbowling.com          /products/<handle>  (Shopify `retired-balls` collection)
Writes <out_dir>/<brand>.json (status 'discontinued', discontinued_on null: the retirement date isn't published).

Rules (RECORD_SPEC): only values printed on the manufacturer's page; anything else is null and listed in `missing`.
15 lb RG/diff/intermediate diff come from the page's per-weight table or a value explicitly labelled 15 lb; a value
for another weight only goes in `notes`.
"""
from __future__ import annotations
import html as htmllib, json, re, sys
from pathlib import Path

BRANDS = {
    'brunswick': ('Brunswick', 'https://brunswickbowling.com/products/balls/retired/{}'),
    'dv8': ('DV8', 'https://dv8bowling.com/products/balls/retired/{}'),
    'radical': ('Radical', 'https://radicalbowling.com/products/balls/retired/{}'),
    'hammer': ('Hammer', 'https://hammerbowling.com/products/{}'),
    'ebonite': ('Ebonite', 'https://ebonite.com/products/{}'),
    'track': ('Track', 'https://trackbowling.com/products/{}'),
}

# Manufacturer performance level -> performance_tier (same mapping as the current-lineup records). Brunswick's
# "High" sits below "Pro"; Hammer's and Track's "High" is their top level.
TIER = {
    'brunswick': {'pro': 'high', 'high': 'upper_mid', 'advanced': 'mid', 'affordable': 'entry', 'polyester': 'spare'},
    'dv8': {'$$$$$$': 'high', '$$$$$': 'upper_mid', '$$$$': 'mid', '$$$': 'mid', '$$': 'entry', '$': 'entry'},
    'radical': {'top shelf': 'high', 'reliable plus': 'upper_mid', 'reliable': 'mid', 'ez-use': 'entry',
                'ez use': 'entry', 'performance polyester': 'spare', 'polyester': 'spare'},
    'hammer': {'high': 'high', 'upper mid': 'upper_mid', 'mid': 'mid', 'lower mid': 'entry', 'spare ball': 'spare',
               'spare': 'spare'},
    'track': {'high': 'high', 'upper mid': 'upper_mid', 'mid': 'mid', 'lower mid': 'entry', 'affordable': 'entry',
              'spare': 'spare'},
    'ebonite': {},
}


def level_of(brand: str, raw: str | None) -> tuple[str | None, str | None]:
    """(level as printed, tier). Only a known level word counts (a page typo like 'Affordable Part Numer' keeps
    'Affordable'); anything else is not treated as a level."""
    if not raw:
        return None, None
    s = raw.strip()
    for k in sorted(TIER[brand], key=len, reverse=True):
        if s.lower() == k or s.lower().startswith(k + ' '):
            return s[:len(k)], TIER[brand][k]
    return (s, None) if brand in ('brunswick', 'dv8', 'radical') else (None, None)

# Spec labels as the sites print them. Longest first so "CORE TYPE" wins over "CORE".
LABELS = [
    'Reaction Shape Strength', 'Best Lane Condition', 'Core Shape', 'Available Weights', 'Factory Finish', 'Lane Condition',
    'Part Number', 'Release Date', 'Cover Type', 'Core Type', 'Coverstock', 'Performance', 'Warranty', 'Weights',
    'Weight', 'Reaction', 'Finish', 'Level', 'Color', 'Core', 'Mass Bias', 'Hook', 'Length',
    'INT DIFF', 'RG', 'DIFF', 'ASY',  # terminators only (numbers are read by weight15)
]
STOP = r'(?:Performance Index|Resources|DOWNLOADS|Downloads|Pro Shop Locator|Stay Informed|Learn more|Share |Warranty Info|Core Numbers|$)'


def clean(raw: str) -> str:
    t = re.sub(r'<script.*?</script>|<style.*?</style>', ' ', raw, flags=re.S)
    t = re.sub(r'<[^>]+>', ' ', t)
    return htmllib.unescape(re.sub(r'\s+', ' ', t))


def meta(raw: str, prop: str) -> str | None:
    m = (re.search(rf'<meta[^>]*property="{prop}"[^>]*content="([^"]*)"', raw)
         or re.search(rf'<meta[^>]*content="([^"]*)"[^>]*property="{prop}"', raw))
    return htmllib.unescape(m.group(1)).strip() if m else None


def spec_region(t: str) -> str | None:
    starts = [m.end() for m in re.finditer(r'(Spec Table|BALL SPECS|Specifications)\b', t)]
    if not starts:
        return None
    s = starts[0]
    m = re.search(STOP, t[s:])
    region = t[s:s + (m.start() if m else 1500)]
    return region[:1500]


def labelled(region: str) -> dict:
    """Split 'Label value Label value ...' into a dict. A page prints its labels either all in Title case (Brunswick
    family, Track, Ebonite) or all in UPPER case (Hammer); only that style counts as a label, so words like 'Factory
    Finish' or 'Hook' inside an UPPER-case page's values don't split them. In Title-case pages only the first letter
    must be capital ('Factory finish' counts). Number labels (Hook, Length, RG, DIFF, ASY, Mass Bias) count only
    before a number, so 'Hitman Low RG Asymmetric' stays one value. A label already seen is not a boundary again
    for Finish ('... Power House Factory Finish Polish' stays inside the Finish value)."""
    upper = bool(re.search(r'\b(COLOR|COVERSTOCK|CORE)\b', region))
    pats = []
    for lab in LABELS:
        if lab.isupper() or upper:
            p = re.escape(lab.upper())
        else:
            p = re.escape(lab[0]) + '(?i:' + re.escape(lab[1:]) + ')'
        if lab in ('Hook', 'Length', 'INT DIFF', 'RG', 'DIFF', 'ASY'):
            p += r'(?=:? ?[\d.(#/])'
        pats.append(p)
    rx = re.compile(r'(?<![A-Za-z])(' + '|'.join(sorted(pats, key=len, reverse=True)) + r')(?![A-Za-z])')

    alias = {'Factory Finish': 'Finish', 'Best Lane Condition': 'Lane Condition', 'Available Weights': 'Weights',
             'Weight': 'Weights'}

    def key_of(lab):
        k = lab.upper() if lab.upper() in ('INT DIFF', 'RG', 'DIFF', 'ASY') else lab.title()
        return alias.get(k, k)

    hits, seen = [], set()
    for h in rx.finditer(region):
        k = key_of(h.group(1))
        if k == 'Finish' and k in seen:
            continue  # '... Polished with Power House Factory Finish Polish' is one finish value
        seen.add(k)
        hits.append((k, h))
    out = {}
    for i, (key, h) in enumerate(hits):
        end = hits[i + 1][1].start() if i + 1 < len(hits) else len(region)
        val = region[h.end():end].strip(' :-|')
        if val and key not in out:
            out[key] = val
    return out


NUM = r'(\d?\.\d{2,3})'


def weight15(t: str) -> tuple[dict, list[str]]:
    """15 lb RG/diff/int diff with the evidence used. Returns ({rg, diff, int}, notes)."""
    v, notes = {}, []
    # a) row table: Core Numbers 16 lb 15 lb 14 lb ... RG a b c ... DIFF a b c ... (ASY|INT DIFF|MB) a b c
    m = re.search(r'Core Numbers ((?:\d{2} lb ){2,})', t)
    if m:
        weights = re.findall(r'(\d{2}) lb', m.group(1))
        rest = t[m.end():m.end() + 600]
        if '15' in weights:
            k = weights.index('15')
            for lab, key in (('RG', 'rg'), ('DIFF', 'diff'), ('(?:ASY|INT DIFF|MB DIFF|PSA)', 'int')):
                r = re.match(rf'.*?\b{lab} ((?:{NUM} ?){{{len(weights)}}})', rest)
                if r:
                    vals = re.findall(NUM, r.group(1))
                    if len(vals) == len(weights):
                        v[key] = vals[k]
            if v:
                return v, ['15 lb values from the per-weight Core Numbers table']
    # b) column table: Core Numbers Weight RG DIFF [ASY] 16 lb a b [c] 15 lb a b [c]
    m = re.search(r'Core Numbers Weights? RG DIFF( ASY| INT DIFF| MB)? ', t, re.I)
    if m:
        has3 = bool(m.group(1))
        r = re.search(r'\b15 lbs? ' + NUM + ' ' + NUM + ((' ' + NUM) if has3 else ''), t[m.end():m.end() + 400])
        if r:
            v['rg'], v['diff'] = r.group(1), r.group(2)
            if has3:
                v['int'] = r.group(3)
            return v, ['15 lb values from the per-weight Core Numbers table']
    # c) Hammer: 15 lb - RG (2.489) DIFF (0.053) [ASY (0.008)]
    r = re.search(r'\b15 lbs?\.? ?- ?RG \(' + NUM + r'\) DIFF \(' + NUM + r'\)(?: (?:ASY|MB|INT DIFF) \(' + NUM + r'\))?', t, re.I)
    if r:
        v = {'rg': r.group(1), 'diff': r.group(2)}
        if r.group(3):
            v['int'] = r.group(3)
        return v, ['15 lb values from the per-weight RG/DIFF list']
    # d) older Hammer: #15 RG (2.50) Diff (.052) [MB (.010)]
    r = re.search(r'#15 ?(?:LBS?)? RG \(' + NUM + r'\) Diff \(' + NUM + r'\)(?: (?:MB|Mass Bias|ASY|Int\.? Diff) \(' + NUM + r'\))?', t, re.I)
    if r:
        v = {'rg': r.group(1), 'diff': r.group(2)}
        if r.group(3):
            v['int'] = r.group(3)
        return v, ['15 lb values from the per-weight RG/Diff list']
    # e) Brunswick spec table: RG 2.473 (15 lb.) DIFF 0.054 (15 lb.) ASY 0.015 (15 lb.)
    for lab, key in (('RG', 'rg'), ('DIFF', 'diff'), ('(?:ASY|INT DIFF|Mass Bias)', 'int')):
        r = re.search(rf'\b{lab} {NUM} \(15 lbs?\.?\)', t)
        if r:
            v[key] = r.group(1)
    if v:
        return v, ['15 lb values from the spec table (labelled 15 lb)']
    other = re.findall(r'\b(RG|DIFF) ' + NUM + r' \((\d{2}) lbs?\.?\)', t)
    if other:
        notes.append('Page gives only non-15 lb core numbers: ' +
                     ', '.join(f'{a} {b} ({c} lb)' for a, b, c in other) + '; 15 lb fields left null.')
    return v, notes



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

def num(s):
    if s is None:
        return None
    x = float(s)
    return round(x, 3)


def cover_type(cover_label: str | None, coverstock: str | None) -> tuple[str, str | None]:
    """From the page's Cover Type, else from the manufacturer's coverstock name. Returns (type, note)."""
    for src, txt in (('Cover Type', cover_label), ('coverstock name', coverstock)):
        if not txt:
            continue
        s = txt.lower()
        found = [k for k, words in (('urethane', ('urethane',)), ('polyester', ('polyester', 'plastic')),
                                    ('hybrid', ('hybrid',)), ('pearl', ('pearl',)), ('solid', ('solid',)))
                 if any(w in s for w in words)]
        if len(found) == 1:
            return found[0], (None if src == 'Cover Type' else f"cover_type from the coverstock name '{txt}'")
        if 'hybrid' in found:
            return 'hybrid', (None if src == 'Cover Type' else f"cover_type from the coverstock name '{txt}'")
    return 'other', 'cover type not published on the page'


def core_type(v: str | None) -> str | None:
    if not v:
        return None
    s = v.lower()
    if 'asym' in s:
        return 'asymmetric'
    if 'sym' in s:
        return 'symmetric'
    if 'pancake' in s:
        return 'pancake'
    return None


MONTHS = {m: i for i, m in enumerate(['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august',
                                      'september', 'october', 'november', 'december'], 1)}


def release(v: str | None) -> str | None:
    if not v:
        return None
    m = re.match(r'([A-Za-z]+)\.? (?:\d{1,2}, )?(\d{4})', v.strip())
    if m and m.group(1).lower() in MONTHS:
        return f'{m.group(2)}-{MONTHS[m.group(1).lower()]:02d}'
    m = re.match(r'(\d{1,2})/\d{1,2}/(\d{2,4})', v.strip())
    if m:
        y = m.group(2)
        y = ('20' + y) if len(y) == 2 else y
        return f'{y}-{int(m.group(1)):02d}'
    return None


def first(s: str | None, n=120):
    if not s:
        return None
    return s.strip()[:n].strip() or None


def parse(brand: str, slug: str, raw: str, shop: dict | None = None) -> dict | None:
    manufacturer, url_t = BRANDS[brand]
    url = url_t.format(slug)
    t = clean(raw)
    if 'Internal Server Error' in t[:400] or 'Verifying your connection' in t[:400]:
        return None  # page didn't load; the ball is listed in the PR as not collected
    name = (shop or {}).get('title') or meta(raw, 'og:title')
    if not name:
        return None
    name = re.sub(r'\s+', ' ', name).strip()
    region = spec_region(t) or ''
    f = labelled(region)
    w, wnotes = weight15(t)
    notes = list(wnotes)
    rg, diff, idiff = num(w.get('rg')), num(w.get('diff')), num(w.get('int'))
    rg, diff, idiff = in_range(rg, diff, idiff, notes, 'the page')
    coverstock = first(f.get('Coverstock'))
    ctype, cnote = cover_type(f.get('Cover Type'), coverstock)
    if cnote:
        notes.append(cnote)
    core_raw = first(f.get('Core'))
    ctyp = core_type(f.get('Core Type'))
    core_name = core_raw
    if core_raw and core_raw.lower() in ('symmetric', 'asymmetric', 'symmetrical', 'asymmetrical'):
        ctyp = ctyp or core_type(core_raw)
        core_name = None
        notes.append(f"page lists the core only as '{core_raw}'")
    if ctyp is None and core_name and (ct := core_type(core_name)) and re.search(r'symmetric', core_name, re.I):
        ctyp = ct
        notes.append(f"core_type from the core name '{core_name}'.")
    if ctyp is None and idiff is not None and idiff >= 0.008:
        notes.append('core_type not stated; an intermediate diff is published')
    # Tier label: 'Level' on Brunswick/DV8/Radical, 'Performance' on Hammer/Track. (DV8's 'Performance' is a
    # reaction description, and Ebonite prints 'Entry Level Bowlers' as a reaction.)
    level, tier = level_of(brand, first(f.get('Level') if brand in ('brunswick', 'dv8', 'radical') else
                                        f.get('Performance') if brand in ('hammer', 'track') else None, 40))
    if level and not tier:
        notes.append(f"manufacturer level '{level}' has no tier mapping")
    if tier:
        notes.append(f'performance_tier mapped from manufacturer level "{level}".')
    if (m := re.search(r'(Intermediate Differential|Mass Bias):? ' + NUM, t)) and idiff is None:
        notes.append(f'Page also lists {m.group(1)} {m.group(2)} without a weight; int_diff_15 left null.')
    oil = first(f.get('Lane Condition') or f.get('Best Lane Condition'), 80)
    mfr = {'hook': None, 'hook_scale': None, 'length': None, 'length_scale': None,
           'backend': None, 'backend_scale': None,
           'reaction_shape': first(f.get('Reaction') or (f.get('Performance') if brand == 'dv8' else None), 60)}
    for k in ('Hook', 'Length'):
        if f.get(k) and re.fullmatch(r'\d{1,3}', f[k].strip()):
            mfr[k.lower()] = int(f[k].strip())
    if mfr['hook'] or mfr['length']:
        notes.append(f'{manufacturer} publishes Hook/Length numbers without stating a scale; *_scale left null.')
    if (m := re.search(r'REACTION SHAPE STRENGTH:? (\d{1,3})', t)):
        mfr['reaction_shape_strength'] = int(m.group(1))
        mfr['reaction_shape_strength_scale'] = '1-100 (higher = stronger reaction shape)'
        if (pi := re.search(r'Performance Index:? [A-Z ]+: .*?\. ([A-Z][A-Z ]+): ', t)):
            mfr['reaction_shape'] = mfr['reaction_shape'] or pi.group(1).strip().title()
    image = None
    if shop and shop.get('images'):
        image = shop['images'][0]['src']
    image = image or meta(raw, 'og:image:secure_url') or meta(raw, 'og:image')
    if image and image.startswith('http://'):
        image = 'https://' + image[7:]
    if image and image.startswith('//'):
        image = 'https:' + image
    rec = {
        'manufacturer': manufacturer, 'parent_company': 'Brunswick', 'name': name,
        'product_line': level, 'performance_tier': tier,
        'release_date': release(f.get('Release Date')),
        'colors': first(f.get('Color'), 80), 'coverstock_name': coverstock, 'cover_type': ctype,
        'core_name': core_name, 'core_type': ctyp,
        'rg_15': rg, 'diff_15': diff, 'int_diff_15': idiff,
        'factory_finish': first(f.get('Finish') or f.get('Factory Finish'), 120),
        'recommended_oil': oil,
        'mfr_ratings': mfr,
        'retailer_ratings': None,
        'motion_chart': None,
        'reaction_description': None,
        'image_url': image, 'image_source': 'manufacturer' if image else None,
        'product_url': url, 'spec_source_urls': [url],
        'status': 'discontinued',
        'notes': ' '.join(['Retired ball from the manufacturer\'s retired-balls listing (backfill 2026-10-27).'] + notes),
    }
    rec['missing'] = [k for k in ('product_line', 'performance_tier', 'release_date', 'colors', 'coverstock_name',
                                  'core_name', 'core_type', 'rg_15', 'diff_15', 'int_diff_15', 'factory_finish',
                                  'recommended_oil', 'image_url') if rec.get(k) is None]
    rec['missing'] += ['retailer_ratings', 'motion_chart', 'reaction_description']
    if ctype == 'other':
        rec['missing'].append('cover_type')
    return rec


def main(pages: Path, out: Path, shop_dir: Path | None = None):
    out.mkdir(parents=True, exist_ok=True)
    shops = {}
    if shop_dir:
        for b, host in (('hammer', 'hammerbowling.com'), ('ebonite', 'ebonite.com'), ('track', 'trackbowling.com')):
            p = shop_dir / f'{host}-ret.json'
            if p.exists():
                shops[b] = {x['handle']: x for x in json.loads(p.read_text())['products']}
    by = {}
    for f in sorted(pages.glob('*__*.html')):
        brand, slug = f.stem.split('__', 1)
        if brand not in BRANDS:
            continue
        rec = parse(brand, slug, f.read_text(errors='replace'), shops.get(brand, {}).get(slug))
        if rec:
            by.setdefault(brand, []).append(rec)
        else:
            print('UNPARSED', f.name, file=sys.stderr)
    for b, recs in by.items():
        (out / f'{b}.json').write_text(json.dumps(recs, indent=1, ensure_ascii=False))
        print(b, len(recs))


if __name__ == '__main__':
    main(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]) if len(sys.argv) > 3 else None)
