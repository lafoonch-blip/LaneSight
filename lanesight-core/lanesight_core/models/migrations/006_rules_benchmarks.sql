-- 006 Rules & benchmarks engine (BENCHMARKS_AND_RECOMMENDATIONS_SPEC §6/§8, DEC-046). Idempotent.
-- Two classes of table:
--   (a) OWNER-ONLY rule data — benchmark_reference, style_template(+_metric), form_rule, drill,
--       engine_config. RLS is enabled with NO authenticated/anon policy and privileges revoked, so no
--       client can select them; only the service role (Mac) and the rules_admin role touch them. Rule
--       data must never ship in the app bundle or an API response (DEC-046).
--   (b) PER-USER derived data — personal_baseline, finding. The owning user can read their own rows.
-- L3 coach_profile (BENCHMARKS §3.4) is post-MVP and intentionally not created here.
-- Extends the existing recommendations / recommendation_outcomes tables (schema v1) rather than
-- re-creating them.

-- rules_admin role (nologin; a marker/grant target — the real client guarantee is RLS-on + no policy).
do $$ begin
  create role rules_admin nologin;
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- (a) Owner-only rule data
-- ---------------------------------------------------------------------------
create table if not exists benchmark_reference (
  id            uuid primary key default gen_random_uuid(),
  metric        text not null,
  range_low     numeric,
  range_high    numeric,
  units         text,
  source        text,
  source_quality text check (source_quality is null or source_quality in ('high','medium','low')),
  applicability jsonb not null default '{}'::jsonb,   -- styles, step count, handedness, view/fps
  shown_to_user boolean not null default false,       -- elite references stay owner-only (DEC-046)
  version       int not null default 1,
  status        text not null default 'draft' check (status in ('draft','tested','published','retired')),
  created_at    timestamptz not null default now()
);

create table if not exists style_template (
  id            text primary key,                     -- 'one_handed_thumb' | 'one_handed_no_thumb' | 'two_handed'
  name          text not null,
  description   text,
  version       int not null default 1,
  status        text not null default 'draft' check (status in ('draft','tested','published','retired'))
);

create table if not exists style_template_metric (
  template_id   text not null references style_template(id) on delete cascade,
  metric        text not null,
  matters       boolean not null default true,
  range_low     numeric,
  range_high    numeric,
  units         text,
  note          text,
  primary key (template_id, metric)
);

create table if not exists drill (
  id            text primary key,                     -- 'DRILL-ball-start'
  name          text not null,
  description   text not null,
  sources       jsonb not null default '[]'::jsonb,   -- citations
  media         jsonb,
  version       int not null default 1,
  status        text not null default 'draft' check (status in ('draft','tested','published','retired'))
);

create table if not exists form_rule (
  id               text not null,                     -- 'RULE-early-timing'
  version          int not null default 1,
  sources          jsonb not null default '[]'::jsonb,
  trigger          jsonb not null,                    -- metric(s), comparison, repetition rule, min confidence, required view/fps
  candidate_causes jsonb not null default '[]'::jsonb,-- ranked upstream causes + check metric
  cue              text,                              -- <=12 words, spoken-friendly
  drill_ref        text references drill(id),
  expected_change  jsonb,                             -- metric + direction + rough magnitude
  verify           jsonb,                             -- metric to watch + success/fail over N shots
  applicability    jsonb not null default '{}'::jsonb,-- styles, step count, handedness
  status           text not null default 'draft' check (status in ('draft','tested','published','retired')),
  created_at       timestamptz not null default now(),
  primary key (id, version)
);

-- Owner-editable engine parameters: prioritizer weights, baseline N, confidence thresholds,
-- power P' reference ranges (DEC-048, values pending Shayne — HANDOFF §7), etc.
create table if not exists engine_config (
  key        text primary key,
  value      jsonb not null,
  description text,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- (b) Per-user derived data
-- ---------------------------------------------------------------------------
create table if not exists personal_baseline (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  metric      text not null,
  view        text,                                   -- capture view
  fps_tier    text,
  slice       text,                                   -- 'all' | per-ball | per-pattern
  median      numeric,
  mad         numeric,
  sd          numeric,
  n           int not null default 0,
  window_kind text,                                   -- 'rolling_30' | 'all_time' (window is a reserved word)
  computed_at timestamptz not null default now()
);
create index if not exists personal_baseline_user_metric_idx on personal_baseline (user_id, metric, view);

create table if not exists finding (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,
  shot_id            uuid references shots(id) on delete cascade,
  session_id         uuid references sessions(id) on delete cascade,
  metric             text not null,
  benchmark_layer    text check (benchmark_layer in ('reference','style','personal','coach')),
  benchmark_version  text,
  level_status       text check (level_status in ('within','watch','outside')),
  consistency_status text check (consistency_status in ('within','watch','outside')),
  confidence         numeric,
  rule_id            text,
  rule_version       int,
  created_at         timestamptz not null default now()
);
create index if not exists finding_user_idx on finding (user_id, created_at desc);
create index if not exists finding_shot_idx on finding (shot_id);

-- Extend the existing recommendations table (BENCHMARKS §6).
alter table recommendations
  add column if not exists engine    text check (engine is null or engine in ('lane','form')),
  add column if not exists rule_id   text,
  add column if not exists rule_version int,
  add column if not exists cue       text,
  add column if not exists drill_ref text;

-- Extend the existing recommendation_outcomes table with verify evidence.
alter table recommendation_outcomes
  add column if not exists followed      boolean,
  add column if not exists verify_metric text,
  add column if not exists verify_before numeric,
  add column if not exists verify_after  numeric;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
-- Owner-only rule tables: enable RLS, no client policy, revoke client privileges, grant rules_admin.
do $$ declare t text; begin
  foreach t in array array['benchmark_reference','style_template','style_template_metric','drill','form_rule','engine_config'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on %I to rules_admin', t);
  end loop;
end $$;

-- Per-user tables: owner can read their own rows; all writes go through the service role.
alter table personal_baseline enable row level security;
drop policy if exists own_rows on personal_baseline;
create policy own_rows on personal_baseline for select to authenticated
  using (user_id = (select auth.uid()));

alter table finding enable row level security;
drop policy if exists own_rows on finding;
create policy own_rows on finding for select to authenticated
  using (user_id = (select auth.uid()));
