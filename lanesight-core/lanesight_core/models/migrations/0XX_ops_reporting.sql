-- 0XX Owner-only ops reporting layer (DEC-0NN — renumber at merge; see ops-dashboard/DEC_DRAFT.md).
-- Additive, idempotent, read-only. Creates NO new base tables and writes NO data: it is a set of
-- aggregate VIEWS over the data LaneSight already records (DEC-086 analysis_attempt, DEC-059 feedback,
-- schema.sql shots/sessions/profiles) so the owner ops dashboard (ops-dashboard/) has a single, honest
-- source for production reporting.
--
-- NOT APPLIED TO LIVE BY CLAUDE CODE. This file is listed as a pending step for Shayne; renumber from
-- 0XX to the next free number at merge (latest applied is 024).
--
-- ---------------------------------------------------------------------------
-- Access model (why these views differ from analysis_attempt_summary in 022/023)
-- ---------------------------------------------------------------------------
-- 022/023's analysis_attempt_summary is PER-USER: it is security_invoker=on so the caller's RLS
-- (own_select: user_id = auth.uid()) scopes it to that bowler's own rows. That is correct for an
-- in-app "review my attempts" surface.
--
-- An OPS dashboard needs the opposite: aggregates ACROSS ALL users, visible ONLY to the owner. So these
-- views are deliberately NOT security_invoker — they run with the definer's rights (the role that applies
-- this migration: postgres in the Supabase SQL editor, or the service_role, both of which bypass the
-- per-user RLS on analysis_attempt). Access is then locked down by GRANTs: revoked from anon/authenticated
-- and granted only to rules_admin (the owner marker role from 006/014/018). The real owner read path is the
-- service_role key, used server-side only by the ops dashboard (never shipped to a browser). A logged-in
-- bowler ('authenticated') can never select these views.
--
-- ---------------------------------------------------------------------------
-- Honesty rules baked into the SQL (CLAUDE.md: no mock/placeholder/fallback numbers)
-- ---------------------------------------------------------------------------
--   * Every rate divides by nullif(denominator, 0) so "no attempts" yields NULL (the dashboard renders
--     NO DATA), never a fake 0%.
--   * STAGED test accounts (profiles.is_staged, DEC-063) MAY hold fabricated/staged data, so the canonical
--     ops views EXCLUDE them (exactly like feedback_review in 018). The staged flag is still carried on the
--     ops_attempt base so a future diagnostic view could include them deliberately.
--   * `env` (dev|beta|live) is kept as a GROUP BY dimension, not pre-filtered, so the dashboard can scope
--     to live/beta and keep dev test runs out of production numbers — honestly, by choice, not by hiding.
--   * Domains with no instrumentation yet (FinOps cost, crashes/Sentry, storage bytes, product funnels)
--     get NO fabricated view. ops_coverage_status enumerates them as NO DATA pending §2 instrumentation.
--   * Staged status is unknown for a DELETED account (profiles row gone, analysis_attempt has no FK): such
--     rows are treated as real (coalesce(is_staged,false)=false). Staged accounts (ls_*) are long-lived.

do $$ begin
  create role rules_admin nologin;   -- 006 already creates it; guard keeps this migration standalone-safe
exception when duplicate_object then null; end $$;

