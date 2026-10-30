#!/usr/bin/env python3
"""One-time recompute of every account's LaneSight Score against the CURRENT formula (DEC-108: 5-shot unlock).
Existing snapshots persist their eligibility (need=20), and /me/score serves the cached snapshot, so a formula
change only reaches accounts on their next shot — this recomputes them now. Reads/writes the LIVE DB via the
service role (same path the API uses). Idempotent: recompute_score saves a fresh snapshot per user.

    cd lanesight-core && source .venv/bin/activate && python3 ops/recompute_scores.py [--dry-run]
"""
import os
import subprocess
import sys


def kc(service):
    return subprocess.run(['security', 'find-generic-password', '-a', 'lanesight', '-s', service, '-w'],
                          capture_output=True, text=True).stdout.strip()


def main():
    # Point the store at the live DB (REST base + service role), exactly like the API.
    os.environ.setdefault('LANESIGHT_DB_URL', kc('lanesight.supabase.db_url'))
    os.environ.setdefault('LANESIGHT_SERVICE_ROLE', kc('lanesight.supabase.service_role'))
    from lanesight_api.store import get_store
    from lanesight_api import engines
    store = get_store()
    if type(store).__name__ != 'PgStore':
        raise SystemExit(f'store is {type(store).__name__}, not PgStore (live) — check LANESIGHT_DB_URL')

    # Existing accounts = those with a score snapshot (they have shots; new accounts recompute on their 1st shot).
    rows = store._get('score_snapshot', 'select=user_id')
    users = sorted({r['user_id'] for r in rows if r.get('user_id')})
    dry = '--dry-run' in sys.argv
    print(f'{len(users)} accounts with shots{" (dry-run)" if dry else ""}')
    for u in users:
        if dry:
            records, intents, handed = store.read_shot_records(u)
            print(f'  {u[:8]}: {len(records)} scored records')
            continue
        snap = engines.recompute_score(store, u, trigger='admin_recompute')
        el = snap.get('eligibility') or {}
        print(f"  {u[:8]}: eligible={snap.get('eligible')} score={snap.get('score')} "
              f"tier={snap.get('tier')} provisional={snap.get('tier_provisional')} "
              f"needs={{{','.join(f'{k}:{v.get('need')}' for k, v in el.items())}}}")
    print('done')


if __name__ == '__main__':
    main()
