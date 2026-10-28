-- 026_arsenal_default_ball.sql — DEC-099.
-- A bowler can mark ONE arsenal ball as their default. The default is the ball a NEW session starts with
-- (Setup pre-selects it); `is_current` stays the ball in use right now (it moves whenever the bowler picks a
-- ball in Setup or on the Active Session, DEC-097), so the two must be separate columns.
-- Additive and idempotent. No backfill: until a bowler sets one, Setup keeps using the current ball.
-- RLS unchanged: the column inherits user_balls' per-owner policies (migration 004).

alter table user_balls add column if not exists is_default boolean not null default false;

-- At most one default per user, enforced by the database (the API also unsets the others first).
create unique index if not exists user_balls_one_default_per_user
  on user_balls (user_id) where is_default;