-- ===========================================================================
-- Base: one row per analysis attempt, across ALL users, flattened + staged-tagged. Owner-only.
-- ===========================================================================
create or replace view ops_attempt as
select a.id,
       a.created_at,
       a.env,
       a.source,                                   -- upload | live
       a.capture_mode,                             -- shot | form
       a.status,                                   -- analyzed | failed
       a.failure_code,
       a.failure_stage,
       a.algorithm_version,
       a.api_revision,
       a.user_id,
       a.shot_id,
       a.session_id,
       a.content_hash,
       coalesce(p.is_staged, false)                        as is_staged,
       round(a.duration_ms / 1000.0, 2)                    as attempt_seconds,
       (a.step_timings->>'analyze_s')::numeric             as server_analyze_s,
       (a.step_timings->'decode'->>'seconds')::numeric     as decode_s,
       (a.step_timings->'decode'->>'passes')::int          as decode_passes,
       (a.step_timings->'client'->>'client_pre_analyze_s')::numeric as phone_pre_analyze_s,
       (a.step_timings->'client'->>'trim_s')::numeric      as phone_trim_s,
       (a.step_timings->'client'->>'upload_s')::numeric    as phone_upload_s,
       (a.step_timings->>'convert_s')::numeric             as hdr_convert_s,
       (a.clip->>'cold_start')::boolean                    as cold_start,
       (a.clip->>'width')::int                             as width,
       (a.clip->>'height')::int                            as height,
       (a.clip->>'short_side_px')::int                     as short_side_px,
       (a.clip->>'rotation')::int                          as rotation_deg,
       (a.clip->>'fps')::numeric                           as fps,
       (a.clip->>'hdr')::boolean                           as hdr,
       (a.clip->>'bit_depth')::int                         as bit_depth,
       (a.clip->>'variable_frame_rate')::boolean           as variable_frame_rate,
       (a.clip->>'duration_s')::numeric                    as clip_seconds,
       round((a.clip->>'bytes')::numeric / 1048576.0, 1)   as clip_mb,
       (a.clip->'precheck'->>'ok')::boolean                as precheck_ok,
       (a.clip->'precheck'->>'code')                       as precheck_code,
       a.clip->>'probe_error'                              as probe_error,
       a.diagnostics->>'far_lane'                          as far_lane,
       a.diagnostics->>'capture_reason'                    as capture_reason,
       (a.diagnostics->>'entry_board')::numeric            as entry_board,
       (a.diagnostics->>'ball_speed')::numeric             as ball_speed,
       (a.diagnostics->>'rev_rate')::numeric               as rev_rate,
       (a.diagnostics->>'n_measured')::int                 as n_measured,
       a.diagnostics->>'view'                              as form_view
from analysis_attempt a
left join profiles p on p.user_id = a.user_id;

comment on view ops_attempt is
  'Owner-only base: every analysis attempt (all users), flattened from clip/step_timings/diagnostics and '
  'tagged is_staged. Cross-user (not security_invoker). Source for the ops dashboard analysis/CV/latency views.';

-- ===========================================================================
-- Analysis reliability: day x env x capture_mode. Real accounts only.
-- ===========================================================================
create or replace view ops_analysis_daily as
select date_trunc('day', created_at)::date                 as day,
       env,
       capture_mode,
       count(*)                                             as attempts,
       count(*) filter (where status = 'analyzed')          as analyzed,
       count(*) filter (where status = 'failed')            as failures,
       round(count(*) filter (where status = 'failed')::numeric
             / nullif(count(*), 0), 4)                      as failure_rate,
       count(distinct user_id)                              as distinct_users,
       round(percentile_cont(0.5) within group (order by attempt_seconds)::numeric, 1) as p50_attempt_seconds,
       round(percentile_cont(0.9) within group (order by attempt_seconds)::numeric, 1) as p90_attempt_seconds,
       round(percentile_cont(0.95) within group (order by attempt_seconds)::numeric, 1) as p95_attempt_seconds
from ops_attempt
where is_staged = false
group by 1, 2, 3;

comment on view ops_analysis_daily is
  'Owner-only: attempts/analyzed/failures/failure_rate + attempt-seconds percentiles + distinct users per '
  'day x env x capture_mode. Real accounts only (staged excluded). failure_rate is NULL when attempts=0.';

-- ===========================================================================
-- Failure breakdown: what is failing, where, on which engine. Real accounts only.
-- ===========================================================================
create or replace view ops_failure_breakdown as
with f as (select * from ops_attempt where is_staged = false and status = 'failed')
select date_trunc('day', created_at)::date as day,
       env,
       capture_mode,
       failure_stage,
       failure_code,
       algorithm_version,
       count(*)                                             as failures
from f
group by 1, 2, 3, 4, 5, 6;

comment on view ops_failure_breakdown is
  'Owner-only: failed attempts by day x env x capture_mode x stage x code x engine version. Real accounts only.';

-- ===========================================================================
-- CV / capture trust: how good is the capture, how often can we read the far lane, framing facts.
-- Real accounts only; shot/upload ball clips (form uses the pose path, excluded from far-lane share).
-- ===========================================================================
create or replace view ops_cv_coverage as
select date_trunc('day', created_at)::date as day,
       env,
       count(*)                                                                   as attempts,
       count(*) filter (where far_lane = 'true')                                  as far_lane_read,
       round(count(*) filter (where far_lane = 'true')::numeric
             / nullif(count(*) filter (where far_lane is not null), 0), 4)        as far_lane_read_rate,
       round(avg(n_measured)::numeric, 1)                                         as avg_metrics_measured,
       count(*) filter (where hdr is true)                                        as hdr_clips,
       count(*) filter (where variable_frame_rate is true)                        as vfr_clips,
       count(*) filter (where cold_start is true)                                 as cold_start_attempts,
       count(*) filter (where precheck_ok is false)                               as precheck_rejects,
       count(*) filter (where precheck_ok is not null)                            as precheck_evaluated,
       count(*) filter (where probe_error is not null)                            as probe_errors
