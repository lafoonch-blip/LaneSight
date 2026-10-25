-- Permanent RLS test for the Dev Build v0 schema (migrations 006-010). Run after applying
-- _shim.sql + schema.sql + migrations 002-010 to a throwaway Postgres (see run_rls_tests.sh).
-- Any failure RAISEs an exception so the run exits non-zero. Guarantees under test:
--   1. A normal (authenticated) user cannot read the owner-only rule/engine tables.
--   2. achievement_definition.params is NOT readable by authenticated (column-level grant excludes it),
--      so any future column stays hidden unless deliberately granted.
--   3. Only active/coming_later achievement rows are visible to authenticated (draft/retired hidden).
--   4. achievement_definition_public is readable, exposes no params column, and only active/coming_later.
--   5. A user sees ONLY their own rows in personal_baseline / finding / score_snapshot.
\set ON_ERROR_STOP on

-- seed as superuser
insert into auth.users(id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222') on conflict do nothing;
insert into profiles(user_id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222') on conflict do nothing;

insert into benchmark_reference(metric) values ('m');
insert into form_rule(id, trigger) values ('RULE-test','{}'::jsonb);
insert into engine_config(key, value) values ('k','{}'::jsonb);
insert into style_template(id, name) values ('two_handed','Two handed') on conflict do nothing;
insert into drill(id, name, description) values ('DRILL-x','x','x') on conflict do nothing;

-- four achievement rows across statuses: 2 visible (active, coming_later), 2 hidden (draft, retired)
insert into achievement_definition(id,category,name,description,rule_type,params,status) values
  ('ACH-ACT','c','Active','d','one_time','{"secret":1}'::jsonb,'active'),
  ('ACH-SOON','c','Soon','d','one_time','{"secret":1}'::jsonb,'coming_later'),
  ('ACH-DRAFT','c','Draft','d','one_time','{"secret":1}'::jsonb,'draft'),
  ('ACH-RET','c','Retired','d','one_time','{"secret":1}'::jsonb,'retired') on conflict do nothing;

insert into personal_baseline(user_id, metric) values
  ('11111111-1111-1111-1111-111111111111','m'),
  ('22222222-2222-2222-2222-222222222222','m');
insert into finding(user_id, metric) values
  ('11111111-1111-1111-1111-111111111111','m'),
  ('22222222-2222-2222-2222-222222222222','m');
insert into score_snapshot(user_id, formula_version, trigger, eligible, eligibility, inputs) values
  ('11111111-1111-1111-1111-111111111111','L-dev-0','shot',false,'{}','{}'),
  ('22222222-2222-2222-2222-222222222222','L-dev-0','shot',false,'{}','{}');

-- become authenticated user A
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', false);
set role authenticated;

-- 1. owner-only rule/engine tables unreadable (permission denied OR 0 rows = can't read)
do $$ declare n int; t text; begin
  foreach t in array array['benchmark_reference','form_rule','engine_config','style_template',
                           'style_template_metric','drill','score_formula_version','engine_event'] loop
    begin
      execute format('select count(*) from %I', t) into n;
      if n > 0 then raise exception 'FAIL: authenticated read % rows from %', n, t;
      else raise notice 'PASS: % returned 0 rows (RLS)', t; end if;
    exception when insufficient_privilege then raise notice 'PASS: % denied', t;
    end;
  end loop;
end $$;

-- 2. params must be unreadable to authenticated (column-level grant excludes it)
do $$ begin
  perform params from achievement_definition limit 1;
  raise exception 'FAIL: authenticated read achievement_definition.params';
exception when insufficient_privilege then raise notice 'PASS: achievement_definition.params denied';
end $$;

-- 3. only active/coming_later rows visible on the base table (draft/retired hidden by policy).
-- Membership check (robust to the real 011 catalog also being present): the test active/coming_later rows
-- are visible, the test draft/retired rows are not.
do $$ declare vis int; hid int; begin
  select count(*) into vis from achievement_definition where id in ('ACH-ACT','ACH-SOON');
  select count(*) into hid from achievement_definition where id in ('ACH-DRAFT','ACH-RET');
  if vis = 2 and hid = 0 then raise notice 'PASS: base table shows active/coming_later, hides draft/retired';
  else raise exception 'FAIL: base table visibility wrong (visible=%, hidden-leaked=%)', vis, hid; end if;
end $$;

-- 4. public view: no params column, readable, only active/coming_later (membership check).
do $$ declare has_params int; vis int; hid int; begin
  select count(*) into has_params from information_schema.columns
    where table_name = 'achievement_definition_public' and column_name = 'params';
  if has_params > 0 then raise exception 'FAIL: achievement_definition_public exposes params'; end if;
  select count(*) into vis from achievement_definition_public where id in ('ACH-ACT','ACH-SOON');
  select count(*) into hid from achievement_definition_public where id in ('ACH-DRAFT','ACH-RET');
  if vis <> 2 or hid <> 0 then raise exception 'FAIL: public view visibility wrong (visible=%, leaked=%)', vis, hid; end if;
  raise notice 'PASS: achievement_definition_public ok (no params column; active/coming_later only)';
end $$;

-- 5. own-rows only
do $$ declare n int; t text; begin
  foreach t in array array['personal_baseline','finding','score_snapshot'] loop
    execute format('select count(*) from %I', t) into n;
    if n = 1 then raise notice 'PASS: % shows only own rows (1)', t;
    else raise exception 'FAIL: % showed % rows to user A (expected 1)', t, n; end if;
  end loop;
end $$;

-- 6. feedback store (migration 014, DEC-059): own-rows-only read, triage columns hidden by column grant,
--    insert own works / insert-as-other rejected, and NO client delete.
reset role;
-- seed one feedback row for each user as superuser (session_id null -> no session dependency needed).
insert into feedback(id, source, user_id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','general','11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','general','22222222-2222-2222-2222-222222222222')
  on conflict do nothing;
-- owner-only triage columns must carry their defaults and stay owner-managed.
do $$ declare s text; begin
  select triage_status into s from feedback where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  if s = 'new' then raise notice 'PASS: feedback.triage_status defaults to new';
  else raise exception 'FAIL: feedback.triage_status default wrong (%)', s; end if;
end $$;

select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', false);
set role authenticated;

-- 6a. own rows only
do $$ declare n int; begin
  select count(*) into n from feedback;
  if n = 1 then raise notice 'PASS: feedback shows only own rows (1)';
  else raise exception 'FAIL: feedback showed % rows to user A (expected 1)', n; end if;
end $$;

-- 6b. triage columns hidden from the bowler (column-level grant excludes them)
do $$ begin
  perform triage_status from feedback limit 1;
  raise exception 'FAIL: authenticated read feedback.triage_status';
exception when insufficient_privilege then raise notice 'PASS: feedback.triage_status denied';
end $$;
do $$ begin
  perform owner_notes from feedback limit 1;
  raise exception 'FAIL: authenticated read feedback.owner_notes';
exception when insufficient_privilege then raise notice 'PASS: feedback.owner_notes denied';
end $$;

-- 6c. bowler can insert their own feedback, but not on behalf of another user (RLS with-check)
do $$ begin
  insert into feedback(source, user_id, text) values
    ('shot_note','11111111-1111-1111-1111-111111111111','mine');
  raise notice 'PASS: bowler can insert own feedback';
end $$;
do $$ begin
  insert into feedback(source, user_id, text) values
    ('shot_note','22222222-2222-2222-2222-222222222222','not mine');
  raise exception 'FAIL: bowler inserted feedback for another user';
exception when insufficient_privilege then raise notice 'PASS: insert-as-other denied (privilege)';
         when check_violation then raise notice 'PASS: insert-as-other denied (RLS with-check)';
end $$;

-- 6d. no client delete (privilege revoked)
do $$ begin
  delete from feedback where user_id = '11111111-1111-1111-1111-111111111111';
  raise exception 'FAIL: bowler deleted feedback (no client delete allowed)';
exception when insufficient_privilege then raise notice 'PASS: client delete denied';
end $$;

reset role;
\echo 'ALL RLS TESTS PASSED'
