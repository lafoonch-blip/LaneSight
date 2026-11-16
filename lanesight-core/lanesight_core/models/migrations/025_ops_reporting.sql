-- 025 Owner-only ops reporting layer (DEC-098). Additive, idempotent, read-only.
--
-- Aggregate VIEWS over data LaneSight already records (DEC-086 analysis_attempt, DEC-059 feedback,
-- schema.sql shots/sessions/profiles) for the owner ops dashboard (ops-dashboard/). Creates NO base
-- tables of real data and writes NO rows (only a one-row owner-id registry).
--
-- ---------------------------------------------------------------------------
-- Security model (reviewed before merge)
-- ---------------------------------------------------------------------------
-- 1. The views live in a PRIVATE schema `ops` that is NOT in PostgREST's exposed schema list
--    (public, graphql_public, storage). So no API client — anon OR authenticated — can read ops.* over
--    REST at all, and we additionally REVOKE usage/select so a direct attempt is "permission denied".
-- 2. The dashboard never uses the service_role. It signs the OWNER in with Supabase Auth and reads data
--    only through SECURITY DEFINER RPCs in `public` that check the caller is the owner:
--        public.ops_rpc_*  ->  if not ops.is_owner() then raise 42501  ->  select from ops.<view>
--    auth.uid() inside the definer function reflects the caller's JWT (PostgREST sets request.jwt.claims),
--    so a non-owner authenticated user gets "not authorized"; anon (no uid) likewise. The function runs as
--    its owner (postgres) which bypasses RLS, so the aggregates span all users — but only for the owner.
-- 3. Owner id is seeded in ops.app_owner and MUST equal lanesight_core/owner.py OWNER_USER_ID
--    (551bc775-dee4-41bd-a19c-116e8691d053 = lafoonch@gmail.com). Update both together.
--
-- Honesty (CLAUDE.md: no mock/placeholder/fallback numbers):
--   * every rate divides by nullif(denominator,0) -> NULL (NO DATA) for an empty window, never a fake 0.
--   * STAGED test accounts (profiles.is_staged, DEC-063) MAY hold fabricated data -> excluded from every
--     canonical view (like feedback_review in 018). The base ops.attempt still carries the flag.
--   * env (dev|beta|live) is a GROUP BY dimension, not a hidden filter.
--   * Domains with no instrumentation yet (FinOps, Storage) are NO DATA in ops.coverage_status, not faked.

-- ===========================================================================
-- Schema + owner registry + owner check
-- ===========================================================================
create schema if not exists ops;

-- Lock the schema down: no API role may enter it. (Definer RPCs run as postgres and are unaffected.)
revoke all on schema ops from public;
revoke usage on schema ops from anon, authenticated;

create table if not exists ops.app_owner (user_id uuid primary key);
insert into ops.app_owner (user_id)
  values ('551bc775-dee4-41bd-a19c-116e8691d053')
  on conflict (user_id) do nothing;
comment on table ops.app_owner is
  'DEC-098: the ops dashboard owner (must match owner.py OWNER_USER_ID). Read only by ops.is_owner().';

create or replace function ops.is_owner() returns boolean
  language sql stable security definer set search_path = '' as $$
  select exists (select 1 from ops.app_owner o where o.user_id = (select auth.uid()));
$$;
comment on function ops.is_owner() is 'DEC-098: true iff the current JWT subject is the ops owner.';

-- ===========================================================================
-- Views (private schema `ops`). Base tables are schema-qualified public.* so creation is search_path-safe.
-- ===========================================================================
create or replace view ops.attempt as
select a.id, a.created_at, a.env, a.source, a.capture_mode, a.status, a.failure_code, a.failure_stage,
       a.algorithm_version, a.api_revision, a.user_id, a.shot_id, a.session_id, a.content_hash,
       coalesce(p.is_staged, false)                                 as is_staged,
       round(a.duration_ms / 1000.0, 2)                             as attempt_seconds,
       (a.step_timings->>'analyze_s')::numeric                      as server_analyze_s,
       (a.step_timings->'decode'->>'seconds')::numeric              as decode_s,
       (a.step_timings->'decode'->>'passes')::int                   as decode_passes,
       (a.step_timings->'client'->>'client_pre_analyze_s')::numeric as phone_pre_analyze_s,
       (a.step_timings->'client'->>'trim_s')::numeric               as phone_trim_s,
       (a.step_timings->'client'->>'upload_s')::numeric             as phone_upload_s,
       (a.step_timings->>'convert_s')::numeric                      as hdr_convert_s,
       (a.clip->>'cold_start')::boolean                             as cold_start,
       (a.clip->>'width')::int                                      as width,
       (a.clip->>'height')::int                                     as height,
       (a.clip->>'short_side_px')::int                              as short_side_px,
       (a.clip->>'rotation')::int                                   as rotation_deg,
       (a.clip->>'fps')::numeric                                    as fps,
       (a.clip->>'hdr')::boolean                                    as hdr,
       (a.clip->>'bit_depth')::int                                  as bit_depth,
       (a.clip->>'variable_frame_rate')::boolean                    as variable_frame_rate,
       (a.clip->>'duration_s')::numeric                             as clip_seconds,
       round((a.clip->>'bytes')::numeric / 1048576.0, 1)            as clip_mb,
       (a.clip->'precheck'->>'ok')::boolean                         as precheck_ok,
       (a.clip->'precheck'->>'code')                                as precheck_code,
       a.clip->>'probe_error'                                       as probe_error,
       a.diagnostics->>'far_lane'                                   as far_lane,
       a.diagnostics->>'capture_reason'                             as capture_reason,
       (a.diagnostics->>'entry_board')::numeric                     as entry_board,
       (a.diagnostics->>'ball_speed')::numeric                      as ball_speed,
       (a.diagnostics->>'rev_rate')::numeric                        as rev_rate,
       (a.diagnostics->>'n_measured')::int                          as n_measured,
       a.diagnostics->>'view'                                       as form_view
