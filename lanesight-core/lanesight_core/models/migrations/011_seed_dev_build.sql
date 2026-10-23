-- 011 Dev Build v0 seed content (SCORE_TIERS §4 + RULES_AND_POWER_REVIEW.md). Idempotent.
-- GENERATED from lanesight_api/rules_seed.py (the single source of truth). Regenerate, don't hand-edit.
-- Seeds owner-only rule data: achievement_definition (active catalog + coming_later), engine_config,
-- style_template(+_metric), drill, form_rule, benchmark_reference. Also sets the L-dev-0 power ranges
-- on score_formula_version so the formula is computable (power ranges confirmed 2026-10-22; 15 lb ball).
-- DO NOT apply to the live project here — the owner applies 011 (and commits) separately.

-- engine_config (owner-editable): power ranges, prioritizer weights, baseline/confidence/repetition.
insert into engine_config (key, value) values ('power_ref_ranges', '{"entry_speed_mph": [14.0, 20.0], "rev_rate_rpm": [250, 500], "entry_angle_deg": [2.0, 6.0], "weight_lb": [14.0, 16.0]}'::jsonb)
  on conflict (key) do update set value = excluded.value, updated_at = now();
insert into engine_config (key, value) values ('prioritizer_weights', '{"timing": 1.2, "drift": 1.0, "finish": 0.8}'::jsonb)
  on conflict (key) do update set value = excluded.value, updated_at = now();
insert into engine_config (key, value) values ('baseline_min_n', '10'::jsonb)
  on conflict (key) do update set value = excluded.value, updated_at = now();
insert into engine_config (key, value) values ('confidence_min', '0.5'::jsonb)
  on conflict (key) do update set value = excluded.value, updated_at = now();
insert into engine_config (key, value) values ('repetition_rule', '3'::jsonb)
  on conflict (key) do update set value = excluded.value, updated_at = now();
insert into engine_config (key, value) values ('focus_hold_shots', '10'::jsonb)
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- Wire the owner-editable power ranges into the active L-dev-0 formula params (DEC-048).
update score_formula_version
  set params = jsonb_set(params, '{power_ref_ranges}', '{"entry_speed_mph": [14.0, 20.0], "rev_rate_rpm": [250, 500], "entry_angle_deg": [2.0, 6.0], "weight_lb": [14.0, 16.0]}'::jsonb, true)
  where id = 'L-dev-0';

-- style_template (+ metrics)
insert into style_template (id, name, status) values ('one_handed_thumb', 'One-handed, with thumb', 'draft')
  on conflict (id) do nothing;
insert into style_template_metric (template_id, metric, matters, note) values ('one_handed_thumb', 'backswing_height_rel', true, 'waist-to-shoulder typical')
  on conflict (template_id, metric) do nothing;
insert into style_template (id, name, status) values ('one_handed_no_thumb', 'One-handed, no thumb', 'draft')
  on conflict (id) do nothing;
insert into style_template_metric (template_id, metric, matters, note) values ('one_handed_no_thumb', 'backswing_height_rel', true, 'often shoulder-to-above-head')
  on conflict (template_id, metric) do nothing;
insert into style_template (id, name, status) values ('two_handed', 'Two-handed', 'draft')
  on conflict (id) do nothing;
insert into style_template_metric (template_id, metric, matters, note) values ('two_handed', 'backswing_height_rel', true, 'often above head')
  on conflict (template_id, metric) do nothing;
insert into style_template_metric (template_id, metric, matters, note) values ('two_handed', 'ball_start_direction', true, 'both hands through the swing')
  on conflict (template_id, metric) do nothing;

-- drill
insert into drill (id, name, description, sources, status) values ('DRILL-ball-start', 'Ball-start timing', 'Start the ball later/more extended so it moves with the key step.', '["NBA", "BTM"]'::jsonb, 'draft')
  on conflict (id) do nothing;
