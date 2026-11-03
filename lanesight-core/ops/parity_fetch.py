"""DEC-128 item 3: assemble the on-device-vs-server parity set from REAL clips.

For every shot of Shayne's accounts that has an uploaded clip, match the clip (by content_hash == storage object
name, else by the storage object uploaded within ~3 min AFTER the shot was created), download it to
ios/LaneSight/Tests/GateClips/<shot8>.mov, and record the shot's SERVER + iOS analysis_metric_outcome rows (the
authoritative per-engine reference). Writes ops/parity_manifest.json. After this, run OnDeviceGateTests on device
and feed its ONDEV_GATE_ROW output + this manifest to ops/parity_report.py.

Read-only against live (downloads + selects); no writes. Creds from the macOS keychain.
  python3 ops/parity_fetch.py [--focus-only]
"""
import os, sys, json, hashlib, subprocess
from datetime import datetime, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GATECLIPS = os.path.abspath(os.path.join(ROOT, '..', 'ios', 'LaneSight', 'Tests', 'GateClips'))
MANIFEST = os.path.join(ROOT, 'ops', 'parity_manifest.json')
BUCKET = 'shot-clips'
USERS = ['4806c8bc-78ae-49c7-8deb-cb8ce5a3522a', '551bc775-dee4-41bd-a19c-116e8691d053']
FOCUS = ['80ae104f', '6ecfcfee', '82eb0b4f']
_PARITY_METRICS = ('ball_speed', 'speed_avg_foul_to_pins', 'rev_rate', 'laydown_board', 'board_at_7ft',
                   'arrows_board', 'breakpoint_board', 'entry_board', 'entry_angle', 'launch_angle', 'loft')


def keychain(service):
    return subprocess.run(['security', 'find-generic-password', '-a', 'lanesight', '-s', service, '-w'],
                          capture_output=True, text=True).stdout.strip()


def _store():
    os.environ['LANESIGHT_DB_URL'] = keychain('lanesight.supabase.db_url')
    os.environ['LANESIGHT_SERVICE_ROLE'] = keychain('lanesight.supabase.service_role')
    from lanesight_api.store import get_store
    st = get_store()
    if st.__class__.__name__ != 'PgStore':
        raise SystemExit(f'expected PgStore, got {st.__class__.__name__}')
    return st


def _ts(s):
    if not s:
        return None
    return datetime.fromisoformat(s.replace('Z', '+00:00'))


def outcome_rows(store, shot_id):
    """{engine: {metric: {status, value, reason_code}}} from analysis_metric_outcome via the shot's attempts."""
    att = store._get('analysis_attempt', f'shot_id=eq.{shot_id}&select=id,platform,status,created_at&order=created_at.desc')
    out = {}
    for a in att:
        eng = 'server' if a['platform'] == 'server' else 'iphone'
        if eng in out:                      # keep the latest attempt per engine
            continue
        rows = store._get('analysis_metric_outcome',
                          f'attempt_id=eq.{a["id"]}&select=metric_key,status,value,reason_code')
        out[eng] = {r['metric_key']: {'status': r['status'], 'value': r['value'],
                                      'reason_code': r.get('reason_code')} for r in rows}
    return out


def main():
    focus_only = '--focus-only' in sys.argv
    store = _store()
    os.makedirs(GATECLIPS, exist_ok=True)
    manifest = {}
    for u in USERS:
        shots = store._get('shots', f'user_id=eq.{u}&select=id,source,created_at,content_hash,analysis_status'
                                    '&order=created_at.desc&limit=300')
        objs = [o for o in store.storage_list(BUCKET, u) if o.get('id') and (o.get('name') or '').endswith('.mov')]
        # download every object ONCE; the storage object name is a random id, so match by sha256(bytes) ==
        # shots.content_hash (the hashless on-device shots fall back to an upload-time match below).
        blob, by_contenthash = {}, {}
        objs_ts = []
        for o in objs:
            data = store.storage_download(BUCKET, f'{u}/{o["name"]}')
            blob[o['name']] = data
            by_contenthash[hashlib.sha256(data).hexdigest()] = o['name']
            objs_ts.append((o, _ts(o.get('updated_at') or o.get('created_at'))))
        objs_ts.sort(key=lambda x: x[1] or datetime.min.replace(tzinfo=None))
        used = set()
        for sh in shots:
            short = sh['id'][:8]
            if focus_only and short not in FOCUS:
                continue
            obj_name = None
            matched_by = None
            h = sh.get('content_hash')
            if h and h in by_contenthash:                 # 1) content hash
                obj_name = by_contenthash[h]; matched_by = 'hash'
            if obj_name is None:                           # 2) nearest upload 0..180 s AFTER the shot
                scr = _ts(sh.get('created_at')); best = None
                for o, ots in objs_ts:
                    if o['name'] in used or ots is None or scr is None:
                        continue
                    dt = (ots - scr).total_seconds()
                    if 0 <= dt <= 180 and (best is None or dt < best[1]):
                        best = (o, dt)
                if best:
                    obj_name = best[0]['name']; matched_by = 'time'
            if obj_name is None:
                continue
            used.add(obj_name)
            fn = f'{short}.mov'
            with open(os.path.join(GATECLIPS, fn), 'wb') as f:
                f.write(blob[obj_name])
            obj = {'name': obj_name}
            eng = outcome_rows(store, sh['id'])
            server = {k: v for k, v in (eng.get('server') or {}).items() if k in _PARITY_METRICS}
            manifest[fn] = {'shot_id': sh['id'], 'user': u[:8], 'source': sh.get('source'),
                            'clip_object': obj['name'], 'matched_by': matched_by,
                            'server': server, 'iphone_db': {k: v for k, v in (eng.get('iphone') or {}).items()
                                                            if k in _PARITY_METRICS}}
            srv_speed = (server.get('ball_speed') or {}).get('value')
            print(json.dumps({'clip': fn, 'src': sh.get('source'), 'by': manifest[fn]['matched_by'],
                              'server_speed': srv_speed, 'focus': short in FOCUS}))
    with open(MANIFEST, 'w') as f:
        json.dump(manifest, f, indent=2)
    found_focus = [k for k, v in manifest.items() if v['shot_id'][:8] in FOCUS]
    print(f'=== {len(manifest)} clips -> GateClips/; manifest written; focus found: {found_focus} ===')


if __name__ == '__main__':
    main()
