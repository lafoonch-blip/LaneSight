"""Form P1 contract, capture-view classifier, advisory spot check (DEC-047/045), owner reset (DEC-051)."""
import pytest
from lanesight_core.form import FORM_P1, analyze_form_clip, classify_view, spot_check
from lanesight_core.form import pose
from lanesight_core.owner import reset_plan, RESET_CLEAR_ORDER


# ---------------------------------------------------------------- Form P1 contract (honest unavailable)
def test_form_metrics_unavailable_without_pose_backend():
    r = analyze_form_clip('clip.mov', view='bowler_facing')
    assert r['status'] == 'unavailable' and r['view'] == 'bowler_facing'
    assert {k for k, _ in FORM_P1} == set(r['metrics'])
    for mm in r['measurements']:
        assert mm['value'] is None and mm['status'] == 'unavailable' and mm['note']   # reason given, no guess

def test_form_uses_pose_backend_when_supplied():
    def backend(video, out_prefix, handed):
        return {'swing_time': {'metric': 'swing_time', 'value': 0.46, 'unit': 's',
                               'status': 'best_effort', 'confidence': 0.6}}
    r = analyze_form_clip('clip.mov', pose_backend=backend)
    assert r['status'] == 'ok'
    assert r['metrics']['swing_time']['value'] == 0.46
    assert r['metrics']['step_count']['status'] == 'unavailable'   # not returned by backend -> unavailable


# ---------------------------------------------------------------- Pose backend (pure helpers; no MediaPipe)
def test_pose_model_checksum_guard():
    with pytest.raises(pose.PoseBackendError):
        pose.verify_model('/nonexistent/pose_model.task')          # missing -> clear error
    with pytest.raises(pose.PoseBackendError):
        pose.verify_model(__file__)                                # wrong checksum -> refuse to run

def test_pose_detect_slowmo():
    # normal 60 fps cadence: not slo-mo
    assert pose.detect_slowmo([0.37, 0.40, 0.58], 1.47) == (False, 1, '')
    # ~4x-stretched cadence: slo-mo, factor snapped to 4
    is_slow, factor, note = pose.detect_slowmo([1.5, 1.6, 2.5], 5.9)
    assert is_slow and factor == 4 and 'slo-mo' in note.lower()

def test_pose_backend_is_a_callable_factory():
    be = pose.build_backend(log=lambda *a: None)
    assert callable(be)                                            # drops into analyze_form_clip(pose_backend=be)


def test_classify_view():
    assert classify_view({'lane_detected': True, 'ball_track_len': 30})['view'] == 'down_lane'
    v = classify_view({'lane_detected': False, 'foreground_motion_px': 400, 'face_toward_camera': True})
    assert v['view'] == 'bowler_facing'
    assert classify_view({'lane_detected': False, 'foreground_motion_px': 10})['view'] == 'unknown'


# ---------------------------------------------------------------- Spot check (never blocks)
def test_spot_check_never_blocks_and_tips():
    assert spot_check({'lane_visible_fraction': 0.6, 'foul_line_visible': True, 'foul_line_y_frac': 0.5}) \
        == {'blocks': False, 'tips': [], 'status': 'looks_good', 'version': 'spotcheck-0.1.0'}
    far = spot_check({'lane_visible_fraction': 0.2, 'foul_line_visible': True, 'foul_line_y_frac': 0.5})
    assert far['blocks'] is False and any('Move back' in t for t in far['tips'])
    low = spot_check({'lane_visible_fraction': 0.6, 'foul_line_visible': False})
    assert low['blocks'] is False and any('foul line' in t for t in low['tips'])
    edge = spot_check({'lane_visible_fraction': 0.6, 'foul_line_visible': True, 'foul_line_y_frac': 0.95})
    assert any('Raise the phone' in t for t in edge['tips'])


# ---------------------------------------------------------------- Owner reset (DEC-051)
def test_reset_plan_archives_then_clears_fk_safe():
    p = reset_plan(['u1', 'u2'])
    assert p['archive'] == p['clear_order'] == RESET_CLEAR_ORDER
    # tier_event (child) cleared before score_snapshot (parent via snapshot_id FK)
    assert p['clear_order'].index('tier_event') < p['clear_order'].index('score_snapshot')
    assert 'achievement_definition' in p['keep'] and 'score_formula_version' in p['keep']
    assert reset_plan([])['clear_order'] == []


