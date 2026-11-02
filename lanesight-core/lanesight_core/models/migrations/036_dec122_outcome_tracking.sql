-- 036 — DEC-122 outcome tracking (append-only history of what each analysis measured vs. couldn't).
-- Additive, idempotent, read-only for clients. Follows the 025/027 owner-only pattern: raw per-attempt rows live
-- in retained PUBLIC tables written ONLY by the service role (RLS on, no client policy); every aggregate is a
-- view in the private `ops` schema, which already excludes staged accounts via `ops.attempt.is_staged`.
--
-- NOT APPLIED TO LIVE BY CLAUDE CODE. This is Shayne's step (per DEC-122 §6f / CLAUDE.md). Pairs with the engine
-- wiring (pipeline/app emit one row per metric + per stage for every attempt — DEC-122 §6 step 6) and a Cloud Run
-- redeploy; data flows only after both land. Backfill of the last 14 days is a separate one-off (DEC-122 §4/§6).
--
-- Why (DEC-122): a single weak stage was blanking an entire shot/form, hiding the metrics that DID work and
-- making failures uncountable. `measurements` on the shot/attempt stays the user-facing CURRENT value; these
-- tables are the immutable per-attempt HISTORY that turns "it failed" into "exactly these metrics/stages failed,
-- here, for this camera/engine, N% of the time" — the data behind per-metric promotion (DEC-106) and the DEC-118
-- supported-camera guidance.
--
-- Honesty (CLAUDE.md): a metric that wasn't measured is `status = 'unavailable'` with a `reason_code` + stage —
-- never a fabricated value. `value` is NULL for unavailable; no estimate is ever written here.

-- ===========================================================================
-- Enums — closed vocabularies for the status columns (open-ended reason_code stays text, see below).
-- PG has no `create type if not exists`, so guard each in a DO block for idempotent re-run.
-- ===========================================================================
-- metric status mirrors the engine's Measurement.status vocabulary (lanesight_core/models/shot.py) so the writer
-- stores it with ONE documented rename and no lossy mapping:
--   engine 'ok'                 -> 'measured'            (fully measured — renamed for clarity in an outcome table)
--   engine 'low_confidence'     -> 'low_confidence'      (value produced, below the confidence floor)
--   engine 'best_effort'        -> 'best_effort'         (value produced with caveats, e.g. DEC-122 §7c foul->pins avg)
--   engine 'calibrated_estimate'-> 'calibrated_estimate' (labeled estimate, not a raw measurement — DEC honesty)
--   engine 'unavailable'        -> 'unavailable'         (not measured; value IS NULL)
-- All non-'unavailable' statuses carry a value (enforced by analysis_metric_outcome_value_chk below).
do $$ begin
  create type public.metric_outcome_status as enum
    ('measured', 'best_effort', 'low_confidence', 'unavailable', 'calibrated_estimate');
exception when duplicate_object then null; end $$;
-- If a prior (narrower) version of the enum already exists, widen it idempotently (ADD VALUE is a no-op if present).
alter type public.metric_outcome_status add value if not exists 'low_confidence';
alter type public.metric_outcome_status add value if not exists 'calibrated_estimate';

do $$ begin
  create type public.stage_outcome_status as enum ('ok', 'failed', 'skipped');
exception when duplicate_object then null; end $$;

-- reason_code is TEXT, not a PG enum: the codes are the DEC-086 AnalysisFailure set (failures.py) and grow as the
-- engine gains stages, so a hard enum would force a migration per new code. It is still "machine-countable" — a
-- controlled vocabulary of exact strings, indexed, grouped on directly by the views below.

-- ===========================================================================
-- metric_catalog — the versioned list of every metric an analysis can produce, per capture mode, with the stages
-- it depends on. Reference data (no user data); RLS-locked like the rest, read via ops. Seeded below.
-- ===========================================================================
create table if not exists public.metric_catalog (
  metric_key       text    not null,
  capture_mode     text    not null check (capture_mode in ('shot', 'form')),
  unit             text,
  required_stages  text[]  not null default '{}',   -- stage keys (see analysis_stage_outcome.stage) this metric rides
  introduced_in    text,                            -- engine version the metric first shipped in (e.g. lanesight-cv-0.7.2)
  display_name     text,
  sort_order       int     not null default 0,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  primary key (metric_key, capture_mode)
);
comment on table public.metric_catalog is
  'DEC-122 §6: versioned catalog of producible metrics per capture mode + the stages each depends on. Drives the '
  '"one row per attempt x EVERY catalog metric" completeness of analysis_metric_outcome.';

-- ===========================================================================
-- analysis_metric_outcome — one row per attempt x EVERY catalog metric (including the ones left unavailable).
-- ===========================================================================
create table if not exists public.analysis_metric_outcome (
  id             uuid primary key default gen_random_uuid(),
  created_at     timestamptz not null default now(),
  attempt_id     uuid not null references public.analysis_attempt(id) on delete cascade,
  engine         text not null check (engine in ('iphone', 'server')),   -- platform 'ios' maps to 'iphone' at write time
  engine_version text,                                                    -- algorithm_version (e.g. lanesight-cv-0.7.2)
  capture_mode   text check (capture_mode in ('shot', 'form')),
  metric_key     text not null,
  unit           text,
  status         public.metric_outcome_status not null,
  value          numeric,                      -- NULL when status = 'unavailable' (never an estimate)
  confidence     numeric,
  reason_code    text,                         -- machine-countable; NULL when measured
  reason_detail  text,                         -- human-readable detail (not for grouping)
  failed_stage   text,                         -- the stage that blocked this metric, when unavailable
  camera_view    text,                         -- analysis-derived framing (e.g. rear_centered, behind_ball_return_offset)
  camera_group   text,                         -- coarser grouping for DEC-118 support buckets
  context        jsonb,                        -- snapshot {device, os, fps, width, height, resolution, source} at attempt time
  constraint analysis_metric_outcome_attempt_metric_uniq unique (attempt_id, metric_key),
  -- Honesty invariant (DEC-122 / CLAUDE.md): unavailable => no value; any other status => a value is present.
  constraint analysis_metric_outcome_value_chk check (
    (status = 'unavailable' and value is null) or (status <> 'unavailable' and value is not null))
);
create index if not exists ame_attempt_idx       on public.analysis_metric_outcome (attempt_id);
create index if not exists ame_metric_engine_idx on public.analysis_metric_outcome (metric_key, engine, engine_version);
create index if not exists ame_reason_idx        on public.analysis_metric_outcome (reason_code) where reason_code is not null;
create index if not exists ame_created_idx       on public.analysis_metric_outcome (created_at desc);
comment on table public.analysis_metric_outcome is
  'DEC-122 §6: one row per attempt x every catalog metric (incl. unavailable). value NULL + reason_code + '
  'failed_stage when not measured — never an estimate. Written by both engines for every attempt.';

-- ===========================================================================
-- analysis_stage_outcome — one row per attempt x stage (the DEC-122 per-stage report, persisted).
-- ===========================================================================
create table if not exists public.analysis_stage_outcome (
  id             uuid primary key default gen_random_uuid(),
  created_at     timestamptz not null default now(),
  attempt_id     uuid not null references public.analysis_attempt(id) on delete cascade,
  engine         text not null check (engine in ('iphone', 'server')),
  engine_version text,
  capture_mode   text check (capture_mode in ('shot', 'form')),
  stage          text not null,                -- decode | stabilize | lane | foul | ball_track | impact | refine | compute | pins | rev | pose | swing_events | delivery_isolation | slowmo
  status         public.stage_outcome_status not null,
  reason_code    text,
  duration_ms    integer,
  diagnostics    jsonb,
  camera_view    text,
  camera_group   text,
  context        jsonb,
  constraint analysis_stage_outcome_attempt_stage_uniq unique (attempt_id, stage)
);
create index if not exists aso_attempt_idx     on public.analysis_stage_outcome (attempt_id);
create index if not exists aso_stage_status_idx on public.analysis_stage_outcome (stage, status);
create index if not exists aso_reason_idx      on public.analysis_stage_outcome (reason_code) where reason_code is not null;
create index if not exists aso_created_idx     on public.analysis_stage_outcome (created_at desc);
comment on table public.analysis_stage_outcome is
  'DEC-122 §6: one row per attempt x stage (ok|failed|skipped + reason_code + duration_ms + diagnostics). The '
  'persisted per-stage report; stored even when the attempt measured nothing (a completed partial, not a fail).';

-- ===========================================================================
-- RLS — owner/service only. The service role (writer) bypasses RLS; no anon/authenticated policy = no client read.
-- ===========================================================================
alter table public.metric_catalog          enable row level security;
alter table public.analysis_metric_outcome enable row level security;
alter table public.analysis_stage_outcome  enable row level security;
revoke all on public.metric_catalog          from anon, authenticated;
revoke all on public.analysis_metric_outcome from anon, authenticated;
revoke all on public.analysis_stage_outcome  from anon, authenticated;

-- ===========================================================================
-- Seed metric_catalog from the live engine catalogs (lanesight_core/cv/pipeline.py _METRIC_CATALOG + form/analyze.py).
-- introduced_in is the first version that shipped the metric; speed_avg_foul_to_pins as a user-facing partial under
-- scale-failure arrived in 0.7.2 (DEC-122 step 7c). required_stages use the analysis_stage_outcome stage keys.
-- ===========================================================================
insert into public.metric_catalog (metric_key, capture_mode, unit, required_stages, introduced_in, display_name, sort_order) values
  ('ball_speed',          'shot', 'mph',   array['lane','ball_track','impact','compute'], 'lanesight-cv-0.6.0', 'Ball speed (release)',        10),
  ('speed_release',       'shot', 'mph',   array['lane','ball_track','impact','compute'], 'lanesight-cv-0.6.0', 'Release speed',               11),
  ('speed_early',         'shot', 'mph',   array['lane','ball_track','impact','compute'], 'lanesight-cv-0.6.0', 'Early-lane speed',            12),
  ('speed_late',          'shot', 'mph',   array['lane','ball_track','impact','compute'], 'lanesight-cv-0.6.0', 'Back-end speed',              13),
  ('speed_avg_foul_to_pins','shot','mph',  array['lane','ball_track','impact'],           'lanesight-cv-0.6.0', 'Foul-to-pins average speed',  14),
  ('loft',                'shot', 'ft',    array['lane','ball_track','compute'],          'lanesight-cv-0.6.0', 'Loft',                        20),
  ('laydown_board',       'shot', 'board', array['lane','ball_track','compute'],          'lanesight-cv-0.6.0', 'Laydown board',               21),
  ('board_at_7ft',        'shot', 'board', array['lane','ball_track','compute'],          'lanesight-cv-0.6.0', 'Board at 7 ft',               22),
  ('arrows_board',        'shot', 'board', array['lane','ball_track','compute'],          'lanesight-cv-0.6.0', 'Board at arrows',             23),
  ('launch_angle',        'shot', 'deg',   array['lane','ball_track','compute'],          'lanesight-cv-0.6.0', 'Launch angle',                24),
  ('breakpoint_board',    'shot', 'board', array['lane','ball_track','compute'],          'lanesight-cv-0.6.0', 'Breakpoint board',            25),
  ('breakpoint_distance', 'shot', 'ft',    array['lane','ball_track','compute'],          'lanesight-cv-0.6.0', 'Breakpoint distance',         26),
  ('entry_board',         'shot', 'board', array['lane','ball_track','impact','compute'], 'lanesight-cv-0.6.0', 'Entry board',                 27),
  ('entry_angle',         'shot', 'deg',   array['lane','ball_track','impact','compute'], 'lanesight-cv-0.6.0', 'Entry angle',                 28),
  ('entry_angle_52_55',   'shot', 'deg',   array['lane','ball_track','impact','compute'], 'lanesight-cv-0.6.0', 'Entry angle (52-55 ft)',      29),
  ('rev_rate_lane',       'shot', 'rpm',   array['ball_track','rev'],                     'lanesight-cv-0.6.0', 'Rev rate (lane)',             30),
  ('rev_rate',            'shot', 'rpm',   array['ball_track','rev'],                     'lanesight-cv-0.6.0', 'Rev rate',                    31),
  ('axis_rotation',       'shot', 'deg',   array['ball_track','rev'],                     'lanesight-cv-0.6.0', 'Axis rotation',               32),
  ('axis_tilt',           'shot', 'deg',   array['ball_track','rev'],                     'lanesight-cv-0.6.0', 'Axis tilt',                   33),
  ('pap',                 'shot', 'in',    array['ball_track','rev'],                     'lanesight-cv-0.6.0', 'PAP',                         34),
  -- Form metrics mirror form/analyze.py FORM_P1 exactly (key + unit); kept in sync by
  -- tests/test_metric_catalog_seed.py (fails if the seed and the engine catalogs drift).
  ('pushaway_time',       'form', 's',     array['pose','swing_events'],                  'lanesight-cv-0.6.0', 'Pushaway time',               50),
  ('backswing_time',      'form', 's',     array['pose','swing_events'],                  'lanesight-cv-0.6.0', 'Backswing time',              51),
  ('downswing_time',      'form', 's',     array['pose','swing_events'],                  'lanesight-cv-0.6.0', 'Downswing time',              52),
  ('release_time',        'form', 's',     array['pose','swing_events'],                  'lanesight-cv-0.6.0', 'Release time',                53),
  ('swing_time',          'form', 's',     array['pose','swing_events'],                  'lanesight-cv-0.6.0', 'Swing time',                  54),
  ('approach_time',       'form', 's',     array['pose','swing_events'],                  'lanesight-cv-0.6.0', 'Approach time',               55),
  ('step_count',          'form', 'count', array['pose','delivery_isolation'],            'lanesight-cv-0.6.0', 'Step count',                  56),
  ('ball_start_step',     'form', 'index', array['pose','swing_events','delivery_isolation'], 'lanesight-cv-0.6.0', 'Ball-start step',         57),
  ('rhythm_ratio',        'form', 'ratio', array['pose','swing_events'],                  'lanesight-cv-0.6.0', 'Rhythm ratio',                58),
  ('finish_hold',         'form', 's',     array['pose','delivery_isolation'],            'lanesight-cv-0.6.0', 'Finish hold',                 59),
  ('backswing_height_rel','form', 'ratio', array['pose','swing_events'],                  'lanesight-cv-0.6.0', 'Backswing height',            60),
  ('drift_boards',        'form', 'board', array['pose','delivery_isolation'],            'lanesight-cv-0.6.0', 'Drift',                       61),
  ('timing_at_slide',     'form', 's',     array['pose','swing_events','delivery_isolation'], 'lanesight-cv-0.6.0', 'Timing at slide',         62),
  ('slide_length',        'form', 'inch',  array['pose','delivery_isolation'],            'lanesight-cv-0.6.0', 'Slide length',                63)
on conflict (metric_key, capture_mode) do update set
  unit = excluded.unit, required_stages = excluded.required_stages, introduced_in = excluded.introduced_in,
  display_name = excluded.display_name, sort_order = excluded.sort_order, is_active = true;

-- ===========================================================================
-- Views (ops schema, owner-only). All exclude staged/test accounts via ops.attempt.is_staged = false.
-- ===========================================================================
create schema if not exists ops;

-- 1) Metric success rate by metric x engine_version x camera_view x week.
create or replace view ops.metric_success_rate as
select
  o.metric_key,
  o.engine,
  o.engine_version,
  coalesce(o.camera_view, 'unknown')                                         as camera_view,
  date_trunc('week', o.created_at)                                           as week,
  count(*)                                                                   as attempts,
  count(*) filter (where o.status = 'measured')                              as measured,
  count(*) filter (where o.status = 'best_effort')                           as best_effort,
  count(*) filter (where o.status = 'low_confidence')                        as low_confidence,
  count(*) filter (where o.status = 'calibrated_estimate')                   as calibrated_estimate,
  count(*) filter (where o.status = 'unavailable')                           as unavailable,
  -- success = produced ANY value (status <> unavailable). Granular columns above let the dashboard compute a
  -- stricter "measured-only" rate when needed.
  round(count(*) filter (where o.status <> 'unavailable')::numeric
        / nullif(count(*), 0), 3)                                            as success_rate
