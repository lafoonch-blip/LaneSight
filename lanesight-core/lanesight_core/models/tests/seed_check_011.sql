-- Seed-presence check for migration 011 (run as the owner/superuser, i.e. the service-role posture).
-- Confirms the dev-build rule/achievement content landed with the exact rule_type + params the engines
-- read. Any mismatch RAISEs so the harness exits non-zero. Run AFTER 002..011 are applied.
\set ON_ERROR_STOP on

-- achievement_definition: active catalog + coming_later present, with the exact rule wiring.
do $$ declare active_n int; coming_n int; begin
  select count(*) into active_n from achievement_definition where status = 'active';
  select count(*) into coming_n from achievement_definition where status = 'coming_later';
  if active_n < 28 then raise exception 'FAIL: expected >=28 active achievements, got %', active_n; end if;
  if coming_n < 30 then raise exception 'FAIL: expected the coming_later set, got %', coming_n; end if;
  raise notice 'PASS: achievement_definition seeded (% active, % coming_later)', active_n, coming_n;
end $$;

-- exact rule_type + params on representative rows the evaluators depend on.
do $$ declare rt text; tgt text; thr text; ir text; begin
  select rule_type, params->>'target' into rt, tgt from achievement_definition where id = 'ACH-010';
  if rt <> 'count_qualifying' or tgt <> '10' then raise exception 'FAIL: ACH-010 wiring (% / %)', rt, tgt; end if;
  select rule_type, params->>'threshold' into rt, thr from achievement_definition where id = 'ACH-017';
  if rt <> 'best_measured' or thr <> '450' then raise exception 'FAIL: ACH-017 wiring (% / %)', rt, thr; end if;
  select rule_type, params->>'target' into rt, tgt from achievement_definition where id = 'ACH-053';
  if rt <> 'cumulative' or tgt <> '100' then raise exception 'FAIL: ACH-053 wiring (% / %)', rt, tgt; end if;
  select rule_type into rt from achievement_definition where id = 'ACH-056';
  if rt <> 'first_tier' then raise exception 'FAIL: ACH-056 not first_tier (%)', rt; end if;
  -- coming_later rows carry an inactive_reason
  select inactive_reason into ir from achievement_definition where id = 'ACH-005';
  if ir is null then raise exception 'FAIL: ACH-005 coming_later has no inactive_reason'; end if;
  raise notice 'PASS: achievement rule_type + params wiring correct';
end $$;

-- engine_config: power ranges anchored to 15 lb ball + the other owner knobs.
do $$ declare wlb jsonb; bn text; rr text; fh text; begin
  select value->'weight_lb' into wlb from engine_config where key = 'power_ref_ranges';
  if wlb is null or wlb->>0 <> '14.0' or wlb->>1 <> '16.0' then
    raise exception 'FAIL: power_ref_ranges.weight_lb not [14,16] (%)', wlb; end if;
  select value::text into bn from engine_config where key = 'baseline_min_n';
  select value::text into rr from engine_config where key = 'repetition_rule';
  select value::text into fh from engine_config where key = 'focus_hold_shots';
  if bn <> '10' or rr <> '3' or fh <> '10' then
    raise exception 'FAIL: engine_config knobs (baseline=% repetition=% focus=%)', bn, rr, fh; end if;
  raise notice 'PASS: engine_config power_ref_ranges (weight anchored to 15 lb) + knobs seeded';
end $$;

-- The L-dev-0 formula now carries the power ranges (so P' and the overall score can compute).
do $$ declare pr jsonb; begin
  select params->'power_ref_ranges' into pr from score_formula_version where id = 'L-dev-0';
  if pr is null or pr->'weight_lb'->>1 <> '16.0' then
    raise exception 'FAIL: L-dev-0 params.power_ref_ranges not set from 011 (%)', pr; end if;
  raise notice 'PASS: L-dev-0 formula reads the seeded power ranges';
end $$;

-- style templates / drills / form rules / references.
do $$ declare st int; stm int; dr int; fr int; br int; elite int; begin
  select count(*) into st from style_template where id in ('one_handed_thumb','one_handed_no_thumb','two_handed');
  select count(*) into stm from style_template_metric;
  select count(*) into dr from drill;
  select count(*) into fr from form_rule where status = 'draft';
  select count(*) into br from benchmark_reference;
  select count(*) into elite from benchmark_reference where shown_to_user = false;
  if st <> 3 then raise exception 'FAIL: style_template count % (expected 3)', st; end if;
  if stm < 4 then raise exception 'FAIL: style_template_metric count %', stm; end if;
  if dr < 8 then raise exception 'FAIL: drill count %', dr; end if;
  if fr < 8 then raise exception 'FAIL: draft form_rule count %', fr; end if;
  if br < 8 then raise exception 'FAIL: benchmark_reference count %', br; end if;
  if elite < 2 then raise exception 'FAIL: expected >=2 owner-only (shown_to_user=false) references, got %', elite; end if;
  raise notice 'PASS: style(%)/drill(%)/form_rule(%)/reference(% incl % owner-only) seeded', st, dr, fr, br, elite;
end $$;

\echo 'ALL 011 SEED CHECKS PASSED'
