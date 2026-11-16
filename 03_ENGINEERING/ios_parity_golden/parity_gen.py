"""Task 2 parity reference generator.
For each of IMG_8751-54: load the geo pkl (bg plate + final lane/vp/t_imp/ground used for the committed golden),
re-run find_lanes(bg) to capture per-STAGE intermediates, confirm it reproduces the committed golden geometry,
and dump:
  - <clip>_plate.bgra   : raw background plate as BGRA bytes (H*W*4), bit-exact input for the Swift detector
  - parity_intermediates.json : per-stage reference (mask %, raw lane count, raw VP, refined lane/foul/VP)
Compares find_lanes(bg) output against 03_ENGINEERING/ios_parity_golden/golden_<clip>.json lane block.
"""
import os, sys, json, pickle, warnings
import numpy as np, cv2
warnings.filterwarnings('ignore')
sys.path.insert(0, os.path.expanduser('~/Developer/LaneSight/lanesight-core'))
from lanesight_core.cv import lanes as LN

GEO = '/private/tmp/claude-501/-Users-shaynel/eb52d328-8f3e-4b88-bf7c-7207c1118a38/scratchpad'
GOLDEN = os.path.expanduser('~/Developer/LaneSight/03_ENGINEERING/ios_parity_golden')
OUT = os.path.dirname(os.path.abspath(__file__))
CLIPS = ['IMG_8751', 'IMG_8752', 'IMG_8753', 'IMG_8754']

# instrument find_lanes by replicating its body enough to capture intermediates at each saturation floor
def instrumented(bg):
    h, w = bg.shape[:2]
    stages = {}
    m = None; lanes = []; good = []; vp = None; used_s = 105
    floors = []
    winner = None
    for s_min in (105, 70, 50):
        mm = LN.lane_mask(bg, s_min=s_min)
        ln, gd, v, detail = _detect_capture(mm, h, w)
        floors.append(dict(s_min=s_min, pct=round(100*float(mm.mean()),4), mask_px=int(mm.sum()),
                           n_tracks=detail['n_tracks'], n_lanes=len(ln), n_good=len(gd),
                           vp=[round(float(v[0]),3), round(float(v[1]),3)] if v is not None else None,
                           raw_lanes=detail['raw_lanes']))
        if m is None: m, lanes = mm, ln
        if gd:
            m, lanes, good, vp, used_s = mm, ln, gd, v, s_min
            winner = floors[-1]
            break
    stages['floors'] = floors
    stages['used_s'] = used_s
    stages['winner'] = winner
    # loose mask stats (used by _refine_edges)
    loose = LN.lane_mask(bg, s_min=min(60, used_s))
    stages['loose_mask_px'] = int(loose.sum()); stages['loose_s_min'] = int(min(60, used_s))
    return stages

RAW = {}  # clip -> captured raw stage detail for the winning floor

def _detect_capture(m, h, w, min_run=40, min_rows=120):
    # exact copy of lanes._detect inner logic
    tracks = []; active = []
    for y in range(h - 1, 0, -2):
        row = m[y]; d = np.diff(np.r_[0, row, 0].astype(int))
        st = np.where(d == 1)[0]; en = np.where(d == -1)[0] - 1
        runs = [(a, b) for a, b in zip(st, en) if b - a >= min_run * (0.3 + 0.7 * y / h)]
        new_active = []
        for a, b in runs:
            hit = None
            for t in active:
                _, pa, pb = t[-1]
                if min(b, pb) - max(a, pa) > 0.5 * min(b - a, pb - pa): hit = t; break
            if hit is None: hit = []; tracks.append(hit)
            hit.append((y, a, b)); new_active.append(hit)
        active = new_active
    tracks = [t for t in tracks if len(t) * 2 >= min_rows]
    n_tracks = len(tracks)
    lanes = []; raw_lanes = []
    for t in tracks:
        T = np.array(t, float)
        L = T[T[:, 1] > 2][:, [1, 0]]; R = T[T[:, 2] < w - 3][:, [2, 0]]
        if len(L) < 30 or len(R) < 30: continue
        pl, sl, nl = LN._fit(L); pr, sr, nr = LN._fit(R)
        y_near = T[:, 0].max()
        lanes.append(dict(left=pl, right=pr, res=(sl, sr), y_rng=(T[:, 0].min(), y_near), npts=len(T), track=T))
        raw_lanes.append(dict(left=[round(float(pl[0]),6), round(float(pl[1]),3)], lres=round(float(sl),4),
                              right=[round(float(pr[0]),6), round(float(pr[1]),3)], rres=round(float(sr),4),
                              y_rng=[int(T[:,0].min()), int(y_near)], npts=int(len(T)),
                              nL=int(len(L)), nR=int(len(R))))
    good = []; vp = None
    if lanes:
        E = [(l['left'], l['res'][0]) for l in lanes] + [(l['right'], l['res'][1]) for l in lanes]
        A = np.array([[1, -p[0]] for p, _ in E]); b = np.array([p[1] for p, _ in E]); wt = np.array([1/(r+0.5) for _, r in E])
        AA = A*wt[:,None]; bb = b*wt
        if np.all(np.isfinite(AA)) and np.all(np.isfinite(bb)):
            try: vp = np.linalg.lstsq(AA, bb, rcond=None)[0]
            except np.linalg.LinAlgError: vp = None
            if vp is not None and np.all(np.isfinite(vp)):
                for l in lanes:
                    dl = abs(vp[0] - np.polyval(l['left'], vp[1])); dr = abs(vp[0] - np.polyval(l['right'], vp[1]))
                    width_near = np.polyval(l['right'], l['y_rng'][1]) - np.polyval(l['left'], l['y_rng'][1])
                    l['vp_miss'] = (dl, dr)
                    if max(dl, dr) < 0.08 * w and width_near > 60: good.append(l)
            else: vp = None
    return lanes, good, vp, dict(n_tracks=n_tracks, raw_lanes=raw_lanes)

