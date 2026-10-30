-- 034 — Durable analysis jobs (Part 3a, 2026-10-30). The job queue was in-process only (jobs.py
-- SerialJobQueue._jobs dict), so GET /jobs/:id returned 404 whenever the poll landed on a different Cloud Run
-- instance than the one that ran the analysis, or after the instance scaled to zero / restarted. That is the
-- "analysis hang + lost session" root cause: the shot analyzed and persisted, but the client could never
-- resolve its job again. This table makes a job resolvable on ANY instance and after a restart.
--
-- The queue writes a row on submit (queued), on start (running) and on finish (done/failed); GET /jobs/:id
-- reads in-memory first, then falls back to this table. result/failure/timings are the SAME shapes the
-- in-memory Job.public() returns, so the client decode path is unchanged.
create table if not exists analysis_job (
  id          text primary key,              -- Job.id (uuid4 hex), matches the job_id the POST returns
  user_id     uuid not null references auth.users(id) on delete cascade,
  shot_id     uuid,                           -- the shot this job analyzes (null before it is known)
  kind        text not null,                  -- 'analyze' | ...
  state       text not null default 'queued', -- queued | running | done | failed
  reason      text,                           -- "CODE: message" back-compat string
  result      jsonb,                          -- the success payload (shot_id + footer), null until done
  failure     jsonb,                          -- {code, stage, user_title, user_message, tip}, null on success
  timings     jsonb,                          -- flat {step: seconds}
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists analysis_job_user_idx on analysis_job(user_id, created_at desc);
-- Reap old finished jobs opportunistically (a client that never came back). The row is only a resume aid;
-- the shot result itself lives on the shot row. 7 days is well beyond any foreground/relaunch window.
create index if not exists analysis_job_stale_idx on analysis_job(updated_at) where state in ('done', 'failed');

-- Bump updated_at on every upsert (the API omits timestamps; created_at defaults on insert). Lets a
-- long-running job's row stay fresh and keeps the stale-reap index meaningful.
create or replace function analysis_job_touch() returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql;
drop trigger if exists analysis_job_touch_trg on analysis_job;
create trigger analysis_job_touch_trg before update on analysis_job
  for each row execute function analysis_job_touch();

alter table analysis_job enable row level security;
-- Service role (the API) bypasses RLS; this policy only matters if the anon/auth key ever reads directly.
drop policy if exists analysis_job_owner on analysis_job;
create policy analysis_job_owner on analysis_job
  for select using (auth.uid() = user_id);
