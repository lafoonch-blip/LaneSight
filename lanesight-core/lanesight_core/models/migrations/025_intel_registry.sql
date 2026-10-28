-- 025 Industry intelligence & opportunity registry (DEC-098, 02_RESEARCH/intel/WEEKLY_OPPORTUNITY_ANALYZER.md).
-- Additive and idempotent. Business data, NOT app data: lives in its own `intel` schema, which is not
-- exposed to the app's API roles. Only the owner (service_role / Supabase SQL connector) reads or writes it.
--
--   intel.run           one row per analyzer run (weekly), with the brief it produced
--   intel.opportunity   one row per tracked development; scores, band, pillars, lifecycle, next action
--   intel.score_history every (re)score of an opportunity, so score drift is visible over time
--   intel.decision      Shayne's decisions and measured outcomes per opportunity (the feedback loop)
--   intel.theme         recurring themes and the opportunities that evidence them
--
-- Retention: nothing is deleted. Archive is a band, not a delete; `rejected` / `closed` are statuses.

create schema if not exists intel;
revoke all on schema intel from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Runs
-- ---------------------------------------------------------------------------
create table if not exists intel.run (
  id             uuid primary key default gen_random_uuid(),
  run_type       text not null default 'weekly' check (run_type in ('weekly','manual','backfill')),
  started_at     timestamptz not null default now(),
  finished_at    timestamptz,
  window_start   date,
  window_end     date,
  sources_checked text[] not null default '{}',
  sources_failed  text[] not null default '{}',
  items_new      int not null default 0,
  items_updated  int not null default 0,
  brief_md       text,              -- the full weekly brief as delivered
  top_actions    jsonb,             -- [{rank, opportunity_id, action, why, effort}]
  notes          text
);