out = {}
for clip in CLIPS:
    geo = pickle.load(open(f'{GEO}/geo_{clip}.pkl', 'rb'))
    bg = geo['bg']; h, w = bg.shape[:2]
    gold = json.load(open(f'{GOLDEN}/golden_{clip}.json'))

    # dump raw BGRA plate (BGR from cv2 + opaque alpha)
    bgra = np.dstack([bg[..., 0], bg[..., 1], bg[..., 2], np.full((h, w), 255, np.uint8)]).astype(np.uint8)
    bgra.tofile(f'{OUT}/{clip}_plate.bgra')
    # dump the winning STRICT mask (s_min=used_s, here 105) + the LOOSE mask (s_min=min(60,used_s)) as 0/1 bytes,
    # so a Swift geometry-only test can run on Python's exact masks (isolates the geometry port from HSV/morph).
    strict = LN.lane_mask(bg, s_min=105)        # all 4 win at 105
    loose = LN.lane_mask(bg, s_min=60)
    strict.astype(np.uint8).tofile(f'{OUT}/{clip}_strict.u8')
    loose.astype(np.uint8).tofile(f'{OUT}/{clip}_loose.u8')

    # run the REAL find_lanes to get refined geometry (should reproduce committed golden)
    G = LN.find_lanes(bg, log=lambda *a, **k: None)
    vp = G['vp']; l0 = G['lanes'][0]
    F = LN.foul_corners(l0)
    # canonical edge a,b via the golden's edges_ab convention (y0=600,y1=1700)
    def edges_ab(lane):
        y0, y1 = 600.0, 1700.0
        xa0, xb0 = LN.lane_x(lane, y0); xa1, xb1 = LN.lane_x(lane, y1)
        la = (xa1-xa0)/(y1-y0); lb = xa0-la*y0
        ra = (xb1-xb0)/(y1-y0); rb = xb0-ra*y0
        return (la, lb), (ra, rb)
    lab, rab = edges_ab(l0)

    stages = instrumented(bg)
    out[clip] = dict(
        image=dict(w=w, h=h),
        plate_file=f'{clip}_plate.bgra',
        stages=stages,
        refined=dict(
            vp=[round(float(vp[0]), 3), round(float(vp[1]), 3)],
            left_ab=[round(lab[0], 6), round(lab[1], 3)],
            right_ab=[round(rab[0], 6), round(rab[1], 3)],
            foul_corners=[[round(float(x), 2), round(float(y), 2)] for x, y in F],
            n_good=len(G['lanes']),
        ),
        golden_lane=gold['lane'],
    )
    gl = gold['lane']
    dvp = (abs(vp[0]-gl['vp'][0]), abs(vp[1]-gl['vp'][1]))
    print(f"{clip}: find_lanes VP=({vp[0]:.1f},{vp[1]:.1f}) golden VP=({gl['vp'][0]:.1f},{gl['vp'][1]:.1f}) "
          f"dVP=({dvp[0]:.2f},{dvp[1]:.2f}) n_good={len(G['lanes'])} used_s={stages['used_s']}")
    print(f"      left_ab {lab} vs golden {gl['left_ab']}")
    print(f"      foul    {out[clip]['refined']['foul_corners']} vs golden {gl['foul_corners']}")

json.dump(out, open(f'{OUT}/parity_intermediates.json', 'w'), indent=1)
print('WROTE', OUT, '(plates + parity_intermediates.json)')
