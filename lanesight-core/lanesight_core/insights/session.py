"""Session / all-time shot analytics: averages, consistency (dispersion), lane heatmap, trends."""
from __future__ import annotations
import numpy as np

KEY = {'arrows': 'arrows_board', 'breakpoint': 'breakpoint_board', 'entry': 'entry_board'}

def _vals(shots, metric):
    return [s['metrics'][metric]['value'] for s in shots
            if metric in s['metrics'] and s['metrics'][metric]['value'] is not None and s['metrics'][metric]['status'] in ('ok', 'calibrated_estimate')]

def summary(shots: list[dict]) -> dict:
    """shots: ShotRecord dicts. Averages + spread for every metric with enough valid values."""
    out = {}
    for metric in ('ball_speed', 'rev_rate', 'loft', 'laydown_board', 'arrows_board', 'breakpoint_board',
                   'breakpoint_distance', 'entry_board', 'entry_angle', 'launch_angle'):
        v = _vals(shots, metric)
        if v: out[metric] = dict(n=len(v), mean=round(float(np.mean(v)), 2), sd=round(float(np.std(v)), 2),
                                 min=round(float(min(v)), 2), max=round(float(max(v)), 2))
    return out

def metric_detail(points: list[dict], metric: str) -> dict:
    """Per-metric detail for the Stats detail screens (MVP-08). `points`: per-shot dicts with `record` (a
    ShotRecord), `session_id`, `ball`, `pattern`, `created_at`. Returns avg, robust spread (1.4826·MAD), range,
    coverage (measured / total), per-session trend (ordered by first shot time), by ball, by oil pattern, and a
    small-sample flag (<20 measured). Only 'ok'/'calibrated_estimate' values count; never fabricates."""
    vals, by_sess, by_ball, by_pat = [], {}, {}, {}
    n_total = len(points)
    for p in points:
        m = (p.get('record', {}).get('metrics') or {}).get(metric) or {}
        v, st = m.get('value'), m.get('status')
        if v is None or st not in ('ok', 'calibrated_estimate'):
            continue
        vals.append(float(v))
        by_sess.setdefault(p.get('session_id'), []).append((p.get('created_at') or 0, float(v)))
        if p.get('ball'):
            by_ball.setdefault(p['ball'], []).append(float(v))
        if p.get('pattern'):
            by_pat.setdefault(p['pattern'], []).append(float(v))
    if not vals:
        return dict(metric=metric, n=0, coverage=round(0 if not n_total else 0.0, 2), status='building',
                    avg=None, spread=None, range=None, trend=[], by_ball=[], by_pattern=[], small_sample=True)
    arr = np.array(vals)
    mad = float(np.median(np.abs(arr - np.median(arr))))
    trend = [dict(session_id=s, n=len(v), mean=round(float(np.mean([x[1] for x in v])), 2))
             for s, v in sorted(by_sess.items(), key=lambda kv: min(t for t, _ in kv[1]))]
    grp = lambda d: [dict(key=k, n=len(v), mean=round(float(np.mean(v)), 2)) for k, v in d.items()]
    return dict(metric=metric, n=len(vals), coverage=round(len(vals) / max(n_total, 1), 2), status='ok',
                avg=round(float(np.mean(arr)), 2), spread=round(1.4826 * mad, 2),
                range=[round(float(arr.min()), 2), round(float(arr.max()), 2)],
                trend=trend, by_ball=grp(by_ball), by_pattern=grp(by_pat), small_sample=len(vals) < 20)


_FOCUS_TITLES = {
    'execution_miss': 'Hit your mark',
    'move': 'Dial in your line',
    'release': 'Finish through the ball',
    'speed': 'Match your speed',
    'no_reliable_data': 'Fix your camera position',
    'pins_unknown': 'Frame the pins',
}


