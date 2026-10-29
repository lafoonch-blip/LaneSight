-- 028 — Engine provenance on analysis_attempt (DEC-103). Additive + backward-compatible.
-- Adds `platform` (server | ios) so server-authoritative and on-device (shadow) attempts can be compared in
-- the ops layer. engine.version/build already exist as analysis_attempt.algorithm_version / api_revision.
-- Existing rows and the current server path are 'server'. No behavior change to the live service.

alter table public.analysis_attempt add column if not exists platform text;
update public.analysis_attempt set platform = 'server' where platform is null;
comment on column public.analysis_attempt.platform is
  'DEC-103: measurement engine platform — server | ios. The device (ios) path is shadow until the ground-truth '
  '+ parity gates pass; server stays authoritative. Null legacy rows are treated as server.';

-- Re-create ops.attempt to expose platform (appended column only — same column order otherwise).
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
       a.diagnostics->>'view'                                       as form_view,
       (a.cost->>'vcpu_s')::numeric                                 as vcpu_s,
       (a.cost->>'gib_s')::numeric                                  as gib_s,
       (a.cost->>'egress_mb')::numeric                              as egress_mb,
       a.user_ref                                                   as user_ref,
       coalesce(a.platform, 'server')                               as platform
from public.analysis_attempt a
left join public.profiles p on p.user_id = a.user_id;

-- Architecture comparison: same metrics as analysis_daily but split by platform (server vs ios).
create or replace view ops.platform_daily as
select date_trunc('day', created_at)::date as day, env, platform, capture_mode,
       count(*)                                           as attempts,
       count(*) filter (where status = 'analyzed')        as analyzed,
       count(*) filter (where status = 'failed')          as failures,
       round(count(*) filter (where status='failed')::numeric / nullif(count(*),0), 4) as failure_rate,
       count(distinct user_id)                            as distinct_users,
       round(percentile_cont(0.5)  within group (order by attempt_seconds)::numeric, 1) as p50_attempt_seconds,
       round(percentile_cont(0.9)  within group (order by attempt_seconds)::numeric, 1) as p90_attempt_seconds,
       round(percentile_cont(0.95) within group (order by attempt_seconds)::numeric, 1) as p95_attempt_seconds,
       round(avg(server_analyze_s)::numeric, 2)           as avg_analyze_s
from ops.attempt where is_staged = false group by 1,2,3,4;

-- Owner-only RPC (same pattern as 025/027: SECURITY DEFINER + ops.is_owner()).
create or replace function public.ops_rpc_platform_daily(p_envs text[], p_since date)
  returns setof ops.platform_daily language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.platform_daily v where v.env = any(p_envs) and v.day >= p_since;
end $$;

do $$
begin
  execute 'revoke all on function public.ops_rpc_platform_daily(text[],date) from public, anon';
  execute 'grant execute on function public.ops_rpc_platform_daily(text[],date) to authenticated';
end $$;