from public.analysis_attempt a
left join public.profiles p on p.user_id = a.user_id;

create or replace view ops.analysis_daily as
select date_trunc('day', created_at)::date as day, env, capture_mode,
       count(*)                                           as attempts,
       count(*) filter (where status = 'analyzed')        as analyzed,
       count(*) filter (where status = 'failed')          as failures,
       round(count(*) filter (where status='failed')::numeric / nullif(count(*),0), 4) as failure_rate,
       count(distinct user_id)                            as distinct_users,
       round(percentile_cont(0.5)  within group (order by attempt_seconds)::numeric, 1) as p50_attempt_seconds,
       round(percentile_cont(0.9)  within group (order by attempt_seconds)::numeric, 1) as p90_attempt_seconds,
       round(percentile_cont(0.95) within group (order by attempt_seconds)::numeric, 1) as p95_attempt_seconds
from ops.attempt where is_staged = false group by 1,2,3;

create or replace view ops.failure_breakdown as
select date_trunc('day', created_at)::date as day, env, capture_mode, failure_stage, failure_code,
       algorithm_version, count(*) as failures
from ops.attempt where is_staged = false and status = 'failed' group by 1,2,3,4,5,6;

create or replace view ops.cv_coverage as
select date_trunc('day', created_at)::date as day, env,
       count(*)                                                                as attempts,
       count(*) filter (where far_lane = 'true')                               as far_lane_read,
       round(count(*) filter (where far_lane='true')::numeric
             / nullif(count(*) filter (where far_lane is not null),0), 4)      as far_lane_read_rate,
       round(avg(n_measured)::numeric, 1)                                      as avg_metrics_measured,
       count(*) filter (where hdr is true)                                     as hdr_clips,
       count(*) filter (where variable_frame_rate is true)                     as vfr_clips,
       count(*) filter (where cold_start is true)                              as cold_start_attempts,
       count(*) filter (where precheck_ok is false)                           as precheck_rejects,
       count(*) filter (where precheck_ok is not null)                        as precheck_evaluated,
       count(*) filter (where probe_error is not null)                        as probe_errors
from ops.attempt where is_staged = false and capture_mode = 'shot' group by 1,2;

create or replace view ops.latency_stages as
select date_trunc('day', created_at)::date as day, env,
       count(*)                                                                         as analyzed,
       round(percentile_cont(0.5) within group (order by attempt_seconds)::numeric,1)   as p50_total_s,
       round(percentile_cont(0.9) within group (order by attempt_seconds)::numeric,1)   as p90_total_s,
       round(percentile_cont(0.5) within group (order by server_analyze_s)::numeric,1)  as p50_server_analyze_s,
       round(percentile_cont(0.5) within group (order by decode_s)::numeric,1)          as p50_decode_s,
       round(percentile_cont(0.5) within group (order by hdr_convert_s)::numeric,1)     as p50_hdr_convert_s,
       round(percentile_cont(0.5) within group (order by phone_trim_s)::numeric,1)      as p50_phone_trim_s,
       round(percentile_cont(0.5) within group (order by phone_upload_s)::numeric,1)    as p50_phone_upload_s,
       round(percentile_cont(0.5) within group (order by phone_pre_analyze_s)::numeric,1) as p50_phone_pre_analyze_s,
       round(count(*) filter (where cold_start is true)::numeric / nullif(count(*),0),4) as cold_start_rate
from ops.attempt where is_staged = false and status = 'analyzed' group by 1,2;

create or replace view ops.release_health as
select algorithm_version, api_revision, env,
       count(*)                                           as attempts,
       count(*) filter (where status='failed')            as failures,
       round(count(*) filter (where status='failed')::numeric / nullif(count(*),0),4) as failure_rate,
       round(percentile_cont(0.5) within group (order by attempt_seconds)::numeric,1) as p50_attempt_seconds,
       round(avg(n_measured)::numeric,1)                  as avg_metrics_measured,
       count(distinct user_id)                            as distinct_users,
       min(created_at)                                    as first_seen,
       max(created_at)                                    as last_seen
from ops.attempt where is_staged = false group by 1,2,3;

