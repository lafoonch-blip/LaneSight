"""SerialJobQueue: background (Mac/local) vs sync (Cloud Run Phase 1) execution."""
import os
import time

from lanesight_api.jobs import SerialJobQueue


def test_sync_mode_runs_inline():
    os.environ['LANESIGHT_SYNC_JOBS'] = '1'
    try:
        q = SerialJobQueue()                       # reads the flag at construction
        ran = []
        job = q.submit('t', lambda jb: ran.append(1) or {'ok': True})
        # in sync mode the job is DONE the instant submit() returns (ran in the caller's thread)
        assert job.state == 'done' and job.result == {'ok': True} and ran
        assert q.get(job.id).state == 'done'
    finally:
        del os.environ['LANESIGHT_SYNC_JOBS']


def test_async_mode_runs_on_worker():
    q = SerialJobQueue()                           # no flag -> background worker
    job = q.submit('t', lambda jb: {'ok': 2})
    for _ in range(100):
        if q.get(job.id).state == 'done':
            break
        time.sleep(0.02)
    assert q.get(job.id).state == 'done' and q.get(job.id).result == {'ok': 2}


def test_sync_mode_records_failure():
    os.environ['LANESIGHT_SYNC_JOBS'] = '1'
    try:
        q = SerialJobQueue()

        def boom(jb):
            raise ValueError('nope')
        job = q.submit('t', boom)
        assert job.state == 'failed' and 'nope' in job.reason
    finally:
        del os.environ['LANESIGHT_SYNC_JOBS']
