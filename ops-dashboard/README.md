# LaneSight Ops Dashboard (§5)

Owner-only production reporting for LaneSight. Reads the owner-only `ops_*` Postgres views over PostgREST
using the Supabase **service_role** key, **server-side only**, and renders real signals with honest
`HEALTHY / NO DATA / NO ACCESS` states. **No mock numbers** — every tile traces to a defined view column
(`definitions.json` / `OPS_REPORTING_DEFINITIONS.md`).

## Architecture

```
Browser ──(owner cookie)──▶ Next.js (App Router, RSC + route handlers)
                                   │  service_role key (server env only, never bundled)
                                   ▼
                        Supabase PostgREST  ──▶  ops_* views (migration 0XX_ops_reporting.sql)
                                                  owner-only: revoked from authenticated,
                                                  granted to rules_admin; service_role bypasses RLS
```

- **Data access** — `lib/supabase.ts` fetches views with the service_role key. It is read in server code
  only, from a non-`NEXT_PUBLIC_` env var, so Next never ships it to the browser. No `@supabase/supabase-js`
  dependency (plain `fetch`).
- **Honesty** — `lib/queries.ts` returns `{state, rows}`; missing key / failed request → `NO_ACCESS`,
  reachable-but-empty → `NO_DATA`, otherwise `HEALTHY`. Rates come pre-`nullif`'d from the views, so an
  empty window is `NULL` → the UI shows "NO DATA", never 0.
- **Definitions** — `definitions.json` is the single source of truth, shared with the SQL and the Python
  validator (`validation/validate_definitions.py`). Change a column in one place → the validator fails.
- **Auth** — `middleware.ts` gates every route behind an owner session cookie (HMAC of a fixed payload
  signed with `OPS_DASHBOARD_SECRET`). Login compares the submitted token to `OPS_DASHBOARD_TOKEN` in
  constant time. **Fails closed**: with the env unset, login is refused and no data is served.

## Pages

Overview · Reliability · CV Trust · Latency · Releases · Feedback. Global scope controls: `env`
(live+beta default) and lookback window.

## Run locally

```bash
cd ops-dashboard
cp .env.example .env.local        # fill in SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, OPS_DASHBOARD_TOKEN/SECRET
npm install
npm run validate                  # static check of definitions.json <-> SQL (no DB needed)
npm run dev                       # http://localhost:3100
```

The dashboard shows real data only once **migration `0XX_ops_reporting.sql` is applied** to the target
Supabase project (the `ops_*` views must exist). Until then every panel renders `NO ACCESS` / `NO DATA` —
by design, never fabricated.

## Pending steps (not done here — no apply, no deploy)

1. **Renumber & apply** `lanesight-core/.../migrations/0XX_ops_reporting.sql` to the live project
   `europwryibstnmipbvam` (owner step; additive, read-only — creates views only).
2. **Run** `validation/assertions.sql` against that DB to confirm the shape is honest.
3. **Configure env** (`.env.local`) with the live `SUPABASE_URL` + `service_role` key (the same secret
   bound to Cloud Run as `LANESIGHT_SERVICE_ROLE`) and owner token/secret.
4. **Build & host** (`npm install && npm run build`); deploy behind the owner gate (e.g. Vercel/Cloud Run,
   private). Set the env vars there.
5. **§2 instrumentation** (held) — see `SECTION2_INSTRUMENTATION_PATCH_PLAN.md`; adds the signals the
   `no_data` domains (FinOps, Storage) and partial domains need.

## Security notes

- The service_role key is a full-access DB credential. Keep it in server env only; never expose an endpoint
  that proxies arbitrary queries. This app only reads the fixed `ops_*` views.
- The owner gate is interim (single shared token). Upgrade path: verify a Supabase JWT belongs to the owner
  / `rules_admin` account instead of a shared token.
