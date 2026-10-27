-- 008 Dev Build v0 fields (HANDOFF §3 DV-01, DEC-049/053). Idempotent.
-- Extends existing tables rather than creating handoff-named ones:
--   profiles (not "bowler_profile"): dob, delivery_style, approach_steps  (handed/style already exist)
--   sensor_devices (not "user_sensor"): user-entered name + default flag (no brand names in UI, DEC-049)
--   shots: capture_mode, bowler_in_view, source, sensor_used, sensor_id
--   shot_intents: created_at (lets Accuracy require intent set before the shot)
-- New: session_feedback (DEC-053).

-- profiles: date of birth (13+ gate at onboarding), delivery style (DEC-046), approach step count.
alter table profiles
  add column if not exists dob            date,
  add column if not exists delivery_style text,
  add column if not exists approach_steps int;
do $$ begin
  alter table profiles add constraint profiles_delivery_style_chk
    check (delivery_style is null or delivery_style in ('one_handed_thumb','one_handed_no_thumb','two_handed'));
exception when duplicate_object then null; end $$;

-- sensor_devices: user-entered display name + default flag. vendor stays nullable for back-compat but
-- the UI only ever shows the user's own name (DEC-049).
alter table sensor_devices
  add column if not exists name       text,
  add column if not exists is_default boolean not null default false;
alter table sensor_devices alter column vendor drop not null;

-- shots: capture mode, whether the bowler is in frame, capture source, and the per-shot sensor answer.
alter table shots
  add column if not exists capture_mode  text,
  add column if not exists bowler_in_view boolean,
  add column if not exists source        text,
  add column if not exists sensor_used   boolean,
  add column if not exists sensor_id     uuid references sensor_devices(id) on delete set null;
do $$ begin
  alter table shots add constraint shots_capture_mode_chk
    check (capture_mode is null or capture_mode in ('shot','form'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table shots add constraint shots_source_chk
    check (source is null or source in ('live','upload'));
exception when duplicate_object then null; end $$;

-- shot_intents: timestamp so "intent set before the shot" (Accuracy eligibility) is auditable.
alter table shot_intents
  add column if not exists created_at timestamptz not null default now();

-- session_feedback (DEC-053): one feedback submission per session end. tags are from
-- {Bug, Metric looked wrong, Advice, Camera/upload, Workflow, Idea}; validated app-side.
create table if not exists session_feedback (
  id              uuid primary key default gen_random_uuid(),
  session_id      uuid not null references sessions(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  rating          int not null check (rating between 1 and 5),
  tags            text[] not null default '{}'::text[],
  text            text,
  diagnostics     jsonb,                 -- timings, errors, versions, shot ids (on by default)
  app_version     text,
  core_version    text,
  formula_version text,
  created_at      timestamptz not null default now()
);
create index if not exists session_feedback_user_idx on session_feedback (user_id, created_at desc);
create index if not exists session_feedback_session_idx on session_feedback (session_id);

alter table session_feedback enable row level security;
drop policy if exists own_select on session_feedback;
create policy own_select on session_feedback for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists own_insert on session_feedback;
create policy own_insert on session_feedback for insert to authenticated
  with check (user_id = (select auth.uid()));

-- Account-deletion cascade: all Dev Build v0 tables (006/007/008) reference auth.users(id) with
-- ON DELETE CASCADE, so deleting the auth user clears score/achievement/feedback/finding/baseline rows.
-- The schema v1 tables key off profiles(user_id); DELETE /me on the Mac service deletes in FK order and
-- removes the auth user last. A full cascade audit of the v1 tables is tracked under DV-03.
