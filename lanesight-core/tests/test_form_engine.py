"""Form-only engine step (lanesight_api.engines.after_form_analyzed): per-metric form baselines (view='form'),
WATCH flags, and the FOCUS insight evaluated from the seeded form_rule rows. No fabricated numbers: with too
few deliveries the baseline is honest 'building' (null on the metric) and FOCUS is None."""
from lanesight_api import engines
from lanesight_api.store import MemoryStore


def _metric(metric, value, unit='s', status='best_effort', conf=0.6):
    return {'metric': metric, 'value': value, 'unit': unit, 'status': status, 'confidence': conf}


def _form_record(finish_hold, swing_time=1.5):
    metrics = {'finish_hold': _metric('finish_hold', finish_hold),
               'swing_time': _metric('swing_time', swing_time)}
    return {'form_version': 'form-0.0.0', 'metrics': metrics, 'measurements': list(metrics.values()),
            'key_frames': ['ball_start', 'top_of_swing', 'release', 'finish']}


def _seed(store, user, session, n, finish_hold=1.2):
    for _ in range(n):
        sh = store.create_shot(user, session, {'source': 'form'})
        store.save_shot_result(sh['id'], _form_record(finish_hold), {'ok': True, 'mode': 'form'})


def test_building_when_under_min_n():
    store = MemoryStore()
    user, session = 'u1', 's1'
    _seed(store, user, session, 3, finish_hold=1.2)           # 3 prior + 1 current = 4 < min_n(10)
    cur = _form_record(0.8)
    footer = engines.after_form_analyzed(store, user, session, cur, analyze_seconds=42.0)
    assert cur['metrics']['finish_hold']['baseline'] is None   # honest building
    assert cur.get('focus') is None and footer['focus'] is None
    assert footer['footer']['analyzed_s'] == 42.0 and footer['footer']['rules_version'] >= 1
    assert footer['n_form_deliveries'] == 4


def test_baseline_watch_and_focus_fire_with_enough_deliveries():
    store = MemoryStore()
    user, session = 'u2', 's2'
    _seed(store, user, session, 12, finish_hold=1.2)          # establishes a ~1.2 s finish-hold baseline
    cur = _form_record(0.8)                                   # this delivery posts short
    footer = engines.after_form_analyzed(store, user, session, cur, analyze_seconds=48.0)
    fh = cur['metrics']['finish_hold']
    assert fh['baseline'] and fh['baseline']['established'] is not False
    assert fh['baseline']['median'] == 1.2 and fh['baseline']['n'] == 13
    assert fh['watch'] is True                                # 0.8 s is outside the personal band
    focus = footer['focus']
    assert focus and focus['metric'] == 'finish_hold' and focus['rule_id'] == 'RULE-short-finish'
    assert focus['cue'] == 'Post the shot until it hits'
    assert focus['drill']['name'] == 'Post the shot' and focus['drill']['how']
    assert 'shorter than your baseline' in focus['comparison_text']
    assert '0.8 s' in focus['comparison_text'] and '1.2 s' in focus['comparison_text']


def test_no_focus_when_in_band():
    store = MemoryStore()
    user, session = 'u3', 's3'
    _seed(store, user, session, 12, finish_hold=1.2)
    cur = _form_record(1.2)                                   # on baseline -> no watch, no focus
    footer = engines.after_form_analyzed(store, user, session, cur, analyze_seconds=10.0)
    assert cur['metrics']['finish_hold'].get('watch') is False
    assert footer['focus'] is None


def test_form_baselines_stored_under_form_view():
    store = MemoryStore()
    user, session = 'u4', 's4'
    _seed(store, user, session, 12, finish_hold=1.2)
    engines.after_form_analyzed(store, user, session, _form_record(1.2), analyze_seconds=1.0)
    views = {b['view'] for b in store.list_baselines(user)}
    assert views == {'form'}                                  # never mixes with ball baselines (view='all')
