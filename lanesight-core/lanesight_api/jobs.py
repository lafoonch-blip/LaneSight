"""Serial job queue (DEC-043): the next shot's analysis starts only when the current one finishes.
In-process, single worker thread. Job states queued/running/done/failed(+reason) with per-step timings
(OPS-01). No in-session concurrency in MVP."""
from __future__ import annotations
import os
import threading
import time
import uuid
from dataclasses import dataclass, field


class AnalysisBusy(Exception):
    """This instance is already running an analysis (per-instance slot taken). The caller returns HTTP 409 so
    the app can retry — not an error, just back-pressure. DEC-043 one-at-a-time is per session anyway."""


@dataclass
class Job:
    id: str
    kind: str
    state: str = 'queued'           # queued | running | done | failed
    reason: str | None = None
    result: dict | None = None
    timings: dict = field(default_factory=dict)   # step -> seconds
    created_at: float = field(default_factory=time.monotonic)
    started_at: float | None = None
    finished_at: float | None = None
    # Durable-job metadata (Part 3a): who owns the job + which shot, so a persisted row is resolvable
    # cross-instance and scoped to the user on GET /jobs/:id.
    user_id: str | None = None
    shot_id: str | None = None
    # Structured failure (DEC-086): the stable code/stage + the numbers behind it, and the user-facing copy.
    failure_code: str | None = None
    failure_stage: str | None = None
    diagnostics: dict | None = None
    failure: dict | None = None     # {code, stage, user_title, user_message, tip} for the app

    def public(self) -> dict:
        # The app decodes `timings` as a flat {String: Double}. Expose ONLY numeric step times there; the
        # nested/structured detail (cv, decode, client, windowed_error, …) goes under `timings_detail` so a new
        # nested timing field can never again break the client's post-analysis fetch (P0 2026-10-29).
        flat, detail = {}, {}
        for k, v in self.timings.items():
            if isinstance(v, (int, float)) and not isinstance(v, bool):
                flat[k] = round(float(v), 3)
            else:
                detail[k] = v
        return dict(id=self.id, kind=self.kind, state=self.state, reason=self.reason,
                    timings=flat, timings_detail=(detail or None),
                    result=self.result, failure=self.failure)     # failure is None on success


class SerialJobQueue:
    def __init__(self):
        self._jobs: dict[str, Job] = {}
        self._q: list[tuple[Job, callable]] = []
        self._lock = threading.Lock()
        self._wake = threading.Condition(self._lock)
        # SYNC mode (LANESIGHT_SYNC_JOBS=1): run the analysis INLINE in the request thread instead of a
        # background worker. Cloud Run (Phase 1, DEPLOY_CLOUDRUN.md) throttles CPU to ~zero once a request
        # returns, so a background thread would stall; running inside the request keeps CPU allocated and
        # lets the instance scale to zero afterward. The Mac/local service keeps the async background worker.
        self._sync = os.environ.get('LANESIGHT_SYNC_JOBS') == '1'
        # Per-INSTANCE cap of one running analysis. With Cloud Run concurrency > 1 (so the light API — home,
        # score, sessions — is served alongside a running analysis instead of queued behind it), two analyze
        # requests could otherwise land on the same instance and run two multi-GB analyses at once → OOM. This
        # non-blocking guard lets the 2nd return a fast BUSY (the app retries) rather than thrash memory. It is
        # NOT a global lock (DEC-043 one-at-a-time is PER SESSION, and a session's shots are serial in practice);
        # different instances still analyse different users concurrently.
        self._analysis_slot = threading.BoundedSemaphore(1)
        # Durable-job sink (Part 3a): set by the app to a best-effort persist(job) that writes the job row to
        # Supabase on every state change, so GET /jobs/:id resolves on any instance / after a restart. None in
        # tests / the Mac service (in-memory is enough there); a persist failure never fails the analysis.
        self.persist = None
        if not self._sync:
            self._worker = threading.Thread(target=self._run, name='lanesight-jobs', daemon=True)
            self._worker.start()

    def _persist(self, job):
        if not self.persist:
            return
        try:
            self.persist(job)
        except Exception as e:                   # best-effort: durability must never fail the analysis
            print(f'job persist skipped ({type(e).__name__}: {e})')

    def submit(self, kind: str, fn, user_id: str | None = None, shot_id: str | None = None) -> Job:
        """fn(job) -> result dict. fn may record per-step timings via job.timings[...]. Runs serially on the
        background worker, or INLINE (done when this returns) in sync mode. An `analyze` job in sync mode holds
        the per-instance analysis slot; if one is already running HERE, raises AnalysisBusy (→ HTTP 409)."""
        job = Job(id=uuid.uuid4().hex, kind=kind, user_id=user_id, shot_id=shot_id)
        with self._lock:
            self._jobs[job.id] = job
        self._persist(job)                       # 'queued' row exists before the POST returns its job_id
        if self._sync:
            if kind == 'analyze':
                if not self._analysis_slot.acquire(blocking=False):
                    raise AnalysisBusy()
                try:
                    self._execute(job, fn)
                finally:
                    self._analysis_slot.release()
            else:
                self._execute(job, fn)
            return job
        with self._lock:
            self._q.append((job, fn))
            self._wake.notify()
        return job

    def get(self, job_id: str) -> Job | None:
        with self._lock:
            return self._jobs.get(job_id)

    def _execute(self, job, fn):
        """Run one job to completion (shared by the background worker and sync mode)."""
        job.state = 'running'
        job.started_at = time.monotonic()
        self._persist(job)                       # a cross-instance poll now sees 'running', not 404
        try:
            job.result = fn(job)
            job.state = 'done'
            # fn() may have learned the shot_id (e.g. a storage analyze that creates the shot) — carry it.
            if isinstance(job.result, dict) and job.result.get('shot_id'):
                job.shot_id = job.result['shot_id']
        except Exception as e:                   # fail visibly with the reason (DEC-043), never silently
            from lanesight_core.failures import AnalysisFailure
            if not isinstance(e, AnalysisFailure):   # wrap anything unexpected as a stable INTERNAL_ERROR
                import traceback
                e = AnalysisFailure('INTERNAL_ERROR', f'{type(e).__name__}: {e}'[:500], stage='internal',
                                    diagnostics={'exc_type': type(e).__name__,
                                                 'traceback_tail': traceback.format_exc()[-800:]})
            job.state = 'failed'
            job.failure_code, job.failure_stage, job.diagnostics = e.code, e.stage, e.diagnostics
            job.failure = e.as_dict()
            job.reason = str(e)                  # "CODE: message" — kept for back-compat
        finally:
            job.finished_at = time.monotonic()
            job.timings['total'] = job.finished_at - job.started_at
            self._persist(job)                   # terminal row: done+result or failed+failure, resolvable anywhere

    def _run(self):
        while True:
            with self._lock:
                while not self._q:
                    self._wake.wait()
                job, fn = self._q.pop(0)
            self._execute(job, fn)
