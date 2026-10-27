-- 005 Ball catalog refresh support. Idempotent.
-- Adds discontinued_on (set only when status = 'discontinued') and source_hash (for change detection on
-- the scheduled catalog refresh, DEC-044) to ball_models.
-- Reconciled into the repo 2026-10-22 from the applied LaneSight Supabase state (europwryibstnmipbvam);
-- it was authored and applied outside this repo. Lineage: schema.sql (001) → 002 → 003 → 004 → 005.

alter table ball_models
  add column if not exists discontinued_on date,
  add column if not exists source_hash     text;

do $$ begin
  alter table ball_models add constraint ball_models_discontinued_chk
    check (discontinued_on is null or status = 'discontinued');
exception when duplicate_object then null; end $$;
