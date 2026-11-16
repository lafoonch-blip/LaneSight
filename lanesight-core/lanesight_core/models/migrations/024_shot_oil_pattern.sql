-- DEC-097: oil pattern is editable on the Active Session and locked per shot at record time.
-- Ball is already per-shot (shots.user_ball_id / ball_configuration_id); oil was per-session only.
-- Add a per-shot oil_pattern_id so a mid-session oil change applies to the NEXT shot only, and a shot
-- already recorded/analyzing keeps the oil it was thrown with. Additive + nullable; existing shots fall
-- back to their session's oil_pattern_id at read time (store.shot_context), so no backfill of old rows is
-- required. New shots store the value sent by the app (or the session's current oil as a backfill).
ALTER TABLE shots ADD COLUMN IF NOT EXISTS oil_pattern_id uuid REFERENCES oil_patterns(id);
