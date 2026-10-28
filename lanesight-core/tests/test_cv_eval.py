"""DEC-094 §1/§2 — eval-harness scoring helpers + ball-label I/O (headless; no clips needed)."""
import json
from ops.cv_eval import (region_index, observations_per_region, coverage, metric_errors,
                         thin_camera_classes, DEFAULT_REGIONS)
from lanesight_core.cv.calib import ball_label as bl


# ---- region binning ----

def test_region_index():
    assert region_index(0) == 0 and region_index(14.9) == 0
    assert region_index(15) == 1 and region_index(39.9) == 1
    assert region_index(40) == 2 and region_index(59.9) == 2
    assert region_index(60) is None and region_index(-1) is None and region_index(None) is None


def test_observations_per_region():
    traj = [{'z_ft': 2}, {'z_ft': 10}, {'z_ft': 20}, {'z_ft': 45}, {'z_ft': 100}, {'z_ft': None}]
    obs = observations_per_region(traj)
    assert obs == {'0-15ft': 2, '15-40ft': 1, '40-60ft': 1}


# ---- coverage ----

def test_coverage_counts_only_analyzed():
    results = [
        {'status': 'analyzed', 'metrics': {'ball_speed': 17.0, 'entry_board': None}},
        {'status': 'analyzed', 'metrics': {'ball_speed': 16.0, 'entry_board': 18.0}},
        {'status': 'failed'},
    ]
    cov = coverage(results, ['ball_speed', 'entry_board'])
    assert cov['ball_speed'] == 1.0 and cov['entry_board'] == 0.5


# ---- metric accuracy + plausible-but-wrong ----

def test_metric_errors_flags_plausible_but_wrong():
    tol = {'metrics': {'ball_speed': 0.5, 'entry_board': 1.0}}
    results = [
        {'id': 'a', 'metrics': {'ball_speed': 17.0, 'entry_board': 18.0}, 'gt_metrics': {'ball_speed': 17.1, 'entry_board': 18.2}},
        {'id': 'b', 'metrics': {'ball_speed': 15.0, 'entry_board': 25.0}, 'gt_metrics': {'ball_speed': 17.0, 'entry_board': 18.0}},
    ]
    agg, wrong = metric_errors(results, tol)
    # shot b: speed off 2.0 (>0.5) and entry off 7.0 (>1.0) -> two plausible-but-wrong; shot a within tol
    assert {w['clip'] for w in wrong} == {'b'} and len(wrong) == 2
    assert agg['ball_speed']['n'] == 2 and agg['entry_board']['n'] == 2


def test_metric_errors_skips_missing_truth():
    tol = {'metrics': {'ball_speed': 0.5}}
    agg, wrong = metric_errors([{'id': 'a', 'metrics': {'ball_speed': 17.0}, 'gt_metrics': {}}], tol)
    assert wrong == [] and agg == {}


def test_gt_metrics_from_ruby_reference(tmp_path):
    from ops.cv_eval import _gt_metrics_from_labels
    ruby = tmp_path / "r.json"
    import json as _j
    ruby.write_text(_j.dumps({"vendor": "ruby", "speed_mph": 16.9, "rev_rate_rpm": 411, "loft_ft": 2.5}))
    gt = _gt_metrics_from_labels(None, {"file": "r.json"}, base_dir=str(tmp_path))
    assert gt == {"ball_speed": 16.9, "rev_rate": 411, "loft": 2.5}


def test_gt_metrics_inline_manual_speed():
    from ops.cv_eval import _gt_metrics_from_labels
    gt = _gt_metrics_from_labels(None, {"speed_foul_to_pins_mph": 15.5}, base_dir=None)
    assert gt == {"ball_speed": 15.5}


def test_secs_after_noon():
    from ops.cv_eval import secs_after_noon
    assert secs_after_noon("12:30:39") == 30 * 60 + 39      # noon-relative
    assert secs_after_noon("1:00:21") == 3600 + 21


