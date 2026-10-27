"""Staged test accounts (DEC-063). Exercises the seed tool against the MemoryStore (the local/offline path),
proving: dry-run plan counts, the never-touch-a-real-account guard, engine-DERIVED score/tier/achievements for
the showcase account, byte-stable reset (same seed -> same derived state), and staged-feedback flagging +
exclusion. No live project is touched."""
import os
import time

# force the offline store + a shared, recent, FIXED clock so backdated shots stay inside the 90-day score
# window AND two seed runs are deterministic (same timestamps -> identical derived state).
os.environ['LANESIGHT_FORCE_MEMORY'] = '1'
os.environ['LANESIGHT_STAGED_NOW'] = str(time.time())

from lanesight_api.store import get_store, MemoryStore
from ops import seed_staged_accounts as S

CFG = {'seed': 20261026}


def _fresh_store():
    # new MemoryStore each test so accounts don't bleed across tests
    import lanesight_api.store as store_mod
    store_mod._store = MemoryStore()
    return store_mod._store


def test_dry_run_plan_counts_deterministic():
    a = S.account_plan('active', CFG['seed'])
    assert a['n_sessions'] == 13 and 15 * 13 <= a['n_shots'] <= 25 * 13 and a['balls'] == 3 and a['uploads'] == 3
    assert S.account_plan('new_user', CFG['seed'])['n_sessions'] == 0
    assert S.account_plan('under_13', CFG['seed'])['n_shots'] == 0
    assert S.account_plan('heavy', CFG['seed'])['n_sessions'] == 150
    # deterministic
    assert S.account_plan('active', CFG['seed']) == S.account_plan('active', CFG['seed'])


def test_guard_refuses_non_staged_account():
    store = _fresh_store()
    store.put_profile('real-shayne', {'handed': 'R'})          # a real (non-staged) profile
    import pytest
    with pytest.raises(RuntimeError, match='REFUSING'):
        S.assert_staged(store, 'real-shayne')
    # a staged account passes
    store.put_profile('staged-x', {'is_staged': True, 'staged_kind': 'active'})
    S.assert_staged(store, 'staged-x')


def test_new_user_and_under_13_are_profile_only():
    store = _fresh_store()
    S.seed_account(store, 'new_user', CFG, 'local')
    S.seed_account(store, 'under_13', CFG, 'local')
    nu = store.get_profile('staged-new_user')
    assert nu['is_staged'] and nu['staged_kind'] == 'new_user' and nu.get('delivery_style')
    assert len(store.user_shots('staged-new_user')) == 0 and len(store.list_arsenal('staged-new_user')) == 0
    u13 = store.get_profile('staged-under_13')
    assert u13['dob'] >= '2013-01-01'                          # under 13
    assert len(store.user_shots('staged-under_13')) == 0


def test_active_has_engine_derived_score_tier_achievements():
    store = _fresh_store()
    S.seed_account(store, 'active', CFG, 'local')
    uid = 'staged-active'
    ls = store.latest_score(uid)
    assert ls and ls['eligible'] is True and ls['score'] is not None   # REAL score, not hand-written
    assert ls['tier'] in ('silver', 'gold', 'platinum', 'onyx')
    assert len(store.tier_events.get(uid, [])) >= 1                    # at least one rank-up
    assert len(store.list_ach_unlocks(uid)) >= 5
    assert len(store.list_uploads(uid)) == 3                           # Lab › Uploads, excluded from score
    assert len(store.list_arsenal(uid)) == 3


def test_reset_is_byte_stable_in_derived_state():
    store = _fresh_store()
    def snapshot():
        S.seed_account(store, 'active', CFG, 'local', reset=True)
        uid = 'staged-active'
        ls = store.latest_score(uid)
        metrics = sorted(round(m['value'], 3) for sh in store.user_shots(uid)
                         for m in (sh['record'].get('metrics') or {}).values() if m.get('value') is not None)
        return (ls['score'], ls['tier'], len(store.user_shots(uid)), len(store.list_ach_unlocks(uid)), metrics)
    first = snapshot()
    second = snapshot()                                   # reset + re-seed, same seed/clock
    assert first == second, 'reset -> re-seed is not byte-stable in derived state'


def test_first_tier_achievement_values_are_numeric():
    """Regression (live-seed 400): first_tier achievements must write NUMERIC current_value/target_value,
    not the tier name — the columns are numeric (untyped MemoryStore hid this)."""
    from lanesight_core.achievements.engine import evaluate
    d = {'id': 'ACH-056', 'rule_type': 'first_tier', 'params': {'tier': 'silver'}}
    reached = evaluate(d, {'reached': True, 'tier': 'silver'})
    assert reached['unlocked'] is True
    assert isinstance(reached['current_value'], (int, float))
    assert isinstance(reached['target_value'], (int, float))
    assert reached['current_value'] == 1 and reached['target_value'] == 1
    not_reached = evaluate(d, {'reached': False, 'tier': 'bronze'})
    assert not_reached['current_value'] == 0 and not_reached['unlocked'] is False


def test_staged_feedback_flagged_and_excluded_from_review():
    store = _fresh_store()
    S.seed_account(store, 'active', CFG, 'local')
    store.put_profile('real-shayne', {'handed': 'R'})
    store.add_feedback('real-shayne', {'source': 'general', 'text': 'real feedback'})
    staged = [f for f in store.feedback_rows if f['user_id'] == 'staged-active']
    real = [f for f in store.feedback_rows if f['user_id'] == 'real-shayne']
    assert staged and all(f['is_staged'] for f in staged)             # staged feedback flagged
    assert real and all(not f['is_staged'] for f in real)
    review = [f for f in store.feedback_rows if not f['is_staged']]   # feedback_review view = is_staged false
    assert all(f['user_id'] != 'staged-active' for f in review)       # staged excluded from review
