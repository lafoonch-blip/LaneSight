-- 035 — Engine parity view (DEC-117 item 5/6). Additive, read-only. Pairs the on-device (ios) and server
-- analysis_attempt rows for the SAME shot and exposes the speed/rev deltas + a disagreement flag, so the ops
-- dashboard can render a parity panel and flag shots for review. The phone value stays primary (DEC-117);
-- a flagged shot is reviewed in ops, never silently swapped. No behavior change to the live service.

create or replace view ops.engine_parity as
with ios as (
  select distinct on (shot_id)
    shot_id, user_id, session_id, created_at,
    (diagnostics->>'ball_speed')::numeric              as ios_speed,
    (diagnostics->>'rev_rate')::numeric                as ios_rev,
    algorithm_version                                  as ios_version,
    (diagnostics#>>'{device,latency_s}')::numeric      as ios_latency_s,
    (diagnostics#>>'{device,peak_mem_mb}')::numeric    as ios_peak_mem_mb,
    (diagnostics#>>'{device,battery_delta}')::numeric  as ios_battery_delta
  from public.analysis_attempt
  where platform = 'ios' and status = 'analyzed'
  order by shot_id, created_at desc
),
srv as (
  select distinct on (shot_id)
    shot_id,
    (diagnostics->>'ball_speed')::numeric as srv_speed,
    (diagnostics->>'rev_rate')::numeric   as srv_rev,
    api_revision                          as srv_version,
    created_at                            as srv_created_at
  from public.analysis_attempt
  where platform = 'server' and status = 'analyzed'
  order by shot_id, created_at desc
)
select
  i.shot_id, i.user_id, i.session_id, i.created_at,
  i.ios_speed, s.srv_speed,
  round(i.ios_speed - s.srv_speed, 3)                                      as speed_delta,
  i.ios_rev, s.srv_rev,
  round(i.ios_rev - s.srv_rev, 1)                                         as rev_delta,
  -- DEC-117 item 3/6 tolerance: speed within 0.3 mph. Flag (don't swap) when the phone & server disagree beyond it.
  (i.ios_speed is not null and s.srv_speed is not null
     and abs(i.ios_speed - s.srv_speed) > 0.3)                            as speed_disagree,
  (i.ios_rev is not null and s.srv_rev is not null
     and abs(i.ios_rev - s.srv_rev) > 50)                                 as rev_disagree,
  i.ios_version, s.srv_version, i.ios_latency_s, i.ios_peak_mem_mb, i.ios_battery_delta
from ios i
left join srv s using (shot_id);

comment on view ops.engine_parity is
  'DEC-117: per-shot phone(ios) vs server speed/rev parity + disagreement flags (speed >0.3 mph, rev >50 rpm). '
  'Phone is primary; flagged shots are reviewed in ops, never silently swapped. Latest attempt per platform per shot.';
