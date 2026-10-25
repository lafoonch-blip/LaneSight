-- 014 One retained feedback store (DEC-059, FEEDBACK_STORE_SPEC v1.0). Additive and idempotent.
-- A single `feedback` table captures every piece of bowler feedback across dev / beta / live:
-- shot notes+tags (DEC-058), session-end feedback (DEC-053), advice 👍/👎, and future form/general notes.
-- Feedback is WRITE-AND-KEEP: nothing in the app reads it to change a measurement, rule, score or advice.
--   * Tagged with app phase (dev/beta/live) and the app/core/rules/formula versions that produced the
--     results it is about.
--   * Links to shot/session/recommendation are NULLABLE and ON DELETE SET NULL, so feedback OUTLIVES the
--     shot or session it was written about; a `context` JSON snapshot keeps "what I saw vs what we
--     measured" comparable even after the source row is gone.
--   * Owner-only triage columns (triage_status/owner_notes/action_ref) are hidden from the bowler by a
--     column-level grant; the bowler can insert and read/update only their own rows, and can NEVER delete.
--   * Account deletion ANONYMIZES rows (user_id -> null, anonymized_at set) rather than deleting them; the
--     Mac service performs that in code (see lanesight_api PgStore.delete_user).
-- Backfill: existing session_feedback rows (migration 008) are copied in by the same id (idempotent).

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------
create table if not exists feedback (
  id               uuid primary key default gen_random_uuid(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  source           text not null
                     check (source in ('shot_note','session_feedback','advice_rating','form_note','general')),
  app_phase        text not null default 'dev' check (app_phase in ('dev','beta','live')),
  app_version      text,
  core_version     text,
  rules_version    text,
  formula_version  text,
  user_id          uuid references auth.users(id) on delete set null,   -- null once the account is deleted
  user_ref         text,                                                -- stable pseudonymous id, kept after deletion
  session_id       uuid references sessions(id) on delete set null,
  shot_id          uuid references shots(id) on delete set null,
  recommendation_id uuid references recommendations(id) on delete set null,
  capture_mode     text check (capture_mode is null or capture_mode in ('shot','form')),
  is_upload        boolean not null default false,
  rating           smallint check (rating is null or rating between 1 and 5),
  thumbs           text check (thumbs is null or thumbs in ('up','down')),
  tags             text[] not null default '{}'::text[],
  text             text,
  context          jsonb,                 -- snapshot at write time of the measured result the feedback is about
  diagnostics      jsonb,                 -- timings, errors, device, capture fps (when the user allows it)
  triage_status    text not null default 'new'
                     check (triage_status in ('new','reviewed','actioned','dismissed')),   -- OWNER-ONLY
  owner_notes      text,                  -- OWNER-ONLY
  action_ref       text,                  -- OWNER-ONLY: rules version / DEC / task id
  anonymized_at    timestamptz            -- set when the account is deleted
);

create index if not exists feedback_created_idx     on feedback (created_at);
create index if not exists feedback_source_phase_idx on feedback (source, app_phase);
create index if not exists feedback_user_ref_idx     on feedback (user_ref);
create index if not exists feedback_shot_idx         on feedback (shot_id);
create index if not exists feedback_session_idx      on feedback (session_id);
create index if not exists feedback_triage_idx       on feedback (triage_status);
create index if not exists feedback_user_idx         on feedback (user_id, created_at desc);

-- Autosaved notes update the same row -> keep updated_at fresh.
create or replace function feedback_set_updated_at() returns trigger
  language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists feedback_updated_at on feedback;
create trigger feedback_updated_at before update on feedback
  for each row execute function feedback_set_updated_at();

-- ---------------------------------------------------------------------------
-- Access (RLS + column-level grants)
-- ---------------------------------------------------------------------------
-- The bowler may INSERT feedback and READ / UPDATE only their own rows; they can never DELETE, and the
-- triage columns are hidden from them by column-level privileges (RLS alone can't hide columns). All
-- server writes go through the service_role (bypassrls); these policies are the client-facing guarantee.
alter table feedback enable row level security;

-- start from no client privilege, then grant exactly what the bowler may touch (triage columns excluded).
revoke all on feedback from anon, authenticated;
grant select (id, created_at, updated_at, source, app_phase, app_version, core_version, rules_version,
              formula_version, user_id, user_ref, session_id, shot_id, recommendation_id, capture_mode,
              is_upload, rating, thumbs, tags, text, context, diagnostics, anonymized_at)
  on feedback to authenticated;
grant insert (source, app_phase, app_version, core_version, rules_version, formula_version, user_id,
              user_ref, session_id, shot_id, recommendation_id, capture_mode, is_upload, rating, thumbs,
              tags, text, context, diagnostics)
  on feedback to authenticated;
grant update (tags, text, context, diagnostics)           -- edit an autosaved note only
  on feedback to authenticated;
-- owner role (marker/grant target; real owner reads run as the service_role, which bypasses RLS).
grant select, insert, update, delete on feedback to rules_admin;

drop policy if exists own_select on feedback;
create policy own_select on feedback for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists own_insert on feedback;
create policy own_insert on feedback for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists own_update on feedback;
create policy own_update on feedback for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
-- NO delete policy and no delete grant: removing feedback is an owner action only.

-- ---------------------------------------------------------------------------
-- Backfill: copy existing session_feedback rows (migration 008) into feedback. Idempotent (by id).
-- These predate the phase/version tagging and the context snapshot; app_phase defaults to 'dev'
-- (the build that produced them) and context stays null.
-- ---------------------------------------------------------------------------
do $$ begin
  if exists (select 1 from information_schema.tables
             where table_schema = 'public' and table_name = 'session_feedback') then
    insert into feedback (id, created_at, updated_at, source, app_phase, app_version, core_version,
                          formula_version, user_id, session_id, rating, tags, text, diagnostics)
    select sf.id, sf.created_at, sf.created_at, 'session_feedback', 'dev', sf.app_version, sf.core_version,
           sf.formula_version, sf.user_id, sf.session_id, sf.rating, coalesce(sf.tags, '{}'::text[]),
           sf.text, sf.diagnostics
      from session_feedback sf
     where not exists (select 1 from feedback f where f.id = sf.id);
  end if;
end $$;
