"""A/B/C/D ablation (handoff §10) — does correct geometry alone make a failing clip measurable?

  A  existing auto geometry + existing auto track          -> `run_A`  (wraps cv.pipeline.analyze)
  B  MANUAL landmarks        + existing auto track          -> `run_B`  (manual H + auto ball centers)
  C  MANUAL landmarks        + MANUAL ball centers          -> `run_C`  (manual H + hand-labeled centers)
  D  new auto geometry       + new auto track               -> later (Phases 2-3; not in PR1)

B and C share one honest reconstruction from a homography + a set of image ball centers
(`reconstruct_from_homography`). Nothing here mutates the production pipeline; Runs B/C are a standalone
re-measurement so we can compare geometry fairly without touching `cv/metrics.compute`.

CLI:
  python -m lanesight_core.cv.calib.ablation A VIDEO OUTPREFIX [--handed R|L]
  python -m lanesight_core.cv.calib.ablation C LANDMARKS.json CENTERS.json   # manual geometry + manual centers
  python -m lanesight_core.cv.calib.ablation template CLIP_ID W H > clip.landmarks.json
"""
from __future__ import annotations
import json
import numpy as np

from .lane_geometry import LaneGeometry, CANONICAL, LANE_WIDTH_IN, BOARDS
from .landmarks import LandmarkSet
from .solve import homography_from_landmarks, CalibrationError


def run_A(video, out_prefix, handed=None, **kw):
    """Baseline: run the production pipeline and capture its metrics, or its error. Slow (video decode)."""
    from ..pipeline import analyze
    try:
        rec = analyze(video, out_prefix, handed=handed, **kw)
        d = rec.to_dict()
        metrics = {k: v.get("value") for k, v in d.get("metrics", {}).items()}
        return dict(run="A", ok=True, metrics=metrics,
                    capture_quality=d.get("capture_quality"), error=None)
    except Exception as e:                            # the pipeline raises RuntimeError with a user-facing reason
        return dict(run="A", ok=False, metrics={}, error=str(e))


def _board_path(X, Z, geometry: LaneGeometry):
    """board_from_left(X), LOESS-smoothed over a covered depth grid (mirrors cv.metrics, read-only)."""
    from ..smooth import loess
    board_fl = X / geometry.lane_width_in * geometry.boards + 0.5
    zz = np.arange(max(0.0, float(Z.min())), min(geometry.z_impact_ft, float(Z.max()) + 1.0) + 1e-6, 0.25)
    covered = np.array([np.min(np.abs(Z - z)) < 3.0 for z in zz])
    zz = zz[covered]
    if len(zz) < 4:
        return None
    bb, sl = loess(Z, board_fl, zz, bw=10.0)
    ok = np.isfinite(bb)
    return zz[ok], bb[ok], sl[ok], board_fl


def reconstruct_from_homography(H_img_to_world, centers_img, geometry: LaneGeometry = CANONICAL):
    """Map image ball centers through a lane-plane homography and read board(Z)/entry — the shared B/C core.

    centers_img: iterable of (t, cx, cy). Returns a dict of measured positions in ABSOLUTE boards
    (1 = right gutter, matching the app) plus the raw path, or an error reason. No speed here (that needs
    reliable timing endpoints; PR1 proves geometry/position first)."""
    C = np.asarray([[c[0], c[1], c[2]] for c in centers_img], float)
    if len(C) < 6:
        return dict(ok=False, error=f"only {len(C)} ball centers; need >= 6 to fit a path")
    t, cx, cy = C[:, 0], C[:, 1], C[:, 2]
    h = np.c_[cx, cy, np.ones(len(cx))] @ H_img_to_world.T
    X, Z = h[:, 0] / h[:, 2], h[:, 1] / h[:, 2]
    keep = (Z > -3) & (Z < geometry.z_impact_ft + 2) & np.isfinite(X) & np.isfinite(Z)
    X, Z, t = X[keep], Z[keep], t[keep]
    if len(Z) < 6:
        return dict(ok=False, error="ball centers do not map onto the lane plane (bad homography or centers)")

    path = _board_path(X, Z, geometry)
    if path is None:
        return dict(ok=False, error="insufficient depth coverage after mapping to the lane plane")
    zz, bb, sl, board_fl = path

    # handedness from the cubic end-slope (same rule as cv.metrics), then report absolute boards.
    pz = np.polyfit(Z, board_fl, 3)
    right_handed = np.polyval(np.polyder(pz), Z.max()) < 0
    to_abs = (lambda b: float(b)) if right_handed else (lambda b: float(geometry.boards + 1 - b))

    out = dict(ok=True, right_handed=bool(right_handed), n_centers=int(len(Z)),
               track_first_ft=float(Z.min()), track_last_ft=float(Z.max()))
    out["entry_board"] = to_abs(np.interp(geometry.z_impact_ft, zz, bb)) if zz.max() > 56 else None
    for zq, name in ((0, "laydown_board"), (7, "board_at_7ft"), (15, "arrows_board")):
        out[name] = to_abs(np.interp(zq, zz, bb)) if zz.min() <= zq + 1 else None
    mid = (zz > 15) & (zz < 55)
    if mid.any():
        k = int(np.where(mid)[0][np.argmin(bb[mid])])
        out["breakpoint_board"] = to_abs(bb[k])
        out["breakpoint_ft"] = float(zz[k])
    else:
        out["breakpoint_board"] = out["breakpoint_ft"] = None
    out["path"] = dict(z_ft=[round(float(z), 2) for z in zz], board=[round(to_abs(b), 2) for b in bb])
    return out


