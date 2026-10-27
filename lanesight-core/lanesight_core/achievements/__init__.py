"""Achievement progress engine (SCORE_TIERS_ACHIEVEMENTS_SPEC §5, DEC-039/051).

Pure and DB-free. Evaluates one achievement definition against a context dict and returns a progress
record; the runner persists progress/unlocks (idempotent via the unique (user, achievement, level) key)
and emits the activity item + notification. Achievements never change the score or tier (DEC-039).
A metric with no qualified data is 'not_trackable' with a reason, never 0% or failed.
"""
from .engine import ACHIEVEMENT_VERSION, RULE_TYPES, evaluate, update_streak

__all__ = ['ACHIEVEMENT_VERSION', 'RULE_TYPES', 'evaluate', 'update_streak']
