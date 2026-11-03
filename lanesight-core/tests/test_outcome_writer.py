"""DEC-122 §6: the outcome-row writer (store.outcome_rows_from_record) must emit one row per EVERY catalog
metric (incl. unavailable), map the engine's Measurement.status vocabulary correctly, and never violate the
analysis_metric_outcome honesty invariant (unavailable <=> value is null)."""
from lanesight_api.store import outcome_rows_from_record, MemoryStore, _uniform_rows
from lanesight_core.cv.pipeline import _METRIC_CATALOG as SHOT
from lanesight_core.form import FORM_P1


def _honest(rows):
    for r in rows:
        if r['status'] == 'unavailable':
            assert r['value'] is None, f"{r['metric_key']}: unavailable must have null value"
            # DEC-122: every unavailable row MUST carry a non-null reason_code AND failed_stage.
            assert r['reason_code'], f"{r['metric_key']}: unavailable needs a reason_code"
            assert r['failed_stage'], f"{r['metric_key']}: unavailable needs a failed_stage"
        else:
            assert r['value'] is not None, f"{r['metric_key']}: {r['status']} must have a value"
            assert r['reason_code'] is None and r['failed_stage'] is None


def test_shot_record_one_row_per_catalog_metric_with_status_mapping():
    metrics = {
        'ball_speed': {'value': 18.5, 'status': 'ok', 'confidence': 0.9, 'note': 'n'},
        'speed_avg_foul_to_pins': {'value': 17.9, 'status': 'best_effort'},
        'loft': {'value': 1.2, 'status': 'low_confidence'},
        'entry_angle': {'value': 3.1, 'status': 'calibrated_estimate'},
        'entry_board': {'value': None, 'status': 'unavailable', 'note': 'far lane unvalidated'},
    }
    stage_report = {'lane': {'status': 'ok', 'duration_ms': 120},
                    'impact': {'status': 'failed', 'reason_code': 'PIN_IMPACT_NOT_DETECTED'}}
    mrows, srows = outcome_rows_from_record('att-1', 'server', 'lanesight-cv-0.7.2', 'shot',
                                            metrics, stage_report, reason_code='LANE_GEOMETRY_UNUSABLE',
                                            failed_stage='lane')
    # one row per EVERY shot catalog metric
    assert len(mrows) == len(SHOT)
    assert {r['metric_key'] for r in mrows} == {k for k, _ in SHOT}
    by = {r['metric_key']: r for r in mrows}
    assert by['ball_speed']['status'] == 'measured' and by['ball_speed']['value'] == 18.5   # ok -> measured
    assert by['speed_avg_foul_to_pins']['status'] == 'best_effort'
    assert by['loft']['status'] == 'low_confidence'
    assert by['entry_angle']['status'] == 'calibrated_estimate'
    assert by['entry_board']['status'] == 'unavailable' and by['entry_board']['value'] is None
    # a metric absent from the record is unavailable, stamped with the attempt-level cause
    assert by['rev_rate']['status'] == 'unavailable'
    assert by['entry_board']['reason_code'] == 'LANE_GEOMETRY_UNUSABLE'
    assert by['entry_board']['failed_stage'] == 'lane'
    _honest(mrows)
    # stage rows mirror the report
    sby = {r['stage']: r for r in srows}
    assert sby['lane']['status'] == 'ok' and sby['lane']['duration_ms'] == 120
    assert sby['impact']['status'] == 'failed' and sby['impact']['reason_code'] == 'PIN_IMPACT_NOT_DETECTED'


def test_stage_duration_ms_float_is_coerced_to_int():
    # The stage report records float ms; the duration_ms column is INTEGER (else PostgREST 22P02).
    _, srows = outcome_rows_from_record('att-d', 'server', 'v', 'shot', {},
                                        {'stabilize': {'status': 'ok', 'duration_ms': 131033.9},
                                         'lane': {'status': 'ok', 'duration_ms': None}})
    sby = {r['stage']: r for r in srows}
    assert sby['stabilize']['duration_ms'] == 131034 and isinstance(sby['stabilize']['duration_ms'], int)
    assert sby['lane']['duration_ms'] is None


def test_successful_shot_unavailable_metrics_get_structural_codes_without_attempt_cause():
    # Mirrors a FULLY successful shot: measured headline metrics + structurally-unavailable far-lane / spin / grip
    # metrics (note only, no attempt-level reason_code). Every unavailable row must still get code + stage.
    metrics = {
        'ball_speed': {'value': 18.5, 'status': 'ok'},
        'speed_late': {'value': None, 'status': 'unavailable', 'note': 'Far-lane metric gated until Phase-2 validation (DEC-065).'},
        'entry_board': {'value': None, 'status': 'unavailable', 'note': 'Far-lane metric gated until Phase-2 validation (DEC-065).'},
        'axis_rotation': {'value': None, 'status': 'unavailable', 'note': 'not yet measured from video'},
        'pap': {'value': None, 'status': 'unavailable', 'note': 'needs grip reference (holes/marker/profile)'},
    }
    mrows, _ = outcome_rows_from_record('att-s', 'server', 'v', 'shot', metrics, {'lane': {'status': 'ok'}})
    _honest(mrows)                                   # proves no null reason_code/failed_stage anywhere
    by = {r['metric_key']: r for r in mrows}
    assert (by['speed_late']['reason_code'], by['speed_late']['failed_stage']) == ('FAR_LANE_UNVALIDATED', 'compute')
    assert (by['entry_board']['reason_code'], by['entry_board']['failed_stage']) == ('FAR_LANE_UNVALIDATED', 'compute')
    assert (by['axis_rotation']['reason_code'], by['axis_rotation']['failed_stage']) == ('AXIS_NOT_MEASURED_FROM_VIDEO', 'rev')
    assert (by['pap']['reason_code'], by['pap']['failed_stage']) == ('PAP_NEEDS_GRIP_REFERENCE', 'rev')


