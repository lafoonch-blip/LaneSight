-- LaneSight core schema v1 (Postgres / Supabase). Row-level security: every user-owned row carries user_id.
-- Measurements keep source + confidence + algorithm version (DEC-009/021/022). History is append-only where noted.

create extension if not exists "pgcrypto";

-- ---------- identity & profile ----------
create table profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text, handed char(1) check (handed in ('R','L')), style text check (style in ('one_handed','two_handed','straight','unknown')) default 'unknown',
  units text default 'imperial', usbc_id text, created_at timestamptz default now()
);
create table bowler_baselines (       -- self-reported or sensor-derived baselines; append-only
  id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles(user_id) on delete cascade,
  speed_mph numeric, rev_rate_rpm numeric, axis_tilt_deg numeric, axis_rotation_deg numeric,
  pap_over_in numeric, pap_up_in numeric, source text not null default 'manual', recorded_at timestamptz default now()
);

-- ---------- arsenal (DEC-007) ----------
create table ball_models (            -- shared catalog
  id uuid primary key default gen_random_uuid(), manufacturer text not null, name text not null, release_year int,
  coverstock text, cover_type text, core_type text check (core_type in ('symmetric','asymmetric','pancake','unknown')),
  rg numeric, diff numeric, int_diff numeric, factory_finish text, unique (manufacturer, name)
);
create table user_balls (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles(user_id) on delete cascade,
  ball_model_id uuid references ball_models(id), nickname text, serial text, weight_lb numeric,
  color_desc text, retired boolean default false, acquired_on date, created_at timestamptz default now()
);
create table ball_configurations (    -- versioned drilling/layout; never overwritten
  id uuid primary key default gen_random_uuid(), user_ball_id uuid not null references user_balls(id) on delete cascade,
  version int not null, effective_from timestamptz not null default now(),
  layout_system text, layout text,      -- e.g. 'Dual Angle' / '50 x 4.5 x 40'
  pin_to_pap_in numeric, psa_to_pap_in numeric, val_angle_deg numeric, drill_angle_deg numeric,
  pap_over_in numeric, pap_up_in numeric, balance_hole boolean, grip text, finger_inserts text, thumb_slug text,
  static_weights text, driller text, notes text, unique (user_ball_id, version)
);
create table surface_events (         -- resurface / polish / sanding; append-only
  id uuid primary key default gen_random_uuid(), user_ball_id uuid not null references user_balls(id) on delete cascade,
  event_at timestamptz not null default now(), grit text, polish text, product text, notes text
);
create table maintenance_events (     -- oil extraction, cleaning, plug & redrill
  id uuid primary key default gen_random_uuid(), user_ball_id uuid not null references user_balls(id) on delete cascade,
  event_at timestamptz not null default now(), kind text not null, notes text
);

-- ---------- oil patterns & centers ----------
create table oil_patterns (
  id uuid primary key default gen_random_uuid(), name text not null, length_ft numeric, volume_ml numeric,
  ratio text, forward_oil_ml numeric, reverse_oil_ml numeric, source text,   -- 'kegel','pba','house','user'
  sheet_url text, created_by uuid references profiles(user_id), is_public boolean default true
);
create table centers (
  id uuid primary key default gen_random_uuid(), name text not null, city text, state text, lane_count int,
  scoring_system text, lane_surface text
);

-- ---------- sessions, games, frames, rolls ----------
create table sessions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles(user_id) on delete cascade,
  center_id uuid references centers(id), oil_pattern_id uuid references oil_patterns(id),
  mode text check (mode in ('practice','league','tournament','warmup_scouting')) default 'practice',
  lane_pair text, default_ball_id uuid references user_balls(id),
  started_at timestamptz default now(), ended_at timestamptz, notes text
);
create table calibrations (
  id uuid primary key default gen_random_uuid(), session_id uuid references sessions(id) on delete cascade,
  lane int, source text not null default 'auto', homography jsonb, vanishing_point jsonb, foul_line jsonb,
  quality numeric, algorithm_version text, created_at timestamptz default now()
);
create table games (
  id uuid primary key default gen_random_uuid(), session_id uuid not null references sessions(id) on delete cascade,
  user_id uuid not null references profiles(user_id) on delete cascade, game_number int, lane int,
  score int, complete boolean default false, source text not null default 'lanesight'   -- 'lanesight','manual','scoring:<system>'
);
create table frames (
  id uuid primary key default gen_random_uuid(), game_id uuid not null references games(id) on delete cascade,
  frame_number int not null check (frame_number between 1 and 10), cumulative_score int, unique (game_id, frame_number)
);
create table rolls (
  id uuid primary key default gen_random_uuid(), frame_id uuid not null references frames(id) on delete cascade,
  roll_number int not null check (roll_number between 1 and 3), pins_down int not null check (pins_down between 0 and 10),
  standing_after int[], foul boolean default false, shot_id uuid, source text not null default 'lanesight',
  corrected boolean default false, unique (frame_id, roll_number)
);

