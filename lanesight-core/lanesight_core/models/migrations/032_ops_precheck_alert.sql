-- 032 — ops: precheck enforcement monitoring + false-rejection alert (2026-10-29).
--
-- With LANESIGHT_PRECHECK_ENFORCE=1, a confident framing reject fails fast (no 2-min wait) and is logged as an
-- analysis_attempt with status='failed' and diagnostics->>'precheck'='true'. We can't re-run the pipeline on a
-- rejected clip (that would defeat the fast-fail), so the false-rejection SAFETY NET is content-hash based: if
-- the SAME clip (content_hash) was precheck-rejected in one attempt AND analyzed successfully in another (e.g.
-- the bowler re-uploaded a good clip the precheck wrongly rejected), that's a real false rejection to review.
-- Additive: two views + owner-gated RPCs, no data change.
set search_path = public;

-- Daily agreement: precheck verdict (reject / inconclusive / pass / none) vs the pipeline outcome, for the
-- clips that DID run (not the enforced rejects) — ongoing version of the ops/precheck_vs_pipeline table.
create or replace view ops.precheck_agreement_daily as
select date_trunc('day', created_at)::date as day, env,
       case when (clip->'precheck'->>'ok') = 'true'  then 'pass'
            when (clip->'precheck'->>'ok') = 'false' then 'reject'
            when clip->'precheck' ? 'ok'             then 'inconclusive'
            else 'none' end                                  as precheck,
       status                                                as pipeline,
       count(*)                                              as attempts
from analysis_attempt
where platform = 'server' and capture_mode = 'shot'
group by 1, 2, 3, 4;
comment on view ops.precheck_agreement_daily is
  'DEC-092 — precheck verdict vs pipeline outcome per day. A reject→analyzed cell is a false rejection (should be 0).';

-- The alert: a clip precheck-rejected in one attempt that analyzed in another (same content_hash) — i.e. the
-- enforced precheck turned away a clip the pipeline can actually read. Should always be EMPTY.
create or replace view ops.precheck_false_rejections as
with rejected as (
  select distinct content_hash, user_id
  from analysis_attempt
  where status = 'failed' and (diagnostics->>'precheck') = 'true' and content_hash is not null
),
ok_runs as (
  select distinct content_hash from analysis_attempt where status = 'analyzed' and content_hash is not null
)
select r.content_hash, r.user_id,
       (select max(created_at) from analysis_attempt a
        where a.content_hash = r.content_hash and a.status = 'analyzed')  as analyzed_at
from rejected r join ok_runs o on o.content_hash = r.content_hash;
comment on view ops.precheck_false_rejections is
  'ALERT (should be empty): a clip the enforced precheck REJECTED that the pipeline analyzed on another attempt.';

create or replace function public.ops_rpc_precheck_agreement_daily(p_envs text[], p_since date)
  returns setof ops.precheck_agreement_daily language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.precheck_agreement_daily v where v.env = any(p_envs) and v.day >= p_since;
end $$;

create or replace function public.ops_rpc_precheck_false_rejections()
  returns setof ops.precheck_false_rejections language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query select * from ops.precheck_false_rejections;
end $$;

do $$ declare fn text; begin
  foreach fn in array array[
    'public.ops_rpc_precheck_agreement_daily(text[],date)', 'public.ops_rpc_precheck_false_rejections()'
  ] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;
