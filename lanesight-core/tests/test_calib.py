"""Phase-1 geometry-harness tests (DEC-062). All synthetic/self-consistent — no real-clip pixel values are
fabricated. Exercises: canonical geometry + provenance, landmark schema round-trip, homography solve on a
known scene, and the B/C reconstruction core on a straight synthetic shot."""
import json
import numpy as np
import pytest
from numpy.linalg import inv

from lanesight_core.cv.metrics import lane_homography, LANE_IN
from lanesight_core.cv.calib.lane_geometry import (
    CANONICAL, LaneGeometry, x_in_for_board, board_from_left, Z_IMPACT_FT)
from lanesight_core.cv.calib.landmarks import LandmarkSet, LandmarkObservation
from lanesight_core.cv.calib.solve import homography_from_landmarks, CalibrationError
from lanesight_core.cv.calib.ablation import reconstruct_from_homography


# ---------------------------------------------------------------- geometry

def test_geometry_constants_and_conventions():
    assert CANONICAL.boards == 39
    assert CANONICAL.lane_width_in == pytest.approx(41.5)
    assert Z_IMPACT_FT == pytest.approx(59.44, abs=0.01)
    # board<->X inverse round-trip
    for b in (1.0, 5.5, 20.0, 39.5):
        assert board_from_left(x_in_for_board(b)) == pytest.approx(b)
    # foul corners known exactly; center is board 20
    assert CANONICAL.world_point("foul_l") == (0.0, 0.0)
    assert CANONICAL.world_point("foul_r") == (pytest.approx(41.5), 0.0)
    assert board_from_left(41.5 / 2) == pytest.approx(20.0)


def test_provenance_no_uncited_or_fabricated_values():
    """Handoff §4 / CLAUDE.md: spec constants must be cited; unknown coords are tbd+None, never invented."""
    for name, lm in CANONICAL.landmarks.items():
        if lm.source == "spec":
            assert lm.citation, f"{name} is 'spec' but has no citation"
        if lm.source == "tbd":
            # a tbd landmark must NOT carry a fabricated world coordinate
            assert lm.z_ft is None or lm.x_in is None, f"{name} is tbd but has a full coordinate"
    # arrows: X known, Z staggered-but-not-yet-filled (must not be a single Z=15 placeholder)
    for b in (5, 10, 15, 20, 25, 30, 35):
        lm = CANONICAL.landmarks[f"arrow_{b}"]
        assert lm.x_in is not None and lm.z_ft is None and lm.source == "tbd"
    # pin spots are known (12-in centers); head pin centered at 60 ft
    p1 = CANONICAL.world_point("pin_1")
    assert p1 == (pytest.approx(41.5 / 2), pytest.approx(60.0))
    assert len([n for n in CANONICAL.landmarks if n.startswith("pin_")]) == 10


# ---------------------------------------------------------------- landmarks

def test_landmark_template_roundtrip_and_correspondences():
    ls = LandmarkSet.template("IMG_TEST", (1080, 1920))
    assert ls.labeled_count() == 0
    assert "foul_l" in ls.observations and "arrow_20" in ls.observations
    # label a few; only labeled AND world-known landmarks become correspondences
    ls.set_point("foul_l", 300, 1500).set_point("foul_r", 780, 1500)
    ls.set_point("pin_1", 540, 300)
    ls.set_point("arrow_20", 540, 1100)          # labeled but world Z is tbd -> excluded
    names, world, image = ls.correspondences()
    assert set(names) == {"foul_l", "foul_r", "pin_1"}
    assert "arrow_20" not in names
    assert world.shape == (3, 2) and image.shape == (3, 2)
    # JSON round-trip preserves points
    rt = LandmarkSet.from_json(ls.to_json())
    assert rt.observations["foul_l"].x == 300 and rt.observations["pin_1"].y == 300
    assert rt.labeled_count() == 4


# ------------------------------------------------- synthetic known scene

def _true_homographies():
    """A self-consistent perspective lane (same technique as test_metrics): returns (H_img_to_world,
    H_world_to_img) in the canonical (X in, Z ft) frame."""
    lane = dict(left=np.array([-0.07, 192.0]), right=np.array([0.07, 208.0]),
                foul=np.array([0.0, 590.0]), res=(1.0, 1.0), y_rng=(20.0, 585.0),
                vp_miss=(0.0, 0.0), track=np.empty((0, 3)))
    vp = np.array([200.0, -150.0])
    pi = np.array([200.0, 40.0])
    H_iw = lane_homography(lane, vp, pi)          # image -> world (X in, Z ft)
    return H_iw, inv(H_iw)


def _project(H_wi, x_in, z_ft):
    p = H_wi @ np.array([x_in, z_ft, 1.0])
    return p[:2] / p[2]


