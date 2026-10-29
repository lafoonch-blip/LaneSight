import numpy as np
import pytest
from lanesight_core.cv.pipeline import far_lane_quality, _unsupported_view_record, _METRIC_CATALOG, ball_speed_plausible, speed_withhold_reasons
from lanesight_core.cv.lanes import classify_capture_view, _vp_solve
from lanesight_core.failures import AnalysisFailure


# ---- capture-view gate (side-view-misroute handoff / DEC-061) ----
# A rear/down-lane view puts the lane band in the lower frame; a side/approach view (IMG_8905) compresses it
# into a thin band high in the frame. Values below are the measured lane y_rng on real clips (frame h=1920).

def test_view_gate_refuses_side_view():
    v = classify_capture_view({'y_rng': (213.0, 381.0)}, (694, 503), (1920, 1080, 3))   # IMG_8905 side
    assert v['view'] == 'side' and v['supported'] is False and 'down-lane' in v['reason'].lower()
    assert v['lane_center_frac'] < 0.4


def test_view_gate_passes_rear_and_elevated_views():
    rear = classify_capture_view({'y_rng': (1491.0, 1753.0)}, (371, 992), (1920, 1080, 3))   # IMG_8753 rear
    assert rear['view'] == 'rear' and rear['supported'] is True
    elevated = classify_capture_view({'y_rng': (864.0, 998.0)}, (140, 250), (1920, 1080, 3))  # cohort 8907 ~0.49
    assert elevated['supported'] is True            # elevated ball-return rear is still supported


def test_view_gate_unknown_when_no_lane():
    v = classify_capture_view({'y_rng': None}, (0, 0), (1920, 1080, 3))
    assert v['view'] == 'unknown' and v['supported'] is False


def test_unsupported_view_record_is_all_unavailable_no_reliable_data():
    S = dict(ts=np.arange(0, 1.0, 1 / 60.0), shift=np.array([0.0, 1.5]), ref=0,
             bg=np.zeros((1920, 1080, 3), np.uint8))
    vinfo = dict(view='side', supported=False, reason='No down-lane view. Set the camera behind the lane.',
                 lane_center_frac=0.16)
    rec = _unsupported_view_record('IMG_8905.MOV', S, vinfo, {'shot_id': 'x'}, '/tmp/x', 'R')
    d = rec.to_dict()
    assert len(d['measurements']) == len(_METRIC_CATALOG)
    assert all(mm['status'] == 'unavailable' and mm['value'] is None for mm in d['measurements'])
    assert d['insights']['state'] == 'no_reliable_data' and d['insights']['recommendations'][0]['move_feet'] == 0
    assert d['capture_quality']['view'] == 'side' and d['capture_quality']['supported'] is False
    assert d['video']['fps'] == 60.0                # fps from the probe, never a constant



def test_speed_speedup_flags_far_lane():
    # A ball can't speed up down the lane -> far lane limited (SHOT_REVIEW 14b234c8: 15.8 -> 19.4).
    limited, reason = far_lane_quality(dict(speed_early_mph=15.8, speed_late_mph=19.4), [])
    assert limited and reason and 'camera' in reason.lower()


def test_plausible_slowdown_is_ok():
    # A real ball loses speed -> not flagged.
    limited, _ = far_lane_quality(dict(speed_early_mph=18.7, speed_late_mph=17.1), [])
    assert not limited


def test_noise_band_tolerated():
    limited, _ = far_lane_quality(dict(speed_early_mph=16.0, speed_late_mph=16.4), [])
    assert not limited


def test_off_lane_entry_flags_geometry():
    # A board is 1..39; an entry board of 45 means the lane homography is broken (awkward framing).
    limited, reason = far_lane_quality(dict(entry_board=45.6, speed_early_mph=22.0, speed_late_mph=22.0), [])
    assert limited and 'off the lane' in reason.lower()
    # on-lane entry with plausible speeds is fine
    assert not far_lane_quality(dict(entry_board=17.5, speed_early_mph=17.0, speed_late_mph=15.8), [])[0]


def test_lateral_jump_flags_far_lane():
    # A >3-board jump between neighbouring samples downlane -> far lane limited.
    zb = [(30.0, 10.0), (42.5, 14.8), (44.0, 2.0)]
    limited, reason = far_lane_quality(dict(speed_early_mph=15.0, speed_late_mph=14.0), zb)
    assert limited and 'jump' in reason.lower()


def test_missing_speeds_and_smooth_path_ok():
    # Dense per-frame samples (as the pipeline passes): a real hook moves <1 board between neighbours.
    zb = [(z / 2.0, 20.0 - 0.1 * z) for z in range(0, 112)]
    limited, _ = far_lane_quality(dict(), zb)
    assert not limited


# ---- headline ball-speed honesty gate (IMG_8929 pre-fix reported 6.1 mph as `ok`) ----

def test_ball_speed_plausible_accepts_real_shots():
    # Real 60 ft foul->pins averages (validation clips) sit in ~12-22 mph.
    for v in (12.0, 15.5, 17.4, 22.0):
        ok, reason = ball_speed_plausible(v)
        assert ok and reason is None


def test_ball_speed_gate_rejects_too_slow():
    # IMG_8929 off the wrong window produced 6.1 mph "ok" — must now be rejected with a timing reason.
    ok, reason = ball_speed_plausible(6.1)
    assert not ok and 'timing' in reason.lower()


