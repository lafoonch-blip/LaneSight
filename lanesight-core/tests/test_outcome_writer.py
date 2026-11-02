"""DEC-122 §6: the outcome-row writer (store.outcome_rows_from_record) must emit one row per EVERY catalog
metric (incl. unavailable), map the engine's Measurement.status vocabulary correctly, and never violate the
analysis_metric_outcome honesty invariant (unavailable <=> value is null)."""
from lanesight_api.store import outcome_rows_from_record, MemoryStore
from lanesight_core.cv.pipeline import _METRIC_CATALOG as SHOT
from lanesight_core.form import FORM_P1


def _honest(rows):
    for r in rows:
        if r['status'] == 'unavailable':
            assert r['value'] is None, f"{r['metric_key']}: unavailable must have null value"
        else:
            assert r['value'] is not None, f"{r['metric_key']}: {r['status']} must have a value"


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


def test_non_numeric_value_is_treated_as_unavailable():
    mrows, _ = outcome_rows_from_record('att-3', 'server', 'v', 'shot',
                                        {'ball_speed': {'value': 'fast', 'status': 'ok'}}, None)
    by = {r['metric_key']: r for r in mrows}
    assert by['ball_speed']['status'] == 'unavailable' and by['ball_speed']['value'] is None
    _honest(mrows)


def test_memory_store_log_outcomes_accumulates():
    s = MemoryStore()
    mrows, srows = outcome_rows_from_record('att-4', 'server', 'v', 'shot',
                                            {'ball_speed': {'value': 18.0, 'status': 'ok'}},
                                            {'lane': {'status': 'ok'}})
    s.log_outcomes(mrows, srows)
    assert len(s.metric_outcomes) == len(SHOT)
    assert len(s.stage_outcomes) == 1
