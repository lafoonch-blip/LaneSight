-- 004 RLS hardening (found by Supabase security advisor on first deploy, 2026-10-22). Idempotent.
-- Schema v1 enabled RLS only on tables that carry user_id. On Supabase every public table is reachable through the
-- API with the anon key, so the other 14 tables were readable/writable by anyone. This migration:
--   1. enables RLS on every remaining table, with ownership resolved through the parent row;
--   2. makes shared reference tables (centers, oil_patterns) read-only to signed-in users (public patterns + own);
--   3. switches metric_variance to security_invoker so it respects the caller's RLS;
--   4. rewrites policies to `(select auth.uid())` (evaluated once per query, not per row) and scopes them to `authenticated`;
--   5. indexes every foreign key used by those policies and by common joins.
-- Writes to centers / ball_models stay service-role only (seed loaders).

-- ---------- 4. own_rows on user_id tables: per-query auth.uid(), authenticated only ----------
do $$ declare t text; begin
  foreach t in array array['profiles','bowler_baselines','user_balls','sessions','games','video_assets','shots','sensor_devices'] loop
    execute format('drop policy if exists own_rows on %I', t);
    execute format('create policy own_rows on %I to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
  end loop;
end $$;

-- ---------- 1. child tables: ownership through the parent ----------
-- via user_balls
do $$ declare t text; begin
  foreach t in array array['ball_configurations','surface_events','maintenance_events'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists own_rows on %I', t);
    execute format($p$create policy own_rows on %I to authenticated
      using (exists (select 1 from user_balls ub where ub.id = user_ball_id and ub.user_id = (select auth.uid())))
      with check (exists (select 1 from user_balls ub where ub.id = user_ball_id and ub.user_id = (select auth.uid())))$p$, t);
  end loop;
end $$;

-- via sessions
do $$ declare t text; begin
  foreach t in array array['calibrations','transition_states'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists own_rows on %I', t);
    execute format($p$create policy own_rows on %I to authenticated
      using (exists (select 1 from sessions s where s.id = session_id and s.user_id = (select auth.uid())))
      with check (exists (select 1 from sessions s where s.id = session_id and s.user_id = (select auth.uid())))$p$, t);
  end loop;
end $$;

-- via shots
do $$ declare t text; begin
  foreach t in array array['shot_intents','shot_feedback','measurements','pin_states'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists own_rows on %I', t);
    execute format($p$create policy own_rows on %I to authenticated
      using (exists (select 1 from shots s where s.id = shot_id and s.user_id = (select auth.uid())))
      with check (exists (select 1 from shots s where s.id = shot_id and s.user_id = (select auth.uid())))$p$, t);
  end loop;
end $$;

-- frames via games; rolls via frames -> games
alter table frames enable row level security;
drop policy if exists own_rows on frames;
create policy own_rows on frames to authenticated
  using (exists (select 1 from games g where g.id = game_id and g.user_id = (select auth.uid())))
  with check (exists (select 1 from games g where g.id = game_id and g.user_id = (select auth.uid())));

alter table rolls enable row level security;
drop policy if exists own_rows on rolls;
create policy own_rows on rolls to authenticated
  using (exists (select 1 from frames f join games g on g.id = f.game_id where f.id = frame_id and g.user_id = (select auth.uid())))
  with check (exists (select 1 from frames f join games g on g.id = f.game_id where f.id = frame_id and g.user_id = (select auth.uid())));

-- sensor_shots via sensor_devices
alter table sensor_shots enable row level security;
drop policy if exists own_rows on sensor_shots;
create policy own_rows on sensor_shots to authenticated
  using (exists (select 1 from sensor_devices d where d.id = device_id and d.user_id = (select auth.uid())))
  with check (exists (select 1 from sensor_devices d where d.id = device_id and d.user_id = (select auth.uid())));

-- recommendations via their session or shot; outcomes via the recommendation
alter table recommendations enable row level security;
drop policy if exists own_rows on recommendations;
create policy own_rows on recommendations to authenticated
  using (exists (select 1 from sessions s where s.id = session_id and s.user_id = (select auth.uid()))
      or exists (select 1 from shots s where s.id = shot_id and s.user_id = (select auth.uid())))
  with check (exists (select 1 from sessions s where s.id = session_id and s.user_id = (select auth.uid()))
      or exists (select 1 from shots s where s.id = shot_id and s.user_id = (select auth.uid())));

alter table recommendation_outcomes enable row level security;
drop policy if exists own_rows on recommendation_outcomes;
create policy own_rows on recommendation_outcomes to authenticated
  using (exists (select 1 from recommendations r where r.id = recommendation_id))      -- recommendations RLS applies inside
  with check (exists (select 1 from recommendations r where r.id = recommendation_id));

-- ---------- 2. shared reference tables ----------
alter table centers enable row level security;
drop policy if exists centers_read on centers;
create policy centers_read on centers for select to authenticated using (true);

alter table oil_patterns enable row level security;
drop policy if exists patterns_read on oil_patterns;
drop policy if exists patterns_own_insert on oil_patterns;
drop policy if exists patterns_own_update on oil_patterns;
drop policy if exists patterns_own_delete on oil_patterns;
create policy patterns_read on oil_patterns for select to authenticated
  using (is_public or created_by = (select auth.uid()));
create policy patterns_own_insert on oil_patterns for insert to authenticated with check (created_by = (select auth.uid()));
create policy patterns_own_update on oil_patterns for update to authenticated
  using (created_by = (select auth.uid())) with check (created_by = (select auth.uid()));
create policy patterns_own_delete on oil_patterns for delete to authenticated using (created_by = (select auth.uid()));

-- ---------- 3. view respects caller RLS ----------
alter view metric_variance set (security_invoker = true);

-- ---------- 5. foreign-key indexes ----------
create index if not exists bowler_baselines_user_id_idx on bowler_baselines (user_id);
create index if not exists user_balls_user_id_idx on user_balls (user_id);
create index if not exists user_balls_ball_model_id_idx on user_balls (ball_model_id);
create index if not exists surface_events_user_ball_idx on surface_events (user_ball_id, event_at desc);
create index if not exists maintenance_events_user_ball_idx on maintenance_events (user_ball_id);
create index if not exists oil_patterns_created_by_idx on oil_patterns (created_by);
create index if not exists sessions_user_id_idx on sessions (user_id);
create index if not exists sessions_center_id_idx on sessions (center_id);
create index if not exists sessions_oil_pattern_id_idx on sessions (oil_pattern_id);
create index if not exists sessions_default_ball_id_idx on sessions (default_ball_id);
create index if not exists calibrations_session_id_idx on calibrations (session_id);
create index if not exists games_session_id_idx on games (session_id);
create index if not exists games_user_id_idx on games (user_id);
create index if not exists rolls_shot_id_idx on rolls (shot_id);
create index if not exists video_assets_user_id_idx on video_assets (user_id);
create index if not exists shots_user_id_idx on shots (user_id);
create index if not exists shots_session_id_idx on shots (session_id);
create index if not exists shots_game_id_idx on shots (game_id);
create index if not exists shots_roll_id_idx on shots (roll_id);
create index if not exists shots_video_asset_id_idx on shots (video_asset_id);
create index if not exists shots_user_ball_id_idx on shots (user_ball_id);
create index if not exists shots_ball_configuration_id_idx on shots (ball_configuration_id);
create index if not exists shots_surface_event_id_idx on shots (surface_event_id);
create index if not exists sensor_devices_user_id_idx on sensor_devices (user_id);
create index if not exists sensor_shots_device_id_idx on sensor_shots (device_id);
create index if not exists sensor_shots_shot_id_idx on sensor_shots (shot_id);
create index if not exists recommendations_shot_id_idx on recommendations (shot_id);
create index if not exists recommendations_session_id_idx on recommendations (session_id);
create index if not exists recommendation_outcomes_next_shot_idx on recommendation_outcomes (next_shot_id);
create index if not exists transition_states_session_id_idx on transition_states (session_id);
create index if not exists transition_states_after_shot_idx on transition_states (after_shot_id);
