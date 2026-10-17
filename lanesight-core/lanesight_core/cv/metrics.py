"""Stage 4: lane-plane homography (foul line + impact reference) and shot metrics."""
import numpy as np, cv2
from .lanes import lane_x, foul_corners
from .track import contact_row

LANE_IN, BOARDS, Z_IMPACT = 41.5, 39, 59.44      # ball centre at first headpin contact: 60 ft - (4.30+2.38)/12

def _edge_point_on_line(edge, p, q):
    """intersection of edge x=a*y+b with line through image points p,q"""
    a, b = edge; (x1, y1), (x2, y2) = p, q
    # param y: x = a*y + b ; line: (x-x1)*(y2-y1) - (y-y1)*(x2-x1) = 0
    A = a * (y2 - y1) - (x2 - x1); B = (b - x1) * (y2 - y1) + y1 * (x2 - x1)
    y = -B / A; return np.array([a * y + b, y])

def lane_homography(lane, vp, impact_px):
    """image -> lane plane (X inches from LEFT edge, Z feet from foul line).
    Far cross-line: through the ball contact point at impact, parallel (in 3D) to the foul line;
    its image passes through the foul line's vanishing point on the horizon (assumed through VP, horizontal)."""
    F = foul_corners(lane)
    fl = np.cross([*F[0], 1], [*F[1], 1]); hz = np.cross([0, vp[1], 1], [1, vp[1], 1])
    xv = np.cross(fl, hz)
    if abs(xv[2]) < 1e-9 * np.abs(xv).max(): far2 = impact_px + (F[1] - F[0])     # parallel in image
    else: xv = xv[:2] / xv[2]; far2 = xv
    P0 = _edge_point_on_line(lane['left'], impact_px, far2); P1 = _edge_point_on_line(lane['right'], impact_px, far2)
    img = np.float32([F[0], F[1], P1, P0]); world = np.float32([[0, 0], [LANE_IN, 0], [LANE_IN, Z_IMPACT], [0, Z_IMPACT]])
    return cv2.getPerspectiveTransform(img, world)

def to_lane(H, x, y):
    p = H @ np.array([x, y, np.ones_like(x)]); return p[0] / p[2], p[1] / p[2]

def mph(fps): return fps * 3600 / 5280

def impact_anchor(raw, t_impact, window=0.35, max_extrap=0.25, vp_y=None):
    """image position of the ball contact point at impact. Row is extrapolated in u = 1/(row - vp_y), which is
    projectively linear in lane distance (so ~linear in time for a rolling ball); column linearly. Robust fit over
    the last ~0.35 s of raw detections, extrapolated at most 0.25 s."""
    t = np.array([c['t'] for c in raw]); cx = np.array([c['cx'] for c in raw]); ct = np.array([c['ct'] for c in raw])
    m = t >= t.max() - window
    if m.sum() < 3: m = np.ones_like(t, bool)
    te = min(t_impact, t.max() + max_extrap)
    def rfit(x, y):
        p = np.polyfit(x, y, 1); r = y - np.polyval(p, x)
        keep = np.abs(r) <= max(2.5 * np.median(np.abs(r)) + 1e-12, 1e-9)
        return np.polyfit(x[keep], y[keep], 1) if keep.sum() >= 3 else p
    col = float(np.polyval(rfit(t[m], cx[m]), te))
    if vp_y is not None:
        u = 1.0 / np.maximum(ct - vp_y, 1.0)
        ue = float(np.polyval(rfit(t[m], u[m]), te)); row = vp_y + 1.0 / max(ue, 1e-6)
    else:
        row = float(np.polyval(rfit(t[m], ct[m]), te))
    return [col, float(row)]

