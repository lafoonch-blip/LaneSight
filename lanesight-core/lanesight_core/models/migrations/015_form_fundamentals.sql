-- 015 Form fundamentals v1 (DEC-057, FORM_BENCHMARKS §0). Additive + idempotent.
-- Adds the owner-editable swing-timing baseline to profiles and seeds the timing-checkpoint on-time
-- windows into engine_config. No data is dropped or rewritten; safe to re-run.
--
-- NOT applied live by this change (per task contract). Validate with:
--   PG16_BIN=/opt/homebrew/opt/postgresql@16/bin lanesight_core/models/tests/run_rls_tests.sh

-- profiles: the bowler's Form swing-timing baseline (Profile › Form baseline). jsonb holds either the
-- entered phase splits {"mode":"entered","pushaway_time":…,"backswing_time":…,"downswing_time":…,
-- "release_time":…,"total":…,"set_at":…} or {"mode":"average"} ("use my average"). NULL = none set yet.
alter table profiles
  add column if not exists form_baseline jsonb;

-- engine_config: form timing-checkpoint on-time windows (owner-editable, PROVISIONAL until tuned on real
-- clips). early if offset < low, late if offset > high, on time in between. Mirrors rules_seed.ENGINE_CONFIG
-- 'form_timing_windows'. Guarded on-conflict so a re-run (or a later owner edit) is preserved/refreshed.
insert into engine_config (key, value) values ('form_timing_windows',
  '{"T1": {"unit": "in", "low": -1.0, "high": 1.0},
    "T2": {"unit": "step", "low": 0.0, "high": 0.0},
    "T3": {"unit": "s", "low": -0.05, "high": 0.05},
    "T4": {"unit": "s", "low": 0.0, "high": 0.10},
    "provisional": true}'::jsonb)
  on conflict (key) do update set value = excluded.value, updated_at = now();
