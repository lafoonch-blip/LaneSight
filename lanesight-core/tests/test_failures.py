"""DEC-086 — structured analysis failures, user copy, and the Lab › Uploads row contract."""
import glob
import os
import re

from lanesight_core.failures import AnalysisFailure, FAILURE_COPY, failure_block
from lanesight_api.store import MemoryStore


def _codes_raised_in_source():
    """Every failure code literal actually used in the pipeline (AnalysisFailure('X', …) or code='X')."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))          # lanesight-core/
    codes = set()
    for path in glob.glob(os.path.join(root, 'lanesight_core', '**', '*.py'), recursive=True):
        src = open(path).read()
        codes |= set(re.findall(r"AnalysisFailure\(\s*'([A-Z_]+)'", src))
        codes |= set(re.findall(r"code\s*=\s*'([A-Z_]+)'", src))
    return codes


def test_every_raised_code_has_user_copy():
    used = _codes_raised_in_source()
    assert used, 'no failure codes found — the source scan is wrong'
    missing = sorted(c for c in used if c not in FAILURE_COPY)
    assert not missing, f'failure codes without FAILURE_COPY entries: {missing}'


def test_failure_copy_entries_are_complete():
    for code, copy in FAILURE_COPY.items():
        assert copy.get('user_title') and copy.get('user_message'), f'{code} missing title/message'


def test_analysis_failure_shape():
    e = AnalysisFailure('TRACK_TOO_SPARSE_FOR_SPEED', 'ball not tracked enough', stage='metrics',
                        diagnostics={'on_lane_pts': 3})
    assert isinstance(e, RuntimeError)                       # keeps pytest.raises(RuntimeError, ...) working
    assert str(e).startswith('TRACK_TOO_SPARSE_FOR_SPEED:') and 'not tracked enough' in str(e)
    d = e.as_dict()
    assert d['code'] == 'TRACK_TOO_SPARSE_FOR_SPEED' and d['stage'] == 'metrics' and d['user_title'] and d['user_message']
    assert e.diagnostics['on_lane_pts'] == 3


def test_bad_stage_defaults_to_internal_and_unknown_code_falls_back():
    assert AnalysisFailure('X', 'm', stage='not_a_stage').stage == 'internal'
    fb = failure_block('TOTALLY_UNKNOWN_CODE')
    assert fb['code'] == 'TOTALLY_UNKNOWN_CODE'
    assert fb['user_title'] == FAILURE_COPY['INTERNAL_ERROR']['user_title']   # generic fallback copy


def test_list_uploads_row_contract_and_failure_copy():
    st = MemoryStore()
    ok = st.create_shot('u', None, {'source': 'upload', 'capture_mode': 'shot'})
    st.save_shot_result(ok['id'], {'metrics': {'ball_speed': {'value': 17.0}}}, {'ok': True}, algo_version='x')
    bad = st.create_shot('u', None, {'source': 'upload', 'capture_mode': 'shot'})
    st.mark_shot_failed(bad['id'], 'TRACK_TOO_SPARSE_FOR_SPEED', 'metrics')
    rows = {r['id']: r for r in st.list_uploads('u')}
    a, f = rows[ok['id']], rows[bad['id']]
    assert a['state'] == 'analyzed' and f['state'] == 'failed'
    # the created_at regression that broke Lab › Uploads: it must never be a raw ISO string
    assert not isinstance(a['created_at'], str) and not isinstance(f['created_at'], str)
    # failed rows carry friendly copy
    assert f['failure_code'] == 'TRACK_TOO_SPARSE_FOR_SPEED' and f['failure_title'] and f['failure_message']
    assert a['failure_title'] is None
    # type parity: both stores build rows with _upload_row, so the key set is identical across row states
    assert set(a.keys()) == set(f.keys())


def test_log_analysis_attempt_is_retained_best_effort():
    st = MemoryStore()
    st.log_analysis_attempt({'user_id': 'u', 'shot_id': 's', 'status': 'failed', 'failure_code': 'X'})
    st.log_analysis_attempt({'user_id': 'u', 'shot_id': 's2', 'status': 'analyzed'})
    assert len(st.analysis_attempts) == 2 and st.analysis_attempts[0]['failure_code'] == 'X'
    assert all('id' in r and 'created_at' in r for r in st.analysis_attempts)
