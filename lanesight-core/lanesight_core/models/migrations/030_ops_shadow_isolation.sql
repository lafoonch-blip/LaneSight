-- 030_ops_shadow_isolation.sql — keep on-device SHADOW attempts out of production KPIs (DEC-106).
-- POST /analysis/shadow writes platform='ios' analysis_attempt rows (shadow; never shown/scored). Every KPI
-- view that aggregates attempts must count ONLY the authoritative server engine, or shadow rows double-count
-- shots and (shadow unavailable→failed) inflate failure rates. Fix: add platform='server' to each KPI view.
-- ops.attempt (raw) and ops.platform_daily / Engine A/B KEEP all platforms — that is the comparison surface.
-- WHERE-only change: columns/RPC return types are unchanged, so no RPC or definitions.json column edits.

create or replace view ops.analysis_daily as
select date_trunc('day', created_at)::date as day, env, capture_mode,
       count(*) as attempts,
       count(*) filter (where status = 'analyzed') as analyzed,
       count(*) filter (where status = 'failed') as failures,
       round(count(*) filter (where status = 'failed')::numeric / nullif(count(*), 0), 4) as failure_rate,
       count(distinct user_id) as distinct_users,
       round(percentile_cont(0.5) within group (order by attempt_seconds::double precision)::numeric, 1) as p50_attempt_seconds,
       round(percentile_cont(0.9) within group (order by attempt_seconds::double precision)::numeric, 1) as p90_attempt_seconds,
       round(percentile_cont(0.95) within group (order by attempt_seconds::double precision)::numeric, 1) as p95_attempt_seconds
from ops.attempt where is_staged = false and platform = 'server'
group by 1, 2, 3;

create or replace view ops.cv_coverage as
select date_trunc('day', created_at)::date as day, env,
       count(*) as attempts,
       count(*) filter (where far_lane = 'true') as far_lane_read,
       round(count(*) filter (where far_lane = 'true')::numeric / nullif(count(*) filter (where far_lane is not null), 0), 4) as far_lane_read_rate,
       round(avg(n_measured), 1) as avg_metrics_measured,
       count(*) filter (where hdr is true) as hdr_clips,
       count(*) filter (where variable_frame_rate is true) as vfr_clips,
       count(*) filter (where cold_start is true) as cold_start_attempts,
       count(*) filter (where precheck_ok is false) as precheck_rejects,
       count(*) filter (where precheck_ok is not null) as precheck_evaluated,
       count(*) filter (where probe_error is not null) as probe_errors
from ops.attempt where is_staged = false and capture_mode = 'shot' and platform = 'server'
group by 1, 2;

create or replace view ops.failure_breakdown as
select date_trunc('day', created_at)::date as day, env, capture_mode, failure_stage, failure_code,
       algorithm_version, count(*) as failures
from ops.attempt where is_staged = false and status = 'failed' and platform = 'server'
group by 1, 2, 3, 4, 5, 6;

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
from ops.attempt where is_staged = false and status = 'analyzed' and platform = 'server' group by 1,2;

create or replace view ops.release_health as
select algorithm_version, api_revision, env,
       count(*) as attempts,
       count(*) filter (where status = 'failed') as failures,
       round(count(*) filter (where status = 'failed')::numeric / nullif(count(*), 0), 4) as failure_rate,
       round(percentile_cont(0.5) within group (order by attempt_seconds::double precision)::numeric, 1) as p50_attempt_seconds,
       round(avg(n_measured), 1) as avg_metrics_measured,
       count(distinct user_id) as distinct_users,
       min(created_at) as first_seen, max(created_at) as last_seen
from ops.attempt where is_staged = false and platform = 'server'
group by algorithm_version, api_revision, env;

create or replace view ops.cost_daily as
with a as (select * from ops.attempt where is_staged = false and platform = 'server'),
     r as (select resource, usd_per_unit from ops.cost_rates
           where effective_from = (select max(effective_from) from ops.cost_rates))
select date_trunc('day', created_at)::date as day, env,
       count(*) as attempts,
       round(sum(vcpu_s), 1) as vcpu_s, round(sum(gib_s), 1) as gib_s, round(sum(egress_mb), 1) as egress_mb,
       round(sum(vcpu_s) * (select r.usd_per_unit from r where r.resource = 'vcpu_s'), 4)
         + round(sum(gib_s) * (select r.usd_per_unit from r where r.resource = 'gib_s'), 4)
         + round(sum(egress_mb) * (select r.usd_per_unit from r where r.resource = 'egress_mb'), 4) as est_usd,
       round((round(sum(vcpu_s) * (select r.usd_per_unit from r where r.resource = 'vcpu_s'), 6)
         + round(sum(gib_s) * (select r.usd_per_unit from r where r.resource = 'gib_s'), 6)
         + round(sum(egress_mb) * (select r.usd_per_unit from r where r.resource = 'egress_mb'), 6))
         / nullif(count(*) filter (where status = 'analyzed'), 0), 4) as est_usd_per_success
from a group by 1, 2;

-- freshness reads analysis_attempt directly (not ops.attempt); the analysis source should reflect SERVER arrival.
create or replace view ops.freshness as
 select 'analysis_attempt'::text as source, max(created_at) as last_ingested, count(*) as rows
   from analysis_attempt where coalesce(platform, 'server') = 'server'
union all
 select 'feedback'::text, max(created_at), count(*) from feedback
union all
 select 'shots'::text, max(created_at), count(*) from shots
union all
 select 'sessions'::text, max(started_at), count(*) from sessions;