insert into drill (id, name, description, sources, status) values ('DRILL-get-going', 'Get it going', 'Trigger the ball with the first step; avoid holding it in the setup.', '["BTM"]'::jsonb, 'draft')
  on conflict (id) do nothing;
insert into drill (id, name, description, sources, status) values ('DRILL-one-step', 'One-step / short approach', 'Groove a repeatable ball start from a one-step drill.', '["NBA"]'::jsonb, 'draft')
  on conflict (id) do nothing;
insert into drill (id, name, description, sources, status) values ('DRILL-walk-spot', 'Walk to a spot', 'Align feet to the target line; walk to a fixed finish spot to control drift.', '["USBC"]'::jsonb, 'draft')
  on conflict (id) do nothing;
insert into drill (id, name, description, sources, status) values ('DRILL-post', 'Post the shot', 'Hold the finish position until the ball hits the pins; balance-hold.', '["USBC"]'::jsonb, 'draft')
  on conflict (id) do nothing;
insert into drill (id, name, description, sources, status) values ('DRILL-slow-first', 'Slow first steps', 'Start slow, accelerate into the slide (rhythm).', '["BTM"]'::jsonb, 'draft')
  on conflict (id) do nothing;
insert into drill (id, name, description, sources, status) values ('DRILL-free-swing', 'Free swing', 'Let the swing fall freely at a consistent ball-start height.', '["NBA"]'::jsonb, 'draft')
  on conflict (id) do nothing;
insert into drill (id, name, description, sources, status) values ('DRILL-place-it', 'Place it here', 'Set the ball-start direction so the swing lines up behind the target.', '["NBA"]'::jsonb, 'draft')
  on conflict (id) do nothing;

-- form_rule (status draft)
insert into form_rule (id, version, trigger, candidate_causes, cue, drill_ref, verify, status) values (
  'RULE-timing-inconsistency', 1, '{"metric": "phase_splits", "comparison": "consistency", "repetition": "SD>baseline band"}'::jsonb, '["variable_ball_start", "variable_step1"]'::jsonb, 'Groove a repeatable ball start', 'DRILL-one-step', '{"metric": "split_sd", "over_shots": 10}'::jsonb, 'draft')
  on conflict (id, version) do nothing;
insert into form_rule (id, version, trigger, candidate_causes, cue, drill_ref, verify, status) values (
  'RULE-short-finish', 1, '{"metric": "finish_hold", "comparison": "level", "rule": "< baseline"}'::jsonb, '["early_timing", "over_speed", "fast_approach"]'::jsonb, 'Post the shot until it hits', 'DRILL-post', '{"metric": "finish_hold", "over_shots": 10}'::jsonb, 'draft')
  on conflict (id, version) do nothing;
insert into form_rule (id, version, trigger, candidate_causes, cue, drill_ref, verify, status) values (
  'RULE-rhythm-inverted', 1, '{"metric": "cadence_ratio", "rule": "last 3 not quicker than first 2"}'::jsonb, '["rushing_early_steps"]'::jsonb, 'Slow the first steps, speed up to the line', 'DRILL-slow-first', '{"metric": "cadence_ratio", "over_shots": 10}'::jsonb, 'draft')
  on conflict (id, version) do nothing;
insert into form_rule (id, version, trigger, candidate_causes, cue, drill_ref, verify, status) values (
  'RULE-drift-excessive', 1, '{"metric": "drift_boards", "rule": "|finish-start|>2 or > coach tol"}'::jsonb, '["ball_start_across_body", "walking_to_target"]'::jsonb, 'Walk to your spot', 'DRILL-walk-spot', '{"metric": "drift_boards", "over_shots": 10}'::jsonb, 'draft')
  on conflict (id, version) do nothing;
