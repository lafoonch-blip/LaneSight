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


def test_sync_failure_exposes_friendly_block_to_the_app():
    """DEC-086: public() must carry the user-facing `failure` block the iOS app shows, never a raw trace."""
    os.environ['LANESIGHT_SYNC_JOBS'] = '1'
    try:
        q = SerialJobQueue()
        # an unexpected error is wrapped as INTERNAL_ERROR with generic friendly copy
        pub = q.submit('t', lambda jb: (_ for _ in ()).throw(ValueError('nope'))).public()
        assert pub['state'] == 'failed'
        assert pub['failure']['code'] == 'INTERNAL_ERROR'
        assert pub['failure']['user_title'] and pub['failure']['user_message']
        assert 'Traceback' not in pub['failure']['user_message']       # the trace never reaches the user

        # a structured AnalysisFailure keeps its stable code + stage
        from lanesight_core.failures import AnalysisFailure
        def sparse(jb):
            raise AnalysisFailure('TRACK_TOO_SPARSE_FOR_SPEED', 'too few points', stage='metrics')
        pub2 = q.submit('t', sparse).public()
        assert pub2['failure']['code'] == 'TRACK_TOO_SPARSE_FOR_SPEED' and pub2['failure']['stage'] == 'metrics'
    finally:
        del os.environ['LANESIGHT_SYNC_JOBS']


def test_durable_job_resolves_cross_instance():
    """Part 3a: a job persisted by one instance must be resolvable by ANOTHER instance (fresh in-memory queue)
    via the shared store — the fix for GET /jobs/:id 404ing the lost session. Simulates two Cloud Run
    instances sharing Supabase with one MemoryStore."""
    from lanesight_api.store import MemoryStore
    os.environ['LANESIGHT_SYNC_JOBS'] = '1'
    try:
        store = MemoryStore()                          # stands in for shared Supabase
        inst_a = SerialJobQueue(); inst_a.persist = lambda jb: store.save_job(_row(jb))
        job = inst_a.submit('analyze', lambda jb: {'shot_id': 'shot-9', 'ok': True},
                            user_id='user-1', shot_id='shot-9')
        assert job.state == 'done'
        # The row went through to the store at queued -> running -> done.
        row = store.get_job(job.id)
        assert row and row['state'] == 'done' and row['result']['shot_id'] == 'shot-9'
        assert row['user_id'] == 'user-1' and row['shot_id'] == 'shot-9'

        # Instance B never saw this job in memory, but resolves it from the store — no 404.
        inst_b = SerialJobQueue()
        assert inst_b.get(job.id) is None              # not in B's memory
        assert store.get_job(job.id)['state'] == 'done'   # ...but durable, so the endpoint's fallback resolves it
    finally:
        del os.environ['LANESIGHT_SYNC_JOBS']


def test_durable_job_persists_failure_cross_instance():
    """A failed analysis must also be durable so the away/relaunch path shows the reason, not a 404."""
    from lanesight_api.store import MemoryStore
    from lanesight_core.failures import AnalysisFailure
    os.environ['LANESIGHT_SYNC_JOBS'] = '1'
    try:
        store = MemoryStore()
        q = SerialJobQueue(); q.persist = lambda jb: store.save_job(_row(jb))
        job = q.submit('analyze',
                       lambda jb: (_ for _ in ()).throw(
                           AnalysisFailure('PIN_IMPACT_NOT_DETECTED', 'no impact', stage='impact')),
                       user_id='user-2', shot_id='shot-x')
        row = store.get_job(job.id)
        assert row['state'] == 'failed' and row['failure']['code'] == 'PIN_IMPACT_NOT_DETECTED'
    finally:
        del os.environ['LANESIGHT_SYNC_JOBS']


def test_job_persist_failure_never_fails_the_analysis():
    """Durability is best-effort: if the store write raises, the analysis still completes (DEC: a logging/
    persistence fault must never fail a shot)."""
    os.environ['LANESIGHT_SYNC_JOBS'] = '1'
    try:
        def boom_persist(_jb):
            raise RuntimeError('supabase down')
        q = SerialJobQueue(); q.persist = boom_persist
        job = q.submit('analyze', lambda jb: {'shot_id': 's'}, user_id='u', shot_id='s')
        assert job.state == 'done' and job.result == {'shot_id': 's'}
    finally:
        del os.environ['LANESIGHT_SYNC_JOBS']


def _row(job):
    pub = job.public()
    return {'id': pub['id'], 'user_id': job.user_id, 'shot_id': job.shot_id, 'kind': pub['kind'],
            'state': pub['state'], 'reason': pub.get('reason'), 'result': pub.get('result'),
            'failure': pub.get('failure'), 'timings': pub.get('timings')}


def test_public_timings_are_flat_numeric_for_the_app():
    """P0 2026-10-29 contract: the app decodes job.timings as a flat {str: float}. public() must therefore emit
    ONLY numeric step times in `timings`; any nested/structured timing (cv/decode/client) or string goes under
    `timings_detail` so a new nested server field can never again break the client's post-analysis fetch."""
    from lanesight_api.jobs import Job
    j = Job(id='j1', kind='analyze')
    j.state = 'done'
    j.timings = {
        'analyze': 12.3456, 'window': 2.0, 'convert': 0,
        'decode': {'passes': 9, 'seconds': 3.5},            # nested (DEC-092)
        'cv': {'stabilize_s': 14.8},                        # nested
        'client': {'trim_s': 1.1},                          # nested (DEC-092 M1)
        'windowed_error': 'no sustained burst',             # string
    }
    pub = j.public()
    # every value the app reads is a number
    assert all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in pub['timings'].values()), pub['timings']
    assert set(pub['timings']) == {'analyze', 'window', 'convert'}
    assert pub['timings']['analyze'] == 12.346                 # rounded to 3dp
    # the nested / non-numeric detail is preserved, just out of the app's path
    assert pub['timings_detail']['decode']['passes'] == 9
    assert pub['timings_detail']['windowed_error'] == 'no sustained burst'
