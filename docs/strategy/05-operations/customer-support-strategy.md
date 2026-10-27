# Customer Experience & Support Strategy
Status: PROPOSED — not an accepted decision  
Version: 1.1  
Last Updated: 2026-10-26  
Authority: `00_CONTEXT/DECISIONS.md` on `dev-build-v0` (v1.43, DEC-082) and current branch `CURRENT_STATE.md` (v1.37). Confirm latest local branch before adoption.  

> Strategy proposals never override accepted DEC entries. Decisions require Shayne's approval and an append-only DEC. This file is additive, not a modification of product authority.

## End-to-end journey
First-use education/permissions → Shot or Form setup → tap-to-record or upload → blocking Analyzing screen → Shot/Form details → Record next or close → session summary. Form capture supports side/rear; does not ask for ball/oil (DEC-081). Form renders key-position images, no full video (DEC-082).

## Failure handling
Upload failure keeps local clip for retry (DEC-080). Show actionable camera-placement guidance for `no_reliable_data`; unreadable pin result asks customer to specify pins; qualified low-confidence results never presented as definitive. Map all user errors to DEC-061 labels.

## Support intake
In-app `feedback` for session ratings, shot notes, advice ratings, Form notes/general comments with phase/version/status; staged accounts excluded (DEC-059/063). Dedicated support email/response SLA are proposals pending operational setup; do not publish a fictitious address.

## Owner workflow
Daily when real Beta traffic exists: classify privacy/security critical, service outage, wrong high-confidence metric, app friction, feature requests. Capture reproducible platform version + reason code without storing production raw video. Weekly publish resolved/actioned vs open.

## Trust requirements
Make derived vs measured explicit; give users control over deleting account and histories subject to required de-identification logic; explain clip deletion and retained key frames clearly.