def run_B(auto_centers_img, landmark_set: LandmarkSet, geometry: LaneGeometry = CANONICAL):
    """Manual geometry + existing auto track. `auto_centers_img`: (t, cx, cy) from the production linker
    (e.g. loaded from the `*_blobs.pkl` track), so we test geometry alone against the same detections."""
    try:
        H_iw, _, diag = homography_from_landmarks(landmark_set, geometry)
    except CalibrationError as e:
        return dict(run="B", ok=False, error=str(e))
    r = reconstruct_from_homography(H_iw, auto_centers_img, geometry)
    r.update(run="B", calibration=diag)
    return r


def run_C(manual_centers_img, landmark_set: LandmarkSet, geometry: LaneGeometry = CANONICAL):
    """Manual geometry + MANUAL ball centers — the identifiability gate. If this can't hit the accuracy
    target, the limit is resolution/geometry, not ML (handoff stop/go)."""
    try:
        H_iw, _, diag = homography_from_landmarks(landmark_set, geometry)
    except CalibrationError as e:
        return dict(run="C", ok=False, error=str(e))
    r = reconstruct_from_homography(H_iw, manual_centers_img, geometry)
    r.update(run="C", calibration=diag)
    return r


def uncertainty_attribution(landmark_set, centers_img, geometry: LaneGeometry = CANONICAL,
                            sigma_px: float = 1.5, n_mc: int = 120, seed: int = 0):
    """Attribute entry-board uncertainty to its three sources (Shayne's request): landmark placement,
    calibration conditioning, and ball-center localization. Tells us where further investment belongs.

    - landmark placement: Monte-Carlo jitter the VERIFIED landmark pixels by N(0, sigma_px), re-solve the
      homography, re-read entry board -> std.
    - ball-center localization: jitter the ball centers by N(0, sigma_px) under the base calibration -> std,
      floored by the scale-invariant centroid bound (resolution.SCALE_INVARIANT).
    - calibration conditioning: the solved per-pixel sensitivity at the entry reference x sigma_px.
    Returns the three std's (boards), the dominant source, and the base entry board. Seeded (reproducible).
    """
    from .resolution import SCALE_INVARIANT
    names, world, image = landmark_set.correspondences(geometry)
    if len(names) < 4:
        return dict(ok=False, error=f"need >=4 verified anchors; have {len(names)}")
    try:
        H_iw, _, diag = homography_from_landmarks(landmark_set, geometry)
    except CalibrationError as e:
        return dict(ok=False, error=str(e))
    base = reconstruct_from_homography(H_iw, centers_img, geometry)
    if not base.get("ok") or base.get("entry_board") is None:
        return dict(ok=False, error="base reconstruction has no entry board (insufficient coverage)")
    base_entry = base["entry_board"]
    rng = np.random.default_rng(seed)

    def _solve(img_pts):
        Hwi, _ = cv2_findhom(world, img_pts)
        if Hwi is None:
            return None
        try:
            return np.linalg.inv(Hwi)
        except np.linalg.LinAlgError:
            return None

    # 1. landmark placement
    lm_entries = []
    for _ in range(n_mc):
        H = _solve(image + rng.normal(0, sigma_px, image.shape))
        if H is None:
            continue
        r = reconstruct_from_homography(H, centers_img, geometry)
        if r.get("ok") and r.get("entry_board") is not None:
            lm_entries.append(r["entry_board"])
    sigma_landmark = float(np.std(lm_entries)) if len(lm_entries) > 5 else None

    # 2. ball-center localization (under the base calibration)
    C = np.asarray([[c[0], c[1], c[2]] for c in centers_img], float)
    bc_entries = []
    for _ in range(n_mc):
        jitter = C.copy()
        jitter[:, 1:] += rng.normal(0, sigma_px, (len(C), 2))
        r = reconstruct_from_homography(H_iw, [tuple(row) for row in jitter], geometry)
        if r.get("ok") and r.get("entry_board") is not None:
            bc_entries.append(r["entry_board"])
    sigma_ball_mc = float(np.std(bc_entries)) if len(bc_entries) > 5 else None
    sigma_ball = max(sigma_ball_mc or 0.0, SCALE_INVARIANT["board_err_clean"])   # floored by the physical bound

    # 3. calibration conditioning (per-pixel sensitivity at entry x sigma_px)
    s_entry = diag["sensitivity_per_px"]["entry_59ft"]["d_board_per_px"]
    sigma_calib = float(s_entry * sigma_px)

    contribs = {"landmark_placement": sigma_landmark, "ball_center": sigma_ball,
                "calibration_conditioning": sigma_calib}
    ranked = sorted(((k, v) for k, v in contribs.items() if v is not None), key=lambda kv: -kv[1])
    return dict(ok=True, base_entry_board=round(base_entry, 2), sigma_px=sigma_px, n_mc=n_mc,
                sigma_boards={k: (round(v, 3) if v is not None else None) for k, v in contribs.items()},
                dominant=ranked[0][0] if ranked else None,
                note="ball_center is floored by the scale-invariant centroid bound; "
                     "if it dominates, the limit is resolution/capture, not labeling or calibration.")