from public.analysis_metric_outcome o
join ops.attempt a on a.id = o.attempt_id and a.is_staged = false
group by o.metric_key, o.engine, o.engine_version, coalesce(o.camera_view, 'unknown'),
         date_trunc('week', o.created_at);
comment on view ops.metric_success_rate is 'DEC-122 §6e: per-metric measured-rate by engine version, camera view, week (staged excluded).';

-- 2) Top reason_codes per metric (why a metric was unavailable).
create or replace view ops.metric_reason_codes as
select
  o.metric_key,
  o.engine,
  o.engine_version,
  o.reason_code,
  o.failed_stage,
  count(*) as n
from public.analysis_metric_outcome o
join ops.attempt a on a.id = o.attempt_id and a.is_staged = false
where o.status = 'unavailable' and o.reason_code is not null
group by o.metric_key, o.engine, o.engine_version, o.reason_code, o.failed_stage
order by o.metric_key, n desc;
comment on view ops.metric_reason_codes is 'DEC-122 §6e: top reason_codes per metric (staged excluded), most frequent first.';

-- 3) Stage failure funnel (where analyses stop).
create or replace view ops.stage_failure_funnel as
select
  s.stage,
  s.engine,
  s.engine_version,
  count(*)                                                       as attempts,
  count(*) filter (where s.status = 'ok')                        as ok,
  count(*) filter (where s.status = 'failed')                    as failed,
  count(*) filter (where s.status = 'skipped')                   as skipped,
  round(count(*) filter (where s.status = 'failed')::numeric
        / nullif(count(*) filter (where s.status <> 'skipped'), 0), 3) as failure_rate,
  round(avg(s.duration_ms) filter (where s.duration_ms is not null), 1) as avg_duration_ms,
  mode() within group (order by s.reason_code)
        filter (where s.status = 'failed')                       as top_reason_code