def test_match_ruby_session_greedy_nearest_no_force():
    from ops.cv_eval import match_ruby_session
    # two clips created at 100s and 200s; three ruby shots. offset 30, window 70.
    rshots = [{'t': 135, 'mph': 16.1}, {'t': 235, 'mph': 17.3}, {'t': 900, 'mph': 15.0}]
    created = {'A': 100, 'B': 200}
    m = match_ruby_session(created, rshots, window=70, offset=30)
    assert m['A']['mph'] == 16.1 and m['B']['mph'] == 17.3     # each nearest its +30 window
    # a clip with no ruby shot in its window is left unmatched (never forced)
    assert match_ruby_session({'C': 500}, rshots, window=70, offset=30) == {}


def test_match_ruby_session_no_double_use():
    from ops.cv_eval import match_ruby_session
    rshots = [{'t': 135, 'mph': 16.1}]       # a single ruby shot, two nearby clips
    m = match_ruby_session({'A': 100, 'B': 104}, rshots, window=70, offset=30)
    assert len(m) == 1 and 'A' in m          # greedy earliest-clip-first claims the shot; B left unmatched


def test_thin_camera_classes():
    manifest = [{'camera_class': 'rear-centered'}] * 7 + [{'camera_class': 'glasses'}] * 2
    thin = thin_camera_classes(manifest, min_per_class=6)
    assert thin == {'glasses': 2}


# ---- ball-label pure core ----

def test_sample_times_grid():
    ts = bl.sample_times(16.5, 17.0, 0.1)
    assert ts[0] == 16.5 and ts[-1] == 17.0 and len(ts) == 6
    assert bl.sample_times(5.0, 4.0, 0.1) == []


def test_upsert_occluded_never_stores_a_position():
    L = bl.empty_labels('IMG_X.MOV', 60.0)
    bl.upsert_ball(L, 17.1, center=(412, 1300), contact=(412, 1316))
    bl.upsert_ball(L, 17.2, occluded=True)
    assert bl.find_ball(L, 17.1)['center'] == [412, 1300]
    occ = bl.find_ball(L, 17.2)
    assert occ['occluded'] is True and occ['center'] is None and occ['contact'] is None
    assert bl.observed_count(L) == 1          # the occluded frame is not an observation


def test_upsert_replaces_and_sorts():
    L = bl.empty_labels('IMG_X.MOV', 60.0)
    bl.upsert_ball(L, 17.2, center=(1, 1))
    bl.upsert_ball(L, 17.1, center=(2, 2))
    bl.upsert_ball(L, 17.2, center=(9, 9))        # replace, not duplicate
    assert [b['t'] for b in L['balls']] == [17.1, 17.2]
    assert bl.find_ball(L, 17.2)['center'] == [9, 9]


def test_clear_ball():
    L = bl.empty_labels('IMG_X.MOV', 60.0)
    bl.upsert_ball(L, 17.1, center=(1, 1))
    bl.clear_ball(L, 17.1)
    assert bl.find_ball(L, 17.1) is None


def test_clear_before_wipes_pre_shot_frames():
    # The reported workflow bug: dozens of pre-shot frames marked occluded. clear_before drops them in one go.
    L = bl.empty_labels('IMG_X.MOV', 60.0)
    for t in (2.0, 5.0, 10.0, 16.9):
        bl.upsert_ball(L, t, occluded=True)        # junk pre-shot frames
    bl.upsert_ball(L, 17.1, center=(412, 1300))    # the real roll starts here
    bl.upsert_ball(L, 17.2, center=(410, 1280))
    removed = bl.clear_before(L, 17.0)
    assert removed == 4
    assert [b['t'] for b in L['balls']] == [17.1, 17.2]


def test_label_roundtrip(tmp_path):
    L = bl.empty_labels('IMG_X.MOV', 60.0)
    bl.upsert_ball(L, 17.1, center=(412, 1300), contact=(412, 1316))
    bl.save(str(tmp_path), 'IMG_X', L)
    back = bl.load(str(tmp_path), 'IMG_X')
    assert back['clip'] == 'IMG_X.MOV' and back['balls'][0]['center'] == [412, 1300]
    assert bl.load(str(tmp_path), 'MISSING') is None