def cv2_findhom(world, image):
    """world->image homography (threshold-in-pixels); plain LS for small clean sets. Returns (H_wi, mask)."""
    import cv2
    method = 0 if len(world) <= 8 else getattr(cv2, "USAC_MAGSAC", cv2.RANSAC)
    return cv2.findHomography(np.asarray(world, float), np.asarray(image, float), method, 3.0)


def _load_centers(path):
    """Centers JSON: [[t, cx, cy], ...] or {"centers": [...]}."""
    with open(path) as fh:
        d = json.load(fh)
    return d["centers"] if isinstance(d, dict) else d


if __name__ == "__main__":
    import sys
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "template":
        _, _, clip_id, w, h = sys.argv[:5]
        print(LandmarkSet.template(clip_id, (int(w), int(h))).to_json())
    elif cmd == "plate":
        # Dump the stabilized background plate (the EXACT image to label on) + an unlabeled template beside it.
        #   python -m lanesight_core.cv.calib.ablation plate STAB.pkl OUTDIR CLIP_ID
        import os, pickle, cv2
        stab_path, outdir, clip_id = sys.argv[2], sys.argv[3], sys.argv[4]
        os.makedirs(outdir, exist_ok=True)
        bg = pickle.load(open(stab_path, "rb"))["bg"]
        h, w = bg.shape[:2]
        png = os.path.join(outdir, f"{clip_id}.plate.png")
        tpl = os.path.join(outdir, f"{clip_id}.landmarks.json")
        cv2.imwrite(png, bg)
        LandmarkSet.template(clip_id, (w, h)).to_json(tpl)
        print(f"wrote {png} ({w}x{h}) and {tpl}")
    elif cmd == "A":
        video, out = sys.argv[2], sys.argv[3]
        handed = sys.argv[sys.argv.index("--handed") + 1] if "--handed" in sys.argv else None
        print(json.dumps(run_A(video, out, handed=handed), indent=1))
    elif cmd == "C":
        ls = LandmarkSet.from_json(sys.argv[2])
        print(json.dumps(run_C(_load_centers(sys.argv[3]), ls), indent=1))
    else:
        print(__doc__)
