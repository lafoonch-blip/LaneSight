-- 023 Analysis-attempt summary v2 (DEC-092 P0). Read-only view update; surfaces the new P0 signals that
-- already live in the attempt jsonb (clip / step_timings / diagnostics): cold start, bit depth, the shadow
-- precheck verdict, decode passes/seconds, server analyze seconds, and the phone-side pre-analyze time.
-- security_invoker so it stays owner-scoped. NOT applied to live by Claude Code — list for Shayne.

create or replace view analysis_attempt_summary
with (security_invoker = true) as
select created_at, env, source, capture_mode, status, failure_code, failure_stage,
       round(duration_ms / 1000.0, 1)              as analyze_seconds,
       (step_timings->>'analyze_s')::numeric       as server_analyze_s,
       (step_timings->'decode'->>'passes')::int    as decode_passes,
       (step_timings->'decode'->>'seconds')::numeric as decode_s,
       (step_timings->'client'->>'client_pre_analyze_s')::numeric as phone_pre_analyze_s,
       (step_timings->'client'->>'trim_s')::numeric   as phone_trim_s,
       (step_timings->'client'->>'upload_s')::numeric as phone_upload_s,
       (step_timings->'convert_s')::numeric        as hdr_convert_s,
       (clip->>'cold_start')::boolean              as cold_start,
       (clip->>'width')::int                       as width,
       (clip->>'height')::int                      as height,
       (clip->>'rotation')::int                    as rotation_deg,
       (clip->>'fps')::numeric                     as fps,
       (clip->>'hdr')::boolean                     as hdr,
       (clip->>'bit_depth')::int                   as bit_depth,
       (clip->>'variable_frame_rate')::boolean     as variable_frame_rate,
       (clip->>'duration_s')::numeric              as clip_seconds,
       round((clip->>'bytes')::numeric / 1048576.0, 1) as clip_mb,
       (clip->'precheck'->>'ok')                   as precheck_ok,
       (clip->'precheck'->>'code')                 as precheck_code,
       (clip->'precheck'->>'seconds')::numeric     as precheck_s,
       diagnostics->>'far_lane'                    as far_lane,
       diagnostics->>'capture_reason'              as capture_reason,
       (diagnostics->>'entry_board')::numeric      as entry_board,
       (diagnostics->>'ball_speed')::numeric       as ball_speed,
       algorithm_version, api_revision, shot_id, session_id, user_id
from analysis_attempt;

comment on view analysis_attempt_summary is
  'DEC-086/092: per-attempt review — camera facts, bit depth, cold start, shadow-precheck verdict, decode '
  'passes/seconds, server analyze time, phone pre-analyze/trim/upload time, HDR convert time. Owner-scoped.';