"""Advisory spot check (DEC-045). NEVER blocks recording — it only suggests a better camera position.

Pure tip logic over already-measured framing features; the same tip is returned alongside failed or
degraded results so the bowler can improve the next clip. Thresholds are provisional/advisory (to be tuned
on real captures); `blocks` is always False by contract.
"""
from __future__ import annotations

SPOTCHECK_VERSION = 'spotcheck-0.1.0'


def spot_check(framing: dict) -> dict:
    """framing: {lane_visible_fraction (0-1), foul_line_visible (bool), foul_line_y_frac (0=top..1=bottom),
    tilt_deg (optional)}. Returns {blocks: False, tips: [...], status, version}. Tips are advisory only."""
    tips = []
    lvf = framing.get('lane_visible_fraction')
    foul_vis = framing.get('foul_line_visible')
    foul_y = framing.get('foul_line_y_frac')

    if foul_vis is False:
        tips.append('Tilt the phone down a little so the foul line is in frame.')
    elif foul_y is not None and foul_y > 0.9:
        tips.append('Raise the phone ~1 ft — the foul line is right at the bottom edge.')

    if lvf is not None:
        if lvf < 0.3:
            tips.append('Move back ~3 ft to get more of the lane in frame.')
        elif lvf > 0.95:
            tips.append('You can move in a little — nearly the whole frame is lane.')

    tilt = framing.get('tilt_deg')
    if tilt is not None and abs(tilt) > 8:
        tips.append('Level the phone — it looks tilted.')

    return dict(blocks=False, tips=tips, status='ok' if tips else 'looks_good', version=SPOTCHECK_VERSION)
