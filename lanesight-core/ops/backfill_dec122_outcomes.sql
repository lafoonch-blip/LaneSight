-- DEC-122 §4/§6 — one-off 14-day backfill of analysis_metric_outcome + analysis_stage_outcome from existing
-- analysis_attempt + measurements rows. Best-effort (pre-DEC-122 attempts have no per-stage report):
--   * metric outcomes: the measurements of each shot, attached to that shot's LATEST analyzed non-staged
--     attempt in the window. value NULL <=> status 'unavailable' (the table's honesty invariant).
--   * stage outcomes: one 'failed' row per failed non-staged attempt (its failure_stage/failure_code). Analyzed
--     attempts have no historical per-stage breakdown, so none is invented — forward attempts carry the full
--     stage report via the engine writer (store.log_outcomes).
-- Idempotent: on conflict do nothing. Ran once against live on 2026-11-02 (metric_rows=1142 over 61 attempts,
-- stage_rows=37, honesty_violations=0). Staged/test accounts excluded.

with latest as (
  select distinct on (a.shot_id) a.id as attempt_id, a.shot_id, a.capture_mode,
         case when a.platform='ios' then 'iphone' else 'server' end as engine, a.algorithm_version
  from public.analysis_attempt a
  left join public.profiles p on p.user_id = a.user_id
  where a.created_at > now() - interval '14 days' and coalesce(p.is_staged,false) = false
    and a.status = 'analyzed' and a.shot_id is not null
  order by a.shot_id, a.created_at desc
),
mapped as (
  select l.attempt_id, l.engine, l.algorithm_version, l.capture_mode, m.metric, m.unit, m.confidence, m.note,
         m.value as rawval,
         case when m.value is null then 'unavailable'
              when m.status = 'unavailable' then 'unavailable'
              when m.status = 'ok' then 'measured'
              when m.status in ('best_effort','low_confidence','calibrated_estimate') then m.status
              else 'measured' end as mstatus
  from latest l
  join public.measurements m on m.shot_id = l.shot_id
  join public.metric_catalog c on c.metric_key = m.metric and c.capture_mode = l.capture_mode
)
insert into public.analysis_metric_outcome
  (attempt_id, engine, engine_version, capture_mode, metric_key, unit, status, value, confidence, reason_detail)
select attempt_id, engine, algorithm_version, capture_mode, metric, unit,
       mstatus::public.metric_outcome_status,
       case when mstatus = 'unavailable' then null else rawval end,
       confidence, left(note, 500)
from mapped
on conflict (attempt_id, metric_key) do nothing;

insert into public.analysis_stage_outcome (attempt_id, engine, engine_version, capture_mode, stage, status, reason_code)
select a.id, case when a.platform='ios' then 'iphone' else 'server' end, a.algorithm_version, a.capture_mode,
       a.failure_stage, 'failed', a.failure_code
from public.analysis_attempt a
left join public.profiles p on p.user_id = a.user_id
where a.created_at > now() - interval '14 days' and coalesce(p.is_staged,false) = false
  and a.status = 'failed' and a.failure_stage is not null
on conflict (attempt_id, stage) do nothing;
