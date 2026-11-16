-- 038 Feedback Insights: AI-consolidated actions + founder approval + approved work queue (DEC-125).
-- Additive and idempotent. DO NOT apply to live — that is Shayne's step. (Number 038 follows 037_ff_cohort;
-- 036 is taken by feat/ios-lane-parity. Apply 037 before 038 — this migration's incremental marker column is
-- independent, but keep them in order.)
--
-- A scheduled Claude "feedback analyst" job groups new feedback into proposed ACTIONS (insights). The founder
-- approves / edits / defers / rejects / merges them on the owner-only ops dashboard; approving creates a
-- `lanesight-queue` GitHub issue (founder-approved spec only, never raw feedback). Nothing is built without
-- approval (DEC-059 "no live effect").
--
-- SCHEMA CHOICE (deviation from the handoff's "ops schema"): the analyst writes with the service role via
-- PostgREST, and the dashboard reads with the OWNER'S JWT via PostgREST — but PostgREST only exposes `public`,
-- and the `ops` schema is deliberately locked away from every API role (025). So, exactly like the `feedback`
-- table, these live in `public` with RLS and are gated to the owner via `ops.is_owner()` (DEC-098). Same
-- owner-only guarantee, reachable by both writers. The ops dashboard page is still owner-only (middleware +
-- this RLS). See FEEDBACK_STORE_SPEC.md.

-- ---------------------------------------------------------------------------
-- Incremental marker on feedback: which rows an analyst run has already considered (so runs don't re-group old
-- feedback). Written by the analyst (service role). Owner-only columns are already hidden from the bowler by
-- 014's column grants; this column is not in the bowler's select grant, so it stays owner/service-role only.
-- ---------------------------------------------------------------------------
alter table feedback add column if not exists insight_considered_at timestamptz;
create index if not exists feedback_insight_considered_idx on feedback (insight_considered_at);

-- ---------------------------------------------------------------------------
-- feedback_insight — one proposed (or approved / shipped) action.
-- ---------------------------------------------------------------------------
create table if not exists feedback_insight (
  id               uuid primary key default gen_random_uuid(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  title            text not null,
  type             text not null
                     check (type in ('bug','analysis_accuracy','ux_design','feature_idea','content')),
  summary          text not null,
  proposed_change  text,
  affected_area    text,
  priority         text check (priority is null or priority in ('P0','P1','P2','P3')),
  effort           text check (effort is null or effort in ('S','M','L')),
  related_decs     text[] not null default '{}'::text[],
  status           text not null default 'proposed'
                     check (status in ('proposed','approved','deferred','rejected',
                                       'merged','queued','in_progress','pr_open','shipped')),
  founder_notes    text,
  reject_reason    text,
  merged_into      uuid references feedback_insight(id) on delete set null,
  github_issue_number integer,
  pr_url           text,
  approved_at      timestamptz
);

create index if not exists feedback_insight_status_idx   on feedback_insight (status, priority);
create index if not exists feedback_insight_updated_idx   on feedback_insight (updated_at desc);

create or replace function feedback_insight_set_updated_at() returns trigger
  language plpgsql set search_path = public, pg_temp
  as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists feedback_insight_updated on feedback_insight;
create trigger feedback_insight_updated before update on feedback_insight
  for each row execute function feedback_insight_set_updated_at();

-- ---------------------------------------------------------------------------
-- feedback_insight_link — many-to-many between an insight and the feedback rows that are its evidence.
-- ---------------------------------------------------------------------------
-- id is a surrogate PK (NOT the (insight_id, feedback_id) pair): feedback_id is ON DELETE SET NULL so that a
-- link row survives the evidence feedback being purged — a PK column can't be null, so the pair can't be the
-- PK. Uniqueness of the pair is a UNIQUE constraint instead (Postgres treats NULLs as distinct, so a nulled
-- feedback_id never collides). Upserts target this unique constraint via `on_conflict=insight_id,feedback_id`.
create table if not exists feedback_insight_link (
  id           uuid primary key default gen_random_uuid(),
  insight_id   uuid not null references feedback_insight(id) on delete cascade,
  feedback_id  uuid references feedback(id) on delete set null,     -- keep the link row if the feedback is purged
  added_at     timestamptz not null default now(),
  unique (insight_id, feedback_id)
);
create index if not exists feedback_insight_link_fb_idx on feedback_insight_link (feedback_id);
create index if not exists feedback_insight_link_ins_idx on feedback_insight_link (insight_id);

-- ---------------------------------------------------------------------------
-- feedback_insight_run — audit log of each analyst run (cost + token accounting for the DEC-043 cap).
-- ---------------------------------------------------------------------------
create table if not exists feedback_insight_run (
  id                uuid primary key default gen_random_uuid(),
  started_at        timestamptz not null default now(),
  finished_at       timestamptz,
  rows_considered   integer not null default 0,
  insights_created  integer not null default 0,
  insights_updated  integer not null default 0,
  model             text,
  tokens_in         integer not null default 0,
  tokens_out        integer not null default 0,
  cost_usd          numeric(10,4) not null default 0,
  status            text not null default 'running'
                      check (status in ('running','ok','failed','capped')),
  error             text
);
create index if not exists feedback_insight_run_started_idx on feedback_insight_run (started_at desc);

-- ---------------------------------------------------------------------------
-- Access: RLS owner-only via ops.is_owner() (DEC-098). The analyst writes with the service role (bypassrls);
-- the dashboard reads/writes with the owner's JWT, which ops.is_owner() recognises. anon/other users: nothing.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['feedback_insight','feedback_insight_link','feedback_insight_run'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on %I to authenticated', t);
    execute format('grant select, insert, update, delete on %I to rules_admin', t);
    execute format('drop policy if exists owner_all on %I', t);
    execute format($p$create policy owner_all on %I for all to authenticated
                     using (ops.is_owner()) with check (ops.is_owner())$p$, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Owner-only read RPC for the dashboard insights list, mirroring the 025 ops_rpc_* pattern (definer + 42501).
-- The list carries per-insight evidence counts so the page can sort by weight without N+1 queries. Status
-- writes are plain owner-RLS updates from the dashboard (policy owner_all above); this RPC is the read path.
-- ---------------------------------------------------------------------------
create or replace function public.ops_rpc_feedback_insights(p_status text default null)
  returns table (
    id uuid, created_at timestamptz, updated_at timestamptz, approved_at timestamptz,
    title text, type text, summary text, proposed_change text, affected_area text,
    priority text, effort text, related_decs text[], status text, founder_notes text,
    reject_reason text, merged_into uuid, github_issue_number integer, pr_url text,
    feedback_count bigint, bowler_count bigint, phases text[]
  )
  language plpgsql stable security definer set search_path = '' as $$
begin
  if not ops.is_owner() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query
    select i.id, i.created_at, i.updated_at, i.approved_at,
           i.title, i.type, i.summary, i.proposed_change, i.affected_area,
           i.priority, i.effort, i.related_decs, i.status, i.founder_notes,
           i.reject_reason, i.merged_into, i.github_issue_number, i.pr_url,
           count(distinct l.feedback_id)                                   as feedback_count,
           count(distinct f.user_ref)                                      as bowler_count,
           coalesce(array_agg(distinct f.app_phase) filter (where f.app_phase is not null), '{}') as phases
      from public.feedback_insight i
      left join public.feedback_insight_link l on l.insight_id = i.id
      left join public.feedback f on f.id = l.feedback_id
     where p_status is null or i.status = p_status
     group by i.id
     order by array_position(array['P0','P1','P2','P3'], i.priority) nulls last,
              count(distinct l.feedback_id) desc, i.updated_at desc;
end $$;

do $$ begin
  revoke all on function public.ops_rpc_feedback_insights(text) from public, anon;
  grant execute on function public.ops_rpc_feedback_insights(text) to authenticated;
end $$;