insert into form_rule (id, version, trigger, candidate_causes, cue, drill_ref, verify, status) values (
  'RULE-early-timing', 1, '{"metric": "timing_at_slide", "rule": "ball ahead of slide vs baseline, repeated", "min_fps": 120}'::jsonb, '["early_ball_start", "short_pushaway", "slow_feet"]'::jsonb, 'Start the ball a touch later', 'DRILL-ball-start', '{"metric": "timing_at_slide", "over_shots": 10}'::jsonb, 'draft')
  on conflict (id, version) do nothing;
insert into form_rule (id, version, trigger, candidate_causes, cue, drill_ref, verify, status) values (
  'RULE-late-timing', 1, '{"metric": "timing_at_slide", "rule": "ball behind at slide", "min_fps": 120}'::jsonb, '["late_ball_start", "short_key_step", "tension"]'::jsonb, 'Get it going with the key step', 'DRILL-get-going', '{"metric": "timing_at_slide", "over_shots": 10}'::jsonb, 'draft')
  on conflict (id, version) do nothing;
insert into form_rule (id, version, trigger, candidate_causes, cue, drill_ref, verify, status) values (
  'RULE-backswing-variance', 1, '{"metric": "backswing_height_rel", "comparison": "consistency", "rule": "apex SD>band"}'::jsonb, '["muscled_swing", "variable_ball_start_height"]'::jsonb, 'Same ball-start height, free swing', 'DRILL-free-swing', '{"metric": "apex_sd", "over_shots": 10}'::jsonb, 'draft')
  on conflict (id, version) do nothing;
insert into form_rule (id, version, trigger, candidate_causes, cue, drill_ref, verify, status) values (
  'RULE-swing-line-off', 1, '{"metric": "swing_line_offset", "rule": "bottom-of-arc offset vs shoulder line > band (rear)"}'::jsonb, '["pushaway_direction"]'::jsonb, 'Place the ball start behind the target', 'DRILL-place-it', '{"metric": "swing_line_offset", "over_shots": 10}'::jsonb, 'draft')
  on conflict (id, version) do nothing;

-- benchmark_reference (elite refs owner-only: shown_to_user=false). Guarded by (metric, source).
insert into benchmark_reference (metric, range_low, range_high, units, source, source_quality, shown_to_user, status)
  select 'ball_start_step', null, null, null, 'NBA', 'medium', true, 'draft'
  where not exists (select 1 from benchmark_reference where metric = 'ball_start_step' and source = 'NBA');
insert into benchmark_reference (metric, range_low, range_high, units, source, source_quality, shown_to_user, status)
  select 'backswing_peak', null, null, null, 'NBA', 'medium', true, 'draft'
  where not exists (select 1 from benchmark_reference where metric = 'backswing_peak' and source = 'NBA');
insert into benchmark_reference (metric, range_low, range_high, units, source, source_quality, shown_to_user, status)
  select 'drift_boards', -2, 2, 'board', 'USBC', 'high', true, 'draft'
  where not exists (select 1 from benchmark_reference where metric = 'drift_boards' and source = 'USBC');
insert into benchmark_reference (metric, range_low, range_high, units, source, source_quality, shown_to_user, status)
  select 'finish_hold', null, null, null, 'USBC', 'high', true, 'draft'
  where not exists (select 1 from benchmark_reference where metric = 'finish_hold' and source = 'USBC');
insert into benchmark_reference (metric, range_low, range_high, units, source, source_quality, shown_to_user, status)
  select 'step_rhythm', null, null, null, 'BTM', 'medium', true, 'draft'
  where not exists (select 1 from benchmark_reference where metric = 'step_rhythm' and source = 'BTM');
insert into benchmark_reference (metric, range_low, range_high, units, source, source_quality, shown_to_user, status)
  select 'entry_angle_deg', 3, 4, 'deg', 'USBC', 'medium', true, 'draft'
  where not exists (select 1 from benchmark_reference where metric = 'entry_angle_deg' and source = 'USBC');
