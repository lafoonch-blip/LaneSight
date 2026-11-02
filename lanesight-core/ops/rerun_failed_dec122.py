"""DEC-122 step 3: re-run the 10 historical FAILED attempts (last 14 days) that still have a retained clip,
through the 0.7.2 engine (engine-identical to live rev d397428), to CONVERT the former hard-failures into
completed partials with full per-metric + per-stage outcome rows. Writes to live via the keychain service role.
In-place: the attempt is flipped failed -> analyzed(partial) with provenance kept in diagnostics; outcome rows
are upserted (replacing the backfilled single stage row). Prints before -> after."""
import os, json, tempfile, hashlib
os.environ.setdefault('LANESIGHT_FFMPEG_DECODE', '1'); os.environ.setdefault('LANESIGHT_FRAME_CACHE_MB', '5500')
from lanesight_api.store import get_store, outcome_rows_from_record
from lanesight_core.models.shot import ALGO_VERSION
from lanesight_runner.core import analyze_clip

ATTEMPTS = [
 ("3e5538b7-f67b-4cfc-8dc2-9fb1c6d472db","29a5f799-60bd-4f20-aa97-ced456f708f7","FOUL_LINE_NOT_IN_VIEW","lane","shot","551bc775-dee4-41bd-a19c-116e8691d053/699ea78dc76a44099b80c6b814176fa3.mov"),
 ("49159ee8-c9da-4dfc-b964-1e9a6354953d","020f3c11-ffbb-4a0d-bbc8-0d693dbb5112","BALL_TRACK_NOT_FOUND","track","shot","551bc775-dee4-41bd-a19c-116e8691d053/601f5aa6ed644ad5b8fc730012155775.mov"),
 ("5f1cdabd-de45-479d-b7ba-3a8a9aa6d8b1","87a1fbb6-d801-464b-b96e-132250179182","FOUL_LINE_NOT_IN_VIEW","lane","shot","551bc775-dee4-41bd-a19c-116e8691d053/4c787c47695f4d2b893d2c333d0d4cbe.mov"),
 ("9c36e380-dfe8-4b1d-b3d3-9cd401502059","ce30c8fa-9eb6-4340-8af3-5c4490801546","LANE_NOT_DETECTED_NO_WOOD","lane","shot","551bc775-dee4-41bd-a19c-116e8691d053/887c3f0016ce4aee92f45c5eaecf71f4.mov"),
 ("15e136d6-dbb8-4193-9f16-24dc02cb92ac","57c1aa3c-7e8f-4fe6-a3c6-3aaae6c72aa1","PIN_IMPACT_NOT_DETECTED","impact","shot","551bc775-dee4-41bd-a19c-116e8691d053/d43318716467423283f19294d214fe84.mov"),
 ("a8f9100e-d9ca-4844-a34b-edc86d3b4cd9","b156a830-7f83-4cd1-9f79-d896aaa21a3e","PIN_IMPACT_NOT_DETECTED","impact","shot","551bc775-dee4-41bd-a19c-116e8691d053/e920822a14bb4b91a3ab6f0c30ecdf36.mov"),
 ("5aaa6b82-b979-4581-bef5-62bdc8448e7a","fcd81fca-dc08-45a7-ab8d-ef2bd4aa9495","FORM_DELIVERY_NOT_ISOLATED","form_pose","form","4806c8bc-78ae-49c7-8deb-cb8ce5a3522a/726c886d01134fad9ecc8070f4c7f900.mov"),
 ("9fc5ec8e-4d16-423b-85b0-78a8ae227af0","dcbd83e7-95e9-4aea-b5b3-56830bf6ef9b","FOUL_LINE_NOT_IN_VIEW","lane","shot","4806c8bc-78ae-49c7-8deb-cb8ce5a3522a/53aee5ef26504e91a088bd476c5e8856.mov"),
 ("efd54432-5c36-43a8-8d56-def46a4d187a","3e76c245-2eb2-435a-92a0-70d7ce36753b","FOUL_LINE_NOT_IN_VIEW","lane","shot","4806c8bc-78ae-49c7-8deb-cb8ce5a3522a/d50885967c66401dbff064ed786802bc.mov"),
 ("105d9f42-ca2b-464a-831d-599d352c1c86","9ca7e2d9-bc87-491f-bd49-b09d859cf6d2","FORM_DELIVERY_NOT_ISOLATED","form_pose","form","4806c8bc-78ae-49c7-8deb-cb8ce5a3522a/b45e3b415287454290a3382dfba5bcb0.mov"),
]
DIAG = os.path.expanduser('~/LaneSightData/diagnostics')


