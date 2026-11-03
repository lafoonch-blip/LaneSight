"""DEC-127: the on-device-first metrics-only endpoint (POST /shots/metrics).

The phone computes all video metrics locally and posts a metrics RECORD (no video). The server must compute the
authoritative Score components + coaching from that record using the SAME pure engines the video path uses, write
DEC-122 outcome rows from the on-device metrics (engine 'iphone', status 'measured'), and return the full shot
card + score in one response. On-device MEASURED metrics are 'measured' and feed the Score exactly like a
server metric — there is no 'best_effort because unvalidated' (validation-vs-truth is a dev gate, not runtime).
No live project is touched (LANESIGHT_FORCE_MEMORY=1)."""
import os, tempfile

os.environ['LANESIGHT_API_DEV'] = '1'
os.environ['LANESIGHT_FORCE_MEMORY'] = '1'
os.environ.setdefault('LANESIGHT_DATA', tempfile.mkdtemp())

from fastapi.testclient import TestClient
from lanesight_api.app import app
from lanesight_api.store import get_store

client = TestClient(app)


def H(u):
    return {'X-Dev-User': u}


def _metrics(entry_board=17.5, entry_angle=5.0, speed=16.5, rev=410.0,
             arrows=15.0, bp=10.0, breakpoint_distance=42.0, laydown=19.0):
    """A full on-device ball metrics record. No status given -> the endpoint treats it as measured ('ok')."""
    return {
        'ball_speed': {'value': speed, 'unit': 'mph'},
        'rev_rate': {'value': rev, 'unit': 'rpm', 'uncertainty': 12.0},
        'entry_board': {'value': entry_board, 'unit': 'board'},
        'entry_angle': {'value': entry_angle, 'unit': 'deg'},
        'arrows_board': {'value': arrows, 'unit': 'board'},
        'breakpoint_board': {'value': bp, 'unit': 'board'},
        'breakpoint_distance': {'value': breakpoint_distance, 'unit': 'ft'},
        'laydown_board': {'value': laydown, 'unit': 'board'},
        'speed_avg_foul_to_pins': {'value': 15.2, 'unit': 'mph', 'status': 'best_effort',
                                   'note': 'approximated impact frame (DEC-112)'},
    }


def _post(u, sid, metrics=None, intent=None):
    body = {'metrics': metrics or _metrics(), 'capture_mode': 'shot', 'source': 'live',
            'algorithm_version': 'ios-ondevice-test', 'app_version': 'test',
            'device_perf': {'latency_s': 7.3},
            'metadata': {'handed': 'R', 'intent': intent or {'arrows_board': 15.0, 'breakpoint_board': 10.0}}}
    if sid is not None:
        body['session_id'] = sid
    return client.post('/shots/metrics', json=body, headers=H(u))


def test_metrics_endpoint_returns_card_and_coaching():
    u = 'dec127a'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    r = _post(u, sid)
    assert r.status_code == 200, r.text
    j = r.json()
    assert j['source'] == 'live' and j['shot_id']
    rec = j['shot']['record']
    M = rec['metrics']
    # DEC-127 PARITY with cv/pipeline.py — on-device metrics get the SAME per-metric status as the server video
    # path, so no metric is 'measured' on one engine and best_effort/unavailable on the other:
    assert M['ball_speed']['status'] == 'best_effort'                 # pipeline.py:592
    assert M['rev_rate']['status'] == 'calibrated_estimate'           # pipeline.py:127
    assert M['speed_avg_foul_to_pins']['status'] == 'best_effort'     # method-approximated impact (DEC-112)
    assert M['arrows_board']['status'] == 'ok'                        # near-lane board is measured
    assert M['arrows_board']['source'] == 'ios-ondevice'
    # far-lane metrics are GATED to unavailable until DEC-065 validation — exactly as the server video path
    assert M['entry_board']['status'] == 'unavailable' and M['entry_board']['value'] is None
    assert M['breakpoint_board']['status'] == 'unavailable'
    assert rec['capture_quality']['far_lane'] == 'limited'
    # key_points keep the raw entry value for the lane view even though the metric is gated
    assert (rec.get('key_points') or {}).get('entry', {}).get('board') == 17.5
    # coaching was computed from the metrics record (coach matrix + lane read), no video involved
    ins = rec['insights']
    assert ins.get('coach') and ins.get('lane')
    assert j['score'] is not None and 'eligible' in j['score']


def test_measured_ondevice_metrics_feed_the_score_components():
    u = 'dec127b'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    snap = None
    for _ in range(5):                         # SCORE_UNLOCK_SHOTS = 5 → s_perf becomes computable
        snap = _post(u, sid).json()['score']
    # Performance uses entry_board (in the pocket range) + entry_angle (in range); with 5 on-device MEASURED
    # shots it must be a real number, proving on-device metrics feed the Score exactly like server metrics.
    assert snap is not None
    # The NON-gated measured on-device metrics feed the Score exactly like server metrics: Accuracy comes from the
    # near-lane arrows board vs intent, Consistency from arrows + rev (calibrated_estimate counts).
    assert snap['a_acc'] is not None, f'accuracy should come from the on-device arrows board: {snap}'
    assert snap['c_cons'] is not None, f'consistency should come from on-device arrows + rev: {snap}'
    # PARITY: Performance needs entry board + angle, which the DEC-065 far-lane gate makes unavailable on BOTH
    # engines — so it stays 'building' and the overall Score is not eligible. Exactly the server's behavior; the
    # on-device path never fabricates a far-lane read the server wouldn't report.
    assert snap['s_perf'] is None, f's_perf must stay building while far-lane is gated: {snap}'
    assert not snap['eligible']


