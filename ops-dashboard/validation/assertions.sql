-- Ops reporting DB assertions (§1) — run AFTER 0XX_ops_reporting.sql is applied, as the owner
-- (service_role / postgres), against the DB the dashboard will read. PENDING STEP (not run by Claude
-- Code — no migration applied, no live access). Read-only: it raises an exception on any violation and
-- changes nothing. Run in the Supabase SQL editor or: psql "$LANESIGHT_DB_URL" -f assertions.sql
--
-- Each block raises if an honesty/structural invariant is broken. "No rows" is a valid, passing state
-- for a young beta DB — these assert the SHAPE is honest, not that data exists.

do $$
declare n int; bad int;
begin
  -- 1. All ten views exist and are selectable by the owner path.
  select count(*) into n from information_schema.views
   where table_schema = 'public'
     and table_name in ('ops_attempt','ops_analysis_daily','ops_failure_breakdown','ops_cv_coverage',
                        'ops_latency_stages','ops_release_health','ops_feedback_summary','ops_usage_daily',
                        'ops_freshness','ops_coverage_status');
  if n <> 10 then raise exception 'expected 10 ops views, found %', n; end if;

  -- 2. Owner-only: no ops view is granted to anon/authenticated (would leak all users' data).
  select count(*) into bad from information_schema.role_table_grants
   where table_schema = 'public' and table_name like 'ops\_%' escape '\'
     and grantee in ('anon','authenticated');
  if bad > 0 then raise exception 'SECURITY: % ops-view grant(s) to anon/authenticated', bad; end if;

  -- 3. Staged accounts are excluded from the canonical reliability view (DEC-063). If any staged attempt
  --    exists, its user_id must NOT appear in ops_analysis_daily's underlying real set.
  select count(*) into bad
    from ops_attempt
   where is_staged = true;
  -- ops_attempt carries staged rows (it is the base); but the staged ones must be flagged, and the
  --    daily/real views must not count them. Verify daily attempts == real (non-staged) attempts.
  perform 1;
  select (select coalesce(sum(attempts),0) from ops_analysis_daily)
       - (select count(*) from ops_attempt where is_staged = false)
    into bad;
  if bad <> 0 then
    raise exception 'ops_analysis_daily attempt total (%) != non-staged ops_attempt count — staged leak or drop',
      (select coalesce(sum(attempts),0) from ops_analysis_daily);
  end if;

  -- 4. No fake 0 rates: wherever attempts=0 the failure_rate must be NULL (NO DATA), never 0.
  select count(*) into bad from ops_analysis_daily where attempts = 0 and failure_rate is not null;
  if bad > 0 then raise exception '% daily row(s) show a non-NULL failure_rate with 0 attempts', bad; end if;

  -- 5. failure_rate, when present, is a real ratio in [0,1].
  select count(*) into bad from ops_analysis_daily where failure_rate is not null and (failure_rate < 0 or failure_rate > 1);
  if bad > 0 then raise exception '% daily row(s) have failure_rate outside [0,1]', bad; end if;
  select count(*) into bad from ops_release_health where failure_rate is not null and (failure_rate < 0 or failure_rate > 1);
  if bad > 0 then raise exception '% release row(s) have failure_rate outside [0,1]', bad; end if;

  -- 6. analyzed + failures = attempts in the reliability view (status is the only terminal set).
  select count(*) into bad from ops_analysis_daily where analyzed + failures <> attempts;
  if bad > 0 then raise exception '% daily row(s) where analyzed+failures != attempts', bad; end if;

  -- 7. Coverage status is honest: exactly 8 domains; every no_data domain has a NULL backing_view.
  select count(*) into n from ops_coverage_status;
  if n <> 8 then raise exception 'expected 8 coverage domains, found %', n; end if;
  select count(*) into bad from ops_coverage_status where status = 'no_data' and backing_view is not null;
  if bad > 0 then raise exception '% no_data domain(s) wrongly claim a backing view', bad; end if;

  -- 8. Freshness lists the four real sources.
  select count(*) into n from ops_freshness;
  if n <> 4 then raise exception 'expected 4 freshness sources, found %', n; end if;

  raise notice 'ops reporting assertions: PASS (shape honest; % staged attempt(s) correctly segregated)',
    (select count(*) from ops_attempt where is_staged = true);
end $$;
