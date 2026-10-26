# Claude Code Handoff — Staged test accounts
Status: READY FOR BUILD
Version: 1.0
Last Updated: 2026-10-26
Owner: Shayne

## Read first
1. `CLAUDE.md`, `AGENTS.md` (read order and rules).
2. `00_CONTEXT/DECISIONS.md` → **DEC-063** (new), DEC-055 (uploads never count), DEC-059 (one retained `feedback` table), DEC-061 (metric statuses / recommendation states).
3. Migrations `007` (score/tiers/achievements), `008` (profile DOB / 13+ gate), `014` (feedback), `016`/`017`.

## Goal
Shayne's own login is an empty account, so he can't see the full app. Give him a set of **separate, staged test accounts**, each seeded into a known state, without ever writing staged data into his real account. His real account stays real-only (it is validation data).

## Rules
- **Never** write to, reset or delete a non-staged account. Every write/reset path must refuse unless `profiles.is_staged = true`.
- Staged data is built by running the **real engines** (score/L-dev-0, tiers, achievements, insights/recommendation states, stats) over staged shot histories — do not hand-write final scores, tiers or unlocks. The point is to exercise real logic.
- Staged shots are derived from **real analyzed shot records** (`lanesight-core/validation/*_shot.json`, the 10-25 / 10-20 research outputs, IMG_8751–8754), perturbed with a deterministic per-account RNG seed. No impossible values; respect DEC-061 statuses.
- Staged data must be excluded from: feedback review/analytics, any cross-user benchmarks/baselines, and any owner analytics view. Uploads stay out of Stats/score/achievements per DEC-055 even when staged.
- Credentials: generated passwords stored in the Mac Keychain (same pattern as the API creds); never printed, logged or committed. Emails come from a config file (`ops/staged_accounts.toml`, git-ignored values) using plus-addressing on Shayne's address.

## Build
1. **Migration `018_staged_accounts.sql`** (additive):
   - `profiles.is_staged boolean not null default false`, `profiles.staged_kind text` (one of the kinds below).
   - `feedback.is_staged boolean not null default false`, set at insert from the author's profile (trigger), so it survives account deletion (DEC-059 keeps rows with `user_id` null).
   - Update any analytics/owner views to filter `is_staged = false`. RLS unchanged (staged users are ordinary users).
   - Validate locally (PG16 + Supabase shim, as in DV-01), run the RLS test script, run the security advisor. **Do not apply to live** — that is Shayne's step.
2. **Seed tool `lanesight-core/ops/seed_staged_accounts.py`**:
   - `--account <kind>|all`, `--reset` (deletes that staged account's data, then re-seeds), `--dry-run` (prints row counts per table), `--target local|live` (live requires an explicit flag and 018 present).
   - Creates the auth user via the Supabase Auth admin API if missing, sets `is_staged`/`staged_kind`, then seeds. Idempotent and deterministic (same seed → same data).
   - Backdates `sessions`/`shots`/snapshots/unlocks across the account's time span so trends and Recent activity look real.
3. **Accounts (kinds)**

| Kind | Staging | Exercises |
|---|---|---|
| `new_user` | Profile complete (DOB 13+, delivery style), no ball, no sessions/uploads | Empty states, first-run prompts, add-a-ball |
| `active` (main showcase) | ~6 weeks, 12–15 practice sessions × 15–25 shots; 3 balls (drilling, layout, surface) from `ball_models`; 2 oil patterns; mid-tier score with one rank-up; 8–10 achievements; session ratings + shot notes; 3–4 uploads in Lab › Uploads; some shots with sensor-used = yes | Full Home, Stats (throw / form / score detail), trends, Recent activity, achievements, Lab |
| `improving` | Same shape as `active`; pocket %, speed consistency, form timing trend up; two tier promotions | Trend charts, tier badges, promotion activity items |
| `struggling` | Wide speed/board spread, pocket misses, declining score with one tier drop | `move` / `execution_miss` recommendations, what-to-watch, demotion display |
| `edge_cases` | Mix of `low_confidence`/`best_effort`/unavailable metrics, `pins_unknown` + user-reported pins (`POST /shots/{id}/pins` path), far-lane "limited" camera banner, one failed analysis, one duplicate upload (hash dedupe), mixed sensor-used flags, `no_reliable_data` state | Every DEC-061 status/state, camera banner, error handling |
| `heavy` | ~12 months, 150+ sessions, 10+ balls, all active achievements, top tier | Long lists, chart density, scrolling/performance |
| `under_13` | DOB under 13, nothing else | Age-gate block |

4. **Tests:** dry-run counts per kind; reset round-trip is byte-stable (seed → reset → seed gives identical rows); refusal test against a non-staged profile; feedback from a staged account is flagged and filtered from the analytics view; engine-derived score/tier/achievement state matches what the app shows for `active`.
5. **Docs:** add a "Staged test accounts" section to `03_ENGINEERING/dev_build_v0/TEST_ON_PHONE.md` (which account tests what, how to reset one, where the passwords live). Update `CURRENT_STATE.md` when done.

## Needs Shayne (end of run)
- Apply migration 018 to live (`europwryibstnmipbvam`).
- Run `seed_staged_accounts.py --target live --account all` (or approve Claude Code running it).
- Push the branch.

## Done when
All seven accounts exist (locally verified, live after Shayne's steps), each opens in the dev build in its described state, any one can be reset in a single command, and nothing in Shayne's real account or real feedback changed.
