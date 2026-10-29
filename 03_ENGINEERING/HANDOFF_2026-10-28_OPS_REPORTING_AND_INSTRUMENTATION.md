# LaneSight handoff — Ops reporting + §2 instrumentation (2026-10-28)

## Read first
Repo `~/Developer/LaneSight`. Read `AGENTS.md`, `00_CONTEXT/CURRENT_STATE.md`, and the last ~8 DECs in `00_CONTEXT/DECISIONS.md` (esp. **DEC-098**).
Rules: don't ask permission — do + report; keep reports short/plain; the only hard gates are **push** and **applying a live migration** (get an explicit OK). Backend tests must pass before committing.
Context docs for this work: `03_ENGINEERING/OPS_REPORTING_DEFINITIONS.md` (metric glossary + advisor note), `ops-dashboard/SECTION2_INSTRUMENTATION_PATCH_PLAN.md` (M1–M5 status), `ops-dashboard/README.md` (dashboard).

## What's live right now
- **Cloud Run:** rev `lanesight-api-00036-lnc` (region `us-east1`, project `project-fd28bc3f-a844-43c2-a1c`), built from branch `dev-build-v0` via `gcloud run deploy --source .`. Health `ok` (`/health` 200, supabase_reachable true, mode live).
- **Ops dashboard:** `https://lanesight-ops.vercel.app` (Vercel project `lanesight-ops`, team `lafoonch-6366s-projects`). Owner-only: Supabase Auth sign-in + `OPS_OWNER_ID` gate (non-owner → 403). Reads live via owner-checked RPCs.
- **Flags / env:** `LANESIGHT_SYNC_JOBS=1`; precheck **shadow** (`LANESIGHT_PRECHECK_ENFORCE` unset, DEC-092); `LANESIGHT_UPLOAD_DEDUPE` off (default); `LANESIGHT_USER_REF_SALT` now a bound secret (§2 M4); `LANESIGHT_VCPU`/`LANESIGHT_GIB` unset → code default 4/4 for cost math; no `ops.cost_rates` rows yet (so cost USD = NULL by design).
- **Migrations applied to live:** through **027**. Duplicate prefixes on live (parallel sessions): two `025` (`025_intel_registry`, `025_ops_reporting`), two `026` (`026_intel_competitor_benchmark`, `026_arsenal_default_ball`), then `027_ops_instrumentation`. NOT applied: none pending for ops.

## Branches (state of each)
- `dev-build-v0` @ `148fe0b` — main working branch; carries ops reporting (DEC-098 §1/§3/§4/§5) + §2 instrumentation. Pushed **y**. Migrations `025_ops_reporting` + `027_ops_instrumentation` applied **y**. Deployed rev `00036` **y**. It is the merge target.
- `ops-instrumentation` @ `df5b845` — §2 build branch (M1–M5 code+tests, migration renumber 026→027). Pushed **y** (`origin/ops-instrumentation`). Migration applied **y** (027). Merged to `dev-build-v0` **y** (merge `148fe0b`). Worktree `~/Developer/LaneSight-worktrees/ops-instrumentation` still present — removable.
- `ops-dashboard` @ `358486e` — ops reporting branch (§1/§3/§4/§5). Pushed **n** as a branch (its commits reached origin as ancestors of the dev-build-v0 merge). Migration applied **y** (025). Merged to `dev-build-v0` **y**. Worktree `~/Developer/LaneSight-worktrees/ops-dashboard` still present — removable.

## What's done
- **DEC-098 owner-only ops reporting (§1/§3/§4/§5):** private `ops` schema + owner-checked SECURITY DEFINER RPCs `public.ops_rpc_*`; Next.js dashboard (Supabase Auth, no service_role in app). Migration `025_ops_reporting` applied live; anon/authenticated denied on `ops`, non-owner RPC → 42501, owner RPC KPIs == hand-SQL. Deployed to Vercel. Definitions single-sourced in `ops-dashboard/definitions.json` (validator `ops-dashboard/validation/validate_definitions.py` green).
- **§2 instrumentation (DEC-098 §2, M1–M5):** migration `027_ops_instrumentation` applied live; `store.py` (`_user_ref` M4, `log_api_request` M2, `log_events` M3, `record_storage_snapshot` M5, cost carried M1); `app.py` (API-metrics middleware M2, `_attempt_cost` M1, `POST /events` M3); iOS `APIClient.postEvents` + `AppModel.track` M3; `ops_storage_snapshot.py` gatherer M5; new ops views/RPCs. **356 backend tests pass.** Deployed rev `00036`.
- **Verified live:** M2 flowing — `ops.api_daily` returns real rows (middleware → `api_request` → owner RPC). M1 cost resource-seconds record on new attempts. M4 user_ref active with the live salt.

## Next round of work (do this)
1. **Wire iOS M3 emit sites** so the funnel/events populate. First step: call `model.track("app_opened")` at launch, `track("session_started")` on session create, `track("first_shot_analyzed")` on the first successful shot result; rebuild in Xcode (needs Xcode — not doable headless). Done-when `ops.funnel`/`ops.event_daily` show rows.
2. **Schedule `lanesight_api/ops_storage_snapshot.py`** (cron, like the other ops jobs) so M5 populates. First step: run it once manually with live creds, then add the cron entry. Done-when `ops.storage_latest` has a row.
3. **Enter sourced Cloud Run rates** into `ops.cost_rates` (provider/resource/usd_per_unit/source/effective_from) so M1 USD is non-null. First step: insert rows (owner SQL). No gate beyond the SQL write.
4. **Add ops-dashboard panels** for the new domains (cost/API/events/storage) + their metrics in `definitions.json`; redeploy Vercel. First step: mirror an existing panel (e.g. reliability) against the new RPCs.
5. **Set Vercel Production Branch = `dev-build-v0`** (project → Git) so dashboard pushes auto-redeploy; currently defaults to `main`.

## Deferred / gated (don't start)
- **Cost USD figures** stay NULL until real rates are entered (item 3) — do NOT seed placeholder rates (violates no-mock-numbers).
- **Dashboard new-domain panels** (item 4) are optional polish; the data/RPCs exist and are owner-safe without them.
- Nothing ops-related is hard-gated/pending apply: `025`+`027` are applied, deployed, pushed.

## Watch out for
- **Duplicate migration prefixes on live.** Pick the next number from `list_migrations` (live), not the repo max — the repo can lag live, and 025/026 are each used twice. Next free is 028.
- **Two extra worktrees** (`ops-dashboard`, `ops-instrumentation`) still exist and are both merged — don't build new work there; `git worktree remove` when convenient.
- **pytest cwd:** run from inside `lanesight-core/` so imports resolve to that checkout; from a worktree *root* Python picks up the main checkout's `lanesight_api` (false ImportErrors).
- **Owner RPC advisor warnings:** the 9 `ops_rpc_*` "authenticated can execute SECURITY DEFINER" lints are **intentional** (each checks `ops.is_owner()`) — see `OPS_REPORTING_DEFINITIONS.md §6`. Don't "fix" them.
- **`LANESIGHT_USER_REF_SALT`** is a live secret now — changing it breaks pseudonym continuity across historical rows.
- **Vercel Deployment Protection** is not blocking the prod alias; the Supabase owner gate is the sole gate — keep it that way.

## Done-when
This round is complete when: iOS emits wired + rebuilt → `ops.funnel`/`ops.event_daily` return rows for a real session; the storage cron is scheduled → `ops.storage_latest` has a row; (optional) rates entered → `ops.cost_daily.est_usd` non-null; dashboard shows the new domains. Final report: deployed rev, which ops domains now have live data, tests green, and anything still gated.
