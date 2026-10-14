"""Demo: the 4 validation shots as one session -> refreshed insights, session summary, consistency, heatmap,
sensor variance, replay renders. Run: python3 examples/demo_session.py"""
import json, sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from lanesight_core.insights.adjust import strike_adjustment
from lanesight_core.insights.spares import spare_plan
from lanesight_core.insights.session import summary, consistency, heatmap
from lanesight_core.replay.render import shot_png, heatmap_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = [os.path.join(ROOT, 'validation', f'{v}_shot.json') for v in ('IMG_8751', 'IMG_8752', 'IMG_8753', 'IMG_8754')]  # Ruby #14,16,17,18
out = os.path.join(ROOT, 'out'); os.makedirs(out, exist_ok=True)
recs, history = [], []
for p in SHOTS:
    r = json.load(open(p)); mt = r['metrics']
    view = {k: v['value'] for k, v in mt.items()}
    view.update(board_at_15ft=mt['arrows_board']['value'], board_at_0ft=mt['laydown_board']['value'],
                entry_angle_deg=mt['entry_angle']['value'], pins_standing=set(r['pins']['standing']), pins_uncertain=set(r['pins']['uncertain']))
    r['insights'] = strike_adjustment(view, r['handed'], history=history, pattern=dict(length_ft=41))
    if not r['pins']['strike']: r['spare_plan'] = spare_plan(set(r['pins']['standing']), r['handed'], strike_stance=None)
    history.append(dict(view, classification=r['insights']['classification']))
    recs.append(r)
    shot_png(r, os.path.join(out, f"replay_{r['shot_id']}.png"))
    var = r['sensor']['compared'] if r.get('sensor') else {}
    print(f"{r['shot_id']:6s} {mt['ball_speed']['value']:.2f} mph | rev {mt['rev_rate']['value']:.0f} | entry {mt['entry_board']['value']:.1f}"
          f" @ {mt['entry_angle']['value']:.1f}° | pins {r['pins']['standing'] or 'X'} | {r['insights']['classification']}")
    print('        ->', r['insights']['recommendations'][0]['reason'])
    if var: print('        sensor variance:', {k: f"{v['diff']:+.2f} ({v['pct']:+.1f}%)" for k, v in var.items()})
    if r.get('spare_plan'): print('        spare:', r['spare_plan']['straight_line'], r['spare_plan']['ball'])
S = dict(summary=summary(recs), consistency=consistency(recs), heatmap=heatmap(recs))
heatmap_png(S['heatmap'], os.path.join(out, 'session_heatmap.png'), 'Session lane usage')
json.dump(S, open(os.path.join(out, 'session.json'), 'w'), indent=1)
print('\nsession summary:', json.dumps(S['summary'], indent=None)[:600])
print('consistency:', S['consistency'])
