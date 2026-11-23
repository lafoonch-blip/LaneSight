-- Removes the SIMULATED history staged on Shayne's real account (551bc775) on 2026-11-23.
-- Everything simulated is tagged: shots.algorithm_version='simulated' (+ record.simulated=true),
-- score_snapshot.inputs.simulated, activity_item.payload.simulated, user_achievement_unlock/progress.evidence_ref.simulated.
-- His real data is untouched by this script. Run in Supabase SQL (project europwryibstnmipbvam).
begin;
delete from activity_item where user_id='551bc775-dee4-41bd-a19c-116e8691d053' and payload->>'simulated'='true';
delete from user_achievement_unlock where user_id='551bc775-dee4-41bd-a19c-116e8691d053' and evidence_ref->>'simulated'='true';
delete from user_achievement_progress where user_id='551bc775-dee4-41bd-a19c-116e8691d053' and evidence_ref->>'simulated'='true'; -- engine recomputes on next shot
delete from tier_event where id='73d6599f-001e-4184-a55d-1ef0447e2a42';
delete from score_snapshot where user_id='551bc775-dee4-41bd-a19c-116e8691d053' and inputs->>'simulated'='true';
delete from measurements where shot_id in (select id from shots where user_id='551bc775-dee4-41bd-a19c-116e8691d053' and algorithm_version='simulated');
delete from shot_intents where shot_id in (select id from shots where user_id='551bc775-dee4-41bd-a19c-116e8691d053' and algorithm_version='simulated');
delete from shots where user_id='551bc775-dee4-41bd-a19c-116e8691d053' and algorithm_version='simulated';
delete from sessions where id in ('fd785928-3354-4ae2-870d-5284e5e627e1','b7c73fa9-320d-4f1d-b31b-c28553f28c35','23cd57c8-9032-441a-9877-72500b39cae1',
 'a84e44bf-3a46-466c-83f8-ea06e26380b6','84306630-b18b-4c62-afb1-17c756489eda','d8ac9963-31cf-40df-a338-b193cdfa0726','fb0fcdb1-16d1-41d9-99c2-64fe16ab7a7b',
 '0343dcd4-c893-4b59-b817-c71b8ae1aba2','8cab97bd-db70-4def-a33a-2011ac01bad7','294f4412-37e9-46c8-b80f-81c9c0718501','cd098e07-791c-4a98-acee-bf45486766f2',
 '87c8c944-6500-400e-9bdf-bdf01f8ce2d7','867b759c-70af-43bb-ab58-c22c3163f671','56307bf2-c47d-480d-8458-d6334910f8a9');
-- tier state before staging was empty (no qualified score); the engine re-derives it on the next session end.
update user_tier_state set tier=null, score=null, best_score=null, best_score_at=null, first_qualified_score=null, below_floor_sessions=0
 where user_id='551bc775-dee4-41bd-a19c-116e8691d053';
commit;
