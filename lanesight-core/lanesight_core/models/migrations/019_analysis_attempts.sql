-- 019 Analysis failure tracking (DEC-086, HANDOFF_2026-10-27_UPLOAD_FAILURES_AND_LAB_UPLOADS). Additive + idempotent.
-- Two things:
--   1. shots gains analysis_status / failure_code / failure_stage / analyzed_at so a failed analysis is a
--      first-class state (Lab › Uploads can show "Couldn't analyze"), and algorithm_version (already a column)
--      is filled on every analysis by the API.
--   2. a RETAINED analysis_attempt log — one row per attempt, successes included (rates need a denominator).
--      Like feedback (DEC-059) it carries NO FK to shots/users (plain uuids), so it survives shot/account
--      deletion and the score reset: it's the long-term record of what LaneSight could and couldn't analyze.
-- DO NOT apply to live — that is Shayne's step.

-- ---------------------------------------------------------------------------
-- shots: failure state + analyzed timestamp
-- ---------------------------------------------------------------------------
alter table shots
  add column if not exists analysis_status text,          -- pending | running | analyzed | failed
  add column if not exists failure_code    text,
  add column if not exists failure_stage   text,
  add column if not exists analyzed_at      timestamptz;

do $$ begin
  alter table shots add constraint shots_analysis_status_chk
    check (analysis_status is null or analysis_status in ('pending','running','analyzed','failed'));
exception when duplicate_object then null; end $$;

create index if not exists shots_analysis_status_idx on shots (analysis_status);
create index if not exists shots_failure_code_idx    on shots (failure_code);

comment on column shots.analysis_status is
  'pending|running|analyzed|failed (DEC-086). Source of truth for Lab › Uploads row state.';
comment on column shots.failure_code is  'stable AnalysisFailure code when analysis_status = failed (DEC-086).';
comment on column shots.failure_stage is 'pipeline stage the failure was attributed to (DEC-086).';

-- Backfill existing rows: a non-empty record = analyzed; an empty/null record = a legacy failure.
update shots set analysis_status = 'analyzed', analyzed_at = coalesce(analyzed_at, created_at)
  where analysis_status is null and record is not null and record <> '{}'::jsonb;
update shots set analysis_status = 'failed', failure_code = 'UNKNOWN_LEGACY', failure_stage = 'internal'
  where analysis_status is null and (record is null or record = '{}'::jsonb);

-- ---------------------------------------------------------------------------
-- analysis_attempt — retained log of every analysis attempt (success + failure). No FK cascade.
-- ---------------------------------------------------------------------------
create table if not exists analysis_attempt (
  id                uuid primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),
  user_id           uuid,                      -- plain uuid (NOT a FK): the row outlives the account
  shot_id           uuid,                      -- plain uuid (NOT a FK): the row outlives the shot
  session_id        uuid,
  source            text,                      -- upload | live
  capture_mode      text,                      -- shot | form
  status            text not null,             -- analyzed | failed
  failure_code      text,
  failure_stage     text,
  diagnostics       jsonb,
  algorithm_version text,
  api_revision      text,                      -- Cloud Run revision (K_REVISION)
  duration_ms       integer,
  step_timings      jsonb,
  content_hash      text,                      -- groups repeat uploads of the same clip
  clip              jsonb,                     -- {fps,width,height,duration_s,codec,hdr,bytes}
  env               text                       -- dev | beta | live
);

do $$ begin
  alter table analysis_attempt add constraint analysis_attempt_status_chk
    check (status in ('analyzed','failed'));
exception when duplicate_object then null; end $$;

create index if not exists analysis_attempt_created_idx     on analysis_attempt (created_at desc);
create index if not exists analysis_attempt_user_idx        on analysis_attempt (user_id, created_at desc);
create index if not exists analysis_attempt_failure_idx     on analysis_attempt (failure_code);
create index if not exists analysis_attempt_algo_idx        on analysis_attempt (algorithm_version);
create index if not exists analysis_attempt_content_idx     on analysis_attempt (content_hash);

comment on table analysis_attempt is
  'DEC-086: one row per analysis attempt (success + failure), retained like feedback (no FK cascade). Short-term '
  'failure triage + long-term analysis-capability trend data.';

-- Access: owner-only read; all writes go through the service role (bypassrls), which the API uses.
alter table analysis_attempt enable row level security;
revoke all on analysis_attempt from authenticated;
grant select on analysis_attempt to authenticated;

do $$ begin
  create policy own_select on analysis_attempt for select to authenticated
    using (user_id = (select auth.uid()));
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Failure-rate trend view (day × algorithm_version × capture_mode × failure_code).
-- ---------------------------------------------------------------------------
create or replace view analysis_failure_rates as
select date_trunc('day', created_at)::date as day,
       algorithm_version,
       capture_mode,
       failure_code,
       count(*)                                        as attempts,
       count(*) filter (where status = 'failed')       as failures,
       round(count(*) filter (where status = 'failed')::numeric / nullif(count(*), 0), 4) as failure_rate
from analysis_attempt
group by 1, 2, 3, 4;

comment on view analysis_failure_rates is
  'DEC-086: analysis attempts/failures/rate by day, engine version, capture mode and failure code.';
