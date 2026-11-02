"""Run the 0.7.1 engine on the 18 labeled 11/1 clips; report per-clip + by camera group vs truth.
truth = 59.44 ft / ((pin_frame - foul_frame)/fps) * 3600/5280. Skip clips with a null foul/pin frame."""
import os, sys, json, tempfile, time
sys.path.insert(0, '.'); os.environ.setdefault('LANESIGHT_FFMPEG_DECODE', '1'); os.environ.setdefault('LANESIGHT_FRAME_CACHE_MB','5500')
from lanesight_runner.core import analyze_clip

LAB = json.load(open('validation/labels/speed_truth_1101.json'))['clips']
CLIPDIR = os.path.expanduser('~/LaneSightData/training_videos/11:1 Shots')
Z = 59.44
rows = []
for cid in sorted(k for k in LAB if isinstance(LAB[k], dict)):
    v = LAB[cid]; ev = v.get('events', {}); fps = v.get('fps')
    ff = (ev.get('foul_cross') or {}).get('frame'); pf = (ev.get('first_pin_contact') or {}).get('frame')
    grp = v.get('camera') or v.get('camera_group') or '?'
    if ff is None or pf is None or not fps or pf <= ff:
        rows.append(dict(clip=cid, group=grp, truth=None, skip='no foul/pin label'));
        print(json.dumps(rows[-1]), flush=True); continue
    truth = Z / ((pf - ff) / fps) * 3600 / 5280
    src = None
    for ext in ('.MOV', '.mov'):
        p = os.path.join(CLIPDIR, cid + ext)
        if os.path.exists(p): src = p; break
    if not src:
        rows.append(dict(clip=cid, group=grp, truth=round(truth,3), skip='clip file missing')); print(json.dumps(rows[-1]), flush=True); continue
    t0 = time.time()
    rec = dict(clip=cid, group=grp, truth=round(truth, 3))
    try:
        r, probe, timings = analyze_clip(src, os.path.join(tempfile.mkdtemp(), 'o'), handed='R', timings={})
        d = r.to_dict() if hasattr(r, 'to_dict') else r
        m = d.get('metrics') or {}
        def val(k):
            x = m.get(k); return (x.get('value') if isinstance(x, dict) else x)
        def note(k):
            x = m.get(k); return (x.get('note') if isinstance(x, dict) else None)
        avg = val('speed_avg_foul_to_pins'); rel = val('ball_speed'); rev = val('rev_rate')
        rec.update(status=d.get('analysis_status') or 'analyzed', avg_f2p=avg, err=(round(avg-truth,3) if avg is not None else None),
                   release=rel, rev=rev, secs=round(time.time()-t0,1),
                   avg_unavail=(note('speed_avg_foul_to_pins') if avg is None else None),
                   far_lane=(d.get('capture_quality') or {}).get('far_lane'))
    except Exception as e:
        rec.update(status='failed', failure_code=getattr(e,'code',None) or type(e).__name__,
                   failure_stage=getattr(e,'stage',None), err_msg=str(e)[:90], secs=round(time.time()-t0,1))
    rows.append(rec); print(json.dumps(rec), flush=True)

json.dump(rows, open('/tmp/eval18_rows.json','w'), indent=1)
# summary by group
print("=== SUMMARY BY CAMERA GROUP ===", flush=True)
from collections import defaultdict
g = defaultdict(list)
for r in rows: g[r['group']].append(r)
for grp, rs in g.items():
    labeled = [r for r in rs if r.get('truth') is not None]
    measured = [r for r in labeled if r.get('avg_f2p') is not None]
    errs = [r['err'] for r in measured if r.get('err') is not None]
    mae = round(sum(abs(e) for e in errs)/len(errs),3) if errs else None
    bias = round(sum(errs)/len(errs),3) if errs else None
    worst = max(errs, key=abs) if errs else None
    print(json.dumps(dict(group=grp, n=len(rs), labeled=len(labeled), measured=len(measured),
                          coverage=f"{len(measured)}/{len(labeled)}", mae=mae, bias=bias, worst=round(worst,3) if worst is not None else None)), flush=True)
print("DONE", flush=True)
