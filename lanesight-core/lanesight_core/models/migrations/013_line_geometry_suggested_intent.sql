-- 013_line_geometry_suggested_intent.sql — Dev Build v0.
-- (1) Owner-editable lane geometry so "Apply this move" can DERIVE the breakpoint by projecting the new
--     feet->arrows sight line to the breakpoint distance (instead of shifting it by the target move):
--     stance is approach_offset_ft behind the foul line, arrows are arrows_ft past it.
-- (2) Store the SUGGESTED target boards next to the USED ones on each shot, so an applied-then-edited shot
--     keeps both. Additive and idempotent.

-- do nothing (not do update): keep any value the owner has edited; this only sets the default once.
insert into engine_config (key, value) values
  ('line_geometry', '{"approach_offset_ft": 15.0, "arrows_ft": 15.0}'::jsonb)
  on conflict (key) do nothing;

alter table shot_intents add column if not exists suggested_feet_board numeric;
alter table shot_intents add column if not exists suggested_arrows_board numeric;
alter table shot_intents add column if not exists suggested_breakpoint_board numeric;
