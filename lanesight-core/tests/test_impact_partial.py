"""DEC-109: a missed pin impact yields a partial result (rev rate measured), never a fabricated speed."""
import numpy as np
from lanesight_core.cv import pipeline as P


def _S():
    return {'ts': np.arange(0, 2, 1 / 60.0), 'shift': np.zeros(3), 'ref': 0}


def test_impact_missed_record_keeps_rev_and_withholds_speed():
    T = [{'t': 1.0 + i / 60, 'D': 40} for i in range(30)]
    rev = (380.0, 0.8, 'surface-pattern periodicity', 12.0, 60.0)
    rec = P._impact_missed_record('clip.mov', _S(), T, T, rev, {'shot_id': 's1'}, '/tmp/x', 'R',
                                  {'center_x_px': 500.0, 'lanes_detected': 1})
    d = rec.to_dict()['metrics']
    assert d['rev_rate_lane']['value'] == 380.0 and d['rev_rate_lane']['status'] != 'unavailable'
    assert d['rev_rate']['value'] is not None
    for k in ('ball_speed', 'speed_release', 'speed_early', 'speed_late', 'entry_board', 'arrows_board',
              'breakpoint_board', 'loft'):
        assert d[k]['value'] is None and d[k]['status'] == 'unavailable', k
    assert 'distance reference' in d['ball_speed']['note']
    assert rec.pins is None                                   # strike not read, never guessed
    assert rec.capture_quality['impact'] == 'not_detected'
    assert rec.insights['state'] == 'no_reliable_data'        # no move from a partial shot
    names = [x.metric for x in rec.measurements]
    assert len(names) == len(set(names)) == len(P._METRIC_CATALOG)


def test_rev_rate_gate_needs_enough_large_frames():
    small = [{'t': i / 60, 'D': 20} for i in range(50)]
    rpm, conf, note, sig, fps = P.measure_rev_rate('clip.mov', _S(), small, None)
    assert rpm is None and conf == 0.0 and 'too few' in note
