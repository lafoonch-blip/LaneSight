-- 027 Ops instrumentation (DEC-098 §2). Additive, idempotent, read-only for clients.
-- Adds the signals the ops dashboard's partial/no_data domains need, following 025's owner-only pattern:
-- new data lives in retained public tables (written by the service role, locked to clients); aggregates
-- live in the private `ops` schema and are read ONLY through owner-checked SECURITY DEFINER RPCs.
--
-- NOT APPLIED TO LIVE BY CLAUDE CODE. Renumbered 026 -> 027 (026 was taken by arsenal_default_ball + intel_competitor_benchmark, both applied to live).
-- Pairs with app.py/store.py (§2 code) + a Cloud Run redeploy — data flows only after both land.
--
-- Honesty (CLAUDE.md): no fabricated numbers.
--   * M1 cost: the view exposes REAL measured resource-seconds (vcpu_s/gib_s/egress_mb); the USD figure is
--     computed from ops.cost_rates and is NULL (NO DATA) until the owner enters SOURCED provider rates.
--     No rates are seeded — a dollar value is never invented.
--   * Every rate/error ratio uses nullif(denominator,0) -> NULL for an empty window.
--   * Staged accounts excluded from product/usage aggregates via user_ref? No — product_event/api_request
--     carry user_ref (pseudonymous), not user_id, so staged filtering happens upstream in app.py (it only
--     emits product events for real accounts); documented there.

-- ===========================================================================
-- M4 — pseudonymise the analysis attempt (strategy §4/§6). user_ref = hmac(salt, user_id), set in store.py.
-- ===========================================================================
alter table analysis_attempt add column if not exists user_ref text;
create index if not exists analysis_attempt_user_ref_idx on analysis_attempt (user_ref);
comment on column analysis_attempt.user_ref is
  'DEC-098 §2: pseudonymous user id = hmac(LANESIGHT_USER_REF_SALT, user_id). Lets the ops layer/exports key '
  'on the pseudonym instead of the raw auth user id.';

-- M1 — per-attempt cost inputs (real measured resource use; USD derived from sourced rates only).
alter table analysis_attempt add column if not exists cost jsonb;
comment on column analysis_attempt.cost is
  'DEC-098 §2 (best_effort): {basis, compute_s, vcpu, gib, vcpu_s, gib_s, egress_mb, rate_ref}. Resource use '
  'is measured; the dollar value is computed in ops.cost_daily from ops.cost_rates, NULL until rates exist.';

-- ===========================================================================
-- M2 — API request log (retained, owner-only). No bodies/tokens (strategy §4 exclusions) — see app.py.
-- ===========================================================================
create table if not exists api_request (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  env         text,
  api_revision text,
  method      text,
  path        text,              -- templated route, never the raw query string
  status      int,
  duration_ms int,
  user_ref    text               -- pseudonymous (never raw user_id)
);
create index if not exists api_request_created_idx on api_request (created_at desc);
create index if not exists api_request_status_idx  on api_request (status);
comment on table api_request is 'DEC-098 §2: one row per API request (no bodies/tokens). Owner-only via ops.api_daily.';

-- M3 — product events (retained, owner-only). Consent-aware, masked; see app.py /events contract.
create table if not exists product_event (
  id            uuid primary key default gen_random_uuid(),
  occurred_at   timestamptz,
  created_at    timestamptz not null default now(),
  env           text,
  event_name    text not null,
  user_ref      text,            -- pseudonymous
  app_version   text,
  feature       text,
  flow_step     text,
  status        text,
  props         jsonb,
  client_event_id text unique    -- idempotency: a retried client batch never double-counts
);
create index if not exists product_event_name_idx on product_event (event_name, created_at desc);
create index if not exists product_event_user_idx on product_event (user_ref, created_at desc);
comment on table product_event is 'DEC-098 §2: consent-aware product events (masked, pseudonymous). Owner-only via ops.event_daily / ops.funnel.';