insert into benchmark_reference (metric, range_low, range_high, units, source, source_quality, shown_to_user, status)
  select 'slide_to_release_ms', 545, 735, 'ms', 'Seiferheld 2023', 'high', false, 'draft'
  where not exists (select 1 from benchmark_reference where metric = 'slide_to_release_ms' and source = 'Seiferheld 2023');
insert into benchmark_reference (metric, range_low, range_high, units, source, source_quality, shown_to_user, status)
  select 'foul_line_distance_m', null, null, null, 'Chu 2002', 'high', false, 'draft'
  where not exists (select 1 from benchmark_reference where metric = 'foul_line_distance_m' and source = 'Chu 2002');

-- achievement_definition: full active catalog + coming_later (params owner-only).
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-050', 'onboarding', 'Welcome to LaneSight', 'Complete your bowler profile.', 'one_time', '{"condition": "profile_complete"}'::jsonb, 40, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-051', 'onboarding', 'First Analysis', 'Analyze your first shot.', 'one_time', '{"condition": "first_valid_shot"}'::jsonb, 40, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-052', 'onboarding', 'Getting Started', 'Finish your first analyzed session.', 'one_time', '{"condition": "first_completed_session"}'::jsonb, 40, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-053', 'volume', 'Data Driven', 'Analyze 100 shots.', 'cumulative', '{"target": 100}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-054', 'volume', 'Shot Scientist', 'Analyze 1,000 shots.', 'cumulative', '{"target": 1000}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-055', 'arsenal', 'Arsenal Builder', 'Add 5 balls to your arsenal.', 'cumulative', '{"target": 5}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-049', 'volume', 'Dedicated Bowler', 'Complete 25 practice sessions.', 'cumulative', '{"target": 25, "unit": "sessions"}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-048', 'streak', 'Practice Warrior', 'Practice in 4 consecutive weeks.', 'weekly_streak', '{"target_weeks": 4}'::jsonb, 60, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-010', 'accuracy', 'Dialed In', '10 shots within 1 board of your target at the arrows.', 'count_qualifying', '{"target": 10, "qualify": "intent shot within +/-1 arrow board"}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-011', 'accuracy', 'Precision Master', 'Within 1 arrow board on 90% of 30+ shots.', 'window_ratio', '{"target_ratio": 0.9, "min_sample": 30, "qualify": "within +/-1 arrow board"}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-013', 'accuracy', 'Pocket Hunter', 'Entry board in the pocket on 80% of 30+ shots.', 'window_ratio', '{"target_ratio": 0.8, "min_sample": 30, "qualify": "entry board in pocket"}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-014', 'accuracy', 'Breakpoint Boss', 'Within 2 boards of your breakpoint on 90% of 30+ shots.', 'window_ratio', '{"target_ratio": 0.9, "min_sample": 30, "qualify": "within +/-2 breakpoint boards"}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-023', 'accuracy', 'Line Locked', '10 shots in a row within 1 arrow board.', 'streak', '{"target": 10, "qualify": "within +/-1 arrow board"}'::jsonb, 60, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-016', 'power', 'Speed Demon', 'Record a shot over 20 mph.', 'best_measured', '{"threshold": 20, "direction": "above", "metric": "ball_speed"}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-017', 'power', 'Rev Machine', 'Record a shot over 450 rpm (band fully above 450).', 'best_measured', '{"threshold": 450, "direction": "above", "metric": "rev_rate"}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-018', 'power', 'Powerhouse', '10 shots at 18+ mph and 400+ rpm.', 'count_qualifying', '{"target": 10, "qualify": ">=18 mph AND >=400 rpm"}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-020', 'accuracy', 'Efficiency Expert', 'Entry angle 4-6 deg on 80% of 30+ shots.', 'window_ratio', '{"target_ratio": 0.8, "min_sample": 30, "qualify": "entry angle 4-6 deg"}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-021', 'consistency', 'Mr. Consistent', 'Ball-speed SD under 0.5 mph across 30+ shots.', 'window_spread', '{"max_sd": 0.5, "min_sample": 30, "metric": "ball_speed"}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-022', 'consistency', 'Repeatable Release', 'Rev CV under 5% across 30+ shots.', 'window_spread', '{"max_cv": 0.05, "min_sample": 30, "metric": "rev_rate", "spread_kind": "cv", "requires": "rev band <= +/-20 (120 fps)"}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-026', 'progress', 'Rising Star', 'Improve your LaneSight Score by 25.', 'baseline_delta', '{"delta": 25}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-027', 'progress', 'Level Up', 'Improve your LaneSight Score by 50.', 'baseline_delta', '{"delta": 50}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-028', 'progress', 'Century Climber', 'Improve your LaneSight Score by 100.', 'baseline_delta', '{"delta": 100}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-056', 'tier', 'Silver Status', 'Reach Silver tier.', 'first_tier', '{"tier": "silver"}'::jsonb, 80, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-057', 'tier', 'Gold Status', 'Reach Gold tier.', 'first_tier', '{"tier": "gold"}'::jsonb, 80, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-058', 'tier', 'Platinum Status', 'Reach Platinum tier.', 'first_tier', '{"tier": "platinum"}'::jsonb, 80, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-059', 'tier', 'Onyx Club', 'Reach Onyx tier.', 'first_tier', '{"tier": "onyx"}'::jsonb, 80, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'FORM-001', 'form', 'Post It', 'Hold your finish 1.5s on 10 shots.', 'count_qualifying', '{"target": 10, "qualify": "finish hold >= 1.5 s", "metric": "finish_hold"}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'FORM-002', 'form', 'Metronome', 'Swing-time SD under 0.05s over 10 shots.', 'window_spread', '{"max_sd": 0.05, "min_sample": 10, "metric": "swing_time"}'::jsonb, 50, 'active', null)
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-001', 'scoring', 'Century Club', 'Bowl a game of 100 or more.', 'best_measured', '{"threshold": 100}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-002', 'scoring', 'Breaking Through', 'Bowl a game of 150 or more.', 'best_measured', '{"threshold": 150}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-003', 'scoring', '200 Club', 'Bowl a game of 200 or more.', 'best_measured', '{"threshold": 200}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-004', 'scoring', 'High Roller', 'Bowl a game of 250 or more.', 'best_measured', '{"threshold": 250}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-005', 'scoring', 'Perfect Game', 'Bowl a 300.', 'best_measured', '{"threshold": 300}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-006', 'scoring', '500 Series Club', 'Bowl a 3-game series of 500+.', 'best_measured', '{"threshold": 500}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-007', 'scoring', '600 Series Club', 'Bowl a 3-game series of 600+.', 'best_measured', '{"threshold": 600}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-008', 'scoring', '700 Series Club', 'Bowl a 3-game series of 700+.', 'best_measured', '{"threshold": 700}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-009', 'scoring', '800 Series Club', 'Bowl a 3-game series of 800+.', 'best_measured', '{"threshold": 800}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-012', 'accuracy', 'Dead Center', 'Arrow error under 0.25 board.', 'best_measured', '{"threshold": 0.25, "direction": "below"}'::jsonb, 50, 'coming_later', 'Research — threshold not yet validated.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-015', 'accuracy', 'Sniper', '10 single-pin spares converted in a row.', 'streak', '{"target": 10}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-019', 'power', 'Controlled Power', '10 strikes with repeatable speed/rev.', 'count_qualifying', '{"target": 10}'::jsonb, 50, 'coming_later', 'Research — threshold not yet validated.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-024', 'consistency', 'Steady Hand', '3 games within 10 pins of each other.', 'window_spread', '{"max_sd": 10, "min_sample": 3}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-025', 'consistency', 'The Machine', '50 shots at a validated variance target.', 'window_spread', '{"min_sample": 50}'::jsonb, 50, 'coming_later', 'Research — threshold not yet validated.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-029', 'progress', 'Average Builder', 'Rolling game average up 10 pins.', 'baseline_delta', '{"delta": 10}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-030', 'progress', 'Spare Specialist', 'Spare conversion up 10 points.', 'baseline_delta', '{"delta": 10}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-031', 'progress', 'Strike Evolution', 'Strike rate up 10 points.', 'baseline_delta', '{"delta": 10}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-032', 'progress', 'Personal Best', 'A new verified best game.', 'one_time', '{"condition": "new_best_game"}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-033', 'progress', 'New Heights', 'A new session-score high.', 'one_time', '{"condition": "new_session_high"}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-034', 'competition', 'League Regular', '10 verified league nights.', 'cumulative', '{"target": 10}'::jsonb, 50, 'coming_later', 'Competition tracking — post-MVP (DEC-035).')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-035', 'competition', 'League Veteran', '100 verified league nights.', 'cumulative', '{"target": 100}'::jsonb, 50, 'coming_later', 'Competition tracking — post-MVP (DEC-035).')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-036', 'competition', 'League Champion', 'Win a league title.', 'one_time', '{"condition": "league_title"}'::jsonb, 50, 'coming_later', 'Competition tracking — post-MVP (DEC-035).')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-037', 'competition', 'Tournament Debut', 'Your first tournament result.', 'one_time', '{"condition": "first_tournament"}'::jsonb, 50, 'coming_later', 'Competition tracking — post-MVP (DEC-035).')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-038', 'competition', 'Tournament Finalist', 'Reach a tournament final.', 'one_time', '{"condition": "tournament_final"}'::jsonb, 50, 'coming_later', 'Competition tracking — post-MVP (DEC-035).')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-039', 'competition', 'Tournament Champion', 'Win a tournament.', 'one_time', '{"condition": "tournament_win"}'::jsonb, 50, 'coming_later', 'Competition tracking — post-MVP (DEC-035).')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-040', 'competition', 'Podium Finisher', 'Top-three tournament finish.', 'one_time', '{"condition": "tournament_top3"}'::jsonb, 50, 'coming_later', 'Competition tracking — post-MVP (DEC-035).')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-041', 'competition', 'Giant Slayer', 'Beat a higher-ranked opponent.', 'one_time', '{"condition": "giant_slayer"}'::jsonb, 50, 'coming_later', 'Competition tracking — post-MVP (DEC-035).')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-042', 'streak', 'Turkey', '3 strikes in a row.', 'streak', '{"target": 3}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-043', 'streak', 'Four Bagger', '4 strikes in a row.', 'streak', '{"target": 4}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-044', 'streak', 'Six Pack', '6 strikes in a row.', 'streak', '{"target": 6}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-045', 'streak', 'Front Nine', 'Strikes in frames 1-9.', 'one_time', '{"condition": "front_nine"}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-046', 'streak', 'Clean Game', 'No open frames in a game.', 'one_time', '{"condition": "clean_game"}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-047', 'streak', 'Spare Streak', '10 spares converted in a row.', 'streak', '{"target": 10}'::jsonb, 50, 'coming_later', 'Needs game scores (pinfall capture) — coming later.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;
insert into achievement_definition (id, category, name, description, rule_type, params, popup_priority, status, inactive_reason) values (
  'ACH-060', 'platform', 'Hall of Fame', '100 distinct achievement unlocks.', 'cumulative', '{"target": 100}'::jsonb, 50, 'coming_later', 'Unlocks once enough achievements exist.')
  on conflict (id) do update set category=excluded.category, name=excluded.name, description=excluded.description, rule_type=excluded.rule_type, params=excluded.params, popup_priority=excluded.popup_priority, status=excluded.status, inactive_reason=excluded.inactive_reason;