def test_spin_grip_structural_code_wins_over_attempt_cause():
    # Even when a stage failed (attempt-level cause present), spin/grip stay structural (never video-measured).
    mrows, _ = outcome_rows_from_record('att-x', 'server', 'v', 'shot',
                                        {'axis_tilt': {'value': None, 'status': 'unavailable'}}, None,
                                        reason_code='PIN_IMPACT_NOT_DETECTED', failed_stage='impact')
    by = {r['metric_key']: r for r in mrows}
    assert by['axis_tilt']['reason_code'] == 'AXIS_NOT_MEASURED_FROM_VIDEO'
    # a non-structural unavailable metric inherits the attempt-level cause
    assert by['ball_speed']['reason_code'] == 'PIN_IMPACT_NOT_DETECTED' and by['ball_speed']['failed_stage'] == 'impact'


def test_form_catalog_and_ios_raw_scalar_shape():
    # on-device payload: metric -> raw scalar (no Measurement dict). Present = measured; missing = unavailable.
    metrics = {'approach_time': 1.1, 'step_count': 5, 'slide_length': None}
    mrows, _ = outcome_rows_from_record('att-2', 'iphone', 'ios-ondevice', 'form', metrics, None)
    assert len(mrows) == len(FORM_P1)
    by = {r['metric_key']: r for r in mrows}
    assert by['approach_time']['status'] == 'measured' and by['approach_time']['value'] == 1.1
    assert by['step_count']['status'] == 'measured' and by['step_count']['value'] == 5.0
    assert by['slide_length']['status'] == 'unavailable'           # explicit None
    assert by['finish_hold']['status'] == 'unavailable'            # absent from payload
    _honest(mrows)


def test_unavailable_with_zero_placeholder_value_is_nulled():
    # The form engine marks unavailable metrics with a 0.0 placeholder, not None. Mapping by STATUS must still
    # null the value, else the row would violate analysis_metric_outcome_value_chk (live form 23514).
    mrows, _ = outcome_rows_from_record('att-f', 'server', 'v', 'form',
                                        {'pushaway_time': {'value': 0.0, 'status': 'unavailable', 'note': 'n'}}, None)
    by = {r['metric_key']: r for r in mrows}
    assert by['pushaway_time']['status'] == 'unavailable' and by['pushaway_time']['value'] is None
    _honest(mrows)


def test_ondevice_scalar_metrics_are_best_effort_not_measured():
    # DEC-126: the on-device engine sends raw scalars with no status; they must record as best_effort (no ground
    # truth), never measured — while the server's default stays measured.
    srv, _ = outcome_rows_from_record('att-sv', 'server', 'v', 'shot', {'ball_speed': 18.5}, None)
    ios, _ = outcome_rows_from_record('att-ph', 'iphone', 'v', 'shot', {'ball_speed': 18.5}, None,
                                      scalar_status='best_effort')
    assert next(r for r in srv if r['metric_key'] == 'ball_speed')['status'] == 'measured'
    assert next(r for r in ios if r['metric_key'] == 'ball_speed')['status'] == 'best_effort'


def test_non_numeric_value_is_treated_as_unavailable():
    mrows, _ = outcome_rows_from_record('att-3', 'server', 'v', 'shot',
                                        {'ball_speed': {'value': 'fast', 'status': 'ok'}}, None)
    by = {r['metric_key']: r for r in mrows}
    assert by['ball_speed']['status'] == 'unavailable' and by['ball_speed']['value'] is None
    _honest(mrows)


def test_uniform_rows_guards_postgrest_bulk_insert():
    # Mixed measured + unavailable rows have different populated keys; the batch sent to PostgREST must still
    # have one common key set (PGRST102 "All object keys must match" otherwise).
    mrows, _ = outcome_rows_from_record('att-u', 'server', 'v', 'shot',
                                        {'ball_speed': {'value': 18.0, 'status': 'ok'}}, None)
    uni = _uniform_rows(mrows)
    keysets = {frozenset(r.keys()) for r in uni}
    assert len(keysets) == 1, 'all rows in a batch must share the same keys'
    # value is still present (as None) on unavailable rows so the honesty check sees an explicit null
    assert all('value' in r and 'reason_code' in r for r in uni)


def test_memory_store_log_outcomes_accumulates():
    s = MemoryStore()
    mrows, srows = outcome_rows_from_record('att-4', 'server', 'v', 'shot',
                                            {'ball_speed': {'value': 18.0, 'status': 'ok'}},
                                            {'lane': {'status': 'ok'}})
    s.log_outcomes(mrows, srows)
    assert len(s.metric_outcomes) == len(SHOT)
    assert len(s.stage_outcomes) == 1
