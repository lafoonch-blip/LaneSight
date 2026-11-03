# Handoff — Home Feedback button (DEC-124) + F&F phase tagging (DEC-123)
Status: READY FOR CLAUDE CODE · Date: 2026-11-02 · Owner: Shayne

Run straight through to the end and report once. Stop only for a real blocker or an irreversible action (live migration, push to main).

## Goal
One Feedback button on Home → small sheet → categorized row in the retained `feedback` table, correctly tagged by app phase. Same flow for F&F, Beta and live.

## Already in place (verify, don't rebuild)
- `POST /feedback` accepts `source = 'general'` (`lanesight_api/app.py`, `_FEEDBACK_SOURCES`); versions stamped by `_stamp_versions`.
- `feedback` table per `03_ENGINEERING/FEEDBACK_STORE_SPEC.md` (DEC-059).

## Build
1. **iOS — Home Feedback button** (follow "01 - Design Standards"; use existing components; flag anything missing).
2. **iOS — Feedback sheet:** category (required): Bug · Wrong/missing numbers · Confusing · Idea · Other; text (required, ≤2,000 chars); optional screenshot (PhotosPicker; upload to a private bucket, store path in `diagnostics`); "Include diagnostics" toggle (default on). Submit → thank-you toast → dismiss. Failed send keeps the text and lets the user retry (never lose typed feedback).
3. **Payload:** `source='general'`, `tags=[category]`, `text`, `app_phase`, `app_version`, and when diagnostics are on: device model, iOS version, current screen, last session id / shot id.
4. **App phase (all feedback sources, not just general):** iOS sends `app_phase` on every feedback call. Value comes from the account cohort: `dev` for Shayne and staged test accounts, `ff` for Friends & Family accounts, `beta`, `live`. Add `ff` to the server phase enum and any check constraint (migration; apply only after tests pass). Server keeps defaulting to `dev` only when absent.
5. **F&F cohort:** account-level cohort flag (`dev` / `ff` / `beta` / `live`) the server can read, so Stats, ops dashboard and feedback can be filtered by cohort (DEC-123). Shayne's real account stays `dev`.
6. **Owner view:** feedback list in the ops dashboard (filter by phase, category, date; triage status) or at minimum the CSV export with category + phase columns.

## Tests / verification
- API test: general feedback with category + `ff` phase round-trips; missing phase → `dev`.
- iOS: sheet validation, retry on failure, payload contents (unit test on the encoder).
- Device check: submit one of each category from a staged test account; confirm rows in Supabase with correct phase and diagnostics.

## Docs
- `APP_DESIGN_CHANGES.md`: add Home Feedback button + Feedback sheet (needs Figma component).
- `FEEDBACK_STORE_SPEC.md`: `general` entry point = Home Feedback button; add `ff` phase; categories list.
- `CURRENT_STATE.md`: note when shipped.
