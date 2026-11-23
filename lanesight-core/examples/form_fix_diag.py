"""Root-cause the 2 real form uploads (rear 0caad150, side be86b1db). Full-clip Python reference."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from lanesight_core.form import pose as P
_ORIG = P.extract_landmarks
CACHE = os.path.expanduser('~/LaneSightData/form/lm_cache'); os.makedirs(CACHE, exist_ok=True)
CLIPS = {'rear_0caad150': 'IMG_rear_0caad150.mov', 'side_be86b1db': 'IMG_side_be86b1db.mov'}
def load(name, path):
    cp = os.path.join(CACHE, name + '.npz')
    if os.path.exists(cp) and not os.environ.get('FORCE'):
        d = np.load(cp); return d['t'], d['lms']
    t, lms = _ORIG(path, log=lambda *a: None)
    np.savez_compressed(cp, t=t, lms=lms); return t, lms
for name, fn in CLIPS.items():
    path = os.path.expanduser(f'~/LaneSightData/form/{fn}')
    t, lms = load(name, path)
    P.extract_landmarks = lambda *a, _t=t, _l=lms, **k: (_t, _l)
    print(f'\n===== {name}  frames={len(t)} dur={t[-1]-t[0]:.1f}s =====')
    rec = P.analyze(path, handed='right', log=lambda *a: None)
    ex = rec['_extras']; ev = ex.get('events') or {}
    print('view:', (ex.get('view_info') or {}).get('view'))
    print('events:', {k: (round(x, 2) if x else None) for k, x in ev.items()})
    print('strikes:', [(round(s, 1), f) for s, f in (ex.get('strikes') or [])][:16], 'n=', len(ex.get('strikes') or []))
    for k in ('step_count', 'approach_time', 'swing_time', 'backswing_height_rel'):
        m = rec.get(k) or {}; print(f'  {k:20s} {str(m.get("value")):8s} {m.get("status")} {m.get("reason_code") or ""}')
