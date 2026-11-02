-- 037 Friends & Family cohort + app-phase 'ff' + F&F consent (DEC-123, DEC-124). Additive and idempotent.
-- DO NOT apply to live — that is Shayne's step. Number 037: re-checked across all remote branches 2026-11-02;
-- 036 is taken by feat/ios-lane-parity's 036_dec122_outcome_tracking, so this + 038 are the next free numbers.
--
-- What this adds:
--   * profiles.cohort (dev|ff|beta|live) — the account's test phase, so Stats, the ops dashboard and the
--     feedback store are separable by cohort (DEC-123). Shayne's real account and staged test accounts are
--     ALWAYS 'dev' — enforced by a guard trigger, not just the app.
--   * profiles.ff_consent_version / ff_consent_at — the F&F one-screen consent the tester accepted and when
--     (DEC-123: recording, 7-day server clip retention DEC-099/104, use of clips/feedback to improve).
--   * feedback.app_phase gains 'ff' and is STAMPED from the author's profile.cohort at insert (mirrors the
--     018 is_staged trigger), so a client can never spoof the phase and Shayne's/staged data never mixes in
--     (DEC-124 "Value comes from the account cohort").

-- ---------------------------------------------------------------------------
-- profiles: cohort + F&F consent
-- ---------------------------------------------------------------------------
alter table profiles
  add column if not exists cohort             text not null default 'dev',
  add column if not exists ff_consent_version text,
  add column if not exists ff_consent_at      timestamptz;

do $$ begin
  alter table profiles add constraint profiles_cohort_chk
    check (cohort in ('dev','ff','beta','live'));
exception when duplicate_object then null; end $$;

create index if not exists profiles_cohort_idx on profiles (cohort);

comment on column profiles.cohort is
  'DEC-123 account test phase: dev (Shayne + staged test accounts) | ff (Friends & Family TestFlight) | '
  'beta | live. Owner and staged accounts are forced to dev by profiles_guard_cohort_trg.';
comment on column profiles.ff_consent_version is
  'DEC-123 version string of the F&F consent the tester accepted (null = not an F&F tester / not accepted).';
comment on column profiles.ff_consent_at is 'DEC-123 when the F&F consent was accepted.';

-- Guard: the owner (must match owner.py OWNER_USER_ID) and every staged account are ALWAYS 'dev', whatever
-- the client sends. Keeps Shayne's real data and staged test data out of the F&F/beta/live cohorts (DEC-123).
create or replace function profiles_guard_cohort() returns trigger
  language plpgsql
  set search_path = public, pg_temp
  as $$
begin
  if new.cohort is null then new.cohort := 'dev'; end if;
  if new.is_staged is true then new.cohort := 'dev'; end if;
  if new.user_id = '551bc775-dee4-41bd-a19c-116e8691d053'::uuid then new.cohort := 'dev'; end if;
  return new;
end $$;
drop trigger if exists profiles_guard_cohort_trg on profiles;
create trigger profiles_guard_cohort_trg before insert or update on profiles
  for each row execute function profiles_guard_cohort();

-- Re-assert the guard on existing rows (owner + any already-staged account -> dev; everyone else keeps dev).
update profiles set cohort = 'dev'
  where cohort is distinct from 'dev'
    and (is_staged = true or user_id = '551bc775-dee4-41bd-a19c-116e8691d053'::uuid);

-- ---------------------------------------------------------------------------
-- feedback.app_phase: add 'ff' to the allowed set, then stamp it from the author's profile.cohort at insert.
-- ---------------------------------------------------------------------------
-- Drop whatever the (inline, auto-named) app_phase check constraint is, then add the widened one by name.
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.feedback'::regclass and contype = 'c'
              and pg_get_constraintdef(oid) ilike '%app_phase%'
  loop
    execute format('alter table public.feedback drop constraint %I', c.conname);
  end loop;
end $$;
alter table feedback
  add constraint feedback_app_phase_check check (app_phase in ('dev','ff','beta','live'));

-- Stamp app_phase from the author's cohort (parallels feedback_set_is_staged in 018). A profile cohort wins
-- over whatever the client sent; with no profile row the client value (or 'dev') stands. Runs before insert.
create or replace function feedback_set_app_phase() returns trigger
  language plpgsql
  set search_path = public, pg_temp
  as $$
declare v_cohort text;
begin
  if new.user_id is not null then
    select p.cohort into v_cohort from profiles p where p.user_id = new.user_id;
    if v_cohort is not null then new.app_phase := v_cohort; end if;
  end if;
  if new.app_phase is null then new.app_phase := 'dev'; end if;
  return new;
end $$;
drop trigger if exists feedback_set_app_phase_trg on feedback;
create trigger feedback_set_app_phase_trg before insert on feedback
  for each row execute function feedback_set_app_phase();

-- Backfill: re-stamp existing feedback whose author now has a non-dev cohort (none at first apply; keeps the
-- migration correct if re-run after F&F accounts exist). Anonymized rows (user_id null) keep their phase.
update feedback f set app_phase = p.cohort
  from profiles p
 where f.user_id = p.user_id and f.app_phase is distinct from p.cohort;
