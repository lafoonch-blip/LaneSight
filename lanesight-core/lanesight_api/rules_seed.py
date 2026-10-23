"""Canonical dev-build rule/achievement seed (single source of truth).

This mirrors `03_ENGINEERING/dev_build_v0/RULES_AND_POWER_REVIEW.md` and SCORE_TIERS §4. It is the one
place the catalog lives in code: migration 011 and `rules/*.yaml` are generated from it, the MemoryStore
serves it offline, and the achievement/score wiring reads it. Rule *params* are owner-only (never shipped
to clients); the service holds them, the client only ever sees name/description/category/status.

Ball weight is 15 lb (confirmed 2026-10-22). Power P' ranges are anchored to Shayne's validation data,
widened to published context (not a grade — a 0-1 normalizer). Weights are never rebalanced.
"""
from __future__ import annotations

# --------------------------------------------------------------------- engine_config (owner-editable)
ENGINE_CONFIG = {
    'power_ref_ranges': {
        'entry_speed_mph': [14.0, 20.0],
        'rev_rate_rpm': [250, 500],
        'entry_angle_deg': [2.0, 6.0],
        'weight_lb': [14.0, 16.0],      # ball = 15 lb -> normalizes to 0.5 (confirmed 2026-10-22)
    },
    'prioritizer_weights': {'timing': 1.2, 'drift': 1.0, 'finish': 0.8},
    'baseline_min_n': 10,
    'confidence_min': 0.5,
    'repetition_rule': 3,
    'focus_hold_shots': 10,
}

# --------------------------------------------------------------------- style templates (L1)
STYLE_TEMPLATES = [
    {'id': 'one_handed_thumb', 'name': 'One-handed, with thumb', 'status': 'draft',
     'metrics': [{'metric': 'backswing_height_rel', 'matters': True, 'note': 'waist-to-shoulder typical'}]},
    {'id': 'one_handed_no_thumb', 'name': 'One-handed, no thumb', 'status': 'draft',
     'metrics': [{'metric': 'backswing_height_rel', 'matters': True, 'note': 'often shoulder-to-above-head'}]},
    {'id': 'two_handed', 'name': 'Two-handed', 'status': 'draft',
     'metrics': [{'metric': 'backswing_height_rel', 'matters': True, 'note': 'often above head'},
                 {'metric': 'ball_start_direction', 'matters': True, 'note': 'both hands through the swing'}]},
]

# --------------------------------------------------------------------- drills
DRILLS = [
    {'id': 'DRILL-ball-start', 'name': 'Ball-start timing', 'status': 'draft',
     'description': 'Start the ball later/more extended so it moves with the key step.', 'sources': ['NBA', 'BTM']},
    {'id': 'DRILL-get-going', 'name': 'Get it going', 'status': 'draft',
     'description': 'Trigger the ball with the first step; avoid holding it in the setup.', 'sources': ['BTM']},
    {'id': 'DRILL-one-step', 'name': 'One-step / short approach', 'status': 'draft',
     'description': 'Groove a repeatable ball start from a one-step drill.', 'sources': ['NBA']},
    {'id': 'DRILL-walk-spot', 'name': 'Walk to a spot', 'status': 'draft',
     'description': 'Align feet to the target line; walk to a fixed finish spot to control drift.', 'sources': ['USBC']},
    {'id': 'DRILL-post', 'name': 'Post the shot', 'status': 'draft',
     'description': 'Hold the finish position until the ball hits the pins; balance-hold.', 'sources': ['USBC']},
    {'id': 'DRILL-slow-first', 'name': 'Slow first steps', 'status': 'draft',
     'description': 'Start slow, accelerate into the slide (rhythm).', 'sources': ['BTM']},
    {'id': 'DRILL-free-swing', 'name': 'Free swing', 'status': 'draft',
     'description': 'Let the swing fall freely at a consistent ball-start height.', 'sources': ['NBA']},
    {'id': 'DRILL-place-it', 'name': 'Place it here', 'status': 'draft',
     'description': 'Set the ball-start direction so the swing lines up behind the target.', 'sources': ['NBA']},
]

