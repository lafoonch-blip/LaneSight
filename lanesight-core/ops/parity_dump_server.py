"""DEC-128 port-parity: dump the SERVER's per-stage ball-track intermediates for a clip, so they can be compared
against the on-device engine's to find where the Swift port diverges. Reference side only (no device).

  LANESIGHT_FFMPEG_DECODE=1 python3 ops/parity_dump_server.py <clip.mov> [<clip2.mov> ...]
"""
import os, sys, json
import numpy as np

from lanesight_core.cv.stabilize import stabilize
from lanesight_core.cv.lanes import find_lanes, foul_corners, lane_x
from lanesight_core.cv import track as T


def dump(path):
    out = {'clip': os.path.basename(path)}
    S = stabilize(path)
    shift = S.get('shift')
    out['camera_motion_px_max'] = round(float(np.max(shift)), 2) if shift is not None else None
    out['camera_motion_px_median'] = round(float(np.median(shift)), 2) if shift is not None else None
    out['n_frames'] = len(S['ts'])
    G = find_lanes(S['bg'])
    vp = G['vp']
    out['lanes_detected'] = len(G['lanes'])
    out['vp'] = [round(float(vp[0]), 1), round(float(vp[1]), 1)]
    # all detected lanes' center_x + width at the foul line (to compare against the device's single lane)
    lanes_geo = []
    for li, lane in enumerate(G['lanes']):
        F = foul_corners(lane); yf = float(F[:, 1].max()); xa, xb = lane_x(lane, yf)
        lanes_geo.append({'lane': li, 'foul_y': round(yf, 0), 'center_x': round(float((xa + xb) / 2), 1),
                          'width': round(float(xb - xa), 1)})
    out['lanes_geo'] = lanes_geo
    best = None
    for li, lane in enumerate(G['lanes']):
        try:
            B = T.extract_blobs(path, S, lane, vp)
        except Exception as e:
            out.setdefault('lane_errors', []).append(f'lane{li}: {type(e).__name__}: {str(e)[:60]}')
            continue
        # recompute thr_eff + bg level for this lane (mirror extract_blobs)
        roi = T.lane_roi(lane, vp, S['bg'].shape)
        ys, xs = np.where(roi)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        bgc = S['bg'][y0:y1, x0:x1].astype(np.int16)
        roic = roi[y0:y1, x0:x1]
        lvl = T._roi_bg_level(bgc.max(axis=2), roic)
        thr_eff = T._adaptive_thr(35, lvl)
        blob_counts = [len(fr['blobs']) for fr in B]
        frames_with_blobs = sum(1 for c in blob_counts if c > 0)
        C = T.candidates(B, lane, vp)        # list-per-frame: C[frame] = [candidate dicts]
        frames_with_candidates = sum(1 for cs in C if cs)
        total_candidates = sum(len(cs) for cs in C)
        Tk = T.link(C, vp)
        laneinfo = {'lane': li, 'bg_level': round(float(lvl), 1), 'thr_eff': round(float(thr_eff), 1),
                    'total_blobs': int(sum(blob_counts)), 'frames_with_blobs': frames_with_blobs,
                    'total_candidates': total_candidates, 'frames_with_candidates': frames_with_candidates,
                    'track_len': len(Tk)}
        if best is None or laneinfo['track_len'] > best['track_len']:
            best = laneinfo
    out['best_lane'] = best
    # decode-level: mean of the max-channel BACKGROUND plate over the whole frame (comparable to the device's
    # working-res bg_luma_mean). A systematic difference here = the YUV->BGR decode diverges.
    out['bg_luma_mean'] = round(float(S['bg'].max(axis=2).mean()), 2)
    return out


def main():
    for p in sys.argv[1:]:
        print('DUMP', json.dumps(dump(p)), flush=True)


if __name__ == '__main__':
    main()
