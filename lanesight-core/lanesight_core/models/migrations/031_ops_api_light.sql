-- 031 — ops: non-analysis ("light") API latency/error panel (P0 2026-10-29).
--
-- ops.api_daily mixes the multi-minute synchronous analysis endpoints in with the light API (home, score,
-- sessions, achievements), so its p95 is dominated by analyses and can't show whether the light API — the
-- part that fails on launch when the single instance is busy (the 'couldn't reach' bug) — is healthy. This
-- adds a light-only view that EXCLUDES the three heavy analysis routes, plus a heavy-only view for symmetry,
-- and owner-gated RPCs matching the 027 pattern. Purely additive: two views + two functions, no data change.
set search_path = public;

-- Templated heavy routes (api_request.path is already low-cardinality, ids collapsed to ':id'): create_shot,
-- the upload analyze, and the standalone analyze all run the pipeline synchronously.
create or replace view ops.api_daily_light as
select date_trunc('day', created_at)::date as day, env,
       (status / 100)                                         as status_class,
       count(*)                                               as requests,
       count(*) filter (where status >= 500)                  as errors_5xx,
       count(*) filter (where status >= 400 and status < 500) as errors_4xx,
       round(count(*) filter (where status >= 500)::numeric / nullif(count(*),0), 4) as error_rate_5xx,
       round(percentile_cont(0.5)  within group (order by duration_ms)::numeric, 0)  as p50_ms,
       round(percentile_cont(0.95) within group (order by duration_ms)::numeric, 0)  as p95_ms
from api_request
where path not in ('/sessions/:id/shots', '/uploads', '/shots/analyze')
group by 1, 2, 3;
comment on view ops.api_daily_light is
  'DEC-098 §2 — the light API only (home/score/sessions/etc.), analysis routes excluded, so launch-time latency/errors are visible without the 2-min analyses skewing p95 (P0 2026-10-29).';

create or replace view ops.api_daily_heavy as
select date_trunc('day', created_at)::date as day, env, path,
       count(*)                                               as requests,
       count(*) filter (where status >= 500)                  as errors_5xx,
       round(percentile_cont(0.5)  within group (order by duration_ms)::numeric, 0)  as p50_ms,
       round(percentile_cont(0.95) within group (order by duration_ms)::numeric, 0)  as p95_ms
from api_request
where path in ('/sessions/:id/shots', '/uploads', '/shots/analyze')
group by 1, 2, 3;
comment on view ops.api_daily_heavy is
  'DEC-098 §2 — the synchronous analysis routes only, split by path (end-to-end upload+analyze latency).';

create or replace function public.ops_rpc_api_daily_light(p_envs text[], p_since date)
  returns setof ops.api_daily_light language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.api_daily_light v where v.env = any(p_envs) and v.day >= p_since;
end $$;

create or replace function public.ops_rpc_api_daily_heavy(p_envs text[], p_since date)
  returns setof ops.api_daily_heavy language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.api_daily_heavy v where v.env = any(p_envs) and v.day >= p_since;
end $$;

do $$ declare fn text; begin
  foreach fn in array array[
    'public.ops_rpc_api_daily_light(text[],date)', 'public.ops_rpc_api_daily_heavy(text[],date)'
  ] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;