# --------------------------------------------------------------------- form rules (all draft)
FORM_RULES = [
    {'id': 'RULE-timing-inconsistency', 'status': 'draft', 'drill_ref': 'DRILL-one-step',
     'cue': 'Groove a repeatable ball start',
     'trigger': {'metric': 'phase_splits', 'comparison': 'consistency', 'repetition': 'SD>baseline band'},
     'candidate_causes': ['variable_ball_start', 'variable_step1'], 'verify': {'metric': 'split_sd', 'over_shots': 10}},
    {'id': 'RULE-short-finish', 'status': 'draft', 'drill_ref': 'DRILL-post', 'cue': 'Post the shot until it hits',
     'trigger': {'metric': 'finish_hold', 'comparison': 'level', 'rule': '< baseline'},
     'candidate_causes': ['early_timing', 'over_speed', 'fast_approach'], 'verify': {'metric': 'finish_hold', 'over_shots': 10}},
    {'id': 'RULE-rhythm-inverted', 'status': 'draft', 'drill_ref': 'DRILL-slow-first',
     'cue': 'Slow the first steps, speed up to the line',
     'trigger': {'metric': 'cadence_ratio', 'rule': 'last 3 not quicker than first 2'},
     'candidate_causes': ['rushing_early_steps'], 'verify': {'metric': 'cadence_ratio', 'over_shots': 10}},
    {'id': 'RULE-drift-excessive', 'status': 'draft', 'drill_ref': 'DRILL-walk-spot', 'cue': 'Walk to your spot',
     'trigger': {'metric': 'drift_boards', 'rule': '|finish-start|>2 or > coach tol'},
     'candidate_causes': ['ball_start_across_body', 'walking_to_target'], 'verify': {'metric': 'drift_boards', 'over_shots': 10}},
    {'id': 'RULE-early-timing', 'status': 'draft', 'drill_ref': 'DRILL-ball-start', 'cue': 'Start the ball a touch later',
     'trigger': {'metric': 'timing_at_slide', 'rule': 'ball ahead of slide vs baseline, repeated', 'min_fps': 120},
     'candidate_causes': ['early_ball_start', 'short_pushaway', 'slow_feet'], 'verify': {'metric': 'timing_at_slide', 'over_shots': 10}},
    {'id': 'RULE-late-timing', 'status': 'draft', 'drill_ref': 'DRILL-get-going', 'cue': 'Get it going with the key step',
     'trigger': {'metric': 'timing_at_slide', 'rule': 'ball behind at slide', 'min_fps': 120},
     'candidate_causes': ['late_ball_start', 'short_key_step', 'tension'], 'verify': {'metric': 'timing_at_slide', 'over_shots': 10}},
    {'id': 'RULE-backswing-variance', 'status': 'draft', 'drill_ref': 'DRILL-free-swing', 'cue': 'Same ball-start height, free swing',
     'trigger': {'metric': 'backswing_height_rel', 'comparison': 'consistency', 'rule': 'apex SD>band'},
     'candidate_causes': ['muscled_swing', 'variable_ball_start_height'], 'verify': {'metric': 'apex_sd', 'over_shots': 10}},
    {'id': 'RULE-swing-line-off', 'status': 'draft', 'drill_ref': 'DRILL-place-it', 'cue': 'Place the ball start behind the target',
     'trigger': {'metric': 'swing_line_offset', 'rule': 'bottom-of-arc offset vs shoulder line > band (rear)'},
     'candidate_causes': ['pushaway_direction'], 'verify': {'metric': 'swing_line_offset', 'over_shots': 10}},
]

