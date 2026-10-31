"""DEC-103/DEC-113 follow-up: after the retained clips are re-run on 0.7.0 and the pre-0.7.0 real speed/CV
measurements are marked legacy, rebuild personal baselines + score for the REAL accounts (the only ones with
engine-measured data touched by the ~14% bug). Staged showcase accounts are intentionally left alone: their
history is synthetic (never engine-measured, so unaffected), and recomputing under the 90-day score window
could alter the curated demo — re-seed them via the DEC-063 seed tool if ever needed.

Clears each real account's ball (view='all') baselines first so metrics that no longer have non-legacy data
don't keep a stale row, then compute_findings re-upserts from the legacy-excluded records and recompute_score
writes a fresh snapshot. Run after rerun_retained_clips.py + the legacy UPDATE.
"""
import os, json
from lanesight_api.store import get_store
from lanesight_api import engines

REAL = {
    '0e5e25a7-5846-44fe-9a1a-c1d1f96b05d2': 'LS Smoke',
    '4806c8bc-78ae-49c7-8deb-cb8ce5a3522a': 'Carlton Lafoon',
    '551bc775-dee4-41bd-a19c-116e8691d053': 'Shayne Lafoon',
}


def main():
    store = get_store()
    assert store.__class__.__name__ == 'PgStore'
    params = store.score_formula_params()
    wd = params.get('window_days')
    for uid, name in REAL.items():
        before = store._get('personal_baseline', f'user_id=eq.{uid}&view=eq.all&select=metric')
        # clear stale ball baselines (keep any view='form')
        store._req(f'personal_baseline?user_id=eq.{uid}&view=eq.all', 'DELETE')
        records, _ints, _h = store.read_shot_records(uid, window_days=wd)   # legacy-excluded
        findings = engines.compute_findings(store, uid, records)
        # trigger must be in the score_snapshot CHECK set (shot|session_end|correction|backfill); this is a
        # historical re-derivation after the engine-version quarantine -> 'backfill'. Skip accounts with no
        # non-legacy records (a 0-shot snapshot is meaningless; leave their last real snapshot in place).
        if not records:
            print(json.dumps({'user': name, 'records_nonlegacy': 0, 'baselines_before': len(before),
                              'baselines_after': 0, 'score': 'skipped (no non-legacy shots)'}), flush=True)
            continue
        snap = engines.recompute_score(store, uid, trigger='backfill')
        after = store._get('personal_baseline', f'user_id=eq.{uid}&view=eq.all&select=metric,median,n')
        print(json.dumps({'user': name, 'records_nonlegacy': len(records),
                          'baselines_before': len(before), 'baselines_after': len(after),
                          'baseline_metrics': sorted({b['metric'] for b in after}),
                          'score': snap.get('score'), 'eligible': snap.get('eligible'),
                          'tier': snap.get('tier')}), flush=True)
    print('DONE', flush=True)


if __name__ == '__main__':
    main()