from ops_attempt
where is_staged = false and capture_mode = 'shot'
group by 1, 2;

comment on view ops_cv_coverage is
  'Owner-only: capture/CV trust per day x env for ball (shot) attempts — far-lane read rate, avg metrics '
  'measured, HDR/VFR/cold-start counts, shadow-precheck rejects, probe errors. Real accounts only. '
  'far_lane_read_rate denominator is attempts where far_lane was recorded (NULL -> NO DATA).';

-- ===========================================================================
-- Latency by stage: where the time goes (phone + server). Analyzed attempts, real accounts only.
-- ===========================================================================
create or replace view ops_latency_stages as
select date_trunc('day', created_at)::date as day,
       env,
       count(*)                                                                            as analyzed,
       round(percentile_cont(0.5)  within group (order by attempt_seconds)::numeric, 1)    as p50_total_s,
       round(percentile_cont(0.9)  within group (order by attempt_seconds)::numeric, 1)    as p90_total_s,
       round(percentile_cont(0.5)  within group (order by server_analyze_s)::numeric, 1)   as p50_server_analyze_s,
       round(percentile_cont(0.5)  within group (order by decode_s)::numeric, 1)           as p50_decode_s,
       round(percentile_cont(0.5)  within group (order by hdr_convert_s)::numeric, 1)      as p50_hdr_convert_s,
       round(percentile_cont(0.5)  within group (order by phone_trim_s)::numeric, 1)       as p50_phone_trim_s,
       round(percentile_cont(0.5)  within group (order by phone_upload_s)::numeric, 1)     as p50_phone_upload_s,
       round(percentile_cont(0.5)  within group (order by phone_pre_analyze_s)::numeric, 1) as p50_phone_pre_analyze_s,
       round(count(*) filter (where cold_start is true)::numeric / nullif(count(*), 0), 4) as cold_start_rate
from ops_attempt
where is_staged = false and status = 'analyzed'
group by 1, 2;

comment on view ops_latency_stages is
  'Owner-only: latency percentiles per day x env for analyzed attempts — total + server analyze, decode, '
  'HDR convert, phone trim/upload/pre-analyze (DEC-092 P0), and cold-start rate. Real accounts only. '
  'A stage percentile is NULL when that stage was never timed in the window (NO DATA, not 0).';

-- ===========================================================================
-- Release & regression: compare engine versions / API revisions. Real accounts only.
-- ===========================================================================
create or replace view ops_release_health as
select algorithm_version,
       api_revision,
       env,
       count(*)                                             as attempts,
       count(*) filter (where status = 'failed')            as failures,
       round(count(*) filter (where status = 'failed')::numeric
             / nullif(count(*), 0), 4)                      as failure_rate,
       round(percentile_cont(0.5) within group (order by attempt_seconds)::numeric, 1) as p50_attempt_seconds,
       round(avg(n_measured)::numeric, 1)                   as avg_metrics_measured,
       count(distinct user_id)                              as distinct_users,
       min(created_at)                                      as first_seen,
       max(created_at)                                      as last_seen
from ops_attempt
where is_staged = false
group by 1, 2, 3;

comment on view ops_release_health is
  'Owner-only: per algorithm_version x api_revision x env — attempts, failure_rate, median analyze time, '
  'avg metrics measured, distinct users, first/last seen. For regression comparison across releases (DEC-092). '
  'Real accounts only.';