def test_ball_speed_gate_rejects_negative_and_nonfinite():
    for v in (-12.6, 0.0, float('nan'), float('inf'), None):
        ok, reason = ball_speed_plausible(v)
        assert not ok and reason


def test_ball_speed_gate_rejects_too_fast():
    # Back-half loss stretches the scale -> >30 mph. Keeps the original "lost in the back half" reason.
    ok, reason = ball_speed_plausible(41.0)
    assert not ok and 'back half' in reason.lower()


def test_ball_speed_gate_boundaries():
    assert ball_speed_plausible(8.0)[0] and ball_speed_plausible(30.0)[0]      # inclusive band
    assert not ball_speed_plausible(7.9)[0] and not ball_speed_plausible(30.1)[0]


# ---- vanishing-point solve guard (IMG_8930 LinAlgError: SVD did not converge) ----

def test_vp_solve_raises_coded_failure_on_nonfinite():
    A = np.array([[1.0, -np.nan], [1.0, -0.2]]); b = np.array([10.0, 20.0]); wt = np.array([1.0, 1.0])
    with pytest.raises(AnalysisFailure) as ei:
        _vp_solve(A, b, wt)
    assert ei.value.code == 'LANE_GEOMETRY_UNUSABLE'


def test_vp_solve_returns_finite_on_good_system():
    # Two clean edge lines x = a*y + b intersect at a finite VP.
    A = np.array([[1.0, -0.10], [1.0, -0.20]]); b = np.array([100.0, 50.0]); wt = np.array([1.0, 1.0])
    vp = _vp_solve(A, b, wt)
    assert vp.shape == (2,) and np.all(np.isfinite(vp))


# ---- DEC-092 precheck three-way verdict: never reject on doubt (HDR / NO_EDGES / foul / low angle) ----

def test_precheck_never_confidently_rejects_hdr():
    from lanesight_core.cv.precheck import _confident_reject
    from lanesight_core.failures import AnalysisFailure
    e = AnalysisFailure('LANE_NOT_DETECTED_NO_WOOD', 'no wood', stage='lane', diagnostics={'pct_pixels_matched': 0.1})
    # same failure that would reject on SDR must be inconclusive on an HLG/PQ clip
    assert _confident_reject(e, 'arib-std-b67') == (False, 'hdr')
    assert _confident_reject(e, 'smpte2084') == (False, 'hdr')


def test_precheck_confident_reject_only_on_empty_lane_sdr():
    from lanesight_core.cv.precheck import _confident_reject
    from lanesight_core.failures import AnalysisFailure
    # non-HDR, essentially no lane-coloured wood anywhere -> confident reject (camera not at a lane)
    empty = AnalysisFailure('LANE_NOT_DETECTED_NO_WOOD', 'no wood', stage='lane', diagnostics={'pct_pixels_matched': 0.2})
    assert _confident_reject(empty, 'bt709')[0] is True
    # some wood but under the strict floor -> uncertain (could be pale/HDR-residual) -> inconclusive
    some = AnalysisFailure('LANE_NOT_DETECTED_NO_WOOD', 'no wood', stage='lane', diagnostics={'pct_pixels_matched': 6.0})
    assert _confident_reject(some, 'bt709')[0] is False


def test_precheck_early_misses_are_inconclusive_but_foul_line_rejects():
    from lanesight_core.cv.precheck import _confident_reject
    from lanesight_core.failures import AnalysisFailure
    # early-stage misses the coarse plate can get wrong where the full background succeeds -> inconclusive
    for code in ('LANE_NOT_DETECTED_NO_EDGES', 'LANE_GEOMETRY_UNUSABLE'):
        e = AnalysisFailure(code, 'x', stage='lane')
        assert _confident_reject(e, 'bt709')[0] is False
    # FOUL_LINE_NOT_IN_VIEW is a LATE verdict (lane+edges+VP found, foul line off-frame) -> confident reject
    # on a non-HDR plate (2026-10-29: warn upfront instead of a 2-min wait for the same pipeline failure).
    foul = AnalysisFailure('FOUL_LINE_NOT_IN_VIEW', 'x', stage='lane')
    assert _confident_reject(foul, 'bt709')[0] is True
    assert _confident_reject(foul, 'arib-std-b67')[0] is False   # but never from an HDR (HLG) plate


def test_speed_withhold_reasons_catches_the_real_over_reads():
    """2026-10-29 soft gate: withhold a speed that passed the 8-30 hard band but is internally inconsistent.
    Replicates the three field over-reads (IMG_8815, IMG_8819, the 26.25 mph clip) + a good control."""
    # good control (IMG_8752): decelerates slightly, breakpoint mid-lane -> consistent, no reasons
    assert speed_withhold_reasons(18.197, 16.951, 36.492) == []
    # IMG_8819: back-half (21.99) FASTER than release (17.08) -> impossible
    assert any('only decelerates' in r for r in speed_withhold_reasons(17.079, 21.99, 43.25))
    # IMG_8815: release(21) vs late(14.67) diverge 6.3 mph AND breakpoint 15.2 ft out of range
    r8815 = speed_withhold_reasons(20.998, 14.668, 15.237)
    assert any('diverge' in x for x in r8815) and any('breakpoint' in x for x in r8815)
    # 26.25 mph clip: breakpoint 15.2 ft out of range (depth scale compressed)
    assert any('breakpoint' in x for x in speed_withhold_reasons(29.648, 25.461, 15.171))
    # missing segment speeds -> can't judge divergence (no crash, no false withhold on that axis)
    assert speed_withhold_reasons(None, None, 40.0) == []
