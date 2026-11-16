"""Rev-rate honesty: a clear spin pattern is read; no pattern is reported unavailable, never the
search-band ceiling. This guards the '672 RPM' bug, where a flat autocorrelation let argmax slide to the
highest-frequency rail (600 lane-rpm × 1.12 = 672) and shipped as a confident wrong reading (DEC-026)."""
import numpy as np
import pytest
from lanesight_core.cv.revrate import rev_rate


def _crops(period_s=None, n=60, fps=60.0, size=64, seed=0):
    """A synthetic ball-crop series. With period_s set, the hue/sat pattern repeats once per revolution
    (a real spin); with period_s None, each frame is independent noise (no repeat to find)."""
    rng = np.random.RandomState(seed)
    base = rng.randint(0, 180, (size, size)).astype(np.uint8)       # a fixed hue texture to rotate
    sat = rng.randint(80, 200, (size, size)).astype(np.uint8)
    out = []
    for k in range(n):
        t = k / fps
        if period_s is None:
            h = rng.randint(0, 180, (size, size)).astype(np.uint8)  # fresh noise every frame: no periodicity
        else:
            shift = int(round((t / period_s) * size)) % size        # rotate the texture once per period
            h = np.roll(base, shift, axis=1)
        bgr = np.stack([h, sat, np.full_like(h, 200)], axis=-1)     # H,S,V packed as 3 channels for cvtColor
        import cv2
        out.append((t, cv2.cvtColor(bgr, cv2.COLOR_HSV2BGR)))
    return out


def test_clear_spin_reads_an_interior_period():
    rpm, info = rev_rate(_crops(period_s=1 / 6.0))      # 6 Hz = 360 lane-rpm, mid-band
    assert not info['at_rail']
    assert 3 < info['argmax'] < len(info['score']) - 4
    assert 300 < rpm < 420                               # near 360, not pinned to the 600 ceiling


def test_no_in_band_period_lands_on_the_rail():
    # A spin far slower than the 4-10 Hz band: no in-band period matches, so the autocorrelation just
    # decays with lag and argmax slides to the shortest-period rail (the real '672' signature).
    _, info = rev_rate(_crops(period_s=0.5))             # 2 Hz, below fmin -> nothing to lock onto in band
    assert info['at_rail']                               # caller reports rev rate unavailable, not 60/P


def test_short_clip_never_reports_a_period_without_data():
    """2026-10-30: with few crops, long periods have no autocorrelation data (NaN score). np.argmax picked the first
    NaN and reported it as a rev rate. Now: no rail-free peak inside the searchable band -> at_rail (unavailable)."""
    import numpy as np
    from lanesight_core.cv.revrate import rev_rate
    rng = np.random.default_rng(0)
    crops = [(i / 60.0, rng.integers(0, 255, (40, 40, 3), dtype=np.uint8)) for i in range(24)]   # pure noise
    rev, info = rev_rate(crops)
    assert not np.isfinite(info['score']).all()          # the NaN tail exists for a clip this short
    assert info['at_rail'] or np.isfinite(info['score'][info['argmax']])
    assert np.isfinite(info['score'][info['argmax']]) or info['at_rail']
    assert info['argmax'] <= int(np.where(np.isfinite(info['score']))[0].max())