-- ===========================================================================
-- Feedback / support signal: real feedback only (mirrors feedback_review's staged exclusion).
-- ===========================================================================
create or replace view ops_feedback_summary as
select date_trunc('day', created_at)::date as day,
       app_phase,
       source,
       count(*)                                             as total,
       count(*) filter (where thumbs = 'up')                as thumbs_up,
       count(*) filter (where thumbs = 'down')              as thumbs_down,
       count(*) filter (where triage_status = 'new')        as untriaged,
       round(avg(rating)::numeric, 2)                       as avg_rating
from feedback
where coalesce(is_staged, false) = false
group by 1, 2, 3;

comment on view ops_feedback_summary is
  'Owner-only: real feedback per day x app_phase x source — volume, thumbs up/down, untriaged count, '
  'avg rating. Staged feedback excluded (DEC-063), matching feedback_review.';

-- ===========================================================================
-- Product usage: sessions / shots / active users per day, from the production DB. Real accounts only.
-- shots/sessions carry no env; they are the connected DB's real rows.
-- ===========================================================================
create or replace view ops_usage_daily as
with s as (
  select date_trunc('day', created_at)::date as day, user_id, id
  from shots sh
  where not exists (select 1 from profiles p where p.user_id = sh.user_id and p.is_staged = true)
),
ses as (
  select date_trunc('day', started_at)::date as day, user_id, id
  from sessions se
  where not exists (select 1 from profiles p where p.user_id = se.user_id and p.is_staged = true)
)
select d.day,
       (select count(*) from s where s.day = d.day)                      as shots,
       (select count(distinct user_id) from s where s.day = d.day)       as active_users_shots,
       (select count(*) from ses where ses.day = d.day)                  as sessions_started
from (select distinct day from s union select distinct day from ses) d
order by d.day;

comment on view ops_usage_daily is
  'Owner-only: real-account shots, distinct active users, and sessions started per day (production DB). '
  'Staged accounts excluded.';

-- ===========================================================================
-- Freshness: last-ingested timestamp + row counts per source. Drives the dashboard NO DATA / staleness state.
-- ===========================================================================
create or replace view ops_freshness as
select 'analysis_attempt'::text as source, max(created_at) as last_ingested, count(*) as rows
  from analysis_attempt
union all
select 'feedback', max(created_at), count(*) from feedback
union all
select 'shots', max(created_at), count(*) from shots
union all
select 'sessions', max(started_at), count(*) from sessions;

comment on view ops_freshness is
  'Owner-only: last-ingested timestamp + row count per ops source. The dashboard shows this as the '
  'freshness SLA / last-updated clock and renders NO DATA when a source is empty.';

-- ===========================================================================
-- Coverage status: which of the strategy's 8 observability domains have REAL instrumentation today.
-- This is metadata (not fabricated metrics): it is the honesty backbone so the dashboard can render
-- HEALTHY vs NO DATA (pending §2 instrumentation) distinctly, per PRODUCTION_MONITORING_OBSERVABILITY §5.
-- ===========================================================================
create or replace view ops_coverage_status as
select * from (values
  ('03 Video & AI Trust',    'available',       'analysis_attempt (DEC-086/092)',            'ops_cv_coverage / ops_analysis_daily'),
  ('04 App/API Performance', 'partial',         'analysis_attempt step_timings',             'ops_latency_stages'),
  ('08 Release & Regression','available',       'analysis_attempt algorithm_version/api_revision', 'ops_release_health'),
  ('02 Customer Journey',    'partial',         'shots / sessions counts only',              'ops_usage_daily'),
  ('07 Security & Controls', 'partial',         'feedback triage; no auth-event log yet',    'ops_feedback_summary'),
  ('01 Executive',           'partial',         'derived from the above real sources',       'ops overview'),
  ('05 Storage & DB',        'no_data',         'not instrumented (needs §2)',               null),
  ('06 Financial Operations','no_data',         'no cost metering yet (needs §2)',           null)
) as t(domain, status, data_source, backing_view);

comment on view ops_coverage_status is
  'Owner-only: per observability domain (PRODUCTION_MONITORING_OBSERVABILITY §5) — available|partial|no_data, '
  'the real data source, and the backing ops view. no_data domains are honestly unavailable pending §2 '
  'instrumentation; the dashboard must NOT fabricate numbers for them.';

-- ===========================================================================
-- Access: owner-only. Revoke from clients; grant to the owner marker role. Real reads run as service_role.
-- ===========================================================================
do $$
declare v text;
begin
  foreach v in array array[
    'ops_attempt','ops_analysis_daily','ops_failure_breakdown','ops_cv_coverage','ops_latency_stages',
    'ops_release_health','ops_feedback_summary','ops_usage_daily','ops_freshness','ops_coverage_status'
  ] loop
    execute format('revoke all on %I from anon, authenticated', v);
    execute format('grant select on %I to rules_admin', v);
  end loop;
end $$;
