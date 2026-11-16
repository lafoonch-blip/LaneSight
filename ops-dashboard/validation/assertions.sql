-- Ops reporting DB assertions (§1) — run AFTER 025_ops_reporting.sql is applied, as the owner
-- (postgres / service_role). Read-only: raises on any violation, changes nothing. Shape + honesty +
-- security structure. The anon/authenticated "permission denied" proof is run separately (SET ROLE tests).

do $$
declare n int; bad int;
begin
  -- 1. private schema + 10 views + 9 RPCs exist.
  if to_regnamespace('ops') is null then raise exception 'schema ops missing'; end if;

  select count(*) into n from information_schema.views where table_schema = 'ops';
  if n < 10 then raise exception 'expected >=10 ops views, found %', n; end if;

  select count(*) into n from information_schema.routines
   where routine_schema = 'public' and routine_name like 'ops\_rpc\_%' escape '\';
  if n < 9 then raise exception 'expected >=9 ops_rpc_* functions, found %', n; end if;

  -- 2. every ops_rpc_* is SECURITY DEFINER (prosecdef) — else it would run with the caller's rights.
  select count(*) into bad from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname like 'ops\_rpc\_%' escape '\' and not p.prosecdef;
  if bad > 0 then raise exception 'SECURITY: % ops_rpc_* function(s) are not SECURITY DEFINER', bad; end if;

  -- 3. owner registry seeded with exactly the owner.py id.
  select count(*) into n from ops.app_owner where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
  if n <> 1 then raise exception 'ops.app_owner not seeded with the owner id'; end if;

  -- 4. schema ops is not reachable by the API roles (usage revoked).
  if has_schema_privilege('anon', 'ops', 'USAGE') then raise exception 'SECURITY: anon has USAGE on schema ops'; end if;
  if has_schema_privilege('authenticated', 'ops', 'USAGE') then raise exception 'SECURITY: authenticated has USAGE on schema ops'; end if;

  -- 5. honesty: staged accounts segregated — daily attempts == non-staged base attempts.
  select (select coalesce(sum(attempts),0) from ops.analysis_daily)
       - (select count(*) from ops.attempt where is_staged = false) into bad;
  if bad <> 0 then raise exception 'ops.analysis_daily attempts != non-staged base (staged leak/drop): %', bad; end if;

  -- 6. no fake 0 rate: attempts=0 -> failure_rate NULL.
  select count(*) into bad from ops.analysis_daily where attempts = 0 and failure_rate is not null;
  if bad > 0 then raise exception '% daily row(s) show failure_rate with 0 attempts', bad; end if;

  -- 7. failure_rate in [0,1]; analyzed+failures=attempts.
  select count(*) into bad from ops.analysis_daily where failure_rate is not null and (failure_rate < 0 or failure_rate > 1);
  if bad > 0 then raise exception '% daily failure_rate out of [0,1]', bad; end if;
  select count(*) into bad from ops.analysis_daily where analyzed + failures <> attempts;
  if bad > 0 then raise exception '% daily analyzed+failures != attempts', bad; end if;

  -- 8. coverage honest: 8 domains; every no_data domain has NULL backing_view. Freshness lists 4 sources.
  select count(*) into n from ops.coverage_status;
  if n <> 8 then raise exception 'expected 8 coverage domains, found %', n; end if;
  select count(*) into bad from ops.coverage_status where status = 'no_data' and backing_view is not null;
  if bad > 0 then raise exception '% no_data domain(s) wrongly claim a backing view', bad; end if;
  select count(*) into n from ops.freshness;
  if n <> 4 then raise exception 'expected 4 freshness sources, found %', n; end if;

  raise notice 'ops reporting assertions: PASS (% staged attempt(s) segregated, % live/beta base attempts)',
    (select count(*) from ops.attempt where is_staged = true),
    (select count(*) from ops.attempt where is_staged = false and env in ('live','beta'));
end $$;