-- ---------- shots & measurements ----------
create table video_assets (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles(user_id) on delete cascade,
  storage_path text not null, fps numeric, duration_s numeric, capture_device text,
  camera_mode text check (camera_mode in ('tripod','handheld','head_mounted','glasses')),
  retain_until timestamptz, created_at timestamptz default now()
);
create table shots (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles(user_id) on delete cascade,
  session_id uuid references sessions(id) on delete set null, game_id uuid references games(id) on delete set null,
  roll_id uuid references rolls(id) on delete set null, video_asset_id uuid references video_assets(id) on delete set null,
  user_ball_id uuid references user_balls(id), ball_configuration_id uuid references ball_configurations(id),
  lane int, sequence int, shooter_type text default 'self' check (shooter_type in ('self','scouted')),
  handed char(1), is_spare_attempt boolean default false,
  t_release numeric, t_touchdown numeric, t_impact numeric,
  trajectory jsonb,          -- {lane:[{t,z_ft,board}], smoothed:[{z_ft,board}], pixel:[{t,x,y}]}
  key_points jsonb,          -- laydown / arrows / breakpoint / entry
  classification text,       -- EXECUTED / EXECUTION_MISS / REACTION_CHANGE / MIXED / NO_INTENT / LOW_CONFIDENCE
  record jsonb not null,     -- full ShotRecord (schema shot-1.0) for reprocessing
  algorithm_version text, created_at timestamptz default now()
);
alter table rolls add constraint rolls_shot_fk foreign key (shot_id) references shots(id) on delete set null;
create table shot_intents (
  shot_id uuid primary key references shots(id) on delete cascade,
  feet_board numeric, laydown_board numeric, arrows_board numeric, breakpoint_board numeric, breakpoint_ft numeric
);
create table shot_feedback (          -- "Did you hit your intended line?" (DEC-006)
  shot_id uuid primary key references shots(id) on delete cascade, hit_line text check (hit_line in ('yes','no','not_sure')),
  notes text, created_at timestamptz default now()
);
create table measurements (           -- one row per metric per source
  id bigint generated always as identity primary key, shot_id uuid not null references shots(id) on delete cascade,
  metric text not null, value numeric, unit text, confidence numeric, status text,
  source text not null, algorithm_version text, note text, unique (shot_id, metric, source)
);
create index on measurements (metric, source);
create table pin_states (
  shot_id uuid primary key references shots(id) on delete cascade, before_state int[], standing int[], uncertain int[],
  strike boolean, confidence numeric, source text default 'lanesight_video', corrected boolean default false
);

-- ---------- sensors (DEC-021) ----------
create table sensor_devices (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles(user_id) on delete cascade,
  vendor text not null, model text, external_id text, paired_at timestamptz default now()
);
create table sensor_shots (
  id uuid primary key default gen_random_uuid(), device_id uuid not null references sensor_devices(id) on delete cascade,
  shot_id uuid references shots(id) on delete set null, captured_at timestamptz not null, match_confidence numeric,
  speed_mph numeric, rev_rate_rpm numeric, axis_tilt_deg numeric, axis_rotation_deg numeric, loft_ft numeric,
  pap_over_in numeric, pap_up_in numeric, breakpoint_ft numeric, skid_ft numeric, hook_ft numeric, roll_ft numeric,
  raw jsonb
);
create view metric_variance as        -- LaneSight vs sensor on overlapping metrics
select s.id as shot_id, s.user_id, ss.device_id, m.metric, m.value as lanesight,
       case m.metric when 'ball_speed' then ss.speed_mph when 'rev_rate' then ss.rev_rate_rpm when 'loft' then ss.loft_ft end as sensor,
       m.value - case m.metric when 'ball_speed' then ss.speed_mph when 'rev_rate' then ss.rev_rate_rpm when 'loft' then ss.loft_ft end as diff
from shots s join sensor_shots ss on ss.shot_id = s.id
join measurements m on m.shot_id = s.id and m.source = 'lanesight_video' and m.metric in ('ball_speed','rev_rate','loft');

-- ---------- coaching ----------
create table recommendations (
  id uuid primary key default gen_random_uuid(), shot_id uuid references shots(id) on delete cascade,
  session_id uuid references sessions(id) on delete cascade, type text not null, direction text,
  move_feet int, move_target int, speed text, reason text not null, evidence jsonb, confidence text,
  rules_version text not null, created_at timestamptz default now()
);
create table recommendation_outcomes (
  recommendation_id uuid primary key references recommendations(id) on delete cascade,
  user_action text check (user_action in ('accepted','rejected','modified','ignored')),
  next_shot_id uuid references shots(id), outcome jsonb, success boolean
);
create table transition_states (
  id bigint generated always as identity primary key, session_id uuid not null references sessions(id) on delete cascade,
  lane int, after_shot_id uuid references shots(id), entry_drift_boards numeric, breakpoint_drift_boards numeric,
  n_shots int, confidence text, created_at timestamptz default now()
);

-- ---------- row-level security ----------
do $$ declare t text; begin
  foreach t in array array['profiles','bowler_baselines','user_balls','sessions','games','video_assets','shots','sensor_devices'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy own_rows on %I using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
end $$;