-- M5 storage/DB size snapshots (retained, owner-only). In PUBLIC so the service-role REST writer can insert
-- (PostgREST only exposes public); ops.storage_latest reads it. Locked to clients like the others.
create table if not exists storage_snapshot (
  id            uuid primary key default gen_random_uuid(),
  captured_at   timestamptz not null default now(),
  bucket        text,
  bytes         bigint,
  objects       int,
  aged_objects  int,                     -- objects past the retention TTL (strategy §8)
  db_bytes      bigint
);
create index if not exists storage_snapshot_idx on storage_snapshot (captured_at desc);
comment on table storage_snapshot is 'DEC-098 §2: periodic storage/DB size metering (ops/storage_snapshot.py). Owner-only via ops.storage_latest.';

-- Lock the new base tables to clients (service role bypasses; owner reads via RPC).
do $$ begin
  alter table api_request     enable row level security;
  alter table product_event   enable row level security;
  alter table storage_snapshot enable row level security;
exception when others then null; end $$;
revoke all on api_request, product_event, storage_snapshot from anon, authenticated;

-- ===========================================================================
-- M1/M5 owner tables inside the private ops schema
-- ===========================================================================
create table if not exists ops.cost_rates (
  provider      text not null,
  resource      text not null,          -- vcpu_s | gib_s | egress_mb
  usd_per_unit  numeric not null,
  source        text not null,          -- REQUIRED citation; no rate without a source
  effective_from date not null,
  primary key (provider, resource, effective_from)
);
comment on table ops.cost_rates is
  'DEC-098 §2: sourced provider unit prices. EMPTY until the owner enters real rates — ops.cost_daily returns '
  'NULL USD (NO DATA) rather than invent a dollar value.';


-- ===========================================================================
-- ops views + base-table refresh
-- ===========================================================================
-- Re-create ops.attempt to also expose cost + user_ref (appended columns only).
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
       a.user_ref                                                   as user_ref
from public.analysis_attempt a
left join public.profiles p on p.user_id = a.user_id;

-- M1 cost rollup: real resource-seconds per day x env; USD only where a sourced rate exists (else NULL).
create or replace view ops.cost_daily as
with a as (select * from ops.attempt where is_staged = false),
r as (select resource, usd_per_unit from ops.cost_rates
      where effective_from = (select max(effective_from) from ops.cost_rates))
select date_trunc('day', a.created_at)::date as day, a.env,
       count(*)                              as attempts,
       round(sum(a.vcpu_s), 1)               as vcpu_s,
       round(sum(a.gib_s), 1)                as gib_s,
       round(sum(a.egress_mb), 1)            as egress_mb,
       -- est_usd is NULL unless rates exist for the resources used (no invented dollars).
       (round(sum(a.vcpu_s)  * (select usd_per_unit from r where resource='vcpu_s'), 4)
      + round(sum(a.gib_s)   * (select usd_per_unit from r where resource='gib_s'), 4)
      + round(sum(a.egress_mb) * (select usd_per_unit from r where resource='egress_mb'), 4)) as est_usd,
       round(( (round(sum(a.vcpu_s)  * (select usd_per_unit from r where resource='vcpu_s'), 6)
              + round(sum(a.gib_s)   * (select usd_per_unit from r where resource='gib_s'), 6)
              + round(sum(a.egress_mb) * (select usd_per_unit from r where resource='egress_mb'), 6)) )
             / nullif(count(*) filter (where a.status='analyzed'), 0), 4) as est_usd_per_success
from a group by 1, 2;

-- M2 API rollup: day x env x status class; error rate + latency percentiles.
create or replace view ops.api_daily as
select date_trunc('day', created_at)::date as day, env,
       (status / 100)                                    as status_class,
       count(*)                                          as requests,
       count(*) filter (where status >= 500)             as errors_5xx,
       count(*) filter (where status >= 400 and status < 500) as errors_4xx,
       round(count(*) filter (where status >= 500)::numeric / nullif(count(*),0), 4) as error_rate_5xx,
       round(percentile_cont(0.5)  within group (order by duration_ms)::numeric, 0) as p50_ms,
       round(percentile_cont(0.95) within group (order by duration_ms)::numeric, 0) as p95_ms
