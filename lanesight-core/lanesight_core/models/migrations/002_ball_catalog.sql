-- 002 Ball catalog: stock photo, out-of-box specs, published ratings and normalized expected reaction.
-- Extends schema v1 `ball_models` (shared catalog, DEC-007). Specs are the 15 lb ball's. Idempotent.
-- Normalized reaction scales (lanesight_core/arsenal/catalog.py):
--   ls_hook 1 (little) .. 10 (max)   ls_length 1 (reads early) .. 10 (very long)   ls_backend 1 (smooth) .. 10 (angular)
-- reaction_basis records where each value came from; 'spec_estimate' values are estimates and must be labeled in the UI.

alter table ball_models
  add column if not exists parent_company   text,
  add column if not exists product_line     text,
  add column if not exists performance_tier text,
  add column if not exists release_date     text,                -- 'YYYY-MM' or 'YYYY' as published
  add column if not exists status           text not null default 'current',
  add column if not exists colors           text,
  add column if not exists core_name        text,
  add column if not exists recommended_oil  text,                -- manufacturer's stated condition
  add column if not exists image_url        text,                -- manufacturer stock photo, linked not hosted
  add column if not exists image_source     text,                -- 'manufacturer' | 'retailer'
  add column if not exists product_url      text,
  add column if not exists spec_source_urls text[] not null default '{}',
  add column if not exists mfr_ratings      jsonb,               -- manufacturer ratings as published (+ scale)
  add column if not exists retailer_ratings jsonb,               -- bowling.com ratings as published (+ scale)
  add column if not exists motion_chart     jsonb,               -- Brunswick Ball Motion Comparison Chart (oil 1-16, shape 1-18)
  add column if not exists reaction_description text,            -- short paraphrase, not marketing copy
  add column if not exists ls_hook          numeric(3,1),
  add column if not exists ls_length        numeric(3,1),
  add column if not exists ls_backend       numeric(3,1),
  add column if not exists ls_oil           text,
  add column if not exists ls_oil_min       text,
  add column if not exists ls_oil_max       text,
  add column if not exists reaction_shape   text,
  add column if not exists reaction_basis   jsonb,
  add column if not exists reaction_confidence text,
  add column if not exists missing_fields   text[] not null default '{}',
  add column if not exists catalog_version  text,
  add column if not exists normalizer_version text,
  add column if not exists retrieved_at     timestamptz,
  add column if not exists updated_at       timestamptz not null default now();

do $$ begin
  alter table ball_models add constraint ball_models_tier_chk
    check (performance_tier is null or performance_tier in ('high','upper_mid','mid','entry','spare'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table ball_models add constraint ball_models_status_chk check (status in ('current','discontinued'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table ball_models add constraint ball_models_cover_chk
    check (cover_type is null or cover_type in ('solid','pearl','hybrid','urethane','polyester','other'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table ball_models add constraint ball_models_oil_chk
    check ((ls_oil is null or ls_oil in ('dry','light','medium','medium_heavy','heavy'))
       and (ls_oil_min is null or ls_oil_min in ('dry','light','medium','medium_heavy','heavy'))
       and (ls_oil_max is null or ls_oil_max in ('dry','light','medium','medium_heavy','heavy')));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table ball_models add constraint ball_models_shape_chk
    check (reaction_shape is null or reaction_shape in ('straight','arc','continuous','angular','skid_flip'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table ball_models add constraint ball_models_ls_range_chk check (
    (ls_hook is null or ls_hook between 1 and 10) and (ls_length is null or ls_length between 1 and 10)
    and (ls_backend is null or ls_backend between 1 and 10));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table ball_models add constraint ball_models_conf_chk
    check (reaction_confidence is null or reaction_confidence in ('high','medium','low'));
exception when duplicate_object then null; end $$;

create index if not exists ball_models_reaction_idx on ball_models (status, ls_oil, ls_hook, ls_length);
create index if not exists ball_models_mfr_idx on ball_models (manufacturer);

-- Shared catalog: everyone signed in can read; only the service role (seed loader) writes.
alter table ball_models enable row level security;
do $$ begin
  create policy catalog_read on ball_models for select to authenticated using (true);
exception when duplicate_object then null; end $$;