def compute(track, lane, vp, t_impact, release_t=None, t_touch=None, anchor_track=None):
    t_first_free = track[0]['t'] if track else None
    T = [c for c in track if c['t'] <= t_impact + 0.01 and not c.get('airborne_candidate')]
    t = np.array([c['t'] for c in T]); cx = np.array([c['cx'] for c in T]); ct = np.array([c['ct'] for c in T])
    # impact contact point: extrapolate image track to the impact time
    raw = [c for c in (anchor_track or T) if not c.get('refined') and not c.get('airborne_candidate') and c['t'] <= t_impact + 0.01]
    pi = impact_anchor(raw, t_impact, vp_y=vp[1])
    H = lane_homography(lane, vp, np.array(pi))
    X, Z = to_lane(H, cx, ct)
    keep = (Z > -3) & (Z < 61) & np.isfinite(X) & np.isfinite(Z)          # physically on the lane before the pins
    T = [c for c, k in zip(T, keep) if k]; t, cx, ct, X, Z = t[keep], cx[keep], ct[keep], X[keep], Z[keep]
    board_from_left = X / LANE_IN * BOARDS + 0.5          # 1..39
    # handedness from hook direction: ball ends moving toward the pocket side
    pz = np.polyfit(Z, board_from_left, 3)
    end_slope = np.polyval(np.polyder(pz), Z.max())
    right_handed = end_slope < 0           # moving toward the left edge late = right-hander's hook
    board = (BOARDS + 1 - board_from_left) if right_handed else board_from_left   # handed frame for path analysis
    to_abs = (lambda b: b) if right_handed else (lambda b: None if b is None else BOARDS + 1 - b)   # report absolute boards (1 = right gutter)
    # speed: windowed linear fits along the lane (robust to occlusion gaps); drop first 4 ft (possible loft)
    def seg(a, b):
        mm = (Z >= a) & (Z < b)
        if mm.sum() < 5 or np.ptp(t[mm]) < 0.08: return None
        return np.polyfit(t[mm], Z[mm], 1)
    early = seg(4, 24)                                      # widen the window if the early lane is sparse
    if early is None: early = seg(4, 30)
    if early is None: early = seg(2, max(32.0, float(Z.max())))
    if early is None:
        raise RuntimeError('ball not tracked enough to measure speed (the rolling track is too short or sparse)')
    late = seg(Z_IMPACT - 15, Z_IMPACT + 2)
    t_foul = float(-early[1] / early[0])
    prof = {}
    for a in range(0, 60, 10):
        p = seg(a, a + 12)
        if p is not None: prof[f'{a}-{a+12}ft'] = round(mph(p[0]), 2)
    out = dict(right_handed=bool(right_handed), n_pts=len(T), t_foul_cross=t_foul, t_impact=t_impact,
               speed_avg_foul_to_pins_mph=mph(Z_IMPACT / (t_impact - t_foul)),
               speed_early_mph=mph(early[0]), speed_late_mph=mph(late[0]) if late is not None else None,
               speed_profile=prof, track_first_ft=float(Z.min()), track_last_ft=float(Z.max()))
    # release time: first clean free-ball detection at the foul line if visible, else foul crossing minus learned offset
    RELEASE_OFFSET_S = 0.068          # learned from training shots (release precedes extrapolated foul crossing)
    near = [c for c, z in zip(T, Z) if -4 <= z <= 2.5]
    if release_t is None:
        if t_first_free is not None and t_first_free < t_foul + 0.02: release_t, src = t_first_free - 0.5 / 60, 'first_free_ball_detection'
        else: release_t, src = t_foul - RELEASE_OFFSET_S, 'foul_cross_minus_offset'
    else: src = 'given'
    out['t_release'] = float(release_t); out['release_source'] = src
    # Headline speed = RELEASE speed: the velocity over the skid (foul->arrows, ~4-24 ft), i.e. what the bowler
    # imparts. This is the bowling-standard number and, unlike the full-lane average, needs only the reliable front
    # half of the track -- so it is immune to back-half fade that otherwise inflates a fixed 60 ft / interval by up
    # to ~12% when the track stops short of the pins (DEC-022r). The 60 ft average (foul->pins) is kept as a
    # secondary metric; it varies with ball/friction and needs the ball tracked to the pins.
    out['ball_speed_mph'] = mph(60.0 / (t_impact - release_t))     # 60 ft foul->pins average; reliable again now
    out['speed_release_mph'] = mph(early[0])                       # that far-lane recovery (extend_forward) tracks
    # the ball to the pins. speed_release is the front-half skid speed: robust when the back half is lost, but it
    # reads ~9% low from a near-field homography Z-scale residual, to be settled against Specto (DEC-030r).
    # loft: release -> touchdown (blob h/w step), times early-lane speed. 60 fps limits this to about +/-0.45 ft
    if src == 'first_free_ball_detection' and t_touch is not None and t_touch > release_t:
        out['loft_ft'] = float(early[0] * (t_touch - release_t)); out['t_touchdown'] = float(t_touch)
    else: out['loft_ft'] = None
    # lateral path vs distance: robust local regression, evaluated only where data exist (no gap extrapolation)
    from .smooth import loess
    zz = np.arange(max(0.0, Z.min()), min(Z_IMPACT, Z.max() + 1.0) + 1e-6, 0.25)
    covered = np.array([np.min(np.abs(Z - z)) < 3.0 for z in zz]); zz = zz[covered]
    bb, sl = loess(Z, board, zz, bw=10.0)
    ok = np.isfinite(bb); zz, bb, sl = zz[ok], bb[ok], sl[ok]
    ang = np.degrees(np.arctan(sl * (LANE_IN / BOARDS) / 12))
    out['lateral_res_boards'] = float(np.median(np.abs(board - np.interp(Z, zz, bb))) * 1.4826)
    mid = (zz > 15) & (zz < 55)
    k = np.where(mid)[0][int(np.argmin(bb[mid]))]
    out['breakpoint_board'] = float(to_abs(bb[k])); out['breakpoint_extreme_ft'] = float(zz[k])
    after = np.where(bb[k:] > bb[k] + 0.25)[0]
    out['breakpoint_ft'] = float(zz[k + after[0]]) if len(after) else None     # end of the flat (skid) top
    seg = (zz >= 52) & (zz <= 55)
    out['entry_angle_52_55_deg'] = float(np.mean(ang[seg])) if seg.sum() >= 4 else None     # Specto-compatible definition
    late = zz > zz.max() - 1.5
    out['entry_angle_deg'] = float(np.mean(ang[late])); out['entry_board'] = float(to_abs(np.interp(Z_IMPACT, zz, bb))) if zz.max() > 56 else None
    for zq in (0, 7, 15):
        if zz.min() <= zq + 1: out[f'board_at_{zq}ft'] = float(to_abs(np.interp(zq, zz, bb)))
    if zz.min() < 3: out['launch_angle_deg'] = float(-np.mean(ang[(zz >= 1) & (zz <= 10)]))
    out['_curve'] = dict(Z=zz.tolist(), board=[float(to_abs(b)) for b in bb])
    out['_series'] = dict(t=t.tolist(), Z=Z.tolist(), board=[float(to_abs(b)) for b in board], X_in=X.tolist(),
                          px=[[float(a), float(b)] for a, b in zip(cx, ct)], curve=out.pop('_curve'))
    return out
