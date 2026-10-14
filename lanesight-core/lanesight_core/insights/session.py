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
