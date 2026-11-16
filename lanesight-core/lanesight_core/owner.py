"""Owner-only operations (DEC-051). Pure spec helpers; the runner executes them with the service role.

Score/tier/achievement data can be reset for chosen users any time before Beta: the data is ARCHIVED,
then CLEARED. Definitions (achievement_definition, score_formula_version) and owner rule data are KEPT.
"""
from __future__ import annotations

# Canonical ops owner (DEC-098). The single human who may read the owner ops dashboard. This id MUST match
# the row seeded in migration 025 ops.app_owner and the OPS_OWNER_ID env var of the ops-dashboard app.
# It is auth.users.id for lafoonch@gmail.com (the real account, LANESIGHT_MASTER_CONTEXT / DEC-063).
OWNER_USER_ID = '551bc775-dee4-41bd-a19c-116e8691d053'

# Per-user data cleared on reset, in FK-safe order (children before parents):
#   tier_event -> score_snapshot (FK snapshot_id); the rest key off auth.users / achievement_definition.
RESET_CLEAR_ORDER = [
    'tier_event', 'score_snapshot', 'user_tier_state',
    'user_achievement_unlock', 'user_achievement_progress', 'user_achievement_pin',
    'activity_item', 'notification',
]
RESET_KEEP = ['achievement_definition', 'score_formula_version',
              'benchmark_reference', 'style_template', 'style_template_metric',
              'drill', 'form_rule', 'engine_config']


def reset_plan(user_ids: list[str]) -> dict:
    """Return the archive+clear plan for the given users. archive mirrors clear (same tables, same filter);
    the runner copies rows to an archive location, then deletes, inside one transaction per user."""
    if not user_ids:
        return dict(user_ids=[], archive=[], clear_order=[], keep=RESET_KEEP, note='no users selected')
    return dict(
        user_ids=list(user_ids),
        archive=list(RESET_CLEAR_ORDER),          # archive before clearing
        clear_order=list(RESET_CLEAR_ORDER),
        keep=list(RESET_KEEP),
        filter='user_id = any(%(user_ids)s)',
        note='archive each table for the users, then delete in clear_order; keep definitions/rules.',
    )
