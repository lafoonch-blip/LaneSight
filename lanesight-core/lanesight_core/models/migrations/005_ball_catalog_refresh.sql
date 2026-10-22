-- 005 Weekly catalog refresh support (lanesight_core/arsenal/refresh.py, data/ball_catalog/REFRESH.md). Idempotent.
-- Balls are never deleted (user arsenals reference them): a ball dropped from a manufacturer's lineup is kept with
-- status 'discontinued' and the date it was first seen missing. source_hash lets the weekly sync upsert only the
-- rows that changed.

alter table ball_models
  add column if not exists discontinued_on date,
  add column if not exists source_hash     text;

do $$ begin
  alter table ball_models add constraint ball_models_discontinued_chk
    check (discontinued_on is null or status = 'discontinued');
exception when duplicate_object then null; end $$;
