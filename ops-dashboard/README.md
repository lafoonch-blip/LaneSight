# LaneSight Ops Dashboard (§5)

Owner-only production reporting for LaneSight. Signs the owner in with **Supabase Auth**, reads data **only
through owner-checked `public.ops_rpc_*` RPCs** over views in the private `ops` schema (migration 025), and
renders real signals with honest `HEALTHY / NO DATA / NO ACCESS` states. **No mock numbers** — every tile
traces to a defined view column (`definitions.json` / `OPS_REPORTING_DEFINITIONS.md`). **No service_role /
JWT secret / DB password anywhere** — only the owner's own session reaches the data.

## Architecture

```
Browser ──signInWithPassword──▶ Supabase Auth ──session cookies──▶ Next.js (RSC + middleware)
   owner gate (middleware): verify session, user.id === OPS_OWNER_ID, else 403
                                   │  owner's JWT
                                   ▼
                   PostgREST rpc  public.ops_rpc_*  (SECURITY DEFINER)
                        if not ops.is_owner() -> raise 42501
                        else select from ops.<view>
                                   ▼
                   ops schema (NOT exposed by PostgREST; usage revoked from anon/authenticated)
                        views over analysis_attempt / feedback / shots / sessions / profiles
```

- **Two-layer owner enforcement.** (1) Next.js middleware verifies the Supabase session and checks
  `user.id === OPS_OWNER_ID`; a non-owner gets **403** (only `/api/logout` is allowed, so they can sign
  out). (2) Each RPC re-checks `ops.is_owner()` in Postgres and raises `42501` otherwise. `OPS_OWNER_ID`
  mirrors `lanesight_core/owner.py OWNER_USER_ID` and `ops.app_owner`.
- **Private data.** The `ops` views live in a schema PostgREST does not expose, with `usage` revoked from
  anon/authenticated — they are unreachable except through the definer RPCs.
- **No privileged secrets in the app.** Only `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`
  (publishable, client-safe) and `OPS_OWNER_ID` (a uuid). The owner's JWT does the reading.
- **Honesty.** `lib/queries.ts` returns `{state, rows}`: RPC error → `NO_ACCESS`, reachable-but-empty →
  `NO_DATA`, else `HEALTHY`. Rates come pre-`nullif`'d from the views, so an empty window is `NULL` → "NO
  DATA", never 0.
- **Definitions.** `definitions.json` is the single source of truth, shared with the SQL and the Python
  validator (`validation/validate_definitions.py`). Change a column in one place → the validator fails.

## Pages

Overview · Reliability · CV Trust · Latency · Releases · Feedback. Global scope controls: `env`
(live+beta default) and lookback window.

## Run locally

```bash
cd ops-dashboard
cp .env.example .env.local        # NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, OPS_OWNER_ID
npm install
npm run validate                  # static check of definitions.json <-> SQL (no DB needed)
npm run dev                       # http://localhost:3100  — sign in with the owner LaneSight account
```

Shows real data once **migration `025_ops_reporting.sql` is applied** (the `ops` views + RPCs exist) and you
sign in as the owner. Any other account → 403. Until configured, panels render NO ACCESS / NO DATA — never
fabricated.

## Deploy (Vercel project `lanesight-ops`)

Env vars (names only; all non-secret): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
`OPS_OWNER_ID`. No service_role, no DB URL. Build `next build`, output standalone. The owner gate is enforced
server-side and in the DB, so a public Vercel URL is still owner-only.

## Security notes

- The anon/publishable key grants nothing on its own: the `ops` schema is unreachable by anon/authenticated,
  and the RPCs refuse non-owners.
- Owner identity is single-sourced in `owner.py`; keep `OPS_OWNER_ID` and `ops.app_owner` equal to it.
- §2 instrumentation (held) — see `SECTION2_INSTRUMENTATION_PATCH_PLAN.md`.