from api_request group by 1, 2, 3;

-- M3 events rollup + a signup -> first-successful-shot funnel.
create or replace view ops.event_daily as
select date_trunc('day', created_at)::date as day, env, event_name,
       count(*)                      as events,
       count(distinct user_ref)      as users
from product_event group by 1, 2, 3;

create or replace view ops.funnel as
select env,
       count(distinct user_ref) filter (where event_name = 'app_opened')          as opened,
       count(distinct user_ref) filter (where event_name = 'session_started')      as started_session,
       count(distinct user_ref) filter (where event_name = 'first_shot_analyzed')  as first_shot
from product_event group by 1;

-- M5 latest storage snapshot per bucket.
create or replace view ops.storage_latest as
select distinct on (bucket) bucket, bytes, objects, aged_objects, db_bytes, captured_at
from public.storage_snapshot order by bucket, captured_at desc;

-- Refresh coverage status: the two no_data domains are now instrumented (data flows after apply + redeploy).
create or replace view ops.coverage_status as
select * from (values
  ('03 Video & AI Trust',    'available','analysis_attempt (DEC-086/092)',                 'ops.cv_coverage / ops.analysis_daily'),
  ('04 App/API Performance', 'available','analysis_attempt + api_request (§2 M2)',         'ops.latency_stages / ops.api_daily'),
  ('08 Release & Regression','available','analysis_attempt algorithm_version/api_revision','ops.release_health'),
  ('02 Customer Journey',    'available','shots/sessions + product_event (§2 M3)',         'ops.usage_daily / ops.funnel / ops.event_daily'),
  ('07 Security & Controls', 'partial',  'feedback triage; no auth-event log yet',         'ops.feedback_summary'),
  ('01 Executive',           'partial',  'derived from the above real sources',            'ops overview'),
  ('05 Storage & DB',        'available','ops.storage_snapshot (§2 M5)',                    'ops.storage_latest'),
  ('06 Financial Operations','available','analysis_attempt.cost (§2 M1); USD needs sourced rates','ops.cost_daily')
) as t(domain, status, data_source, backing_view);

-- Belt-and-braces revoke on any new ops views.
do $$ declare r record; begin
  for r in select table_name from information_schema.views where table_schema='ops' loop
    execute format('revoke all on ops.%I from anon, authenticated, public', r.table_name);
  end loop;
end $$;

-- ===========================================================================
-- Owner-checked RPCs for the new views (same pattern as 025).
-- ===========================================================================
create or replace function public.ops_rpc_cost_daily(p_envs text[], p_since date)
  returns setof ops.cost_daily language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.cost_daily v where v.env = any(p_envs) and v.day >= p_since;
end $$;

create or replace function public.ops_rpc_api_daily(p_envs text[], p_since date)
  returns setof ops.api_daily language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.api_daily v where v.env = any(p_envs) and v.day >= p_since;
end $$;

create or replace function public.ops_rpc_event_daily(p_envs text[], p_since date)
  returns setof ops.event_daily language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.event_daily v where v.env = any(p_envs) and v.day >= p_since;
end $$;

create or replace function public.ops_rpc_funnel(p_envs text[])
  returns setof ops.funnel language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.funnel v where v.env = any(p_envs);
end $$;

create or replace function public.ops_rpc_storage_latest()
  returns setof ops.storage_latest language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.storage_latest;
end $$;

do $$ declare fn text; begin
  foreach fn in array array[
    'public.ops_rpc_cost_daily(text[],date)','public.ops_rpc_api_daily(text[],date)',
    'public.ops_rpc_event_daily(text[],date)','public.ops_rpc_funnel(text[])',
    'public.ops_rpc_storage_latest()'
  ] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;
