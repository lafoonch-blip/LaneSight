-- 033 — DEC-108: LaneSight Score unlocks after 5 eligible shots (was 20); tier provisional until 20.
-- The LIVE source of the floors is score_formula_version.params (PgStore.score_formula_params reads it, not the
-- code default), so the threshold change must update this row. Idempotent. (migration-007 seed is also updated
-- for fresh DBs.) Does NOT touch the coach "your normal" baseline (10) or the plausibility speed baseline (20).
update score_formula_version
set params = jsonb_set(
               jsonb_set(params, '{eligibility_floors}',
                         '{"s_perf":5,"a_acc":5,"c_cons":5,"p_power":5}'::jsonb),
               '{tier_provisional_until}', '20'::jsonb)
where id = 'L-dev-0';
-- After this, recompute every account's score so the new floors reach existing snapshots
-- (ops/recompute_scores.py, or they recompute on each account's next shot).
