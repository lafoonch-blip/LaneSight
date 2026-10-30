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


def test_scale_unreliable_partial_keeps_rev():
    """DEC-110: a corrupt depth scale (IMPOSSIBLE_SPEED_SCALE / TRACK_TOO_SPARSE_FOR_SPEED) must also degrade to
    the partial — rev measured, scale-dependent metrics unavailable — not fail the whole shot."""
    T = [{'t': 1.0 + i / 60, 'D': 40} for i in range(30)]
    rev = (402.0, 0.8, 'surface-pattern periodicity', 10.0, 60.0)
    reason = "We couldn't pin down a trustworthy lane distance for this shot, so speed and the lane read aren't available"
    rec = P._impact_missed_record('clip.mov', _S(), T, T, rev, {'shot_id': 's2'}, '/tmp/x', 'R',
                                  {'center_x_px': 500.0, 'lanes_detected': 1},
                                  reason=reason, impact_status='scale_unreliable')
    d = rec.to_dict()['metrics']
    assert d['rev_rate_lane']['value'] == 402.0 and d['ball_speed']['value'] is None
    assert rec.capture_quality['impact'] == 'scale_unreliable'
    assert reason in rec.capture_quality['reason']
    assert rec.insights['state'] == 'no_reliable_data'


def test_no_impact_partial_survives_full_api_path(monkeypatch):
    """The 2026-10-30 crash: a no-impact partial whose rev measurement carried a NaN broke PgStore.save_shot_result
    (PostgREST PGRST102 'Empty or invalid json' — json.dumps emits NaN/Infinity tokens). Drive the SAME partial,
    with a NaN in it, through the full server write + engine path and prove nothing fails and no invalid JSON is
    ever sent. Covers the path the record builder test alone missed (that test skips the DB write)."""
    import json as _json
    from lanesight_api.store import PgStore, _json_safe
    from lanesight_api import engines

    # A partial with NaN in the rev measurement (what the real clip produced).
    T = [{'t': 1.0 + i / 60, 'D': 40} for i in range(30)]
    rev = (380.0, float('nan'), 'surface-pattern periodicity', float('nan'), 60.0)
    rec = P._impact_missed_record('clip.mov', _S(), T, T, rev, {'shot_id': 'sx'}, '/tmp/x', 'R',
                                  {'center_x_px': 500.0, 'lanes_detected': 1}).to_dict()
    rec['shot_id'] = 'sx'

    # 1) PgStore write boundary: capture every body sent to PostgREST; each must be strict, NaN-free JSON.
    sent = []

    class _Resp:
        status = 204
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def read(self): return b''
    monkeypatch.setattr('urllib.request.urlopen', lambda req, timeout=None: sent.append(req.data) or _Resp())
    store = PgStore('https://x.supabase.co/rest/v1/', 'service-key')
    store.save_shot_result('sx', rec, {'ok': True})     # used to raise RuntimeError PGRST102
    assert sent, 'no PostgREST write was attempted'
    for body in sent:
        assert b'NaN' not in body and b'Infinity' not in body, body[:120]
        _json.loads(body)                                # parses (strict JSON, no exception)

    # 2) Engine path (score/achievements/insights) on a partial — must not crash, score stays ineligible.
    footer = engines.after_shot_analyzed(store, 'u-partial', None, rec)
    assert footer['eligible'] is False and footer['score'] is None


def test_rev_rate_gate_needs_enough_large_frames():
    small = [{'t': i / 60, 'D': 20} for i in range(50)]
    rpm, conf, note, sig, fps = P.measure_rev_rate('clip.mov', _S(), small, None)
    assert rpm is None and conf == 0.0 and 'too few' in note
