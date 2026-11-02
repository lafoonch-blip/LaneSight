"""Unit tests for the event-based step detector logic (synthetic gait — no video, no model).

Covers the three behaviours the detector depends on: visibility mode selection, alternating-leg event
detection, and the hip-translation gate that rejects in-place motion (weight shifts / backswing / slide
adjustments). OFFLINE experiment module.
"""
import numpy as np
import pytest
from experiments.step_events.detector import detect_steps, L_KNEE, R_KNEE
from lanesight_core.form import pose as P

FPS = 60.0


def _tri(N, centers, amp=0.06, width=9):
    a = np.zeros(N)
    for c in centers:
        for i in range(N):
            d = abs(i - c)
            if d < width:
                a[i] += amp * (1 - d / width)
    return a


def build(N=108, hipx=None, advL_centers=(), advR_centers=(), vis_ankle=0.9, vis_knee=0.9, vis_foot=None):
    """Synthetic gait: hip translates along +x; each ankle = hip + a triangular advance at its step centers.
    Returns (t, lms[N,33,4]) with x,y,z,visibility."""
    vis_foot = vis_ankle if vis_foot is None else vis_foot
    t = np.arange(N) / FPS
    if hipx is None:
        hipx = np.linspace(0.0, 0.3, N)
    lms = np.zeros((N, 33, 4), np.float32)
    lms[:, :, 3] = 0.9
    lms[:, :, 1] = 0.5  # all y constant -> forward axis resolves to +x
    for i in (P.L_HIP, P.R_HIP):
        lms[:, i, 0] = hipx
    advL, advR = _tri(N, advL_centers), _tri(N, advR_centers)
    lms[:, P.L_ANKLE, 0] = hipx + advL; lms[:, P.L_ANKLE, 3] = vis_ankle
    lms[:, P.R_ANKLE, 0] = hipx + advR; lms[:, P.R_ANKLE, 3] = vis_ankle
    lms[:, P.L_FOOT, 3] = vis_foot; lms[:, P.R_FOOT, 3] = vis_foot
    lms[:, L_KNEE, 0] = hipx + advL; lms[:, L_KNEE, 3] = vis_knee
    lms[:, R_KNEE, 0] = hipx + advR; lms[:, R_KNEE, 3] = vis_knee
    return t, lms


def test_feet_mode_detects_alternating_advances():
    t, lms = build(advL_centers=(12, 48, 84), advR_centers=(30, 66))   # 5 alternating advances, hip translating
    r = detect_steps(t, lms, (t[0], t[-1]))
    assert r['visibility_mode'] == 'feet'
    legs = [s['leg'] for s in r['steps']]
    assert 4 <= r['step_count'] <= 6                     # ~5, without knowing the expected count
    assert all(legs[i] != legs[i + 1] for i in range(len(legs) - 1))   # strictly alternating
    assert all(s['evidence'] == 'ankle' for s in r['steps'])
    assert r['step_count'] == len(r['steps'])            # count is just len(events) — never an expected value


def test_alternation_collapses_consecutive_same_leg():
    # two L advances with no R between -> the detector must not emit L,L (keeps the stronger)
    t, lms = build(advL_centers=(12, 30, 72), advR_centers=(50,))
    r = detect_steps(t, lms, (t[0], t[-1]))
    legs = [s['leg'] for s in r['steps']]
    assert all(legs[i] != legs[i + 1] for i in range(len(legs) - 1))


def test_hip_gate_rejects_in_place_advance():
    # hip rises, holds flat, rises again. An advance DURING the flat (no hip translation since the last step) is
    # a weight shift and must be rejected; the same advances with the hip translating throughout are kept.
    N = 120
    flat = np.concatenate([np.linspace(0, 0.10, 30), np.full(40, 0.10), np.linspace(0.10, 0.20, 30), np.full(20, 0.20)])
    moving = np.linspace(0.0, 0.30, N)
    centersL, centersR = (20, 65), (50, 85)             # @65 falls in the flat region
    r_flat = detect_steps(*build(N=N, hipx=flat, advL_centers=centersL, advR_centers=centersR), window=(0, N / FPS))
    r_move = detect_steps(*build(N=N, hipx=moving, advL_centers=centersL, advR_centers=centersR), window=(0, N / FPS))
    assert r_flat['step_count'] < r_move['step_count']   # the in-place advance is dropped only when the hip is still
    # and the surviving events never include the in-place one at ~65/FPS s when hip was flat
    assert all(abs(s['t_s'] - 65 / FPS) > 0.08 for s in r_flat['steps'])


def test_knees_only_mode_when_ankles_hidden():
    t, lms = build(advL_centers=(12, 48, 84), advR_centers=(30, 66), vis_ankle=0.1, vis_foot=0.1, vis_knee=0.9)
    r = detect_steps(t, lms, (t[0], t[-1]))
    assert r['visibility_mode'] == 'knees_only'
    assert all(s['evidence'] == 'knee' for s in r['steps'])


def test_insufficient_mode_marks_unavailable():
    t, lms = build(advL_centers=(12, 48), advR_centers=(30,), vis_ankle=0.1, vis_foot=0.1, vis_knee=0.1)
    r = detect_steps(t, lms, (t[0], t[-1]))
    assert r['visibility_mode'] == 'insufficient'
    assert r['step_count'] is None and r['reason']       # unavailable with a reason, never a guessed count


def test_detector_output_shape():
    t, lms = build(advL_centers=(12, 48, 84), advR_centers=(30, 66))
    r = detect_steps(t, lms, (t[0], t[-1]))
    for s in r['steps']:
        assert set(s) >= {'frame', 't_s', 'leg', 'evidence', 'confidence'}
        assert s['leg'] in ('L', 'R') and 0.0 <= s['confidence'] <= 1.0
