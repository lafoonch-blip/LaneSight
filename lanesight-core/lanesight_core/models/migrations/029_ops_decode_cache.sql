-- 029_ops_decode_cache.sql — surface the DEC-092 P1 decode-once frame cache on the ops dashboard.
-- Additive + read-only: restates ops.attempt (adds decode_cache_complete + decode_cached_passes from
-- step_timings.decode) and ops.latency_stages (adds decode_cache_engaged_rate), and refreshes the latency RPC.
-- No data migration. Reversible by reverting the two views. See 03_ENGINEERING/DECODE_ONCE_FINDINGS.md.
--
-- DEPENDS ON the platform-provenance migration (DEC-103) that adds analysis_attempt.platform and exposes it on
-- ops.attempt. That migration is live but its file lives on feat/on-device-analysis, not mainline — bring it to
-- mainline during the reconcile BEFORE this runs on a fresh DB (on the live DB both are already applied).

create or replace view ops.attempt as
select a.id, a.created_at, a.env, a.source, a.capture_mode, a.status, a.failure_code, a.failure_stage,
       a.algorithm_version, a.api_revision, a.user_id, a.shot_id, a.session_id, a.content_hash,
       coalesce(p.is_staged, false)                                 as is_staged,
       round(a.duration_ms::numeric / 1000.0, 2)                    as attempt_seconds,
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
       coalesce(a.platform, 'server')                               as platform,
       (a.step_timings->'decode'->>'cache_complete')::boolean       as decode_cache_complete,  -- DEC-092 P1
       (a.step_timings->'decode'->>'cached_passes')::int            as decode_cached_passes
from public.analysis_attempt a
left join public.profiles p on p.user_id = a.user_id;

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
       round(count(*) filter (where cold_start is true)::numeric / nullif(count(*),0),4) as cold_start_rate,
       round(count(*) filter (where decode_cache_complete is true)::numeric
             / nullif(count(*) filter (where decode_cache_complete is not null),0),4)    as decode_cache_engaged_rate
from ops.attempt where is_staged = false and status = 'analyzed' group by 1,2;

create or replace function public.ops_rpc_latency_stages(p_envs text[], p_since date)
  returns setof ops.latency_stages language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.latency_stages v where v.env = any(p_envs) and v.day >= p_since;
end $$;
revoke all on function public.ops_rpc_latency_stages(text[],date) from public, anon;
grant execute on function public.ops_rpc_latency_stages(text[],date) to authenticated;
