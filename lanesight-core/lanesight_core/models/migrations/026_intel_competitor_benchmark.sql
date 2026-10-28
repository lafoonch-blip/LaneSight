-- 026 Weekly competitor benchmark + write functions for the unattended analyzer (DEC-099).
-- Additive and idempotent. intel schema only; nothing in app schemas changes.
--
-- Why the functions: the Supabase connector asks for an interactive confirmation on UPDATE statements.
-- A scheduled run has nobody to answer it, so the run could insert items but never close its run row or
-- update an existing item (2026-10-28, run 7b870931). Shayne approved routing the analyzer's updates
-- through these narrow, intel-only functions, called with SELECT. They update; they never delete.
--
--   intel.competitor           one row per tracked competitor / adjacent product (static identity)
--   intel.competitor_snapshot  append-only weekly benchmark per competitor (insert-only; history = rows)
--   intel.finish_run()         close a run row (counts, sources, top actions, brief)
--   intel.update_opportunity() patch an opportunity from an allowlist of columns; can append sources
--   intel.update_theme()       patch a theme; can append opportunity ids

-- ---------------------------------------------------------------------------
-- Competitors
-- ---------------------------------------------------------------------------
create table if not exists intel.competitor (
  id              uuid primary key default gen_random_uuid(),
  slug            text not null unique,            -- lower-case, e.g. 'lanetrax'
  name            text not null,
  kind            text not null check (kind in (
                    'phone_video_metrics',   -- phone/camera ball metrics (LaneTrax, Bowlin)
                    'center_camera',         -- installed camera/tracking systems (Specto)
                    'ball_sensor',           -- in-ball/wearable sensors (Ruby, Witsee, BowlSense, F5)
                    'coach_platform',        -- coach feedback / practice tools (BowlersAI)
                    'scoring_stats',         -- scoring/stat apps (LaneTalk, LeaguePals)
                    'other')),
  website         text,
  opportunity_id  uuid references intel.opportunity(id) on delete set null,  -- its registry item, if any
  first_seen_at   timestamptz not null default now()
);

create table if not exists intel.competitor_snapshot (
  id                 bigint generated always as identity primary key,
  competitor_id      uuid not null references intel.competitor(id) on delete cascade,
  run_id             uuid references intel.run(id) on delete set null,
  captured_at        timestamptz not null default now(),
  status             text not null default 'active' check (status in ('active','beta','preorder','discontinued','unknown')),
  platforms          text[] not null default '{}',     -- ios, android, web, pc, center
  hardware_required  text,                             -- e.g. 'phone + tripod', 'in-ball sensor', 'center install'
  price_summary      text,                             -- as published, with currency, e.g. '$9.99/mo or $89.99/yr; 30-day trial'
  metrics_claimed    text[] not null default '{}',     -- as the vendor names them
  form_analysis      boolean,                          -- claims body/pose/form analysis (null = not stated)
  coaching           boolean,                          -- coach workflow or automated advice (null = not stated)
  latest_version     text,
  version_date       date,
  rating             numeric(3,2),
  rating_count       int,
  downloads          text,                             -- as published ('25k+')
  changes            text,                             -- what changed since the previous snapshot; 'no change' allowed
  lanesight_gap      text,                             -- hypothesis: where they lead / trail LaneSight (labeled)
  evidence_level     text not null default 'secondary'
                       check (evidence_level in ('primary','secondary','community','rumor')),
  source_urls        text[] not null default '{}',     -- every page actually read for this snapshot
  unverified         text[] not null default '{}',     -- fields that could not be confirmed this week
  unique (competitor_id, run_id)
);
create index if not exists competitor_snapshot_comp_idx on intel.competitor_snapshot (competitor_id, captured_at desc);

-- ---------------------------------------------------------------------------
-- Write functions (SELECT-callable). Invoker rights; owner-only grants below.
-- ---------------------------------------------------------------------------
create or replace function intel.finish_run(
  p_run_id          uuid,
  p_items_new       int,
  p_items_updated   int,
  p_sources_checked text[],
  p_sources_failed  text[],
  p_top_actions     jsonb,
  p_brief_md        text,
  p_notes           text default null
) returns intel.run language plpgsql set search_path = '' as $$
declare r intel.run;
begin
  update intel.run set
    finished_at     = now(),
    items_new       = p_items_new,
    items_updated   = p_items_updated,
    sources_checked = coalesce(p_sources_checked, '{}'),
    sources_failed  = coalesce(p_sources_failed, '{}'),
    top_actions     = p_top_actions,
    brief_md        = p_brief_md,
    notes           = coalesce(p_notes, notes)
  where id = p_run_id
  returning * into r;
  if not found then raise exception 'intel.finish_run: run % not found', p_run_id; end if;
  return r;
end $$;

