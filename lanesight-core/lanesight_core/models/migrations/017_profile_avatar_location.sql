-- 017: profile photo + location column (GUARDRAILS 3.7 workstream G).
-- Dev Build stores the processed avatar on the Mac service's disk (DATA_ROOT/avatars/<user_id>.jpg) and the
-- API serves it via GET /me/avatar; the phone only ever talks to the API. avatar_path is that relative path.
-- (A Supabase private Storage bucket is the target for the cloud build; the Mac Dev Build uses local disk.)
-- Also fixes the bug where PUT /me/profile silently dropped `location` (there was no column): added here.

alter table profiles add column if not exists avatar_path text;
alter table profiles add column if not exists avatar_updated_at timestamptz;
alter table profiles add column if not exists location text;

comment on column profiles.avatar_path is 'relative path to the processed 512px JPEG avatar on the API host (DEC-057 profile photo).';
comment on column profiles.location is 'free-text home center / city shown on the profile.';
