"""Smoke tests for cv.metrics.compute(). This path had no unit test, which let an
array-truthiness crash ('seg(...) or seg(...)') ship and break every normal shot.
A straight shot is built by round-tripping desired (X in, Z ft) lane coordinates back
to pixels through the real lane homography, so the geometry is self-consistent."""
import numpy as np
import pytest
from numpy.linalg import inv
from lanesight_core.cv.metrics import compute, lane_homography, LANE_IN


def _straight_shot(n_ft=56, fps=60, ft_per_s=25.0):
    # perspective lane: edges converge upward to a VP above the frame; foul near the bottom
    lane = dict(left=np.array([-0.07, 192.0]), right=np.array([0.07, 208.0]),
                foul=np.array([0.0, 590.0]), res=(1.0, 1.0), y_rng=(20.0, 585.0),
                vp_miss=(0.0, 0.0), track=np.empty((0, 3)))
    vp = np.array([200.0, -150.0])
    pi = np.array([200.0, 40.0])                       # impact anchor near the pins
    Hi = inv(lane_homography(lane, vp, pi))

    def px(x_in, z_ft):
        p = Hi @ np.array([x_in, z_ft, 1.0]); return p[:2] / p[2]

    track = []
    for i, z in enumerate(np.arange(0.5, float(n_ft), 1.0)):
        x, y = px(LANE_IN / 2, float(z))               # straight down the middle
        track.append(dict(i=i, t=0.5 + z / ft_per_s, cx=float(x), ct=float(y),
                          D=40.0, u=1.0 / max(y - vp[1], 1), frac=0.5))
    return track, lane, vp


def test_compute_returns_speed_for_a_normal_track():
    track, lane, vp = _straight_shot()
    M = compute(track, lane, vp, track[-1]['t'] + 0.05, anchor_track=track)
    assert 12 < M['ball_speed_mph'] < 24          # a thrown ball, no crash on the early-segment fit
    assert M['n_pts'] > 20
    assert M['speed_early_mph'] is not None


def test_compute_raises_cleanly_on_a_sparse_track():
    track, lane, vp = _straight_shot()
    with pytest.raises(RuntimeError, match='not tracked enough'):
        compute(track[:3], lane, vp, track[3]['t'], anchor_track=track[:3])
