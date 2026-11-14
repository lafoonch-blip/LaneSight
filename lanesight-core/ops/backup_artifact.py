#!/usr/bin/env python3
"""DEC-130 — persist + dual-backup a trained artifact with a sha256 manifest.

For each file: sha256, copy to ~/LaneSightData/dec130/backup/, upload to the gs cloudbuild bucket under dec130/,
and append a row to BOTH ~/LaneSightData/dec130/ARTIFACTS.md and 03_ENGINEERING/DEC130_ARTIFACTS.md (committed).

  python -m ops.backup_artifact <file> [<file> ...] [--note "v3 unified ball+lane, val_recall 0.97"]
"""
from __future__ import annotations
import argparse, hashlib, os, shutil, subprocess, datetime

BUCKET = 'gs://project-fd28bc3f-a844-43c2-a1c_cloudbuild/dec130'
BACKUP = os.path.expanduser('~/LaneSightData/dec130/backup')
MANIFESTS = [os.path.expanduser('~/LaneSightData/dec130/ARTIFACTS.md'),
             os.path.join(os.path.dirname(__file__), '..', '..', '03_ENGINEERING', 'DEC130_ARTIFACTS.md')]


def sha256(path):
    h = hashlib.sha256()
    if os.path.isdir(path):                       # .mlpackage is a dir — hash its files deterministically
        for root, _d, files in sorted(os.walk(path)):
            for f in sorted(files):
                with open(os.path.join(root, f), 'rb') as fh:
                    for chunk in iter(lambda: fh.read(1 << 20), b''):
                        h.update(chunk)
        return h.hexdigest()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def size_of(path):
    if os.path.isdir(path):
        return sum(os.path.getsize(os.path.join(r, f)) for r, _d, fs in os.walk(path) for f in fs)
    return os.path.getsize(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('files', nargs='+')
    ap.add_argument('--note', default='')
    ap.add_argument('--ts', default=None, help='timestamp string (pass in; os clock not used for determinism)')
    a = ap.parse_args()
    os.makedirs(BACKUP, exist_ok=True)
    ts = a.ts or datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
    rows = []
    for f in a.files:
        if not os.path.exists(f):
            print(f'MISSING {f}'); continue
        digest = sha256(f); sz = size_of(f); base = os.path.basename(f.rstrip('/'))
        # local backup
        dst = os.path.join(BACKUP, base)
        if os.path.isdir(f):
            shutil.rmtree(dst, ignore_errors=True); shutil.copytree(f, dst)
        else:
            shutil.copy2(f, dst)
        # gs backup (best-effort; local backup already satisfies "second location")
        gs = f'{BUCKET}/{base}'
        gsflag = '-m' if os.path.isdir(f) else ''
        rc = subprocess.run(f'gsutil {gsflag} cp -r "{f}" "{BUCKET}/"', shell=True,
                            capture_output=True, text=True)
        gs_ok = rc.returncode == 0
        rows.append((base, digest, sz, dst, gs if gs_ok else '(gs upload failed; local backup only)', a.note, ts))
        print(f'{base}: sha256={digest[:16]}… size={sz/1e6:.1f}MB backup={dst} gs={"ok" if gs_ok else "FAILED"}')
    # append to manifests
    for man in MANIFESTS:
        new = not os.path.exists(man)
        with open(man, 'a') as fh:
            if new:
                fh.write('# DEC-130 artifact manifest\n\n'
                         'Trained checkpoints + Core ML exports with sha256 + dual backup (local `backup/` + gs bucket).\n\n'
                         '| artifact | sha256 | size(MB) | local backup | gs | note | ts |\n'
                         '|---|---|---|---|---|---|---|\n')
            for (base, digest, sz, dst, gs, note, t) in rows:
                fh.write(f'| {base} | `{digest}` | {sz/1e6:.1f} | {dst} | {gs} | {note} | {t} |\n')
    print(f'manifest rows appended to {len(MANIFESTS)} files')


if __name__ == '__main__':
    main()
