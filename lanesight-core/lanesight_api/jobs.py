"""Serial job queue (DEC-043): the next shot's analysis starts only when the current one finishes.
In-process, single worker thread. Job states queued/running/done/failed(+reason) with per-step timings
(OPS-01). No in-session concurrency in MVP."""
from __future__ import annotations
import threading
import time
import uuid
from dataclasses import dataclass, field


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

    def public(self) -> dict:
        return dict(id=self.id, kind=self.kind, state=self.state, reason=self.reason,
                    timings={k: round(v, 3) for k, v in self.timings.items()},
                    result=self.result)


class SerialJobQueue:
    def __init__(self):
        self._jobs: dict[str, Job] = {}
        self._q: list[tuple[Job, callable]] = []
        self._lock = threading.Lock()
        self._wake = threading.Condition(self._lock)
        self._worker = threading.Thread(target=self._run, name='lanesight-jobs', daemon=True)
        self._worker.start()

    def submit(self, kind: str, fn) -> Job:
        """fn(job) -> result dict. fn may record per-step timings via job.timings[...]. Runs serially."""
        job = Job(id=uuid.uuid4().hex, kind=kind)
        with self._lock:
            self._jobs[job.id] = job
            self._q.append((job, fn))
            self._wake.notify()
        return job

    def get(self, job_id: str) -> Job | None:
        with self._lock:
            return self._jobs.get(job_id)

    def _run(self):
        while True:
            with self._lock:
                while not self._q:
                    self._wake.wait()
                job, fn = self._q.pop(0)
            job.state = 'running'
            job.started_at = time.monotonic()
            try:
                job.result = fn(job)
                job.state = 'done'
            except Exception as e:               # fail visibly with the reason (DEC-043), never silently
                job.state = 'failed'
                job.reason = f'{type(e).__name__}: {e}'
            finally:
                job.finished_at = time.monotonic()
                job.timings['total'] = job.finished_at - job.started_at