create or replace view ops.feedback_summary as
select date_trunc('day', created_at)::date as day, app_phase, source,
       count(*)                                           as total,
       count(*) filter (where thumbs='up')                as thumbs_up,
       count(*) filter (where thumbs='down')              as thumbs_down,
       count(*) filter (where triage_status='new')        as untriaged,
       round(avg(rating)::numeric,2)                      as avg_rating
from public.feedback where coalesce(is_staged,false) = false group by 1,2,3;

create or replace view ops.usage_daily as
with s as (
  select date_trunc('day', created_at)::date as day, user_id, id from public.shots sh
   where not exists (select 1 from public.profiles p where p.user_id = sh.user_id and p.is_staged = true)
),
ses as (
  select date_trunc('day', started_at)::date as day, user_id, id from public.sessions se
   where not exists (select 1 from public.profiles p where p.user_id = se.user_id and p.is_staged = true)
)
select d.day,
       (select count(*) from s where s.day = d.day)                as shots,
       (select count(distinct user_id) from s where s.day = d.day) as active_users_shots,
       (select count(*) from ses where ses.day = d.day)            as sessions_started
from (select distinct day from s union select distinct day from ses) d order by d.day;

create or replace view ops.freshness as
select 'analysis_attempt'::text as source, max(created_at) as last_ingested, count(*) as rows from public.analysis_attempt
union all select 'feedback', max(created_at), count(*) from public.feedback
union all select 'shots',    max(created_at), count(*) from public.shots
union all select 'sessions', max(started_at), count(*) from public.sessions;

create or replace view ops.coverage_status as
select * from (values
  ('03 Video & AI Trust',    'available','analysis_attempt (DEC-086/092)',                 'ops.cv_coverage / ops.analysis_daily'),
  ('04 App/API Performance', 'partial',  'analysis_attempt step_timings',                  'ops.latency_stages'),
  ('08 Release & Regression','available','analysis_attempt algorithm_version/api_revision','ops.release_health'),
  ('02 Customer Journey',    'partial',  'shots / sessions counts only',                   'ops.usage_daily'),
  ('07 Security & Controls', 'partial',  'feedback triage; no auth-event log yet',         'ops.feedback_summary'),
  ('01 Executive',           'partial',  'derived from the above real sources',            'ops overview'),
  ('05 Storage & DB',        'no_data',  'not instrumented (needs §2)',                    null),
  ('06 Financial Operations','no_data',  'no cost metering yet (needs §2)',                null)
) as t(domain, status, data_source, backing_view);

-- Belt-and-braces: revoke any object-level access in ops from API roles (schema usage is already revoked).
do $$ declare r record; begin
  for r in select table_name from information_schema.views where table_schema='ops' loop
    execute format('revoke all on ops.%I from anon, authenticated, public', r.table_name);
  end loop;
end $$;

-- ===========================================================================
-- Owner-checked RPCs (public, SECURITY DEFINER). The ONLY read path for the dashboard.
-- ===========================================================================
create or replace function public.ops_rpc_analysis_daily(p_envs text[], p_since date)
  returns setof ops.analysis_daily language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.analysis_daily v where v.env = any(p_envs) and v.day >= p_since;
end $$;

create or replace function public.ops_rpc_failure_breakdown(p_envs text[], p_since date)
  returns setof ops.failure_breakdown language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.failure_breakdown v where v.env = any(p_envs) and v.day >= p_since;
end $$;

create or replace function public.ops_rpc_cv_coverage(p_envs text[], p_since date)
  returns setof ops.cv_coverage language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.cv_coverage v where v.env = any(p_envs) and v.day >= p_since;
end $$;

create or replace function public.ops_rpc_latency_stages(p_envs text[], p_since date)
  returns setof ops.latency_stages language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.latency_stages v where v.env = any(p_envs) and v.day >= p_since;
end $$;

create or replace function public.ops_rpc_release_health(p_envs text[], p_since date)
  returns setof ops.release_health language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.release_health v where v.env = any(p_envs) and v.last_seen >= p_since;
end $$;

create or replace function public.ops_rpc_feedback_summary(p_since date)
  returns setof ops.feedback_summary language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.feedback_summary v where v.day >= p_since;
end $$;

create or replace function public.ops_rpc_usage_daily(p_since date)
  returns setof ops.usage_daily language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.usage_daily v where v.day >= p_since;
end $$;

create or replace function public.ops_rpc_freshness()
  returns setof ops.freshness language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.freshness;
end $$;

create or replace function public.ops_rpc_coverage_status()
  returns setof ops.coverage_status language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.coverage_status;
end $$;

-- Only signed-in users may call; the function itself rejects non-owners. anon cannot call at all.
do $$ declare fn text; begin
  foreach fn in array array[
    'public.ops_rpc_analysis_daily(text[],date)','public.ops_rpc_failure_breakdown(text[],date)',
    'public.ops_rpc_cv_coverage(text[],date)','public.ops_rpc_latency_stages(text[],date)',
    'public.ops_rpc_release_health(text[],date)','public.ops_rpc_feedback_summary(date)',
    'public.ops_rpc_usage_daily(date)','public.ops_rpc_freshness()','public.ops_rpc_coverage_status()'
  ] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;