def _local_clip(shot_id):
    for root, _, files in os.walk(DIAG):
        for f in files:
            if f == f'{shot_id}.mov':
                return os.path.join(root, f)
    return None


def run():
    store = get_store()
    assert store.__class__.__name__ == 'PgStore', store.__class__.__name__
    print(f'engine={ALGO_VERSION}', flush=True)
    rows = []
    pose_backend = None
    for aid, sid, code, stage, mode, path in ATTEMPTS:
        rec_out = {'attempt': aid[:8], 'shot': sid[:8], 'before': code, 'mode': mode}
        try:
            src = _local_clip(sid)
            if src is None:
                data = store.storage_download('shot-clips', path)
                src = os.path.join(tempfile.mkdtemp(), 'c.mov')
                with open(src, 'wb') as f:
                    f.write(data)
            out_prefix = os.path.join(tempfile.mkdtemp(), 'o')
            if mode == 'form':
                from lanesight_core.form import analyze_form_clip
                from lanesight_core.form.pose import pose_backend as _pb
                d = analyze_form_clip(src, out_prefix=out_prefix, handed='R', pose_backend=_pb)
            else:
                r, _, _ = analyze_clip(src, out_prefix, handed='R', timings={})
                d = r.to_dict() if hasattr(r, 'to_dict') else r
            sr = d.get('stage_report') or {}
            m = d.get('metrics') or {}
            def mv(x): return x.get('value') if isinstance(x, dict) else x
            measured = sum(1 for x in m.values() if mv(x) is not None)
            total = len(m)
            cq = d.get('capture_quality') or {}
            rc = cq.get('reason_code') or code
            fs = cq.get('failed_stage') or stage
            mrows, srows = outcome_rows_from_record(aid, 'server', ALGO_VERSION, mode, m, sr,
                                                    reason_code=rc, failed_stage=fs)
            store.log_outcomes(mrows, srows)
            # Flip the attempt failed -> analyzed(partial), provenance preserved.
            store._req(f'analysis_attempt?id=eq.{aid}', 'PATCH', {
                'status': 'analyzed', 'failure_code': None, 'failure_stage': None,
                'algorithm_version': ALGO_VERSION,
                'diagnostics': {'dec122_reran': True, 'original_failure_code': code, 'partial': True,
                                'measured': measured, 'metrics_total': total}}, prefer='return=minimal')
            rec_out.update({'after': 'partial', 'measured': measured, 'metrics_total': total,
                            'stages_ok': sum(1 for v in sr.values() if v.get('status') == 'ok'),
                            'stages_failed': [k for k, v in sr.items() if v.get('status') == 'failed'],
                            'metric_rows': len(mrows), 'stage_rows': len(srows)})
        except Exception as e:
            import traceback
            rec_out.update({'after': 'ERROR', 'exc': f'{type(e).__name__}: {str(e)[:90]}'})
            traceback.print_exc()
        rows.append(rec_out)
        print("RR " + json.dumps(rec_out), flush=True)
    json.dump(rows, open('/private/tmp/claude-501/-Users-shaynel-Developer-LaneSight-shot/01171e4d-fae8-4363-add7-889722644b1d/scratchpad/rerun_failed.json', 'w'), indent=1)
    print('DONE', flush=True)


run()
