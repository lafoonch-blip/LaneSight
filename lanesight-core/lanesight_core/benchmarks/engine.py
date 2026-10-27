"""Benchmark resolution, classification and prioritization (BENCHMARKS spec §3-5, DEC-046).

Deviation is not a fault: a value becomes a finding only when it is Outside the benchmark *and* repeated
(default >=3 of the last comparable shots), or when its shot-to-shot spread exceeds the personal band.
Only Measured metrics are classified; unavailable/low-confidence values never produce a finding (DEC-042).
One primary focus at a time; downstream symptoms are suppressed under their upstream cause.
"""
from __future__ import annotations
import numpy as np

BENCHMARK_VERSION = 'benchmarks-0.1.0'
# Resolution order (BENCHMARKS §3): coach target wins, else personal baseline (if established), else style
# template, else sourced reference, else no benchmark (show value only).
LAYER_ORDER = ['coach', 'personal', 'style', 'reference']


def personal_baseline(values, min_n: int = 10) -> dict:
    """L2 baseline (BENCHMARKS §3.3): median and robust band (median +/- 1.5*MAD); SD for consistency.
    Established only at >= min_n qualifying shots (owner-configurable, DEC-046); otherwise 'building'."""
    a = np.asarray([v for v in values if v is not None], float)
    n = int(a.size)
    if n == 0:
        return dict(status='building', n=0, established=False, median=None, mad=None, sd=None,
                    band_low=None, band_high=None)
    median = float(np.median(a))
    mad = float(1.4826 * np.median(np.abs(a - median)))
    band = 1.5 * mad
    established = n >= min_n
    return dict(status='ok' if established else 'building', n=n, established=established,
                median=round(median, 3), mad=round(mad, 3), sd=round(float(np.std(a)), 3),
                band_low=round(median - band, 3), band_high=round(median + band, 3))


def resolve_benchmark(coach=None, personal=None, style=None, reference=None) -> tuple[str | None, dict | None]:
    """Pick the governing benchmark per BENCHMARKS §3. personal is used only when established.
    Each argument is a benchmark dict ({low,high} or {target,tol,...}) or None. Returns (layer_name, bench)."""
    candidates = {'coach': coach,
                  'personal': personal if (personal and personal.get('established')) else None,
                  'style': style, 'reference': reference}
    for layer in LAYER_ORDER:
        b = candidates.get(layer)
        if b:
            return layer, b
    return None, None


def _band(bench) -> tuple[float, float]:
    if 'low' in bench and 'high' in bench:
        return float(bench['low']), float(bench['high'])
    t = float(bench['target']); tol = float(bench.get('tol', 0))
    return t - tol, t + tol


def classify_level(value, bench, uncertainty: float = 0.0,
                   streak_outside: int = 0, repetition: int = 3) -> dict:
    """Level signal: Within / Watch / Outside. Outside requires the repetition rule to be met; a single
    out-of-band shot is only Watch. If |value - center| < measurement uncertainty, classify Within
    (don't flag inside the error bar, BENCHMARKS §4.4)."""
    if value is None or bench is None:
        return dict(status='unavailable')
    low, high = _band(bench)
    center = (low + high) / 2
    if low <= value <= high:
        return dict(status='within', streak_outside=0, distance=round(value - center, 3))
    past_edge = (value - high) if value > high else (low - value)   # distance outside the band
    if past_edge < uncertainty:                                     # inside the measurement error bar
        return dict(status='within', streak_outside=0, distance=round(value - center, 3), within_error=True)
    side = 'high' if value > high else 'low'
    dist_bands = (value - high) / (high - low) if value > high else (value - low) / (high - low)
    new_streak = streak_outside + 1
    status = 'outside' if new_streak >= repetition else 'watch'
    return dict(status=status, side=side, streak_outside=new_streak,
                distance=round(value - center, 3), distance_bands=round(dist_bands, 2))


def classify_consistency(spread, baseline_spread, factor: float = 1.5) -> dict:
    """Consistency signal (often more useful than level): shot-to-shot spread vs the baseline spread."""
    if spread is None or baseline_spread is None or baseline_spread <= 0:
        return dict(status='unavailable')
    ratio = spread / baseline_spread
    status = 'outside' if ratio > factor else ('watch' if ratio > 1.0 else 'within')
    return dict(status=status, ratio=round(ratio, 2))


def prioritize(findings: list[dict], weights: dict | None = None, max_secondary: int = 2) -> dict:
    """Pick one primary focus + up to max_secondary notes (BENCHMARKS §5.3).
    A finding scores severity*confidence*outcome_impact*upstream_weight (missing fields default to 1.0,
    except severity which defaults to its distance_bands). A coach `focus` flag wins outright. Findings
    marked downstream of the primary's metric are suppressed (root cause before symptom)."""
    if not findings:
        return dict(primary=None, secondary=[], suppressed=[])
    w = weights or {}

    def score(f):
        sev = f.get('severity', abs(f.get('distance_bands', 1.0)))
        return (sev * f.get('confidence', 1.0) * f.get('outcome_impact', 1.0)
                * f.get('upstream_weight', 1.0) * w.get(f.get('metric'), 1.0))

    focus = [f for f in findings if f.get('focus')]
    ranked = sorted(findings, key=score, reverse=True)
    primary = focus[0] if focus else ranked[0]
    pm = primary.get('metric')
    rest, suppressed = [], []
    for f in ranked:
        if f is primary:
            continue
        if pm is not None and pm in (f.get('downstream_of') or []):
            suppressed.append(f)            # symptom explained by the primary cause
        else:
            rest.append(f)
    return dict(primary=primary, secondary=rest[:max_secondary], suppressed=suppressed + rest[max_secondary:])
