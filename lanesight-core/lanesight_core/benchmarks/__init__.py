"""Benchmarks & recommendations engine (BENCHMARKS_AND_RECOMMENDATIONS_SPEC, DEC-046).

Pure and DB-free. Owner-only rule data (L0 references, L1 style templates, thresholds, prioritizer
weights) is passed in as plain dicts — the runner loads it from the owner-only tables and never ships it
to clients. This module only decides findings and cues from that data; it holds no rule content itself.
"""
from .engine import (
    BENCHMARK_VERSION, LAYER_ORDER,
    personal_baseline, resolve_benchmark, classify_level, classify_consistency, prioritize,
)

__all__ = [
    'BENCHMARK_VERSION', 'LAYER_ORDER',
    'personal_baseline', 'resolve_benchmark', 'classify_level', 'classify_consistency', 'prioritize',
]
