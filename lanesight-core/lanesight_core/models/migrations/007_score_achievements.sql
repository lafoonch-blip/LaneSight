-- 007 LaneSight Score, tiers & achievements (SCORE_TIERS_ACHIEVEMENTS_SPEC §7, DEC-048/051). Idempotent.
-- Dev/Beta score L-dev-0 (DEC-048), session-end tiers with hysteresis, and the full achievement engine
-- with the no-pinfall launch catalog active (others 'coming_later'). Achievements never change the score
-- or tier (DEC-039). FK to sessions(id) (the spec draft said session(id); the live table is sessions).
-- Owner-only: score_formula_version and achievement_definition.params (served to clients only through a
-- params-free view). engine_event is service-role only.

-- Score formula versions (owner-managed)
create table if not exists score_formula_version (
  id          text primary key,                 -- 'L-dev-0', later 'DEC-038-v1'
  description text not null,
  params      jsonb not null,                   -- weights, pocket range, angle range, power ref ranges, floors, hysteresis
  status      text not null check (status in ('draft','active','retired')),
  created_at  timestamptz not null default now()
);

-- Every recompute
create table if not exists score_snapshot (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  formula_version text not null references score_formula_version(id),
  computed_at    timestamptz not null default now(),
  trigger        text not null check (trigger in ('shot','session_end','correction','backfill')),
  session_id     uuid references sessions(id) on delete set null,
  eligible       boolean not null,
  score          int check (score between 0 and 1000),   -- null when not eligible
  s_perf numeric, a_acc numeric, c_cons numeric, p_power numeric,   -- 0-100 or null
  eligibility    jsonb not null,                 -- per-part counts vs floors
  inputs         jsonb not null,                 -- shot ids + window summary for audit/recompute
  tier           text check (tier in ('bronze','silver','gold','platinum','onyx'))
);
create index if not exists score_snapshot_user_idx on score_snapshot (user_id, computed_at desc);

-- Current tier state (one row per user)
create table if not exists user_tier_state (
  user_id              uuid primary key references auth.users(id) on delete cascade,
  tier                 text,
  score                int,
  best_score           int,
  best_score_at        timestamptz,
  first_qualified_score int,                      -- baseline for ACH-026..028
  below_floor_sessions int not null default 0,
  updated_at           timestamptz not null default now()
);

create table if not exists tier_event (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  from_tier   text, to_tier text not null,
  kind        text not null check (kind in ('promotion','demotion')),
  first_time  boolean not null,
  score       int not null,
  snapshot_id uuid not null references score_snapshot(id) on delete cascade,
  occurred_at timestamptz not null default now()
);

-- Achievements
create table if not exists achievement_definition (
  id            text primary key,               -- 'ACH-023'
  category      text not null,
  name          text not null,
  description   text not null,                  -- user-facing
  rule_type     text not null,
  params        jsonb not null,                 -- thresholds, windows, sample floors, quality gates (owner-only)
  levels        int not null default 1,
  rule_version  int not null default 1,
  popup_priority int not null default 50,
  status        text not null check (status in ('active','coming_later','draft','retired')),
  inactive_reason text,                          -- 'needs game scores', etc.
  badge_asset   text
);

create table if not exists user_achievement_progress (
  user_id        uuid not null references auth.users(id) on delete cascade,
  achievement_id text not null references achievement_definition(id),
  level          int not null default 1,
  status         text not null check (status in ('locked','in_progress','not_trackable','unlocked')),
  current_value numeric, best_value numeric, target_value numeric,
  qualifying_count int, sample_count int,
  unavailable_reason text,
  last_event_at  timestamptz,
  evidence_ref   jsonb,
  primary key (user_id, achievement_id, level)
);

create table if not exists user_achievement_unlock (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  achievement_id text not null references achievement_definition(id),
  level          int not null default 1,
  unlocked_at    timestamptz not null default now(),
  value          numeric,
  source_event_id uuid,
  evidence_ref   jsonb not null,
  rule_version   int not null,
  revoked_at timestamptz, revoke_reason text,
  unique (user_id, achievement_id, level)
);