def test_outcome_rows_written_measured_engine_iphone():
    u = 'dec127c'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    # one measured + one explicitly-unavailable metric with a reason
    m = _metrics()
    m['rev_rate'] = {'value': None, 'status': 'unavailable', 'note': 'rev needs 120 fps'}
    _post(u, sid, metrics=m)
    rows = [r for r in getattr(get_store(), 'metric_outcomes', []) if r.get('engine') == 'iphone']
    assert rows, 'on-device outcome rows must be written'
    by_metric = {r['metric_key']: r for r in rows}
    # outcome-row statuses mirror the server video path per metric (no cross-engine disagreement):
    assert by_metric['arrows_board']['status'] == 'measured'          # near-lane board
    assert by_metric['ball_speed']['status'] == 'best_effort'         # pipeline.py:592
    assert by_metric['speed_avg_foul_to_pins']['status'] == 'best_effort'   # approximated impact (DEC-112)
    # entry board is far-lane GATED to unavailable with a non-null reason (DEC-065) — same as the server
    eb = by_metric['entry_board']
    assert eb['status'] == 'unavailable'
    assert eb.get('reason_code') == 'FAR_LANE_UNVALIDATED' and eb.get('failed_stage')
    # a metric the engine genuinely couldn't read is unavailable + its own reason (DEC-122 honesty invariant)
    assert by_metric['rev_rate']['status'] == 'unavailable'
    assert by_metric['rev_rate'].get('reason_code') and by_metric['rev_rate'].get('failed_stage')


def test_trajectory_builds_path_fit_for_the_lane_view():
    u = 'dec127e'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    smoothed = [{'z_ft': float(z), 'board': 20.0 - z * 0.05} for z in range(0, 60, 3)]
    body = {'metrics': _metrics(), 'capture_mode': 'shot', 'source': 'live', 'session_id': sid,
            'algorithm_version': 'ios-ondevice-test',
            'trajectory': {'smoothed': smoothed, 'series': smoothed},
            'metadata': {'handed': 'R', 'intent': {'arrows_board': 15.0, 'breakpoint_board': 10.0}}}
    r = client.post('/shots/metrics', json=body, headers=H(u))
    assert r.status_code == 200, r.text
    rec = r.json()['shot']['record']
    # _shot_card_enrich builds path_fit from the on-device trajectory, so the shot-card lane view draws the path.
    assert rec.get('path_fit') and rec['path_fit'].get('points'), f'path_fit should be built: {rec.get("path_fit")}'
    assert rec['path_fit'].get('measured_extent_ft') == [0.0, 57.0]


def test_engine_failure_reason_propagates_to_every_metric():
    """DEC-127: when the on-device engine failed a stage (e.g. no lane), every unavailable metric must carry the
    REAL reason_code + failed_stage the engine reported (LANE_NOT_DETECTED), not a blanket METRIC_UNAVAILABLE."""
    u = 'dec127f'
    sid = client.post('/sessions', json={}, headers=H(u)).json()['id']
    # the engine measured nothing and reported a lane failure
    body = {'metrics': {'ball_speed': {'value': None, 'status': 'unavailable'}},
            'reason_code': 'LANE_NOT_DETECTED', 'failed_stage': 'lane',
            'stage_report': {'lane': {'status': 'failed', 'reason_code': 'LANE_NOT_DETECTED'}},
            'session_id': sid, 'capture_mode': 'shot', 'source': 'live',
            'algorithm_version': 'ios-ondevice-test', 'metadata': {'handed': 'R'}}
    r = client.post('/shots/metrics', json=body, headers=H(u))
    assert r.status_code == 200, r.text
    assert r.json()['shot']['record']['capture_quality'].get('reason_code') == 'LANE_NOT_DETECTED'
    rows = [x for x in getattr(get_store(), 'metric_outcomes', []) if x.get('engine') == 'iphone']
    # the just-created shot's rows: unavailable ball_speed carries the lane reason, not METRIC_UNAVAILABLE
    bs = [x for x in rows if x['metric_key'] == 'ball_speed'][-1]
    assert bs['status'] == 'unavailable'
    assert bs['reason_code'] == 'LANE_NOT_DETECTED' and bs['failed_stage'] == 'lane'


def test_upload_does_not_feed_score():
    u = 'dec127d'
    r = _post(u, None)                          # no session_id -> standalone upload
    assert r.status_code == 200, r.text
    j = r.json()
    assert j['source'] == 'upload'
    assert j['score'] is None                   # uploads never feed the Score (DEC-055)