def test_classify_view_from_pose_side_vs_rear():
    # MVP-03: pure-function view classifier (no mediapipe). Side = horizontal travel -> down_lane;
    # rear = vertical travel (up-frame toward pins) -> rear; barely moving -> unknown.
    import numpy as np
    from lanesight_core.form.pose import classify_view_from_pose, L_SHOULDER, R_SHOULDER, L_HIP, R_HIP

    def track(dx, dy, n=40):
        lms = np.zeros((n, 33, 5), np.float32)
        lms[:, :, 3] = 1.0
        xs = np.linspace(0.2, 0.2 + dx, n)
        ys = np.linspace(0.5, 0.5 + dy, n)
        for idx in (L_HIP, R_HIP, L_SHOULDER, R_SHOULDER):
            lms[:, idx, 0] = xs
            lms[:, idx, 1] = ys
        lms[:, L_SHOULDER, 1] -= 0.2      # shoulders above hips so torso height > 0
        lms[:, R_SHOULDER, 1] -= 0.2
        return np.linspace(0, 2, n), lms

    t, side = track(0.6, 0.08)
    assert classify_view_from_pose(t, side)['view'] == 'down_lane'
    t, rear = track(0.3, 0.5)
    assert classify_view_from_pose(t, rear)['view'] == 'rear'
    t, still = track(0.02, 0.02)
    assert classify_view_from_pose(t, still)['view'] == 'unknown'


def test_key_frame_poses_overlay_is_cropnormalized_and_confident_only():
    """Display-only skeleton joints: re-normalized to the crop, low-confidence / NaN / out-of-crop → None."""
    import numpy as np
    lms = np.full((1, 33, 5), 0.5, np.float32)   # all joints centered, placeholder vis
    lms[:, :, 3] = 0.9                            # visibility high by default
    lms[0, 0, 3] = 0.5                            # joint 0: low confidence -> None
    lms[0, 1, 0] = np.nan                         # joint 1: undetected -> None
    lms[0, 2, 0:2] = 0.95                         # joint 2: outside the 0.2..0.8 crop -> None
    t = np.array([1.0], np.float32)
    events = {'E2': 1.0}
    crops = {'ball_start': (0.2, 0.2, 0.8, 0.8)}
    out = pose.key_frame_poses(lms, t, events, crops)
    assert 'ball_start' in out
    j = out['ball_start']
    assert len(j) == 33
    assert j[0] is None and j[1] is None and j[2] is None
    # a centered joint maps to the crop centre (0.5 -> (0.5-0.2)/0.6 = 0.5)
    assert j[5] == [0.5, 0.5]
    assert sum(1 for p in j if p) >= 6


# --- event sanity gates (form shot c9df6ca0: events landed ~1s late) -------------------------

def test_gate_events_all_plausible_pass():
    # a normal delivery: ball start 1.8s before release, release at the slide stop, in order
    ev = dict(E2=10.0, E3=10.3, E4=11.2, E6=11.75, E7=11.8, E8=11.75)
    ok, reasons = pose.gate_events(ev)
    assert ok == {'E2', 'E3', 'E4', 'E6', 'E7'} and reasons == {}


def test_gate_events_release_not_at_slide_stop_drops_all():
    # the real c9df6ca0 numbers: release 0.57s BEFORE the slide stop -> whole delivery untrusted
    ev = dict(E2=17.418, E3=17.5, E4=18.1, E6=18.49, E7=18.503, E8=19.072)
    ok, reasons = pose.gate_events(ev)
    assert ok == set()                       # nothing survives
    assert 'E7' in reasons and 'slide stop' in reasons['E7']


def test_gate_events_short_ball_start_to_release_drops_start():
    # release sits at the slide stop, but ball start -> release is only 1.0s (too short)
    ev = dict(E2=11.0, E3=11.1, E4=11.6, E6=11.95, E7=12.0, E8=11.95)
    ok, reasons = pose.gate_events(ev)
    assert 'E2' in reasons and 'E3' in reasons and 'E2' not in ok
    assert 'E4' in ok and 'E7' in ok         # the trusted back-half events survive


def test_gate_events_out_of_order_drops_offender():
    ev = dict(E2=10.0, E3=10.3, E4=9.9, E6=11.75, E7=11.8, E8=11.75)   # E4 before E3
    ok, reasons = pose.gate_events(ev)
    assert 'E4' in reasons and 'E4' not in ok


def test_gate_events_missing_slide_stop_is_lenient():
    # no E8 -> can't anchor release; keep ordering + duration checks only, never crash
    ev = dict(E2=10.0, E3=10.3, E4=11.2, E6=11.75, E7=11.8, E8=None)
    ok, reasons = pose.gate_events(ev)
    assert 'E7' in ok