-- Patch keys allowed: any of the columns listed in v_allowed. Extra key 'add_source_urls' (json array)
-- appends URLs not already present. score/band are generated and can't be set; ids and first_* are fixed.
-- When any score component changes, last_scored_at is set and the score_history trigger logs it
-- (tagged with p_run_id).
create or replace function intel.update_opportunity(
  p_id     uuid,
  p_patch  jsonb,
  p_run_id uuid default null
) returns intel.opportunity language plpgsql set search_path = '' as $$
declare
  v_allowed text[] := array['title','summary','why_it_matters','category','pillars','entities','source_urls',
    'published_at','event_date','evidence_level','strategic_fit','impact','urgency','feasibility','confidence',
    'differentiation','risk_critical','score_rationale','status','owner','next_action','due_date',
    'estimated_cost','expected_outcome','related_ids','last_seen_at'];
  v_bad   text[];
  o       intel.opportunity;
  n       intel.opportunity;
  v_add   text[];
begin
  select array_agg(k) into v_bad
  from jsonb_object_keys(p_patch) k
  where k <> 'add_source_urls' and k <> all (v_allowed);
  if v_bad is not null then
    raise exception 'intel.update_opportunity: keys not allowed: %', v_bad;
  end if;

  select * into o from intel.opportunity where id = p_id for update;
  if not found then raise exception 'intel.update_opportunity: opportunity % not found', p_id; end if;

  n := jsonb_populate_record(o, p_patch - 'add_source_urls');
  v_add := coalesce(array(select jsonb_array_elements_text(p_patch->'add_source_urls')), '{}');

  if p_run_id is not null then
    perform set_config('intel.run_id', p_run_id::text, true);
  end if;

  update intel.opportunity set
    title = n.title, summary = n.summary, why_it_matters = n.why_it_matters, category = n.category,
    pillars = n.pillars, entities = n.entities,
    source_urls = n.source_urls || array(select u from unnest(v_add) u where u <> all (n.source_urls)),
    published_at = n.published_at, event_date = n.event_date, evidence_level = n.evidence_level,
    strategic_fit = n.strategic_fit, impact = n.impact, urgency = n.urgency, feasibility = n.feasibility,
    confidence = n.confidence, differentiation = n.differentiation, risk_critical = n.risk_critical,
    score_rationale = n.score_rationale, status = n.status, owner = n.owner, next_action = n.next_action,
    due_date = n.due_date, estimated_cost = n.estimated_cost, expected_outcome = n.expected_outcome,
    related_ids = n.related_ids, last_seen_at = n.last_seen_at,
    last_scored_at = case
      when (n.strategic_fit, n.impact, n.urgency, n.feasibility, n.confidence, n.differentiation, n.risk_critical)
           is distinct from
           (o.strategic_fit, o.impact, o.urgency, o.feasibility, o.confidence, o.differentiation, o.risk_critical)
      then now() else o.last_scored_at end
  where id = p_id
  returning * into n;
  return n;
end $$;

-- Patch keys allowed: description, pillars, opportunity_ids, last_seen_at, status.
-- Extra key 'add_opportunity_ids' (json array of uuids) appends ids not already present.
create or replace function intel.update_theme(
  p_id    uuid,
  p_patch jsonb
) returns intel.theme language plpgsql set search_path = '' as $$
declare
  v_allowed text[] := array['description','pillars','opportunity_ids','last_seen_at','status'];
  v_bad   text[];
  o       intel.theme;
  n       intel.theme;
  v_add   uuid[];
begin
  select array_agg(k) into v_bad
  from jsonb_object_keys(p_patch) k
  where k <> 'add_opportunity_ids' and k <> all (v_allowed);
  if v_bad is not null then
    raise exception 'intel.update_theme: keys not allowed: %', v_bad;
  end if;

  select * into o from intel.theme where id = p_id for update;
  if not found then raise exception 'intel.update_theme: theme % not found', p_id; end if;

  n := jsonb_populate_record(o, p_patch - 'add_opportunity_ids');
  v_add := coalesce(array(select (jsonb_array_elements_text(p_patch->'add_opportunity_ids'))::uuid), '{}');

  update intel.theme set
    description = n.description, pillars = n.pillars,
    opportunity_ids = n.opportunity_ids || array(select u from unnest(v_add) u where u <> all (n.opportunity_ids)),
    last_seen_at = n.last_seen_at, status = n.status
  where id = p_id
  returning * into n;
  return n;
end $$;

-- ---------------------------------------------------------------------------
-- Access: owner only (same as 025).
-- ---------------------------------------------------------------------------
alter table intel.competitor          enable row level security;
alter table intel.competitor_snapshot enable row level security;
revoke all on all tables in schema intel from public, anon, authenticated;
revoke all on all functions in schema intel from public, anon, authenticated;