-- ---------------------------------------------------------------------------
-- Opportunities (every meaningful development, acted on or not)
-- ---------------------------------------------------------------------------
create table if not exists intel.opportunity (
  id               uuid primary key default gen_random_uuid(),
  dedupe_key       text not null unique,   -- lower(entity)|event-slug|yyyy-mm  (see runbook)
  title            text not null,
  summary          text not null,          -- what happened (fact only)
  why_it_matters   text,                   -- hypothesis: why it matters to LaneSight
  category         text not null check (category in (
                     'product_feature','integration_api','distribution_channel','creator_influencer',
                     'coaching','tournament_event','regulatory_policy','competitor_threat','user_insight')),
  pillars          text[] not null default '{}' check (pillars <@ array[
                     'product','engineering_technology','marketing_growth','partnerships','finance',
                     'competitive_strategy']::text[]),
  entities         text[] not null default '{}',
  source_urls      text[] not null default '{}',
  published_at     date,                   -- when the source was published
  event_date       date,                   -- when the thing happens/happened (may differ)
  evidence_level   text not null default 'secondary'
                     check (evidence_level in ('primary','secondary','community','rumor')),
  -- Score components (strategy doc §4); total and band are derived, never hand-set.
  strategic_fit    smallint not null check (strategic_fit between 0 and 25),
  impact           smallint not null check (impact between 0 and 25),
  urgency          smallint not null check (urgency between 0 and 15),
  feasibility      smallint not null check (feasibility between 0 and 15),
  confidence       smallint not null check (confidence between 0 and 10),
  differentiation  smallint not null check (differentiation between 0 and 10),
  risk_critical    boolean not null default false,   -- rule/privacy/competition risk: never below Investigate
  score            smallint generated always as
                     (strategic_fit + impact + urgency + feasibility + confidence + differentiation) stored,
  band             text generated always as (
                     case
                       when strategic_fit + impact + urgency + feasibility + confidence + differentiation >= 80 then 'act'
                       when strategic_fit + impact + urgency + feasibility + confidence + differentiation >= 60 or risk_critical then 'investigate'
                       when strategic_fit + impact + urgency + feasibility + confidence + differentiation >= 40 then 'monitor'
                       else 'archive'
                     end) stored,
  score_rationale  text,
  status           text not null default 'new' check (status in (
                     'new','triaged','researching','outreach_planned','contacted','evaluating','approved',
                     'executing','measured','closed','watchlist','rejected')),
  owner            text not null default 'Shayne',
  next_action      text,
  due_date         date,
  estimated_cost   text,
  expected_outcome text,
  related_ids      uuid[] not null default '{}',
  first_run_id     uuid references intel.run(id) on delete set null,
  first_seen_at    timestamptz not null default now(),
  last_seen_at     timestamptz not null default now(),
  last_scored_at   timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists opportunity_band_idx on intel.opportunity (band, score desc);
create index if not exists opportunity_status_idx on intel.opportunity (status);
create index if not exists opportunity_pillars_idx on intel.opportunity using gin (pillars);

-- ---------------------------------------------------------------------------
-- Score history (every score write, including the first)
-- ---------------------------------------------------------------------------
create table if not exists intel.score_history (
  id              bigint generated always as identity primary key,
  opportunity_id  uuid not null references intel.opportunity(id) on delete cascade,
  run_id          uuid references intel.run(id) on delete set null,
  scored_at       timestamptz not null default now(),
  strategic_fit   smallint, impact smallint, urgency smallint, feasibility smallint,
  confidence      smallint, differentiation smallint, risk_critical boolean,
  score           smallint, band text,
  rationale       text
);

create or replace function intel.log_score() returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT'
     or (new.strategic_fit, new.impact, new.urgency, new.feasibility, new.confidence, new.differentiation, new.risk_critical)
        is distinct from
        (old.strategic_fit, old.impact, old.urgency, old.feasibility, old.confidence, old.differentiation, old.risk_critical)
  then
    insert into intel.score_history (opportunity_id, run_id, strategic_fit, impact, urgency, feasibility,
                                     confidence, differentiation, risk_critical, score, band, rationale)
    values (new.id, nullif(current_setting('intel.run_id', true), '')::uuid, new.strategic_fit, new.impact, new.urgency,
            new.feasibility, new.confidence, new.differentiation, new.risk_critical, new.score, new.band,
            new.score_rationale);
  end if;
  return null;
end $$;
drop trigger if exists opportunity_score_log on intel.opportunity;
create trigger opportunity_score_log after insert or update on intel.opportunity
  for each row execute function intel.log_score();

create or replace function intel.touch() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists opportunity_touch on intel.opportunity;
create trigger opportunity_touch before update on intel.opportunity
  for each row execute function intel.touch();

-- ---------------------------------------------------------------------------
-- Decisions & outcomes (written when Shayne decides; the analyzer only proposes)
-- ---------------------------------------------------------------------------
create table if not exists intel.decision (
  id              bigint generated always as identity primary key,
  opportunity_id  uuid not null references intel.opportunity(id) on delete cascade,
  decided_at      timestamptz not null default now(),
  decided_by      text not null default 'Shayne',
  decision        text not null check (decision in ('act','investigate','monitor','archive','reject','defer')),
  action_taken    text,
  outcome         text,             -- filled later: what happened (measured result)
  outcome_at      timestamptz,
  repo_ref        text,             -- DEC id / PR / doc path if it changed strategy
  notes           text
);

-- ---------------------------------------------------------------------------
-- Recurring themes (patterns across many items, e.g. "release consistency demand")
-- ---------------------------------------------------------------------------
create table if not exists intel.theme (
  id               uuid primary key default gen_random_uuid(),
  name             text not null unique,
  description      text,
  pillars          text[] not null default '{}',
  opportunity_ids  uuid[] not null default '{}',
  evidence_count   int generated always as (coalesce(array_length(opportunity_ids, 1), 0)) stored,
  first_seen_at    timestamptz not null default now(),
  last_seen_at     timestamptz not null default now(),
  status           text not null default 'emerging' check (status in ('emerging','established','fading','retired'))
);

-- ---------------------------------------------------------------------------
-- Access: owner only. RLS on with no policies = deny for every API role; service_role bypasses.
-- ---------------------------------------------------------------------------
alter table intel.run           enable row level security;
alter table intel.opportunity   enable row level security;
alter table intel.score_history enable row level security;
alter table intel.decision      enable row level security;
alter table intel.theme         enable row level security;
revoke all on all tables in schema intel from public, anon, authenticated;
revoke all on all functions in schema intel from public, anon, authenticated;