# --------------------------------------------------------------------- L0 benchmark references
# shown_to_user: elite research refs stay owner-only (DEC-046).
BENCHMARK_REFERENCES = [
    {'metric': 'ball_start_step', 'reference': 'step 1 (4-step) / step 2 (5-step), in time with the slide-foot step',
     'source': 'NBA', 'source_quality': 'medium', 'shown_to_user': True, 'status': 'draft'},
    {'metric': 'backswing_peak', 'reference': 'peaks during pivot-step compression',
     'source': 'NBA', 'source_quality': 'medium', 'shown_to_user': True, 'status': 'draft'},
    {'metric': 'drift_boards', 'range_low': -2, 'range_high': 2, 'units': 'board',
     'reference': '<=1-2 boards, repeatable direction', 'source': 'USBC', 'source_quality': 'high',
     'shown_to_user': True, 'status': 'draft'},
    {'metric': 'finish_hold', 'reference': 'hold at the line until the ball reaches the pins',
     'source': 'USBC', 'source_quality': 'high', 'shown_to_user': True, 'status': 'draft'},
    {'metric': 'step_rhythm', 'reference': 'early steps slower, last three quicker',
     'source': 'BTM', 'source_quality': 'medium', 'shown_to_user': True, 'status': 'draft'},
    {'metric': 'entry_angle_deg', 'range_low': 3, 'range_high': 4, 'units': 'deg',
     'reference': '~3-4 deg typical for 180-200 avg (shot-reading context)', 'source': 'USBC',
     'source_quality': 'medium', 'shown_to_user': True, 'status': 'draft'},
    {'metric': 'slide_to_release_ms', 'range_low': 545, 'range_high': 735, 'units': 'ms',
     'reference': 'elite 640 +/- 95 ms', 'source': 'Seiferheld 2023', 'source_quality': 'high',
     'shown_to_user': False, 'status': 'draft'},
    {'metric': 'foul_line_distance_m', 'reference': 'elite men 0.35 m, women 0.16 m',
     'source': 'Chu 2002', 'source_quality': 'high', 'shown_to_user': False, 'status': 'draft'},
]

