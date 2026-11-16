"""DEC-098 §2 (M5): periodic storage/DB size metering. Best-effort — gathers what it can and records a
snapshot row per bucket via the store; a signal it can't measure is left NULL (NO DATA), never invented.

Run (owner, with live creds): python -m lanesight_api.ops_storage_snapshot
Schedule it the same way as the other ops jobs. NOT run by Claude Code (needs live creds); the writer path
(store.record_storage_snapshot) is unit-tested, the gather below is live-only.
"""
from __future__ import annotations
import json
import os
import time
import urllib.request

from .store import get_store
from .config import settings

# Buckets to meter. Keep in sync with the storage buckets the app uses (shot-clips, frames/avatars).
BUCKETS = (os.environ.get('LANESIGHT_STORAGE_BUCKETS') or 'shot-clips,images').split(',')
AGED_DAYS = int(os.environ.get('LANESIGHT_STORAGE_AGED_DAYS', '30'))   # strategy §8 default TTL


def _storage_base() -> str | None:
    base = settings().supabase_base
    return base.rstrip('/') + '/storage/v1' if base else None


def _list_bucket(base: str, key: str, bucket: str) -> dict:
    """Sum bytes/objects and count aged objects for one bucket (best-effort, paginated)."""
    bytes_total, objects, aged, offset = 0, 0, 0, 0
    cutoff = time.time() - AGED_DAYS * 86400
    while True:
        body = json.dumps({'prefix': '', 'limit': 1000, 'offset': offset}).encode()
        req = urllib.request.Request(f'{base}/object/list/{bucket}', data=body, method='POST', headers={
            'apikey': key, 'Authorization': f'Bearer {key}', 'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=30) as r:
            page = json.loads(r.read().decode() or '[]')
        if not page:
            break
        for obj in page:
            meta = obj.get('metadata') or {}
            bytes_total += int(meta.get('size') or 0)
            objects += 1
            created = obj.get('created_at')
            if created:
                try:
                    from datetime import datetime
                    if datetime.fromisoformat(created.replace('Z', '+00:00')).timestamp() < cutoff:
                        aged += 1
                except Exception:
                    pass
        if len(page) < 1000:
            break
        offset += 1000
    return {'bucket': bucket, 'bytes': bytes_total, 'objects': objects, 'aged_objects': aged}


def gather() -> list[dict]:
    base = _storage_base()
    store = get_store()
    key = getattr(store, '_key', None)
    if not base or not key:
        print('storage snapshot: no live creds; nothing gathered')
        return []
    rows = []
    for bucket in (b.strip() for b in BUCKETS if b.strip()):
        try:
            rows.append(_list_bucket(base, key, bucket))
        except Exception as e:
            # Honest: record the bucket with NULL sizes + the error, never a fabricated size.
            print(f'storage snapshot: bucket {bucket} failed ({e})')
            rows.append({'bucket': bucket, 'bytes': None, 'objects': None, 'aged_objects': None})
    return rows


def main() -> int:
    store = get_store()
    rows = gather()
    if rows:
        store.record_storage_snapshot(rows)
        print(f'storage snapshot: recorded {len(rows)} bucket row(s)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
