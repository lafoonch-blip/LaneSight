"""Job.public() must serialize non-numeric timing values (regression: the ball analyze path puts a nested
`cv` profiling dict and a `windowed_error` string into timings; round() on those raised TypeError and 500'd
every GET /jobs/{id} poll, which the app surfaced as a 'network error')."""
from lanesight_api.jobs import Job


def test_job_public_tolerates_nonnumeric_timings():
    j = Job(id='x', kind='analyze')
    j.timings = {'analyze': 1.2345, 'cv': {'stabilize': 0.9, 'blobs': 2.5}, 'windowed_error': 'retry'}
    pub = j.public()                                 # must not raise (was round(dict) -> TypeError)
    assert isinstance(pub['timings']['analyze'], float)          # floats still rounded
    assert pub['timings']['cv'] == {'stabilize': 0.9, 'blobs': 2.5}   # nested dict passed through untouched
    assert pub['timings']['windowed_error'] == 'retry'               # string passed through untouched
