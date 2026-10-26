#!/usr/bin/env python3
"""Seed staged test accounts (DEC-063, HANDOFF_2026-10-26_STAGED_TEST_ACCOUNTS).

Gives Shayne a set of SEPARATE, seeded test accounts in known states, without ever writing staged data into
his real account. Staged shot histories are built from REAL analyzed shot records (validation/*_shot.json)
perturbed with a deterministic per-account RNG, then run through the REAL engines (score L-dev-0, tiers,
achievements, findings, notifications) — nothing is hand-written. Idempotent and deterministic.

  python -m ops.seed_staged_accounts --account all|<kind> [--reset] [--dry-run] [--target local|live] [--seed N]

Targets:
  local (default) — in-process MemoryStore (what the tests + e2e use). Validates the seed logic; does NOT
                    persist for the phone. Forces LANESIGHT_FORCE_MEMORY=1.
  live            — the real Supabase project; creates auth users (admin API) and writes real rows. Requires
                    migration 018 applied and creds present, and an explicit --i-understand-live flag.

Safety: every write/reset refuses unless the target profile has is_staged = true (except first creation of a
staged account). Passwords (live) are generated and stored in the macOS Keychain, never printed or committed.
"""
from __future__ import annotations
import argparse
import datetime as dt
import json
import os
import pathlib
import random
import secrets
import subprocess
import sys

KINDS = ('new_user', 'active', 'improving', 'struggling', 'edge_cases', 'heavy', 'under_13')
_BASE_RECORD_PATH = pathlib.Path(__file__).resolve().parents[1] / 'validation' / 'IMG_8753_shot.json'
DAY = 86400.0

# Per-persona shape. means/spread drive the perturbed metrics; trend shifts them over the account's lifespan.
PERSONAS = {
    'new_user':  dict(sessions=0, shots=(0, 0), span_days=0, balls=0, uploads=0),
    'active':    dict(sessions=13, shots=(15, 25), span_days=42, balls=3, oils=2, uploads=3, sensor_frac=0.3,
                      trend='flat', board=17.5, angle=5.0, speed=17.0, rev=405, spread=1.1),
    'improving': dict(sessions=14, shots=(15, 22), span_days=56, balls=3, oils=2, uploads=2, sensor_frac=0.3,
                      trend='up', board=19.5, angle=4.0, speed=16.0, rev=360, spread=1.8),
    'struggling':dict(sessions=12, shots=(15, 22), span_days=42, balls=2, oils=1, uploads=1, sensor_frac=0.2,
                      trend='down', board=15.0, angle=3.2, speed=18.2, rev=330, spread=2.6),
    'edge_cases':dict(sessions=3, shots=(6, 9), span_days=10, balls=2, oils=1, uploads=2, sensor_frac=0.5,
                      trend='flat', board=17.5, angle=5.0, speed=17.0, rev=405, spread=1.4, edge=True),
    'heavy':     dict(sessions=150, shots=(15, 25), span_days=365, balls=12, oils=3, uploads=4, sensor_frac=0.3,
                      trend='flat', board=17.8, angle=5.2, speed=17.2, rev=415, spread=1.0),
    'under_13':  dict(sessions=0, shots=(0, 0), span_days=0, balls=0, uploads=0),
}

BALL_CATALOG = [  # free-text staged balls (no catalog dependency); nickname + specs
    ('Phaze II', 15, 'pin up', '2000 abralon'), ('Zen', 15, 'pin down', '1500 polished'),
    ('IQ Tour', 15, 'pin up', '4000 abralon'), ('Hustle', 14, 'pin down', 'polished'),
    ('Idol', 15, 'pin up', '3000 abralon'), ('DV8', 15, 'pin down', 'solid'),
    ('Rhino', 14, 'pin up', 'pearl'), ('Hyroad', 15, 'pin up', '5000 grit'),
    ('Venom', 15, 'pin down', '2000 abralon'), ('Gem', 15, 'pin up', 'polished'),
    ('Wrath', 15, 'pin down', 'solid'), ('Mix', 14, 'pin up', 'urethane'),
]
OIL_NAMES = ['House shot', 'Kegel Main Street', 'PBA Cheetah']


def _base_record():
    return json.loads(_BASE_RECORD_PATH.read_text())


def _m(value, status='ok', unit=None, unc=None):
    d = {'value': (round(value, 2) if value is not None else None), 'status': status}
    if unit:
        d['unit'] = unit
    if unc is not None:
        d['uncertainty'] = unc
    return d


