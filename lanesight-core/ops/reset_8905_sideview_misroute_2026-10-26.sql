-- ============================================================================
-- NEEDS SHAYNE — DO NOT RUN AUTOMATICALLY.
-- One-off data reset for the side-view-misroute handoff
-- (03_ENGINEERING/dev_build_v0/HANDOFF_2026-10-26_SIDE_VIEW_FORM_MISROUTE.md).
--
-- Problem: IMG_8905 is a SIDE/approach (Form) clip. On the pre-fix backend it was
-- routed down the SHOT pipeline, which fit a lane anyway and produced confident-
-- wrong metrics (speed early 15.8 / late 19.4, breakpoint 2.0, entry 10.5, "Move
-- Right 8 ft"). That bogus shot counted toward the LaneSight Score (3/20 …) and
-- achievement progress in Shayne's REAL account.
--
-- Backend fix already shipped (this branch): a capture-view gate refuses side/
-- unknown views with no_reliable_data + a camera tip and ZERO metrics, so this
-- can't recur. This script UNDOES the contamination the one bad shot caused.
--
-- Fix: delete the single bogus shot row (cascades to its measurements / intent /
-- feedback) and clear the owner's DERIVED state (score snapshots, tier, achievement
-- progress/unlocks/pins, findings, notifications) so the engines recompute cleanly
-- from the legitimate shots only. No other shot rows are touched.
--
-- Review the finder SELECT, put the real shot id in :shot_id below, then run the
-- BEGIN..COMMIT block manually (Supabase SQL editor). ROLLBACK if before/after
-- counts look wrong. After the reset, re-capture/upload IMG_8905 as a FORM clip.
-- ============================================================================

-- Owner = Shayne's real account (confirm it is the same account as the prior reset;
-- change if the misrouted shot belongs to a different user_id):
--   user_id = 551bc775-dee4-41bd-a19c-116e8691d053

-- 0) FINDER — identify the bogus 8905 shot among the owner's recent shots. It is a
--    side-view clip that nonetheless has shot metrics (the tell-tale: late speed >
--    early speed, and/or video.file referencing IMG_8905). Copy its id into step 2.
select s.id,
       s.created_at,
       s.capture_mode,
       s.classification,
       s.record->'video'->>'file'            as video_file,
       s.record->'capture_quality'->>'view'  as view,
       (select value from measurements m where m.shot_id = s.id and m.metric = 'speed_early') as speed_early,
       (select value from measurements m where m.shot_id = s.id and m.metric = 'speed_late')  as speed_late,
       (select value from measurements m where m.shot_id = s.id and m.metric = 'entry_board') as entry_board
  from shots s
 where s.user_id = '551bc775-dee4-41bd-a19c-116e8691d053'
 order by s.created_at desc
 limit 25;

-- ----------------------------------------------------------------------------
-- 1) Set the shot id you identified above. (Supabase SQL editor: replace the
--    placeholder literal in step 2; psql: use \set shot_id '...').
-- ----------------------------------------------------------------------------

begin;

-- 2) BEFORE: confirm exactly one row, owned by the user, and that it is the bogus shot.
select id, user_id, capture_mode, classification, record->'video'->>'file' as video_file
  from shots
 where id = '<SHOT_ID>'                       -- <-- paste the id from the finder
   and user_id = '551bc775-dee4-41bd-a19c-116e8691d053';

-- 3) Delete the bogus shot (cascades to measurements / shot_intents / shot_feedback).
delete from shots
 where id = '<SHOT_ID>'
   and user_id = '551bc775-dee4-41bd-a19c-116e8691d053';

-- 4) Clear the owner's derived state so the engines recompute from the clean shot set.
delete from score_snapshot            where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from user_tier_state           where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from tier_event                where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from user_achievement_progress where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from user_achievement_unlock   where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from user_achievement_pin      where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from finding                   where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';
delete from notification              where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';

-- 5) AFTER: the bogus shot is gone; derived tables empty for the user (they rebuild
--    on the next analyzed shot / score recompute).
select count(*) as bogus_shot_left from shots where id = '<SHOT_ID>';
select count(*) as score_snapshots_left from score_snapshot
 where user_id = '551bc775-dee4-41bd-a19c-116e8691d053';

-- If the above look right:  COMMIT;   otherwise:  ROLLBACK;
commit;
