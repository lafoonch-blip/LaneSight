-- 003 Drilling + surface inputs for the configured reaction (lanesight_core/arsenal/configured.py). Idempotent.
-- A user ball's expected reaction = catalog box reaction, adjusted by its current layout (ball_configurations,
-- versioned) and its current surface (surface_events, append-only — the bowler can re-sand/polish any time).

alter table ball_configurations
  add column if not exists pin_buffer_in numeric,          -- VLS third number
  add column if not exists pin_position  text;             -- when the bowler only knows "pin up / pin down"
do $$ begin
  alter table ball_configurations add constraint ball_configurations_pin_position_chk
    check (pin_position is null or pin_position in ('above_fingers','near_fingers','below_fingers'));
exception when duplicate_object then null; end $$;
-- layout_system stays free text: configured.parse_layout accepts 'Dual Angle' / 'dual_angle' / 'VLS' / 'Vector'.

alter table surface_events
  add column if not exists grit_value int,                 -- effective grit of the last step (e.g. 2000)
  add column if not exists polished   boolean,             -- polish/compound applied after sanding
  add column if not exists source     text not null default 'manual';   -- manual | pro_shop | resurface_service
do $$ begin
  alter table surface_events add constraint surface_events_grit_chk check (grit_value is null or grit_value between 180 and 30000);
exception when duplicate_object then null; end $$;

-- Each shot keeps the surface it was thrown with, so history isn't rewritten when the bowler re-sands (DEC-007).
alter table shots add column if not exists surface_event_id uuid references surface_events(id);

-- Current state per user ball: latest configuration version + latest surface event (null = box finish).
create or replace view user_ball_current with (security_invoker = true) as
select ub.id as user_ball_id, ub.user_id, ub.ball_model_id,
       bc.id as ball_configuration_id, bc.version as configuration_version,
       se.id as surface_event_id, se.event_at as surface_changed_at, se.grit_value, se.polished, se.grit, se.polish
from user_balls ub
left join lateral (select * from ball_configurations c where c.user_ball_id = ub.id
                   order by c.version desc limit 1) bc on true
left join lateral (select * from surface_events s where s.user_ball_id = ub.id
                   order by s.event_at desc limit 1) se on true;

-- surface_events / ball_configurations belong to the user through user_balls.
alter table ball_configurations enable row level security;
alter table surface_events enable row level security;
do $$ begin
  create policy own_rows on ball_configurations
    using (exists (select 1 from user_balls ub where ub.id = user_ball_id and ub.user_id = auth.uid()))
    with check (exists (select 1 from user_balls ub where ub.id = user_ball_id and ub.user_id = auth.uid()));
exception when duplicate_object then null; end $$;
do $$ begin
  create policy own_rows on surface_events
    using (exists (select 1 from user_balls ub where ub.id = user_ball_id and ub.user_id = auth.uid()))
    with check (exists (select 1 from user_balls ub where ub.id = user_ball_id and ub.user_id = auth.uid()));
exception when duplicate_object then null; end $$;
