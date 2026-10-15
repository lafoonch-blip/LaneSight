"""Pin reading: which pins are standing after the shot.
Pin spots are projected through the lane homography; each pin's upper body (neck/head band, where fallen
deadwood cannot be) is tested for 'pin white' in the settled frame vs a pre-impact reference frame.
Pins directly behind a standing front pin (5<-1, 8<-2, 9<-3 from a rear view) are flagged uncertain."""
import cv2, numpy as np
from .stabilize import frames

LANE_IN = 41.5
ROW_FT = 10.392 / 12            # pin row spacing
# pin: (lateral offset inches, right = +, as seen from the foul line; feet from foul line)
PINS = {1: (0, 60.0), 2: (-6, 60 + ROW_FT), 3: (6, 60 + ROW_FT), 4: (-12, 60 + 2 * ROW_FT), 5: (0, 60 + 2 * ROW_FT),
        6: (12, 60 + 2 * ROW_FT), 7: (-18, 60 + 3 * ROW_FT), 8: (-6, 60 + 3 * ROW_FT), 9: (6, 60 + 3 * ROW_FT),
        10: (18, 60 + 3 * ROW_FT)}
BEHIND = {5: 1, 8: 2, 9: 3}
PIN_H_IN, PIN_W_IN = 15.0, 4.0

def pin_pixels(H_img2lane):
    Hi = np.linalg.inv(H_img2lane); out = {}
    for p, (dx, z) in PINS.items():
        X = LANE_IN / 2 + dx
        b = Hi @ [X, z, 1]; b = b[:2] / b[2]
        r = Hi @ [X + LANE_IN, z, 1]; r = r[:2] / r[2]               # one lane-width to the right -> px scale
        ppi = np.linalg.norm(r - b) / LANE_IN                        # pixels per inch at the pin
        out[p] = dict(u=float(b[0]), v=float(b[1]), ppi=float(ppi))
    return out

def _white(img):
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    return ((hsv[..., 1] < 70) & (hsv[..., 2] > 160)).astype(np.float32)

def _band(W, pp):
    w = max(2, int(0.35 * PIN_W_IN * pp['ppi'])); h = PIN_H_IN * pp['ppi']        # narrow band: pin centre only
    y0, y1 = int(pp['v'] - 0.92 * h), int(pp['v'] - 0.45 * h)        # neck/head band
    x0, x1 = int(pp['u'] - w), int(pp['u'] + w) + 1
    if y0 < 0 or x0 < 0 or y1 > W.shape[0] or x1 > W.shape[1]: return np.nan
    return float(W[y0:y1, x0:x1].mean())

