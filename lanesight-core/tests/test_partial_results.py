"""DEC-122: no analysis fails as a whole because one part failed. Every former-fatal code must come back as a
COMPLETED partial result — measured metrics kept, the rest `unavailable` with the stage + reason, plus a
per-stage report — never a raised failure (except unreadable video / a crash). One check per former-fatal code."""
import os, tempfile
import numpy as np
import pytest
from lanesight_core.cv import pipeline as P
from lanesight_core.failures import FAILURE_COPY


def _S():
    return {'ts': np.arange(0, 2, 1 / 60.0), 'shift': np.zeros(3), 'ref': 0}


# Former-fatal codes that now route through the all-`unavailable` partial (_no_metrics_record): lane/foul/track
# detection + a pin-impact miss with no readable spin + an unsupported capture view.
FORMER_FATAL_NO_METRICS = [
    ('LANE_NOT_DETECTED_NO_WOOD', 'lane'),
    ('LANE_NOT_DETECTED_NO_EDGES', 'lane'),
    ('FOUL_LINE_NOT_IN_VIEW', 'lane'),
    ('LANE_GEOMETRY_UNUSABLE', 'lane'),
    ('BALL_TRACK_NOT_FOUND', 'track'),
    ('PIN_IMPACT_NOT_DETECTED', 'impact'),
    ('CAPTURE_VIEW_UNSUPPORTED', 'lane'),
    ('TRACK_TOO_SPARSE_FOR_SPEED', 'compute'),
]


@pytest.mark.parametrize('code,stage', FORMER_FATAL_NO_METRICS)
def test_former_fatal_code_returns_completed_partial(code, stage):
    stages = {stage: {'status': 'failed', 'reason_code': code, 'reason': 'x', 'failed_stage': stage}}
    rec = P._no_metrics_record('clip.mov', _S(), f'reason for {code}', stage, stages, '/tmp/x', 'R',
                               {'shot_id': 's'}, reason_code=code)
    d = rec.to_dict()
    # (a)+(b): a record came back with EVERY catalog metric present and unavailable + reason (no raise, no fabrication)
    names = [x.metric for x in rec.measurements]
    assert len(names) == len(set(names)) == len(P._METRIC_CATALOG)
    for mname, mv in d['metrics'].items():
        assert mv['value'] is None and mv['status'] == 'unavailable', mname
        assert 'Not measured' in (mv['note'] or ''), mname
    # (c): the per-stage report is attached and names the failed stage + code
    assert rec.stage_report is stages
    assert rec.capture_quality['reason_code'] == code and rec.capture_quality['failed_stage'] == stage
    # every code has user-facing copy so the app can render it
    assert code in FAILURE_COPY, f'{code} has no FAILURE_COPY entry'


def test_impact_partial_carries_stage_report():
    T = [{'t': 1.0 + i / 60, 'D': 40} for i in range(30)]
    rev = (380.0, 0.8, 'surface-pattern periodicity', 12.0, 60.0)
    stages = {'stabilize': {'status': 'ok'}, 'lane': {'status': 'ok'}, 'ball_track': {'status': 'ok'},
              'impact': {'status': 'failed', 'reason_code': 'PIN_IMPACT_NOT_DETECTED'}}
    rec = P._impact_missed_record('clip.mov', _S(), T, T, rev, {'shot_id': 's'}, '/tmp/x', 'R',
                                  {'center_x_px': 500.0, 'lanes_detected': 1}, stage_report=stages)
    # rev is still MEASURED (partial), and the stage report rides along
    assert rec.to_dict()['metrics']['rev_rate_lane']['value'] == 380.0
    assert rec.stage_report is stages and rec.stage_report['impact']['status'] == 'failed'


def test_form_delivery_not_isolated_is_a_partial_not_a_fail():
    """DEC-122: when every swing event fails the gates (FORM_DELIVERY_NOT_ISOLATED) the form analysis still
    COMPLETES — events unavailable, but it returns with a stage report (the API no longer raises)."""
    from lanesight_core.form.analyze import analyze_form_clip
    from lanesight_core.form import FORM_P1

    def fake_backend(video, out_prefix=None, handed=None):
        # all P1 metrics unavailable (events nulled), with a stage report marking the isolation failure
        out = {k: {'metric': k, 'value': None, 'unit': u, 'status': 'unavailable', 'confidence': 0.0,
                   'note': 'swing events failed the sanity gates'} for k, u in FORM_P1}
        out['_extras'] = {'events': {'E2': None, 'E3': None, 'E4': None, 'E6': None, 'E7': None}, 'fps': 60.0}
        out['stage_report'] = {'decode': {'status': 'ok'}, 'pose': {'status': 'ok'},
                               'swing_events': {'status': 'failed', 'reason_code': 'FORM_DELIVERY_NOT_ISOLATED'},
                               'delivery_isolation': {'status': 'failed', 'reason_code': 'FORM_DELIVERY_NOT_ISOLATED'}}
        return out

    rec = analyze_form_clip('clip.mov', pose_backend=fake_backend)
    assert rec['status'] == 'ok'                         # completed, not failed
    assert rec.get('stage_report') and rec['stage_report']['delivery_isolation']['status'] == 'failed'
    assert all(mm['value'] is None for mm in rec['metrics'].values())   # events unavailable, nothing fabricated


@pytest.mark.parametrize('clip,ext', [('IMG_8973', 'MOV'), ('IMG_8963', 'MOV')])
def test_real_clip_returns_partial_not_raise(clip, ext):
    """End-to-end: a clip that used to hard-fail now returns a record (no raise) with a stage report. Skips if the
    clip isn't on this machine (like the regression tier)."""
    src = os.path.expanduser(f'~/LaneSightData/training_videos/11:1 Shots/{clip}.{ext}')
    if not os.path.exists(src):
        pytest.skip(f'{clip} not present')
    os.environ.setdefault('LANESIGHT_FFMPEG_DECODE', '1')
    from lanesight_runner.core import analyze_clip
    rec, _, _ = analyze_clip(src, os.path.join(tempfile.mkdtemp(), 'o'), handed='R', timings={})
    d = rec.to_dict() if hasattr(rec, 'to_dict') else rec
    sr = d.get('stage_report') or {}
    assert sr, 'no stage_report on the returned record'
    assert any(v.get('status') == 'failed' for v in sr.values()), 'expected at least one failed stage'
    assert 'metrics' in d and len(d['metrics']) == len(P._METRIC_CATALOG)