# --------------------------------------------------------------------- achievement catalog
# params are owner-only; the 'qualify' strings document the predicate the context builder implements.
ACTIVE_ACHIEVEMENTS = [
    {'id': 'ACH-050', 'category': 'onboarding', 'name': 'Welcome to LaneSight',
     'description': 'Complete your bowler profile.', 'rule_type': 'one_time',
     'params': {'condition': 'profile_complete'}, 'popup_priority': 40},
    {'id': 'ACH-051', 'category': 'onboarding', 'name': 'First Analysis',
     'description': 'Analyze your first shot.', 'rule_type': 'one_time',
     'params': {'condition': 'first_valid_shot'}, 'popup_priority': 40},
    {'id': 'ACH-052', 'category': 'onboarding', 'name': 'Getting Started',
     'description': 'Finish your first analyzed session.', 'rule_type': 'one_time',
     'params': {'condition': 'first_completed_session'}, 'popup_priority': 40},
    {'id': 'ACH-053', 'category': 'volume', 'name': 'Data Driven',
     'description': 'Analyze 100 shots.', 'rule_type': 'cumulative', 'params': {'target': 100}},
    {'id': 'ACH-054', 'category': 'volume', 'name': 'Shot Scientist',
     'description': 'Analyze 1,000 shots.', 'rule_type': 'cumulative', 'params': {'target': 1000}},
    {'id': 'ACH-055', 'category': 'arsenal', 'name': 'Arsenal Builder',
     'description': 'Add 5 balls to your arsenal.', 'rule_type': 'cumulative', 'params': {'target': 5}},
    {'id': 'ACH-049', 'category': 'volume', 'name': 'Dedicated Bowler',
     'description': 'Complete 25 practice sessions.', 'rule_type': 'cumulative',
     'params': {'target': 25, 'unit': 'sessions'}},
    {'id': 'ACH-048', 'category': 'streak', 'name': 'Practice Warrior',
     'description': 'Practice in 4 consecutive weeks.', 'rule_type': 'weekly_streak',
     'params': {'target_weeks': 4}, 'popup_priority': 60},
    {'id': 'ACH-010', 'category': 'accuracy', 'name': 'Dialed In',
     'description': '10 shots within 1 board of your target at the arrows.', 'rule_type': 'count_qualifying',
     'params': {'target': 10, 'qualify': 'intent shot within +/-1 arrow board'}},
    {'id': 'ACH-011', 'category': 'accuracy', 'name': 'Precision Master',
     'description': 'Within 1 arrow board on 90% of 30+ shots.', 'rule_type': 'window_ratio',
     'params': {'target_ratio': 0.90, 'min_sample': 30, 'qualify': 'within +/-1 arrow board'}},
    {'id': 'ACH-013', 'category': 'accuracy', 'name': 'Pocket Hunter',
     'description': 'Entry board in the pocket on 80% of 30+ shots.', 'rule_type': 'window_ratio',
     'params': {'target_ratio': 0.80, 'min_sample': 30, 'qualify': 'entry board in pocket'}},
    {'id': 'ACH-014', 'category': 'accuracy', 'name': 'Breakpoint Boss',
     'description': 'Within 2 boards of your breakpoint on 90% of 30+ shots.', 'rule_type': 'window_ratio',
     'params': {'target_ratio': 0.90, 'min_sample': 30, 'qualify': 'within +/-2 breakpoint boards'}},
    {'id': 'ACH-023', 'category': 'accuracy', 'name': 'Line Locked',
     'description': '10 shots in a row within 1 arrow board.', 'rule_type': 'streak',
     'params': {'target': 10, 'qualify': 'within +/-1 arrow board'}, 'popup_priority': 60},
    {'id': 'ACH-016', 'category': 'power', 'name': 'Speed Demon',
     'description': 'Record a shot over 20 mph.', 'rule_type': 'best_measured',
     'params': {'threshold': 20, 'direction': 'above', 'metric': 'ball_speed'}},
    {'id': 'ACH-017', 'category': 'power', 'name': 'Rev Machine',
     'description': 'Record a shot over 450 rpm (band fully above 450).', 'rule_type': 'best_measured',
     'params': {'threshold': 450, 'direction': 'above', 'metric': 'rev_rate'}},
    {'id': 'ACH-018', 'category': 'power', 'name': 'Powerhouse',
     'description': '10 shots at 18+ mph and 400+ rpm.', 'rule_type': 'count_qualifying',
     'params': {'target': 10, 'qualify': '>=18 mph AND >=400 rpm'}},
    {'id': 'ACH-020', 'category': 'accuracy', 'name': 'Efficiency Expert',
     'description': 'Entry angle 4-6 deg on 80% of 30+ shots.', 'rule_type': 'window_ratio',
     'params': {'target_ratio': 0.80, 'min_sample': 30, 'qualify': 'entry angle 4-6 deg'}},
    {'id': 'ACH-021', 'category': 'consistency', 'name': 'Mr. Consistent',
     'description': 'Ball-speed SD under 0.5 mph across 30+ shots.', 'rule_type': 'window_spread',
     'params': {'max_sd': 0.5, 'min_sample': 30, 'metric': 'ball_speed'}},
    {'id': 'ACH-022', 'category': 'consistency', 'name': 'Repeatable Release',
     'description': 'Rev CV under 5% across 30+ shots.', 'rule_type': 'window_spread',
     'params': {'max_cv': 0.05, 'min_sample': 30, 'metric': 'rev_rate', 'spread_kind': 'cv',
                'requires': 'rev band <= +/-20 (120 fps)'}},
    {'id': 'ACH-026', 'category': 'progress', 'name': 'Rising Star',
     'description': 'Improve your LaneSight Score by 25.', 'rule_type': 'baseline_delta', 'params': {'delta': 25}},
    {'id': 'ACH-027', 'category': 'progress', 'name': 'Level Up',
     'description': 'Improve your LaneSight Score by 50.', 'rule_type': 'baseline_delta', 'params': {'delta': 50}},
    {'id': 'ACH-028', 'category': 'progress', 'name': 'Century Climber',
     'description': 'Improve your LaneSight Score by 100.', 'rule_type': 'baseline_delta', 'params': {'delta': 100}},
    {'id': 'ACH-056', 'category': 'tier', 'name': 'Silver Status',
     'description': 'Reach Silver tier.', 'rule_type': 'first_tier', 'params': {'tier': 'silver'}, 'popup_priority': 80},
    {'id': 'ACH-057', 'category': 'tier', 'name': 'Gold Status',
     'description': 'Reach Gold tier.', 'rule_type': 'first_tier', 'params': {'tier': 'gold'}, 'popup_priority': 80},
    {'id': 'ACH-058', 'category': 'tier', 'name': 'Platinum Status',
     'description': 'Reach Platinum tier.', 'rule_type': 'first_tier', 'params': {'tier': 'platinum'}, 'popup_priority': 80},
    {'id': 'ACH-059', 'category': 'tier', 'name': 'Onyx Club',
     'description': 'Reach Onyx tier.', 'rule_type': 'first_tier', 'params': {'tier': 'onyx'}, 'popup_priority': 80},
    {'id': 'FORM-001', 'category': 'form', 'name': 'Post It',
     'description': 'Hold your finish 1.5s on 10 shots.', 'rule_type': 'count_qualifying',
     'params': {'target': 10, 'qualify': 'finish hold >= 1.5 s', 'metric': 'finish_hold'}},
    {'id': 'FORM-002', 'category': 'form', 'name': 'Metronome',
     'description': 'Swing-time SD under 0.05s over 10 shots.', 'rule_type': 'window_spread',
     'params': {'max_sd': 0.05, 'min_sample': 10, 'metric': 'swing_time'}},
]

