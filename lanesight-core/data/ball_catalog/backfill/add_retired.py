"""Append collected retired balls to raw/<brand>.json (never touching existing records).

    python data/ball_catalog/backfill/add_retired.py data/ball_catalog/raw <collected_dir> [<collected_dir> ...]
        [--motiv-retired-names names.txt]

A collected ball is skipped when the brand's raw file already has a ball with the same name (ignoring case and
punctuation, '!Q' = 'IQ'): the existing record wins, current or not. Two collected balls with the same name keep
the first. Prints what was added and skipped per brand.
"""
from __future__ import annotations
import argparse, json, re
from pathlib import Path


def norm(name: str) -> str:
    s = name.lower().replace('!q', 'iq').replace('&', 'and').replace('limited edition', '')
    return re.sub(r'[^a-z0-9]', '', s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('raw_dir', type=Path)
    ap.add_argument('collected', type=Path, nargs='+')
    ap.add_argument('--motiv-retired-names', type=Path)
    a = ap.parse_args()
    motiv_official = set()
    if a.motiv_retired_names:
        motiv_official = {norm(x) for x in a.motiv_retired_names.read_text().splitlines() if x.strip()}
    report = {}
    for raw in sorted(a.raw_dir.glob('*.json')):
        existing = json.loads(raw.read_text())
        have = {norm(r['name']) for r in existing}
        added, skipped = [], []
        for d in a.collected:
            src = d / raw.name
            if not src.exists():
                continue
            for rec in json.loads(src.read_text()):
                k = norm(rec['name'])
                if k in have:
                    skipped.append(rec['name'])
                    continue
                if rec['manufacturer'] == 'Motiv' and k in motiv_official:
                    rec['notes'] += " Also listed on Motiv's own Retired Balls page."
                have.add(k)
                added.append(rec)
        if not added:
            continue
        merged = existing + sorted(added, key=lambda r: r['name'].lower())  # existing records untouched, in order
        raw.write_text(json.dumps(merged, indent=2, ensure_ascii=False) + '\n')
        report[raw.stem] = {'added': len(added), 'skipped_same_name': skipped}
    print(json.dumps(report, indent=1))


if __name__ == '__main__':
    main()
