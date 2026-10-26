-- 018 Staged test accounts (DEC-063, HANDOFF_2026-10-26_STAGED_TEST_ACCOUNTS). Additive and idempotent.
-- Flags a profile (and, at insert, its feedback) as STAGED so the full-experience test accounts are seeded
-- into known states without ever contaminating Shayne's real account, and so staged data is excluded from
-- feedback review, analytics and cross-user baselines. RLS is unchanged — staged users are ordinary users;
-- the service role does all seeding/resetting and enforces the "never touch a non-staged account" rule in
-- code (ops/seed_staged_accounts.py). DO NOT apply to live — that is Shayne's step.

-- ---------------------------------------------------------------------------
-- profiles: is_staged + staged_kind
-- ---------------------------------------------------------------------------
alter table profiles
  add column if not exists is_staged   boolean not null default false,
  add column if not exists staged_kind text;

do $$ begin
  alter table profiles add constraint profiles_staged_kind_chk
    check (staged_kind is null or staged_kind in
           ('new_user','active','improving','struggling','edge_cases','heavy','under_13'));
exception when duplicate_object then null; end $$;
-- staged_kind only makes sense on a staged profile
do $$ begin
  alter table profiles add constraint profiles_staged_kind_requires_flag
    check (staged_kind is null or is_staged = true);
exception when duplicate_object then null; end $$;

comment on column profiles.is_staged is
  'true = a seeded full-experience TEST account (DEC-063); excluded from feedback review/analytics/baselines. Never a real bowler.';
comment on column profiles.staged_kind is
  'which staged persona (new_user|active|improving|struggling|edge_cases|heavy|under_13); null for real accounts.';

-- ---------------------------------------------------------------------------
-- feedback: is_staged, stamped at insert from the author's profile so it SURVIVES account deletion
-- (DEC-059 keeps feedback rows after user_id -> null). A trigger copies profiles.is_staged on insert.
-- ---------------------------------------------------------------------------
alter table feedback add column if not exists is_staged boolean not null default false;
create index if not exists feedback_is_staged_idx on feedback (is_staged);

create or replace function feedback_set_is_staged() returns trigger
  language plpgsql as $$
begin
  if new.user_id is not null then
    select coalesce(p.is_staged, false) into new.is_staged
      from profiles p where p.user_id = new.user_id;
  end if;
  return new;
end $$;
drop trigger if exists feedback_is_staged on feedback;
create trigger feedback_is_staged before insert on feedback
  for each row execute function feedback_set_is_staged();

-- Backfill: any existing feedback authored by an already-staged profile (none at first apply, but keeps the
-- migration correct if re-run after seeding). Real-account feedback stays is_staged = false.
update feedback f set is_staged = true
  from profiles p
 where f.user_id = p.user_id and p.is_staged = true and f.is_staged = false;

-- ---------------------------------------------------------------------------
-- Owner-facing feedback review view: excludes staged feedback (triage columns included — owner/service-role
-- only; this view is not granted to authenticated). Replaces ad-hoc "select from feedback" for triage so the
-- staged exclusion is in one place. Real rows only.
-- ---------------------------------------------------------------------------
create or replace view feedback_review as
  select * from feedback where is_staged = false;

revoke all on feedback_review from anon, authenticated;
grant select on feedback_review to rules_admin;
comment on view feedback_review is 'Owner feedback triage — REAL feedback only (staged excluded, DEC-063).';