def make_record(shot_id, rng, p, progress, edge_state=None):
    """One perturbed ShotRecord derived from the real base record. `progress` in 0..1 applies the persona
    trend (improving pulls the line toward the pocket + tightens spread; struggling the opposite)."""
    rec = json.loads(json.dumps(_base_record()))      # deep copy the real record
    rec['shot_id'] = shot_id
    spread = p['spread']
    board, angle, speed, rev = p['board'], p['angle'], p['speed'], p['rev']
    if p.get('trend') == 'up':
        board -= 1.5 * progress; angle += 1.0 * progress; rev += 40 * progress; spread *= (1 - 0.4 * progress)
    elif p.get('trend') == 'down':
        board -= 1.2 * progress; angle -= 0.6 * progress; spread *= (1 + 0.5 * progress)
    m = {}
    def put(name, mean, sd, status='ok', unit=None, unc=None):
        m[name] = _m(rng.gauss(mean, sd), status=status, unit=unit, unc=unc)
    put('entry_board', board, spread, unit='board')
    put('entry_angle', angle, 0.5 * spread, unit='deg')
    put('ball_speed', speed, 0.6, unit='mph')
    put('speed_late', speed - abs(rng.gauss(1.2, 0.3)), 0.2, unit='mph')
    put('speed_early', speed + abs(rng.gauss(1.0, 0.3)), 0.2, unit='mph')
    put('rev_rate', rev, 25, status='calibrated_estimate', unit='rpm', unc=15)
    put('arrows_board', 15 + rng.gauss(0, 0.7), 0.5, unit='board')
    put('breakpoint_board', 8 + rng.gauss(0, 1.3), 0.5, unit='board')
    classification = 'EXECUTED'
    far_limited = False
    if edge_state == 'low_conf':
        for k in ('entry_board', 'entry_angle', 'breakpoint_board'):
            m[k]['status'] = 'low_confidence'
        far_limited = True
    elif edge_state == 'best_effort':
        m['rev_rate']['status'] = 'best_effort'
        m['entry_board']['status'] = 'best_effort'
    elif edge_state == 'unavailable':
        for k in ('entry_board', 'entry_angle', 'breakpoint_board'):
            m[k] = _m(None, status='unavailable')
        classification = 'LOW_CONFIDENCE'
    rec['metrics'] = m
    rec['insights'] = {'classification': classification, 'recommendations': []}
    cq = {'far_lane': 'limited' if far_limited else 'ok'}
    if far_limited:
        cq['reason'] = 'Far-lane read limited by camera position.'
    rec['capture_quality'] = cq
    return rec


def account_plan(kind, seed):
    """Deterministic plan (sessions -> shot counts, uploads, balls). Used for --dry-run and seeding."""
    p = PERSONAS[kind]
    rng = random.Random(f'{seed}:{kind}:plan')
    sessions = [rng.randint(*p['shots']) for _ in range(p['sessions'])] if p['sessions'] else []
    return dict(kind=kind, sessions=sessions, n_sessions=len(sessions), n_shots=sum(sessions),
                balls=p.get('balls', 0), uploads=p.get('uploads', 0))


# ----------------------------------------------------------------------- keychain (live passwords)
_KEYCHAIN_SERVICE = 'com.lanesight.staged'


def _keychain_set(account, password):
    subprocess.run(['security', 'add-generic-password', '-U', '-s', _KEYCHAIN_SERVICE, '-a', account,
                    '-w', password], check=True, capture_output=True)


