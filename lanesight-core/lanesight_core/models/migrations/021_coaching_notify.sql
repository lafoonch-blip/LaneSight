-- 021 Coaching launch notify flag (DEC-084). Additive + idempotent.
-- The Coaching tab's "Notify me when it's ready" button records a per-user interest flag so the one launch
-- notification can go out later. Stored on profiles (owner RLS already covers it). No live apply here.

alter table profiles
  add column if not exists notify_coaching_launch    boolean,
  add column if not exists notify_coaching_launch_at timestamptz;

comment on column profiles.notify_coaching_launch is
  'DEC-084: user asked to be notified when the Coaching feature launches (one notification at launch).';
