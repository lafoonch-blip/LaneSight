"""Simulated history for one REAL account, via the app's own PgStore code + engines, with PostgREST
replaced by an in-memory emulator that records every write. Output: SQL to replay on live + a cleanup list.

Every simulated shot record carries "simulated": true, and all row ids are listed in the cleanup output.
"""
import datetime as dt, json, random, re, sys, uuid, pathlib

sys.path.insert(0, '/home/claude/lanesight/lanesight-core')
from lanesight_api import store as S
from lanesight_api import engines
sys.path.insert(0, '/home/claude/lanesight/lanesight-core/ops')
import seed_staged_accounts as seedmod

USER = '551bc775-dee4-41bd-a19c-116e8691d053'
REF = json.loads(pathlib.Path('/home/claude/work/ref.json').read_text())

TABLES = {}          # table -> list[row]
SIM_NOW = [None]     # simulated clock (epoch) for engine-written timestamps
WRITES = []          # (method, path, body, prefer)


def _cmp_val(a):
    try:
        return (0, float(a))
    except (TypeError, ValueError):
        return (1, str(a))


def _match(row, col, expr):
    neg = False
    if expr.startswith('not.'):
        neg, expr = True, expr[4:]
    op, _, val = expr.partition('.')
    v = row.get(col)
    if op == 'eq':
        r = str(v).lower() == val.lower() if isinstance(v, bool) else str(v) == val
    elif op == 'neq':
        r = str(v) != val
    elif op == 'is':
        if val == 'null':
            r = v is None
        else:
            r = bool(v) == (val == 'true') if v is not None else (val == 'false')   # column default false
    elif op == 'in':
        items = [x.strip('"') for x in val.strip('()').split(',')]
        r = str(v) in items
    elif op in ('gte', 'gt', 'lte', 'lt'):
        from urllib.parse import unquote
        val = unquote(val)
        if v is None:
            r = False
        else:
            a, b = _norm_ts(v), _norm_ts(val)
            r = {'gte': a >= b, 'gt': a > b, 'lte': a <= b, 'lt': a < b}[op]
    elif op == 'cs':
        r = True
    else:
        raise RuntimeError(f'unsupported op {op}')
    return (not r) if neg else r


def _norm_ts(x):
    if isinstance(x, (int, float)):
        return _cmp_val(x)
    s = str(x)
    try:
        return (0, dt.datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp())
    except ValueError:
        return _cmp_val(s)


def _query(table, query):
    rows = [dict(r) for r in TABLES.get(table, [])]
    order, limit, select = None, None, '*'
    for part in [p for p in query.split('&') if p]:
        k, _, v = part.partition('=')
        if k == 'order':
            order = v
        elif k == 'limit':
            limit = int(v)
        elif k == 'select':
            select = v
        elif k in ('offset', 'on_conflict'):
            pass
        else:
            rows = [r for r in rows if _match(r, k, v)]
    # embedded relation like shots(capture_mode)
    for emb in re.findall(r'(\w+)\(([^)]*)\)', select):
        child, cols = emb
        single_fk = (child[:-1] if child.endswith('s') else child) + '_id'
        fk = table[:-1] + '_id' if table.endswith('s') else table + '_id'
        for r in rows:
            if single_fk in r:      # many-to-one (shots -> sessions)
                par = next((x for x in TABLES.get(child, []) if x.get('id') == r.get(single_fk)), None)
                r[child] = {c: par.get(c) for c in cols.split(',')} if par else None
            else:
                r[child] = [{c: x.get(c) for c in cols.split(',')} for x in TABLES.get(child, []) if x.get(fk) == r.get('id')]
    if order:
        for o in reversed(order.split(',')):
            bits = o.split('.')
            col, desc = bits[0], 'desc' in bits[1:]
            rows.sort(key=lambda r: (r.get(col) is None, _norm_ts(r.get(col)) if r.get(col) is not None else (0, 0)),
                      reverse=desc)
    if limit is not None:
        rows = rows[:limit]
    return rows


class PgStore(S.PgStore):
    def __init__(self):
        super().__init__('http://emulator/', 'x')

    def _get(self, table, query=''):
        return _query(table, query)

    def _post(self, table, row):
        self._req(table, 'POST', row)

    def _req(self, path, method, body=None, prefer='return=minimal'):
        body = S._json_safe(body) if body is not None else None
        WRITES.append((method, path, body, prefer))
        table, _, query = path.partition('?')
        if method == 'POST':
            items = body if isinstance(body, list) else [body]
            conflict = None
            m = re.search(r'on_conflict=([\w,]+)', query)
            if m:
                conflict = m.group(1).split(',')
            for it in items:
                it = dict(it)
                if SIM_NOW[0] is not None:
                    iso = dt.datetime.fromtimestamp(SIM_NOW[0], dt.timezone.utc).isoformat()
                    if table in ('activity_item', 'tier_event', 'score_snapshot', 'user_tier_state', 'finding'):
                        it['created_at'] = iso
                    if table == 'user_achievement_unlock':
                        it['unlocked_at'] = iso
                    if table == 'user_tier_state' and it.get('best_score_at'):
                        it['best_score_at'] = iso
                it.setdefault('created_at', dt.datetime.now(dt.timezone.utc).isoformat())
                tbl = TABLES.setdefault(table, [])
                keys = conflict or (['id'] if 'id' in it else (['user_id'] if table in ('profiles', 'user_tier_state') else None))
                existing = None
                if keys:
                    existing = next((r for r in tbl if all(r.get(k) == it.get(k) for k in keys)), None)
                if existing is not None:
                    if 'ignore-duplicates' in prefer:
                        continue
                    existing.update(it)
                else:
                    tbl.append(it)
        elif method == 'PATCH':
            for r in _query(table, query):
                for real in TABLES.get(table, []):
                    if real.get('id', real.get('user_id')) == r.get('id', r.get('user_id')) and all(real.get(k) == r.get(k) for k in r if k in real):
                        real.update(body)
        elif method == 'DELETE':
            keep = {id(x) for x in []}
            matched = _query(table, query)
            TABLES[table] = [r for r in TABLES.get(table, []) if not any(r == m for m in matched)]
        return None