def _keychain_get(account):
    r = subprocess.run(['security', 'find-generic-password', '-s', _KEYCHAIN_SERVICE, '-a', account, '-w'],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


# ----------------------------------------------------------------------- time backdating (store-aware)
def _set_created(store, user_id, shot_id, epoch):
    """Backdate a shot's created_at in the store's native type (MemoryStore: epoch float; Pg: ISO8601)."""
    from lanesight_api.store import MemoryStore
    if isinstance(store, MemoryStore):
        store.patch_shot(user_id, shot_id, {'created_at': epoch})
    else:
        iso = dt.datetime.fromtimestamp(epoch, dt.timezone.utc).isoformat()
        store.patch_shot(user_id, shot_id, {'created_at': iso})


# ----------------------------------------------------------------------- account identity / guard
def resolve_user(store, kind, cfg, target, create):
    """Return the user_id for a staged account, creating the auth user (live) or a deterministic id (local)."""
    from lanesight_api.store import MemoryStore
    if isinstance(store, MemoryStore):
        return f'staged-{kind}'
    # live: create (or find) the Supabase auth user, store a generated password in the Keychain
    from lanesight_api import userauth
    email = cfg_email(cfg, kind)
    if create:
        pw = _keychain_get(email) or secrets.token_urlsafe(18)
        _keychain_set(email, pw)
        s = userauth.signup(email, pw)          # tolerates "already registered"
        return s['user_id']
    raise RuntimeError('live reset requires the account to exist; run without --reset first')


def cfg_email(cfg, kind):
    acct = (cfg.get('accounts', {}) or {}).get(kind, {}) or {}
    if acct.get('email'):
        return acct['email']
    base = cfg.get('base_email')
    if not base or '@' not in base:
        raise RuntimeError(f'no email for {kind}: set accounts.{kind}.email or base_email in staged_accounts.toml')
    local, domain = base.split('@', 1)
    local = local.split('+', 1)[0]
    return f'{local}+ls_{kind}@{domain}'


def assert_staged(store, user_id):
    prof = store.get_profile(user_id) or {}
    if not prof.get('is_staged'):
        raise RuntimeError(f'REFUSING: {user_id} is not a staged account (is_staged != true). '
                           f'The seed tool never touches real accounts.')


# ----------------------------------------------------------------------- seeding
def seed_account(store, kind, cfg, target, reset=False, now=None):
    from lanesight_api import engines
    p = PERSONAS[kind]
    seed = cfg.get('seed', 20261026)
    now = now or _env_now()

    user_id = resolve_user(store, kind, cfg, target, create=True)
    # profile (always) — flags the account staged FIRST so the guard + feedback trigger apply.
    prof = {'is_staged': True, 'staged_kind': kind, 'handed': 'R', 'display_name': f'Staged · {kind}'}
    if kind == 'under_13':
        prof['dob'] = (dt.date(2015, 6, 1)).isoformat()           # <13
    else:
        prof['dob'] = (dt.date(1990, 3, 14)).isoformat()
        prof['delivery_style'] = 'one_handed_thumb'
    store.put_profile(user_id, prof)

    if reset:
        assert_staged(store, user_id)
        store.reset_user_data(user_id)
        store.put_profile(user_id, prof)                          # reset clears nothing on profile, but re-assert

    plan = account_plan(kind, seed)
    counts = dict(user_id=user_id, kind=kind, sessions=0, shots=0, uploads=0, balls=0, feedback=0)

    # balls
    rng = random.Random(f'{seed}:{kind}:balls')
    for i in range(p.get('balls', 0)):
        name, wt, layout, surface = BALL_CATALOG[i % len(BALL_CATALOG)]
        store.add_ball(user_id, {'nickname': name, 'weight_lb': wt, 'layout': layout, 'surface': surface,
                                 'make_current': i == 0})
        counts['balls'] += 1

    if p['sessions'] == 0:                                        # new_user / under_13: profile only
        return counts

    span = p['span_days'] * DAY
    for si, nshots in enumerate(plan['sessions']):
        # backdate the session across the lifespan, oldest first
        s_epoch = now - span + (span * si / max(1, p['sessions'] - 1)) if p['sessions'] > 1 else now - span
        oil = OIL_NAMES[si % max(1, p.get('oils', 1))]
        sess = store.create_session(user_id, {'oil_pattern_name': oil, 'mode': 'practice'})
        sid = sess['id']
        srng = random.Random(f'{seed}:{kind}:{si}')
        progress = si / max(1, p['sessions'] - 1)
        for k in range(nshots):
            edge = _edge_for(kind, si, k) if p.get('edge') else None
            sh = store.create_shot(user_id, sid, {'intent': {'arrows_board': 15.0, 'breakpoint_board': 10.0},
                                                  'handed': 'R', 'source': 'live', 'capture_mode': 'shot',
                                                  'sensor_used': srng.random() < p.get('sensor_frac', 0)})
            _set_created(store, user_id, sh['id'], s_epoch + k * 40)
            rec = make_record(sh['id'], srng, p, progress, edge_state=edge)
            store.save_shot_result(sh['id'], rec, {'ok': True})
            counts['shots'] += 1
        store.end_session(user_id, sid)
        # Run the real engines once per session END (not per shot): the session-end snapshot is the one the
        # app shows as score history, and tiers only move at session end anyway — so this reproduces the
        # app's final state while avoiding thousands of per-shot recomputes against live PostgREST.
        engines.at_session_end(store, user_id, sid)
        counts['sessions'] += 1
        # a session rating + the occasional note (flagged is_staged by the profile)
        store.add_feedback(user_id, {'source': 'session_feedback', 'session_id': sid,
                                     'rating': srng.randint(3, 5), 'tags': ['Workflow'] if si % 3 == 0 else [],
                                     'text': 'staged session feedback' if si % 4 == 0 else None})
        counts['feedback'] += 1

    # standalone uploads (DEC-055: never counted in score/stats/achievements) in Lab › Uploads
    for u in range(p.get('uploads', 0)):
        urng = random.Random(f'{seed}:{kind}:upload:{u}')
        sh = store.create_shot(user_id, None, {'handed': 'R', 'source': 'upload', 'capture_mode': 'shot'})
        _set_created(store, user_id, sh['id'], now - (u + 1) * DAY)
        store.save_shot_result(sh['id'], make_record(sh['id'], urng, p, 0.5), {'ok': True})
        if store.__class__.__name__ == 'MemoryStore':
            store.set_content_hash(sh['id'], f'stagedhash-{kind}-{u}')
        counts['uploads'] += 1
    # edge_cases: a duplicate upload (same content hash -> dedupe path) + a failed analysis
    if p.get('edge'):
        dup = store.create_shot(user_id, None, {'handed': 'R', 'source': 'upload', 'capture_mode': 'shot'})
        store.save_shot_result(dup['id'], make_record(dup['id'], random.Random('dup'), p, 0.5), {'ok': True})
        if store.__class__.__name__ == 'MemoryStore':
            store.set_content_hash(dup['id'], f'stagedhash-{kind}-0')    # same as upload 0
        counts['uploads'] += 1
        fail = store.create_shot(user_id, None, {'handed': 'R', 'source': 'upload', 'capture_mode': 'shot'})
        store.save_shot_result(fail['id'], {'shot_id': fail['id'], 'metrics': {},
                                            'insights': {'classification': 'LOW_CONFIDENCE'}},
                               {'ok': False, 'reason': 'pin impact not detected'})
    return counts


def _edge_for(kind, si, k):
    pattern = ['low_conf', 'best_effort', 'unavailable', None, None]
    return pattern[(si * 3 + k) % len(pattern)]


def _env_now():
    # allow a fixed clock for deterministic tests
    v = os.environ.get('LANESIGHT_STAGED_NOW')
    return float(v) if v else __import__('time').time()


# ----------------------------------------------------------------------- CLI
def load_cfg():
    import tomllib
    path = pathlib.Path(__file__).resolve().parent / 'staged_accounts.toml'
    if path.exists():
        return tomllib.loads(path.read_text())
    return {}


def main(argv=None):
    ap = argparse.ArgumentParser(description='Seed staged test accounts (DEC-063)')
    ap.add_argument('--account', default='all', help='all | ' + ' | '.join(KINDS))
    ap.add_argument('--reset', action='store_true', help='clear the staged account data, then re-seed')
    ap.add_argument('--dry-run', action='store_true', help='print planned row counts; no writes')
    ap.add_argument('--target', choices=('local', 'live'), default='local')
    ap.add_argument('--seed', type=int, default=20261026)
    ap.add_argument('--i-understand-live', action='store_true', help='required for --target live')
    a = ap.parse_args(argv)

    kinds = KINDS if a.account == 'all' else (a.account,)
    for k in kinds:
        if k not in KINDS:
            ap.error(f'unknown account kind: {k}')

    if a.dry_run:
        print(f'{"kind":12} {"sessions":>9} {"shots":>7} {"uploads":>8} {"balls":>6}')
        for k in kinds:
            pl = account_plan(k, a.seed)
            print(f'{k:12} {pl["n_sessions"]:>9} {pl["n_shots"]:>7} {pl["uploads"]:>8} {pl["balls"]:>6}')
        return 0

    if a.target == 'live':
        if not a.i_understand_live:
            ap.error('--target live requires --i-understand-live (creates real users + rows). '
                     'Apply migration 018 to live first.')
    else:
        os.environ['LANESIGHT_FORCE_MEMORY'] = '1'

    from lanesight_api.store import get_store
    cfg = dict(load_cfg(), seed=a.seed)
    store = get_store()
    for k in kinds:
        counts = seed_account(store, k, cfg, a.target, reset=a.reset)
        print(f'seeded {k}: {counts}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