def next_focus(points: list[dict], lookback: int = 15, min_share: float = 0.34) -> dict:
    """Home 'next focus' (MVP-12): the single recurring issue across recent live shots. Reuses each shot's own
    recommendation copy (no invented numbers/text) — only the short focus TITLE is templated. Returns a
    'building' status under 3 recent shots; 'Keep repeating' when recent shots are mostly striking."""
    recent = points[-lookback:]
    if len(recent) < 3:
        return {'status': 'building', 'reason': 'Not enough recent shots to pick a focus yet.'}
    states, reps = {}, {}
    for p in recent:
        ins = p.get('record', {}).get('insights') or {}
        st = ins.get('state')
        if not st or st == 'strike_repeat':           # strikes aren't a problem to focus on
            continue
        states[st] = states.get(st, 0) + 1
        if st not in reps:
            rec0 = (ins.get('recommendations') or [{}])[0] or {}
            reps[st] = {'reason': rec0.get('reason'), 'expected': rec0.get('expected')}
    if not states:
        return {'status': 'ok', 'focus': 'Keep repeating', 'state': 'strike_repeat', 'based_on': len(recent),
                'detail': 'Your recent shots are hitting — repeat your line and speed.'}
    dom, n = max(states.items(), key=lambda kv: kv[1])
    if n / len(recent) < min_share:
        return {'status': 'ok', 'focus': 'Mixed results', 'state': None, 'based_on': len(recent),
                'detail': 'No single issue stands out in your recent shots — keep logging shots.'}
    rep = reps.get(dom, {})
    return {'status': 'ok', 'focus': _FOCUS_TITLES.get(dom, 'Next focus'), 'state': dom,
            'detail': rep.get('reason'), 'expected': rep.get('expected'),
            'based_on': len(recent), 'share': round(n / len(recent), 2)}


def consistency(shots: list[dict]) -> dict:
    """dispersion at each checkpoint (boards) + a 0-100 repeatability score (lower spread = higher score)"""
    d = {k: float(np.std(_vals(shots, m))) for k, m in KEY.items() if len(_vals(shots, m)) >= 3}
    if not d: return {}
    score = 100 * np.exp(-np.mean(list(d.values())) / 2.0)
    bp = [(s['key_points']['breakpoint']['board'], s['key_points']['breakpoint']['z_ft']) for s in shots
          if s['key_points']['breakpoint']['board'] is not None]
    ell = None
    if len(bp) >= 3:
        A = np.array(bp); C = np.cov(A.T); w, V = np.linalg.eigh(C)
        ell = dict(center=A.mean(0).round(2).tolist(), axes=(2 * np.sqrt(np.maximum(w, 0))).round(2).tolist(),
                   angle_deg=round(float(np.degrees(np.arctan2(V[1, 1], V[0, 1]))), 1))     # ~86% ellipse (2 sigma)
    return dict(dispersion_boards={k: round(v, 2) for k, v in d.items()}, repeatability_score=round(float(score), 1),
                breakpoint_ellipse=ell)

def heatmap(shots: list[dict], z_step=1.0, board_step=1.0) -> dict:
    """lane-usage heatmap: how often the smoothed ball path occupies each (distance, board) cell"""
    zs = np.arange(0, 60 + z_step, z_step); bs = np.arange(1, 40 + board_step, board_step)
    grid = np.zeros((len(zs) - 1, len(bs) - 1))
    for s in shots:
        sm = s['trajectory']['smoothed']
        if not sm: continue
        z = np.array([p['z_ft'] for p in sm]); b = np.array([p['board'] for p in sm])
        zq = (zs[:-1] + zs[1:]) / 2; ok = (zq >= z.min()) & (zq <= z.max())
        bq = np.interp(zq[ok], z, b)
        for zi, bi in zip(np.where(ok)[0], bq):
            j = int(np.clip((bi - 1) // board_step, 0, len(bs) - 2)); grid[zi, j] += 1
    return dict(z_edges=zs.tolist(), board_edges=bs.tolist(), counts=grid.astype(int).tolist(), n_shots=len(shots))

def trends(shots: list[dict], metric: str, window=5) -> list:
    v = [s['metrics'].get(metric, {}).get('value') for s in shots]
    out = []
    for i in range(len(v)):
        w = [x for x in v[max(0, i - window + 1):i + 1] if x is not None]
        out.append(round(float(np.mean(w)), 2) if w else None)
    return out
