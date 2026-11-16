"""DEC-103/DEC-113 follow-up: re-run every retained clip through the canon3 (0.7.0 canonical-decode) engine
IN PLACE, so the shot's speeds stop being ~14% low. Retained clips live in the private `shot-clips` bucket
({user_id}/{hex}.mov); the shot is matched by sha256(bytes) == shots.content_hash. Previously-analyzed shots
are overwritten with 0.7.0 measurements (algorithm_version bumped, legacy stays false); clips that fail precheck
(framing) are reported and left untouched. Run with the canonical env:
  LANESIGHT_FFMPEG_DECODE=1 LANESIGHT_FRAME_CACHE_MB=5500 python3 ops/rerun_retained_clips.py
"""
import os, sys, json, hashlib, tempfile, time
from lanesight_api.store import get_store
from lanesight_core.models.shot import ALGO_VERSION
from lanesight_runner.core import analyze_clip

BUCKETS = 'shot-clips'
USERS = ['4806c8bc-78ae-49c7-8deb-cb8ce5a3522a', '551bc775-dee4-41bd-a19c-116e8691d053']


def old_speed(store, shot_id):
    rows = store._get('measurements', f'shot_id=eq.{shot_id}&metric=eq.ball_speed&select=value,algorithm_version')
    return (rows[0].get('value'), rows[0].get('algorithm_version')) if rows else (None, None)


def main():
    assert os.environ.get('LANESIGHT_FFMPEG_DECODE') == '1', 'set LANESIGHT_FFMPEG_DECODE=1'
    store = get_store()
    assert store.__class__.__name__ == 'PgStore', f'expected PgStore, got {store.__class__.__name__}'
    print(f'engine ALGO_VERSION={ALGO_VERSION}')
    results = []
    for u in USERS:
        objs = store.storage_list(BUCKETS, u)
        for o in objs:
            name = o.get('name')
            if not o.get('id') or not name or not name.endswith('.mov'):   # skip folder placeholders
                continue
            path = f'{u}/{name}' if not name.startswith(u) else name
            data = store.storage_download(BUCKETS, path)
            h = hashlib.sha256(data).hexdigest()
            shots = store._get('shots', f'content_hash=eq.{h}&select=id,user_id,session_id,handed,source,'
                                        'capture_mode,analysis_status,algorithm_version')
            if not shots:
                results.append({'path': path, 'sha256': h[:12], 'match': None, 'note': 'no shot with this hash'})
                continue
            sh = shots[0]
            o_speed, o_ver = old_speed(store, sh['id'])
            tmp = os.path.join(tempfile.mkdtemp(), 'c.mov')
            with open(tmp, 'wb') as f:
                f.write(data)
            t = time.time()
            try:
                rec, probe, timings = analyze_clip(tmp, os.path.splitext(tmp)[0],
                                                   handed=sh.get('handed'), timings={})
                d = rec.to_dict() if hasattr(rec, 'to_dict') else rec
                # save_shot_result's measurements upsert resolves on the PK (id), not (shot_id,metric,source),
                # so re-saving a shot that already has rows 409s. Clear this shot's video measurements first,
                # then save_shot_result inserts the fresh 0.7.0 rows cleanly. (Form rows untouched.)
                store._req(f'measurements?shot_id=eq.{sh["id"]}&source=eq.lanesight_video', 'DELETE')
                store.save_shot_result(sh['id'], d, {'ok': True}, algo_version=ALGO_VERSION)
                n_speed = ((d.get('metrics') or {}).get('ball_speed') or {}).get('value')
                results.append({'path': path, 'shot_id': sh['id'], 'user': u[:8],
                                'prev_status': sh.get('analysis_status'), 'prev_ver': o_ver,
                                'old_speed': o_speed, 'new_speed': n_speed,
                                'secs': round(time.time() - t, 1), 'outcome': 'reanalyzed'})
            except Exception as e:
                results.append({'path': path, 'shot_id': sh['id'], 'user': u[:8],
                                'prev_status': sh.get('analysis_status'), 'old_speed': o_speed,
                                'outcome': f'FAILED {type(e).__name__}: {str(e)[:70]}', 'secs': round(time.time() - t, 1)})
            print(json.dumps(results[-1]), flush=True)
    print('=== SUMMARY ===', flush=True)
    reana = [r for r in results if r.get('outcome') == 'reanalyzed']
    print(f'clips={len(results)} reanalyzed={len(reana)} failed={len([r for r in results if str(r.get("outcome","")).startswith("FAILED")])} '
          f'no_match={len([r for r in results if r.get("match") is None and "note" in r])}', flush=True)
    print('DONE', flush=True)


if __name__ == '__main__':
    main()
