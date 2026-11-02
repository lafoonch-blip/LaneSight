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


def test_gate_events_anchors_on_slide_stop_not_posted_finish():
    """DEC-095 / Form baseline (2026-11-01): the gate anchors release to E8 = the slide-foot STOP (release
    happens as the slide foot settles). E8 is now the slide stop itself — the detector no longer passes the much
    later posted-finish start (hold_start) as E8, which created a ~0.85 s false gap that nulled EVERY real
    delivery (IMG_8824/8846). Validated on form_labels.json: release sits within ±0.05 s of the labeled slide
    stop. Same delivery, two E8 meanings:"""
    base = dict(E2=10.0, E3=10.3, E4=11.2, E6=11.75, E7=11.8)
    # E8 = the real slide stop (release sits right at it) -> all events trusted
    ok, reasons = pose.gate_events(dict(base, E8=11.75))
    assert ok == {'E2', 'E3', 'E4', 'E6', 'E7'} and reasons == {}
    # E8 = the OLD bug (posted-finish start, 0.85 s after release) -> release reads far from the "stop" -> dropped.
    # This is the shape the slide-stop detector fix removed; the gate still rejects it if it ever recurs.
    ok_bug, reasons_bug = pose.gate_events(dict(base, E8=12.6))
    assert ok_bug == set() and 'slide stop' in reasons_bug['E7']


def test_slide_stop_is_slide_foot_settling_not_both_feet_still():
    """Slide stop (E8) = the slide foot's OWN speed settling after its slide peak, searched from an anchor near
    release (the bottom of the swing arc). The trail foot is still swinging in the follow-through, so a
    both-feet-still test would land much later — _slide_stop must ignore the trail foot and must not fire on the
    slow setup before the slide."""
    import numpy as np
    fps = 60.0
    t = np.arange(0, 3.0, 1.0 / fps)
    # slide foot: slow in the setup (~0.05), one fast slide peak ~1.5s, then settles to rest (~0.03) by ~1.6s.
    slide = np.full_like(t, 0.05)
    slide[(t >= 1.3) & (t < 1.6)] = 1.0            # the slide itself
    slide[t >= 1.6] = 0.03                         # at rest at the line
    stop = pose._slide_stop(t, slide, anchor=1.55, t_to=2.5)
    assert stop is not None and abs(stop - 1.6) <= 2.0 / fps     # within ~2 frames of the true settle
    # the earlier low-speed setup (t<1.3) must not win, because it precedes the slide peak
    assert stop > 1.3
    # _slide_foot picks the foot that comes to rest; trail foot keeps moving through the window
    trail = np.full_like(t, 0.6)
    foot, spd = pose._slide_foot(t, Rs=trail, Ls=slide, t0=1.2, t1=2.5, handed='right')
    assert foot == 'L' and spd is slide


def test_setup_hold_end_anchors_step_search_at_the_first_step():
    """The step window must start where the setup stance ends (step 1 breaks the stillness), not inside the
    motion burst — else steps 1–2 can never be found (DEC-120). Synthetic: both feet still until 1.0s, then the
    approach moves; the motion-burst detector would only fire ~0.4s later, but _setup_hold_end returns ~1.0s."""
    import numpy as np
    fps = 60.0
    t = np.arange(0, 3.0, 1.0 / fps)
    both_still_until = 1.0
    Rs = np.where(t < both_still_until, 0.02, 0.6)      # stance still, then walking
    Ls = np.where(t < both_still_until, 0.02, 0.6)
    burst_start = 1.4                                   # detector fires late (after step 1)
    start = pose._setup_hold_end(t, Rs, Ls, burst_start)
    assert abs(start - both_still_until) <= 3.0 / fps and start < burst_start
    # no clear setup hold (rolling start: always moving) -> safe fallback near the burst, never crashes
    moving = np.full_like(t, 0.6)
    fb = pose._setup_hold_end(t, moving, moving, burst_start)
    assert abs(fb - (burst_start - 0.4)) <= 3.0 / fps
