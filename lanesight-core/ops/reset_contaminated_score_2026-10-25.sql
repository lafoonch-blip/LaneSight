-- ============================================================================
-- NEEDS SHAYNE — DO NOT RUN AUTOMATICALLY.
-- One-off data reset for SHOT_REVIEW 2026-10-25 / handoff workstream E.
--
-- Problem: three clips were uploaded into a session BEFORE DEC-055 (uploads are
-- standalone and must never feed Score/Stats/achievements). They are counted in
-- the LaneSight Score (3/20) for user 551bc775-dee4-41bd-a19c-116e8691d053.
--
-- Fix: detach the three uploads from the session so they become proper standalone
-- uploads (read_shot_records already excludes source='upload'), then clear the
-- user's DERIVED state (score snapshots, tier, achievement progress/unlocks/pins,
-- findings, notifications) so the engines recompute cleanly from the legit
-- session shots only. Measured shot rows are NOT deleted.
--
-- Review the counts the SELECTs print, then run the BEGIN..COMMIT block manually
-- (e.g. Supabase SQL editor). Keep it wrapped in a transaction; ROLLBACK if the
-- before/after counts look wrong.
-- ============================================================================

-- The contaminated uploads (full ids) and the owner:
--   03f7b6e8-88c4-43d4-bf9d-0bf20764f3ac
--   bae3d3df-a26c-4cdb-8537-c8d19fe37bd4
--   f2c0d0e5-f3d5-4520-8e6e-a18cd730952d
--   user_id   = 551bc775-dee4-41bd-a19c-116e8691d053
--   session   = 3338e9ec-c745-4349-9331-ef1fb3f2b5b4

-- 0) BEFORE: confirm the three rows are uploads still attached to the session.
select id, source, session_id from shots
where id in ('03f7b6e8-88c4-43d4-bf9d-0bf20764f3ac',
             'bae3d3df-a26c-4cdb-8537-c8d19fe37bd4',
             'f2c0d0e5-f3d5-4520-8e6e-a18cd730952d');

begin;

-- 1) Detach the uploads from the session (make them true standalone uploads).
update shots
   set session_id = null, source = 'upload'
 where id in ('03f7b6e8-88c4-43d4-bf9d-0bf20764f3ac',
              'bae3d3df-a26c-4cdb-8537-c8d19fe37bd4',
              'f2c0d0e5-f3d5-4520-8e6e-a18cd730952d');

-- 2) Clear the owner's derived state so the engines recompute from the clean shot set.
delete from score_snapshot           where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from user_tier_state          where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from tier_event               where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from user_achievement_progress where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from user_achievement_unlock  where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from user_achievement_pin     where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from finding                  where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from notification             where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';

-- 3) AFTER: the three shots should now have session_id = null; derived tables empty for the user.
select id, source, session_id from shots
where id in ('03f7b6e8-88c4-43d4-bf9d-0bf20764f3ac',
             'bae3d3df-a26c-4cdb-8537-c8d19fe37bd4',
             'f2c0d0e5-f3d5-4520-8e6e-a18cd730952d');
select count(*) as score_snapshots_left from score_snapshot where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';

-- If the above look right:  COMMIT;   otherwise:  ROLLBACK;
commit;
