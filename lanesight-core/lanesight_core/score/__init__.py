"""LaneSight dev/Beta score engine (L-dev-0, DEC-048) and tier evaluation (DEC-051).

Pure and DB-free: functions take ShotRecord dicts + a params dict and return plain dicts.
The runner supplies params (from score_formula_version / engine_config) and owns persistence.
The target formula remains DEC-038; L-dev-0 is the no-pinfall dev/Beta stand-in.
"""
from .ldev0 import (
    SCORE_VERSION, DEFAULT_LDEV0_PARAMS,
    accuracy, consistency, performance, power_component, compute,
)
from .tiers import tier_for, evaluate_tier

__all__ = [
    'SCORE_VERSION', 'DEFAULT_LDEV0_PARAMS',
    'accuracy', 'consistency', 'performance', 'power_component', 'compute',
    'tier_for', 'evaluate_tier',
]
