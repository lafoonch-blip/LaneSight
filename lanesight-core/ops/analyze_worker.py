"""DEC-116 ephemeral analysis worker — the entrypoint of the `lanesight-cv-analyze` Cloud Run Job (always
gen2 microVM, so the CPU-heavy CV runs on the fast/steady Jobs pool, ~2x the slow gVisor service). One Job
execution analyzes ONE shot and drives its durable analysis_job row to done/failed, so the app's existing
GET /jobs/:id polling (DEC-110) resolves with no app change. Reuses the SERVICE's exact analyze→persist→footer
closure (app._build_run) and job execution/persistence (app._queue._execute + app._persist_job) so the result
is byte-identical to the in-service path.

Per-execution inputs come as env (set by the API's :run override): LSW_JOB_ID, LSW_SHOT_ID, LSW_USER_ID,
LSW_SESSION_ID (blank = standalone upload), LSW_CLIP_PATH ({user}/{hex}.mov in shot-clips), LSW_HANDED,
LSW_MODE (shot|form), LSW_IS_UPLOAD (0/1), LSW_CONTENT_HASH. Exits 0 on done, 1 on failed — but the row is
already terminal either way, and a crash/timeout is reconciled by the API's reaper (never a stuck 'running')."""
import os, sys, tempfile, traceback


def main():
    job_id = os.environ['LSW_JOB_ID']
    shot_id = os.environ['LSW_SHOT_ID']
    user_id = os.environ['LSW_USER_ID']
    session_id = os.environ.get('LSW_SESSION_ID') or None
    clip_path = os.environ['LSW_CLIP_PATH']
    handed = os.environ.get('LSW_HANDED') or None
    mode = os.environ.get('LSW_MODE') or 'shot'
    is_upload = os.environ.get('LSW_IS_UPLOAD') == '1'
    content_hash = os.environ.get('LSW_CONTENT_HASH') or None

    from lanesight_api import app as A
    from lanesight_api.jobs import Job
    store = A.get_store()

    # Mark running immediately so a poll never sees a stale 'queued' while the clip downloads.
    job = Job(id=job_id, kind='analyze', user_id=user_id, shot_id=shot_id)
    try:
        data = store.storage_download('shot-clips', clip_path)
    except Exception as e:
        # Can't fetch the clip → fail the row with a coded reason (never leave it 'running'/'queued').
        from lanesight_core.failures import AnalysisFailure
        job.state = 'failed'
        fail = AnalysisFailure('CLIP_FETCH_FAILED', f'{type(e).__name__}: {e}'[:300], stage='fetch')
        job.failure_code, job.failure_stage = fail.code, fail.stage
        job.failure = fail.as_dict(); job.reason = str(fail)
        A._persist_job(job)
        try:
            store.mark_shot_failed(shot_id, fail.code, fail.stage)
        except Exception:
            pass
        print(f'[worker] CLIP_FETCH_FAILED: {e}', file=sys.stderr)
        sys.exit(1)

    dest = tempfile.mkdtemp()
    local = os.path.join(dest, 'clip.mov')
    with open(local, 'wb') as f:
        f.write(data)

    run = A._build_run(shot_id, local, handed, user_id, session_id, mode=mode, is_upload=is_upload,
                       content_hash=content_hash, clip_storage_path=clip_path)
    # _execute drives running→done/failed, wraps unexpected errors as INTERNAL_ERROR, records timings, and
    # persists the terminal row via app._persist_job (_queue.persist is wired at import). Never raises.
    A._queue._execute(job, run)
    print(f'[worker] job={job_id} shot={shot_id} state={job.state} reason={job.reason}', flush=True)
    sys.exit(0 if job.state == 'done' else 1)


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f'[worker] fatal {type(e).__name__}: {e}\n{traceback.format_exc()[-1500:]}', file=sys.stderr)
        sys.exit(2)
