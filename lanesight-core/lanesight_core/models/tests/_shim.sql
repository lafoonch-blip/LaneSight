-- Supabase-isms shim for local Postgres validation of LaneSight migrations/RLS.
-- Provides the auth schema/table, auth.uid() (reads a session GUC we set in tests), the
-- anon/authenticated/service_role roles, and the default grants Supabase applies, so RLS policies and
-- GRANT/REVOKE behave as on Supabase. Run as the connecting superuser BEFORE schema.sql.
create extension if not exists pgcrypto;

do $$ begin create role anon          nologin noinherit; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin noinherit; exception when duplicate_object then null; end $$;
do $$ begin create role service_role  nologin noinherit bypassrls; exception when duplicate_object then null; end $$;

create schema if not exists auth;
create table if not exists auth.users (id uuid primary key);
create or replace function auth.uid() returns uuid
  language sql stable
  as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated, service_role;