create table if not exists user_achievement_pin (
  user_id        uuid not null references auth.users(id) on delete cascade,
  achievement_id text not null references achievement_definition(id),
  kind           text not null check (kind in ('showcase','pursuit')),
  position       int not null check (position between 1 and 3),
  primary key (user_id, kind, position)
);

create table if not exists engine_event (
  idempotency_key text primary key,
  user_id         uuid not null references auth.users(id) on delete cascade,
  event_type      text not null,
  source_ref      jsonb not null,
  occurred_at     timestamptz not null,
  processed_at    timestamptz
);

create table if not exists activity_item (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null check (kind in ('achievement_unlocked','achievement_revoked','tier_promotion','tier_demotion','personal_best')),
  ref_id     text not null,
  payload    jsonb not null,
  created_at timestamptz not null default now(),
  unique (user_id, kind, ref_id)
);

create table if not exists notification (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null check (kind in ('achievement_popup','tier_celebration','tier_banner')),
  ref_id     text not null,
  priority   int not null,
  payload    jsonb not null,
  created_at timestamptz not null default now(),
  delivered_at timestamptz, dismissed_at timestamptz,
  unique (user_id, kind, ref_id)
);

-- Params-free, active-catalog view that clients may read (achievement_definition.params stays owner-only).
create or replace view achievement_definition_public as
  select id, category, name, description, status, inactive_reason, badge_asset
  from achievement_definition
  where status in ('active','coming_later');

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
-- Owner-only tables: no client access.
do $$ declare t text; begin
  foreach t in array array['score_formula_version','achievement_definition','engine_event'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
  end loop;
end $$;
grant select on achievement_definition_public to authenticated;

-- Per-user read-only tables (service role writes).
do $$ declare t text; begin
  foreach t in array array['score_snapshot','user_tier_state','tier_event','user_achievement_progress','user_achievement_unlock','activity_item'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists own_rows_read on %I', t);
    execute format('create policy own_rows_read on %I for select to authenticated using (user_id = (select auth.uid()))', t);
  end loop;
end $$;

-- user_achievement_pin: users manage their own pins.
alter table user_achievement_pin enable row level security;
drop policy if exists own_pins on user_achievement_pin;
create policy own_pins on user_achievement_pin to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- notification: users read their own and may update their own (to set dismissed_at).
alter table notification enable row level security;
drop policy if exists own_read on notification;
create policy own_read on notification for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists own_update on notification;
create policy own_update on notification for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Seed: the L-dev-0 formula version (DEC-048). Power P' reference ranges are owner-editable and
-- intentionally left null pending Shayne's start values (HANDOFF §7) — no fabricated numbers.
-- ---------------------------------------------------------------------------
insert into score_formula_version (id, description, params, status) values (
  'L-dev-0',
  'Dev/Beta no-pinfall LaneSight Score (DEC-048). Target formula remains DEC-038.',
  jsonb_build_object(
    'weights', jsonb_build_object('s_perf',0.40,'a_acc',0.25,'c_cons',0.25,'p_power',0.10),
    's_perf', jsonb_build_object('pocket_weight',0.6,'angle_weight',0.4,
                                 'pocket_board_range',jsonb_build_array(16,19),'pocket_board_range_left_mirror',true,
                                 'entry_angle_range_deg',jsonb_build_array(4,6)),
    'power_ref_ranges', null,            -- entry speed / rev / entry angle / weight — PENDING SHAYNE (HANDOFF §7)
    'eligibility_floors', jsonb_build_object('s_perf',5,'a_acc',5,'c_cons',5,'p_power',5),
    'window_days', 90,
    'tier_ranges', jsonb_build_object('bronze',jsonb_build_array(0,399),'silver',jsonb_build_array(400,549),
                                      'gold',jsonb_build_array(550,699),'platinum',jsonb_build_array(700,849),
                                      'onyx',jsonb_build_array(850,1000)),
    'tier_hysteresis', jsonb_build_object('points_below_floor',15,'consecutive_sessions',2),
    'label', 'Beta · dev formula'
  ),
  'active'
) on conflict (id) do nothing;
