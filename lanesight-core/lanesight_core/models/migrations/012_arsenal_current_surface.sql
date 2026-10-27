-- 012_arsenal_current_surface.sql — Dev Build v0.
-- Lets the app persist a full arsenal (catalog or custom ball + layout + surface + which ball is current)
-- and link every shot to the ball_configuration it was thrown with (shots.ball_configuration_id already
-- exists; this adds the two columns the app needs to round-trip the arsenal). Additive and idempotent.
-- RLS is unchanged: the new columns inherit the existing per-owner policies on user_balls and
-- ball_configurations (migration 004), which gate by user_id / parent user_ball_id.

-- Exactly one "current ball" per user is enforced in the API (it unsets the others on set-current); a
-- not-null default keeps existing rows valid.
alter table user_balls add column if not exists is_current boolean not null default false;

-- surface_events stays the append-only resurface/polish history. This is the quick "current surface"
-- string the app stores next to layout on a ball_configuration (dev-build convenience, e.g. '3000 abralon').
alter table ball_configurations add column if not exists surface text;
