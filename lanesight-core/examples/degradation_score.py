# Record of the 2026-10-14 capture-tier test (paths refer to the cloud workspace where it ran).
import json, os, numpy as np
GT = {  # visual ground truth (absolute video time) + Ruby + trim offset
 's1': dict(rel=25.670, imp=28.063, pins={3,6,10}, ruby=dict(ball_speed=17.0, rev_rate=428, loft=1.5), off=22.67, full='/home/claude/shots/s1/auto1_shot.json'),
 's2': dict(rel=9.262, imp=11.555, pins=set(), ruby=dict(ball_speed=17.8, rev_rate=392, loft=2.6), off=6.26, full='/home/claude/shots/s2/s2_shot.json'),
 's3': dict(rel=18.500, imp=20.860, pins=set(), ruby=dict(ball_speed=17.4, rev_rate=407, loft=2.0), off=15.5, full='/home/claude/shots/s3/s3_shot.json'),
 's4': dict(rel=26.637, imp=28.985, pins=set(), ruby=dict(ball_speed=16.9, rev_rate=411, loft=2.5), off=23.64, full='/home/claude/shots/s4/s4_shot.json'),
}
LAT = ['laydown_board', 'arrows_board', 'breakpoint_board', 'breakpoint_distance', 'entry_board', 'entry_angle', 'speed_early', 'speed_late']
rows = []
for shot, g in GT.items():
    for var in ['full', '60_720', '30_1080', '30_720']:
        p = g['full'] if var == 'full' else f'/home/claude/degrade/{shot}_{var}_shot.json'
        if not os.path.exists(p): rows.append(dict(shot=shot, var=var, status='missing')); continue
        r = json.load(open(p)); mt = {k: v['value'] for k, v in r['metrics'].items()}
        off = 0 if var == 'full' else g['off']
        ref = json.load(open(g['full']))['metrics']
        row = dict(shot=shot, var=var, status='ok',
                   rel_err_ms=round(1000 * (r['events']['t_release'] + off - g['rel'])),
                   imp_err_ms=round(1000 * (r['events']['t_impact'] + off - g['imp'])),
                   pins_ok=(set(r['pins']['standing']) == g['pins']) if r.get('pins') else None)
        for k, v in g['ruby'].items():
            row[f'{k}_vs_ruby'] = None if mt.get(k) is None else round(mt[k] - v, 2)
        for k in LAT:
            a, b = mt.get(k), ref[k]['value']
            row[f'{k}_vs_full'] = None if (a is None or b is None) else round(a - b, 2)
        rows.append(row)
json.dump(rows, open('/home/claude/degrade/scores.json', 'w'), indent=1)
import collections
agg = collections.defaultdict(lambda: collections.defaultdict(list))
for r in rows:
    if r['status'] != 'ok': continue
    for k, v in r.items():
        if k in ('shot', 'var', 'status'): continue
        agg[r['var']][k].append(v)
keys = sorted({k for r in rows for k in r if k not in ('shot', 'var', 'status')})
print(f"{'metric':28s}" + ''.join(f'{v:>18s}' for v in ['full', '60_720', '30_1080', '30_720']))
for k in keys:
    line = f'{k:28s}'
    for v in ['full', '60_720', '30_1080', '30_720']:
        vals = agg[v][k]
        if not vals: line += f"{'—':>18s}"; continue
        if k == 'pins_ok':
            ok = [x for x in vals if x is not None]; line += f"{sum(ok)}/{len(ok)}".rjust(18); continue
        nn = [x for x in vals if x is not None]
        miss = len(vals) - len(nn)
        s = f"MAE {np.mean(np.abs(nn)):.2f}" if nn else 'n/a'
        line += (s + (f' ({miss} n/a)' if miss else '')).rjust(18)
    print(line)