def test_solver_recovers_known_homography():
    H_iw_true, H_wi_true = _true_homographies()
    ls = LandmarkSet.template("SYNTH", (400, 600))
    # label the known landmarks by projecting their true world coords into the image
    for name in ("foul_l", "foul_r", "pin_1", "pin_7", "pin_10"):
        w = CANONICAL.world_point(name)
        x, y = _project(H_wi_true, w[0], w[1])
        ls.set_point(name, float(x), float(y))
    H_iw, H_wi, diag = homography_from_landmarks(ls)
    # recovered mapping reproduces the known world coords essentially exactly
    assert diag["reproj_board_rmse"] < 0.05
    assert diag["reproj_ft_rmse"] < 0.05
    assert diag["longitudinal_spread_ft"] > 55           # foul (0) to pins (~60)
    assert diag["n_correspondences"] == 5
    # sensitivity: a 1-px wobble hurts the far region more than the near region (depth compression)
    s = diag["sensitivity_per_px"]
    assert s["entry_59ft"]["d_board_per_px"] >= s["foul_0ft"]["d_board_per_px"]
    assert all(np.isfinite(v["d_board_per_px"]) for v in s.values())


def test_solver_rejects_too_few_points():
    ls = LandmarkSet.template("SYNTH", (400, 600))
    ls.set_point("foul_l", 100, 500).set_point("foul_r", 300, 500)
    with pytest.raises(CalibrationError):
        homography_from_landmarks(ls)


# ------------------------------------------------- reconstruction (B/C core)

def test_reconstruct_straight_shot_down_center():
    H_iw_true, H_wi_true = _true_homographies()
    centers = []
    for k, z in enumerate(np.arange(0.5, 58.5, 1.0)):
        x, y = _project(H_wi_true, LANE_IN / 2, float(z))        # straight down board 20
        centers.append((0.5 + z / 25.0, float(x), float(y)))
    r = reconstruct_from_homography(H_iw_true, centers)
    assert r["ok"], r.get("error")
    assert r["entry_board"] == pytest.approx(20.0, abs=0.5)
    assert r["laydown_board"] == pytest.approx(20.0, abs=0.5)
    assert r["track_last_ft"] > 56


def test_reconstruct_needs_enough_centers():
    H_iw_true, _ = _true_homographies()
    r = reconstruct_from_homography(H_iw_true, [(0.0, 200.0, 500.0)] * 3)
    assert not r["ok"] and "need" in r["error"]


# ------------------------------------------------- verification-tool safeguards (Step 3)

def test_only_verified_points_calibrate():
    """Fail-closed: suggested/ambiguous/not-visible are excluded; only verified feed correspondences."""
    from lanesight_core.cv.calib.landmarks import (STATUS_SUGGESTED, STATUS_VERIFIED, STATUS_AMBIGUOUS)
    ls = LandmarkSet.template("C", (1080, 1920))
    ls.suggest("foul_l", 300, 1500, 0.9, "auto")          # suggested -> excluded
    ls.set_point("foul_r", 760, 1500)                      # verified   -> included
    ls.set_point("pin_1", 540, 300, status=STATUS_AMBIGUOUS)   # ambiguous -> excluded
    assert ls.observations["foul_l"].usable is False
    assert ls.observations["foul_r"].usable is True
    names, world, image = ls.correspondences()
    assert names == ["foul_r"]
    assert ls.verified_count() == 1 and ls.suggested_count() == 1
    # round-trip preserves status/source/confidence
    rt = LandmarkSet.from_json(ls.to_json())
    assert rt.observations["foul_l"].status == STATUS_SUGGESTED and rt.observations["foul_l"].confidence == 0.9
    assert rt.observations["foul_r"].status == STATUS_VERIFIED


def test_merge_never_clobbers_verified():
    from lanesight_core.cv.calib.label_tool import (merge_existing_and_suggestions,
                                                    view_to_image, image_to_view)
    ex = LandmarkSet.template("C", (1080, 1920)); ex.set_point("foul_l", 300, 1500)
    sg = LandmarkSet.template("C", (1080, 1920))
    sg.suggest("foul_l", 999, 999, 0.9, "auto")           # must NOT overwrite the verified foul_l
    sg.suggest("foul_r", 700, 1500, 0.9, "auto")
    m = merge_existing_and_suggestions(ex, sg)
    assert m.observations["foul_l"].x == 300 and m.observations["foul_l"].usable
    assert m.observations["foul_r"].status == "suggested"
    # coordinate transform stores ORIGINAL image pixels (round-trips exactly)
    view = dict(zoom=0.37, ox=140.0, oy=512.0)
    for ix, iy in ((0, 0), (1080, 1920), (537.5, 999.25)):
        vx, vy = image_to_view(ix, iy, view)
        rx, ry = view_to_image(vx, vy, view)
        assert abs(rx - ix) < 1e-6 and abs(ry - iy) < 1e-6


def test_resolution_scale_invariant_bounds():
    """The lateral board error is scale-invariant ≈ k·8.07 boards — the key physical result."""
    from lanesight_core.cv.calib.resolution import BOARD_ERR_CLEAN, BOARD_ERR_BLUR, SCALE_INVARIANT
    assert BOARD_ERR_CLEAN == pytest.approx(0.97, abs=0.05)
    assert BOARD_ERR_BLUR == pytest.approx(2.42, abs=0.05)
    assert BOARD_ERR_CLEAN < 1.0 < BOARD_ERR_BLUR          # ±1 board only with a clean ball
    assert SCALE_INVARIANT["board_err_clean"] == BOARD_ERR_CLEAN
