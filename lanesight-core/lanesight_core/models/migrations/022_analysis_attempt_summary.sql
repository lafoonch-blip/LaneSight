-- 022 Analysis-attempt summary view (DEC-086). Read-only convenience over analysis_attempt: flattens the
-- clip + diagnostics jsonb into the columns needed to review a live session — camera/recording facts
-- (resolution, rotation, fps, HDR, variable-frame-rate), capture quality (far-lane read?), headline geometry,
-- and analyze time — alongside status/failure. security_invoker=on so RLS still scopes rows to the owner.

create or replace view analysis_attempt_summary
with (security_invoker = true) as
select created_at, env, source, capture_mode, status, failure_code, failure_stage,
       round(duration_ms / 1000.0, 1)              as analyze_seconds,
       (clip->>'width')::int                       as width,
       (clip->>'height')::int                      as height,
       (clip->>'short_side_px')::int               as short_side_px,
       (clip->>'rotation')::int                    as rotation_deg,
       (clip->>'fps')::numeric                     as fps,
       (clip->>'nominal_fps')::numeric             as nominal_fps,
       (clip->>'hdr')::boolean                     as hdr,
       (clip->>'variable_frame_rate')::boolean     as variable_frame_rate,
       (clip->>'duration_s')::numeric              as clip_seconds,
       round((clip->>'bytes')::numeric / 1048576.0, 1) as clip_mb,
       clip->>'probe_error'                        as probe_error,
       diagnostics->>'far_lane'                    as far_lane,
       diagnostics->>'capture_reason'              as capture_reason,
       (diagnostics->>'entry_board')::numeric      as entry_board,
       (diagnostics->>'ball_speed')::numeric       as ball_speed,
       (diagnostics->>'rev_rate')::numeric         as rev_rate,
       (diagnostics->>'n_measured')::int           as n_measured,
       diagnostics->>'view'                        as form_view,
       algorithm_version, api_revision, shot_id, session_id, user_id, diagnostics
from analysis_attempt;

comment on view analysis_attempt_summary is
  'DEC-086: per-attempt review (camera/recording facts + capture quality + analyze time + failure). Owner-scoped.';

-- Keep the existing failure-rate rollup owner-scoped too (it was created without security_invoker in 019).
alter view analysis_failure_rates set (security_invoker = true);