def read_pins(path, S, H_img2lane, t_impact, log=print):
    h, w = S['bg'].shape[:2]; PP = pin_pixels(H_img2lane)
    us = [p['u'] for p in PP.values()]; vs = [p['v'] for p in PP.values()]; s = max(p['ppi'] for p in PP.values())
    box = (int(min(vs) - 20 * s), int(max(vs) + 4 * s), int(min(us) - 8 * s), int(max(us) + 8 * s))
    box = (max(box[0], 0), min(box[1], h), max(box[2], 0), min(box[3], w))
    pre, post = [], []
    for i, f in frames(path):
        if i >= len(S['Hs']): break
        t = S['ts'][i]
        if t < t_impact - 0.7: continue
        if t > t_impact + 1.7: break
        g = cv2.warpPerspective(f, S['Hs'][i], (w, h))
        if t < t_impact - 0.3: pre.append(g)
        elif t > t_impact + 0.4: post.append((t, g))
    if not pre or not post: return None
    ref = np.median(np.stack(pre), 0).astype(np.uint8)
    # read window +0.8..+1.6 s: deadwood has left the neck/head band, and the sweep bar (if down) only hides pin bases
    win = [g for t, g in post if t_impact + 0.8 <= t <= t_impact + 1.6]
    if len(win) < 5: win = [g for _, g in post[:30]]
    t_set = t_impact + 1.2
    settled = np.median(np.stack(win), 0).astype(np.uint8)
    crop = lambda g: cv2.cvtColor(g[box[0]:box[1], box[2]:box[3]], cv2.COLOR_BGR2GRAY).astype(np.float32)
    (dx, dy), _ = cv2.phaseCorrelate(crop(ref), crop(settled))
    settled = cv2.warpAffine(settled, np.float32([[1, 0, -dx], [0, 1, -dy]]), (w, h))
    Wr, Ws = _white(ref), _white(settled)
    # snap the projected rack onto the real pins: the full rack in the pre-impact frame maximizes pin-white at all spots
    best = (-1, 0, 0)
    for sx in range(-12, 13):
        for sy in range(-3, 4):
            sc = 0.0
            for pp in PP.values():
                v = _band(Wr, dict(pp, u=pp['u'] + sx, v=pp['v'] + sy))
                sc += 0 if not np.isfinite(v) else v
            if sc > best[0]: best = (sc, sx, sy)
    _, sx, sy = best
    PP = {p: dict(pp, u=pp['u'] + sx, v=pp['v'] + sy) for p, pp in PP.items()}
    res = {}
    for p, pp in PP.items():
        a, b = _band(Wr, pp), _band(Ws, pp)
        res[p] = dict(ref=a, now=b, ratio=(b / a) if a and a > 0.05 else np.nan)
    standing, uncertain = [], []
    for p in range(1, 11):
        r = res[p]['ratio']
        st = (r > 0.45) if np.isfinite(r) else False
        res[p]['standing'] = bool(st)
    for p, front in BEHIND.items():                       # a rear pin can't be seen when its front pin stands
        if res[front]['standing']:
            uncertain.append(p); res[p]['standing'] = None
    standing = [p for p in range(1, 11) if res[p]['standing']]
    conf = np.mean([min(1.0, abs((res[p]['ratio'] if np.isfinite(res[p]['ratio']) else 0.45) - 0.45) / 0.35)
                    for p in range(1, 11) if res[p]['standing'] is not None])
    # Reliability: a "no pins standing" result is only a real strike if we could actually SEE the settled deck.
    # The masking unit just above the pins is static background, so if it changed between the pre-impact reference
    # and the settled frame, something (usually the bowler standing into frame) is blocking the deck. A would-be
    # strike under that condition is reported as unreadable, not a false strike -- LaneSight reads pins from the
    # video, so when the video doesn't show them it must say so rather than guess. (A visible leave is still
    # reported; occlusion most dangerously HIDES standing pins and makes a leave look like a strike.)
    clip_end = float(S['ts'][min(len(S['ts']), len(S['Hs'])) - 1])
    vmin = min(pp['v'] for pp in PP.values()); ppi = max(pp['ppi'] for pp in PP.values())
    us = [pp['u'] for pp in PP.values()]
    by0, by1 = max(int(vmin - 24 * ppi), 0), max(int(vmin - 15 * ppi), 1)
    bx0, bx1 = max(int(min(us) - 8 * ppi), 0), min(int(max(us) + 8 * ppi), w)
    occluded = False
    if by1 > by0 + 2 and bx1 > bx0 + 2:
        rb = cv2.cvtColor(ref[by0:by1, bx0:bx1], cv2.COLOR_BGR2GRAY).astype(np.float32).ravel()
        sb = cv2.cvtColor(settled[by0:by1, bx0:bx1], cv2.COLOR_BGR2GRAY).astype(np.float32).ravel()
        # real strike/leave leaves the masking unit intact (corr ~0.7-0.95); a bowler blocking it drops corr far
        # lower (shot 5: ~0.07). 0.35 sits in the wide gap, biased to avoid ever false-flagging a real result.
        if rb.std() > 1 and sb.std() > 1: occluded = float(np.corrcoef(rb, sb)[0, 1]) < 0.35
    settled_enough = clip_end >= t_impact + 0.6                     # a floor: pins need a moment to fall on screen
    readable, reason = True, None
    if not standing and not uncertain and (occluded or not settled_enough):
        readable = False
        reason = ("the pin deck was blocked (the bowler stepped into view) as the pins settled" if occluded
                  else f"the clip ends {clip_end - t_impact:.1f}s after the ball reached the pins — too soon to read the pins")
    out = dict(t_settled=float(t_set), standing=(standing if readable else None),
               uncertain=(uncertain if readable else None), strike=((not standing and not uncertain) if readable else None),
               readable=readable, unread_reason=reason,
               pins_down_min=(10 - len(standing) - len(uncertain)) if readable else None,
               pins_down_max=(10 - len(standing)) if readable else None,
               confidence=float(conf) if readable else 0.0,
               per_pin={p: {k: (round(v, 3) if isinstance(v, float) else v) for k, v in d.items()} for p, d in res.items()}, pin_px=PP)
    out['rack_snap_px'] = (sx, sy)
    log(f"pins: rack snapped by ({sx},{sy}) px; " + (f"UNREADABLE ({reason})" if not readable else
        f"standing {standing}{' uncertain ' + str(uncertain) if uncertain else ''} "
        f"({'STRIKE' if out['strike'] else str(out['pins_down_min']) + ' down'})") + f" settled t={t_set:.2f}s conf {conf:.2f}")
    return out