def main():
    TABLES['score_formula_version'] = REF['score_formula_version']
    TABLES['profiles'] = [REF['profile']]
    TABLES['user_balls'] = REF['balls']
    from lanesight_api.rules_seed import achievement_definitions, ENGINE_CONFIG
    TABLES['achievement_definition'] = [dict(d) for d in achievement_definitions()]
    TABLES['engine_config'] = [{'key': k, 'value': v} for k, v in ENGINE_CONFIG.items()]
    # his REAL existing unlocks, so the engine doesn't re-unlock them
    for aid, at in [('ACH-017', '2026-11-03T22:05:10+00:00'), ('ACH-048', '2026-11-23T15:08:52+00:00'),
                    ('ACH-050', '2026-11-02T00:38:36+00:00'), ('ACH-051', '2026-11-02T00:38:36+00:00'),
                    ('ACH-052', '2026-11-02T00:39:02+00:00')]:
        TABLES.setdefault('user_achievement_unlock', []).append(
            {'id': str(uuid.uuid4()), 'user_id': USER, 'achievement_id': aid, 'level': 1, 'unlocked_at': at,
             'revoked_at': None, '_real': True})
    store = PgStore()
    p = dict(seedmod.PERSONAS['improving'])
    p['sessions'] = 14
    p['span_days'] = 56
    now = dt.datetime(2026, 11, 22, 23, 0, tzinfo=dt.timezone.utc).timestamp()   # history ends yesterday
    seed = 20261123
    plan_rng = random.Random(f'{seed}:shayne:plan')
    sessions = [plan_rng.randint(12, 20) for _ in range(p['sessions'])]
    span = p['span_days'] * seedmod.DAY
    ids = {'sessions': [], 'shots': []}
    oils = ['House shot', 'Kegel Main Street']
    for si, nshots in enumerate(sessions):
        s_epoch = now - span + span * si / (len(sessions) - 1)
        sess = store.create_session(USER, {'mode': 'practice'})
        sid = sess['id']
        ids['sessions'].append(sid)
        srng = random.Random(f'{seed}:shayne:{si}')
        progress = si / (len(sessions) - 1)
        for k in range(nshots):
            sh = store.create_shot(USER, sid, {'intent': {'arrows_board': 15.0, 'breakpoint_board': 10.0},
                                               'handed': 'R', 'source': 'live', 'capture_mode': 'shot',
                                               'sensor_used': False})
            ids['shots'].append(sh['id'])
            seedmod._set_created(store, USER, sh['id'], s_epoch + k * 40)
            rec = seedmod.make_record(sh['id'], srng, p, progress)
            rec['simulated'] = True
            store.save_shot_result(sh['id'], rec, {'ok': True})
        SIM_NOW[0] = s_epoch + nshots * 40 + 60
        store.end_session(USER, sid)
        engines.at_session_end(store, USER, sid)
        seedmod._backdate_session(store, USER, sid, s_epoch, s_epoch + nshots * 40 + 60)
    out = pathlib.Path('/home/claude/work')
    (out / 'writes.json').write_text(json.dumps(WRITES, default=str))
    (out / 'ids.json').write_text(json.dumps(ids))
    ts = TABLES.get('user_tier_state')
    print('sessions', len(ids['sessions']), 'shots', len(ids['shots']), 'writes', len(WRITES))
    print('tier', ts)
    snaps = TABLES.get('score_snapshot', [])
    print('snapshots', len(snaps), [ (s.get('score'), s.get('tier')) for s in snaps[-3:]])
    print('activity', [(a.get('kind'), (a.get('payload') or {}).get('name') or (a.get('payload') or {}).get('to_tier')) for a in TABLES.get('activity_item', [])])
    from collections import Counter
    print(Counter((w[0], w[1].split('?')[0]) for w in WRITES))


if __name__ == '__main__':
    main()

def debug():
    main()
    snaps = TABLES.get('score_snapshot', [])
    print(json.dumps(snaps[-1], default=str)[:1500])
    sh = TABLES['shots'][-1]
    print({k: (str(v)[:80]) for k, v in sh.items()})
    print(json.dumps(TABLES['measurements'][-1], default=str)[:600])
