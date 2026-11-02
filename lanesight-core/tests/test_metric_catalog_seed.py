"""DEC-122 §6: the metric_catalog seed in migration 036 must stay in lock-step with the engine's own metric
catalogs — the shot catalog (lanesight_core.cv.pipeline._METRIC_CATALOG) and the form catalog
(lanesight_core.form.FORM_P1). If an engine metric is added/renamed/re-unit'd and the seed isn't updated (or vice
versa), outcome tracking would silently miss or mislabel a metric. This test fails on any drift, in either
direction, on both key AND unit."""
import os
import re

from lanesight_core.cv.pipeline import _METRIC_CATALOG as SHOT_CATALOG
from lanesight_core.form import FORM_P1

MIGRATION = os.path.join(os.path.dirname(__file__), '..', 'lanesight_core', 'models', 'migrations',
                         '036_dec122_outcome_tracking.sql')

# A seeded row literal: ('<key>', '<shot|form>', '<unit or NULL>', array[...], ...). We only need key/mode/unit.
_ROW = re.compile(r"\(\s*'([a-z_0-9]+)'\s*,\s*'(shot|form)'\s*,\s*(?:'([a-z_]+)'|NULL)\s*,", re.IGNORECASE)


def _seed_rows():
    """Parse the INSERT ... VALUES block of metric_catalog into {(key, mode): unit}."""
    with open(MIGRATION) as f:
        sql = f.read()
    start = sql.index('insert into public.metric_catalog')
    end = sql.index('on conflict', start)
    block = sql[start:end]
    rows = {}
    for key, mode, unit in _ROW.findall(block):
        rows[(key, mode)] = unit
    assert rows, 'no metric_catalog rows parsed from the migration — parser/seed format drift'
    return rows


def test_shot_seed_matches_engine_catalog():
    seed = {(k, 'shot'): u for (k, m), u in _seed_rows().items() if m == 'shot'}
    engine = {(k, 'shot'): u for k, u in SHOT_CATALOG}
    assert seed == engine, (
        'shot metric_catalog seed drifted from pipeline._METRIC_CATALOG.\n'
        f'  only in seed:   {sorted(set(seed) - set(engine))}\n'
        f'  only in engine: {sorted(set(engine) - set(seed))}\n'
        f'  unit mismatch:  {sorted((k, seed[k], engine[k]) for k in set(seed) & set(engine) if seed[k] != engine[k])}')


def test_form_seed_matches_engine_catalog():
    seed = {(k, 'form'): u for (k, m), u in _seed_rows().items() if m == 'form'}
    engine = {(k, 'form'): u for k, u in FORM_P1}
    assert seed == engine, (
        'form metric_catalog seed drifted from form.FORM_P1.\n'
        f'  only in seed:   {sorted(set(seed) - set(engine))}\n'
        f'  only in engine: {sorted(set(engine) - set(seed))}\n'
        f'  unit mismatch:  {sorted((k, seed[k], engine[k]) for k in set(seed) & set(engine) if seed[k] != engine[k])}')


def test_seed_has_no_duplicate_keys():
    rows = _seed_rows()
    # _seed_rows() dedups via dict; compare against the raw literal count to catch an accidental duplicate row.
    with open(MIGRATION) as f:
        sql = f.read()
    block = sql[sql.index('insert into public.metric_catalog'):sql.index('on conflict')]
    assert len(_ROW.findall(block)) == len(rows), 'duplicate (metric_key, capture_mode) in the seed'