_PINFALL = 'Needs game scores (pinfall capture) — coming later.'
_COMP = 'Competition tracking — post-MVP (DEC-035).'
_RESEARCH = 'Research — threshold not yet validated.'
_FUTURE = 'Unlocks once enough achievements exist.'

COMING_LATER = [
    ('ACH-001', 'scoring', 'Century Club', 'Bowl a game of 100 or more.', 'best_measured', {'threshold': 100}, _PINFALL),
    ('ACH-002', 'scoring', 'Breaking Through', 'Bowl a game of 150 or more.', 'best_measured', {'threshold': 150}, _PINFALL),
    ('ACH-003', 'scoring', '200 Club', 'Bowl a game of 200 or more.', 'best_measured', {'threshold': 200}, _PINFALL),
    ('ACH-004', 'scoring', 'High Roller', 'Bowl a game of 250 or more.', 'best_measured', {'threshold': 250}, _PINFALL),
    ('ACH-005', 'scoring', 'Perfect Game', 'Bowl a 300.', 'best_measured', {'threshold': 300}, _PINFALL),
    ('ACH-006', 'scoring', '500 Series Club', 'Bowl a 3-game series of 500+.', 'best_measured', {'threshold': 500}, _PINFALL),
    ('ACH-007', 'scoring', '600 Series Club', 'Bowl a 3-game series of 600+.', 'best_measured', {'threshold': 600}, _PINFALL),
    ('ACH-008', 'scoring', '700 Series Club', 'Bowl a 3-game series of 700+.', 'best_measured', {'threshold': 700}, _PINFALL),
    ('ACH-009', 'scoring', '800 Series Club', 'Bowl a 3-game series of 800+.', 'best_measured', {'threshold': 800}, _PINFALL),
    ('ACH-012', 'accuracy', 'Dead Center', 'Arrow error under 0.25 board.', 'best_measured', {'threshold': 0.25, 'direction': 'below'}, _RESEARCH),
    ('ACH-015', 'accuracy', 'Sniper', '10 single-pin spares converted in a row.', 'streak', {'target': 10}, _PINFALL),
    ('ACH-019', 'power', 'Controlled Power', '10 strikes with repeatable speed/rev.', 'count_qualifying', {'target': 10}, _RESEARCH),
    ('ACH-024', 'consistency', 'Steady Hand', '3 games within 10 pins of each other.', 'window_spread', {'max_sd': 10, 'min_sample': 3}, _PINFALL),
    ('ACH-025', 'consistency', 'The Machine', '50 shots at a validated variance target.', 'window_spread', {'min_sample': 50}, _RESEARCH),
    ('ACH-029', 'progress', 'Average Builder', 'Rolling game average up 10 pins.', 'baseline_delta', {'delta': 10}, _PINFALL),
    ('ACH-030', 'progress', 'Spare Specialist', 'Spare conversion up 10 points.', 'baseline_delta', {'delta': 10}, _PINFALL),
    ('ACH-031', 'progress', 'Strike Evolution', 'Strike rate up 10 points.', 'baseline_delta', {'delta': 10}, _PINFALL),
    ('ACH-032', 'progress', 'Personal Best', 'A new verified best game.', 'one_time', {'condition': 'new_best_game'}, _PINFALL),
    ('ACH-033', 'progress', 'New Heights', 'A new session-score high.', 'one_time', {'condition': 'new_session_high'}, _PINFALL),
    ('ACH-034', 'competition', 'League Regular', '10 verified league nights.', 'cumulative', {'target': 10}, _COMP),
    ('ACH-035', 'competition', 'League Veteran', '100 verified league nights.', 'cumulative', {'target': 100}, _COMP),
    ('ACH-036', 'competition', 'League Champion', 'Win a league title.', 'one_time', {'condition': 'league_title'}, _COMP),
    ('ACH-037', 'competition', 'Tournament Debut', 'Your first tournament result.', 'one_time', {'condition': 'first_tournament'}, _COMP),
    ('ACH-038', 'competition', 'Tournament Finalist', 'Reach a tournament final.', 'one_time', {'condition': 'tournament_final'}, _COMP),
    ('ACH-039', 'competition', 'Tournament Champion', 'Win a tournament.', 'one_time', {'condition': 'tournament_win'}, _COMP),
    ('ACH-040', 'competition', 'Podium Finisher', 'Top-three tournament finish.', 'one_time', {'condition': 'tournament_top3'}, _COMP),
    ('ACH-041', 'competition', 'Giant Slayer', 'Beat a higher-ranked opponent.', 'one_time', {'condition': 'giant_slayer'}, _COMP),
    ('ACH-042', 'streak', 'Turkey', '3 strikes in a row.', 'streak', {'target': 3}, _PINFALL),
    ('ACH-043', 'streak', 'Four Bagger', '4 strikes in a row.', 'streak', {'target': 4}, _PINFALL),
    ('ACH-044', 'streak', 'Six Pack', '6 strikes in a row.', 'streak', {'target': 6}, _PINFALL),
    ('ACH-045', 'streak', 'Front Nine', 'Strikes in frames 1-9.', 'one_time', {'condition': 'front_nine'}, _PINFALL),
    ('ACH-046', 'streak', 'Clean Game', 'No open frames in a game.', 'one_time', {'condition': 'clean_game'}, _PINFALL),
    ('ACH-047', 'streak', 'Spare Streak', '10 spares converted in a row.', 'streak', {'target': 10}, _PINFALL),
    ('ACH-060', 'platform', 'Hall of Fame', '100 distinct achievement unlocks.', 'cumulative', {'target': 100}, _FUTURE),
]


def _coming_rows():
    return [{'id': i, 'category': c, 'name': n, 'description': d, 'rule_type': rt,
             'params': p, 'status': 'coming_later', 'popup_priority': 50, 'inactive_reason': ir}
            for (i, c, n, d, rt, p, ir) in COMING_LATER]


def achievement_definitions() -> list[dict]:
    """The full seeded catalog: active rows + coming_later rows, each a complete definition dict."""
    active = [dict(a, status='active', inactive_reason=None,
                   popup_priority=a.get('popup_priority', 50)) for a in ACTIVE_ACHIEVEMENTS]
    return active + _coming_rows()


def active_definitions() -> list[dict]:
    return [d for d in achievement_definitions() if d['status'] == 'active']