from public.analysis_stage_outcome s
join ops.attempt a on a.id = s.attempt_id and a.is_staged = false
group by s.stage, s.engine, s.engine_version;
comment on view ops.stage_failure_funnel is 'DEC-122 §6e: per-stage ok/failed/skipped funnel + top failure reason (staged excluded).';

-- 4) iPhone vs server agreement per metric (same shot, both engines measured).
create or replace view ops.engine_metric_agreement as
with m as (
  select o.metric_key, o.unit, a.shot_id, o.engine, o.value, o.created_at
  from public.analysis_metric_outcome o
  join ops.attempt a on a.id = o.attempt_id and a.is_staged = false
  where o.status in ('measured', 'best_effort') and o.value is not null and a.shot_id is not null
),
ios as (select distinct on (metric_key, shot_id) metric_key, unit, shot_id, value, created_at
          from m where engine = 'iphone' order by metric_key, shot_id, created_at desc),
srv as (select distinct on (metric_key, shot_id) metric_key, shot_id, value, created_at
          from m where engine = 'server' order by metric_key, shot_id, created_at desc)
select
  i.metric_key,
  i.unit,
  i.shot_id,
  i.value                                   as iphone_value,
  s.value                                   as server_value,
  round(i.value - s.value, 3)               as delta,
  round(abs(i.value - s.value), 3)          as abs_delta
from ios i
join srv s on s.metric_key = i.metric_key and s.shot_id = i.shot_id;
comment on view ops.engine_metric_agreement is 'DEC-122 §6e: per-metric iPhone-vs-server value delta on the same shot (staged excluded).';
