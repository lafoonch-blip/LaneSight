"""Server-side replay renders (M6-03): top-down lane with trajectory, key points and pin leave; session heatmap.
Lane is drawn with the foul line at the bottom and pins at the top, boards 39 (left) to 1 (right) as seen by the bowler."""
from __future__ import annotations
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Circle
from ..scoring.pins import PIN_BOARD, PIN_ROW

NAVY, LANE_BLUE, ELECTRIC, GRAY, ICE = '#0B1320', '#007BFF', '#00D2FF', '#A7B0BE', '#F7F9FC'
WOOD = '#C99A5B'
ARROW_BOARDS = [5, 10, 15, 20, 25, 30, 35]
ARROW_FT = {5: 12.67, 10: 13.33, 15: 14.0, 20: 14.67, 25: 14.0, 30: 13.33, 35: 12.67}   # V-shaped arrow layout (approx.)

def _x(board): return 40 - board          # plot x: left gutter on the left

def _lane(ax, z_max=62.8):
    ax.add_patch(Rectangle((0.5, 0), 39, z_max, color=WOOD, zorder=0))
    for b in range(1, 40): ax.plot([_x(b) - 0.5] * 2, [0, 60], color='#B38448', lw=0.3, zorder=1)
    for b in ARROW_BOARDS:
        z = ARROW_FT[b]; ax.fill([_x(b) - 0.35, _x(b) + 0.35, _x(b)], [z, z, z + 0.9], color=NAVY, zorder=2)
    for b in (3, 5, 8, 11, 14, 26, 29, 32, 35, 37): ax.plot(_x(b), 7, 'o', ms=1.6, color=NAVY, zorder=2)
    ax.plot([0.5, 39.5], [0, 0], color=NAVY, lw=1.5)
    ax.set_xlim(-1, 41); ax.set_ylim(-2, z_max + 1); ax.set_aspect(2.2); ax.axis('off')

def _pins(ax, standing=(), uncertain=()):
    for p in range(1, 11):
        z = 60 + (PIN_ROW[p] - 1) * 10.392 / 12
        col = ICE if p in standing else ('#F2C94C' if p in uncertain else '#00000030')
        ax.add_patch(matplotlib.patches.Ellipse((_x(PIN_BOARD[p]), z), 1.6, 0.75, color=col, zorder=5, ec=NAVY if p in standing else 'none'))

def shot_png(rec: dict, path: str):
    fig, ax = plt.subplots(figsize=(4.2, 9), facecolor=NAVY)
    _lane(ax)
    sm = rec['trajectory']['smoothed']
    if sm:
        ax.plot([_x(p['board']) for p in sm], [p['z_ft'] for p in sm], color=ELECTRIC, lw=2.6, zorder=4, solid_capstyle='round')
    raw = rec['trajectory']['lane']
    ax.plot([_x(p['board']) for p in raw], [p['z_ft'] for p in raw], '.', color=LANE_BLUE, ms=2, zorder=3, alpha=0.6)
    kp = rec['key_points']
    for name, lab in (('laydown', 'Laydown'), ('arrows', 'Arrows'), ('breakpoint', 'Breakpoint'), ('entry', 'Entry')):
        k = kp[name]
        if k.get('board') is None or k.get('z_ft') is None: continue
        ax.plot(_x(k['board']), k['z_ft'], 'o', ms=7, color=ICE, mec=NAVY, zorder=6)
        extra = f" {k['angle_deg']:.1f}°" if name == 'entry' and k.get('angle_deg') else ''
        ax.annotate(f"{lab} {k['board']:.1f}{extra}" + (f" @{k['z_ft']:.0f} ft" if name == 'breakpoint' else ''),
                    (_x(k['board']), k['z_ft']), xytext=(8, -3), textcoords='offset points', color=ICE, fontsize=8, zorder=7,
                    bbox=dict(boxstyle='round,pad=0.2', fc=NAVY, ec='none', alpha=0.85))
    pins = rec.get('pins') or {}
    _pins(ax, pins.get('standing', []), pins.get('uncertain', []))
    mt = rec['metrics']; fmt = lambda k, u, d=1: (f"{mt[k]['value']:.{d}f} {u}" if mt.get(k) and mt[k]['value'] is not None else '—')
    title = f"{fmt('ball_speed', 'mph')}   {fmt('rev_rate', 'rpm', 0)}   loft {fmt('loft', 'ft')}"
    leave = 'Strike' if pins.get('strike') else ('Leave ' + '-'.join(map(str, pins.get('standing', []))) if pins else '')
    ax.set_title(title + '\n' + leave, color=ICE, fontsize=10)
    rec0 = (rec.get('insights') or {}).get('recommendations') or [{}]
    fig.text(0.05, 0.015, rec0[0].get('reason', '')[:120], color=GRAY, fontsize=7, wrap=True)
    fig.savefig(path, dpi=130, facecolor=NAVY, bbox_inches='tight'); plt.close(fig)

def heatmap_png(hm: dict, path: str, title='Lane usage'):
    C = np.array(hm['counts'], float)
    fig, ax = plt.subplots(figsize=(4.2, 9), facecolor=NAVY)
    _lane(ax, 60)
    if C.max() > 0:
        z = np.array(hm['z_edges']); b = np.array(hm['board_edges'])
        X, Y = np.meshgrid(40 - b, z)
        ax.pcolormesh(X, Y, np.ma.masked_equal(C, 0), cmap='plasma', alpha=0.75, zorder=3, shading='flat')
    ax.set_title(f"{title} ({hm['n_shots']} shots)", color=ICE, fontsize=10)
    fig.savefig(path, dpi=130, facecolor=NAVY, bbox_inches='tight'); plt.close(fig)
