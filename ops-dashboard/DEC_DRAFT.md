# DEC draft — DEC-098 (confirmed free at authoring; re-check at merge)

> Insert into `00_CONTEXT/DECISIONS.md`.

---

### DEC-098 — Owner-only ops reporting: honest views in a private schema, read via owner-checked RPCs, with a Supabase-Auth Next.js dashboard; instrumentation held

**Decision (2026-10-28).** Build production ops reporting as a thin, honest layer over the signals LaneSight
already records — the retained `analysis_attempt` log (DEC-086/092) plus `feedback`/`shots`/`sessions`/
`profiles` — a concrete first slice of `01_PRODUCT/PRODUCTION_MONITORING_OBSERVABILITY_CONTEXT.md`. Four
parts ship; §2 instrumentation is held.

1. **Definitions (§3).** `ops-dashboard/definitions.json` (machine-readable single source of truth) +
   `03_ENGINEERING/OPS_REPORTING_DEFINITIONS.md` (human). Every metric names its real source column,
   formula, denominator, honesty rule, and observability domain.
2. **Owner-only views + RPCs (§4).** Migration `025_ops_reporting.sql` — ten aggregate views in a **private
   `ops` schema** (not exposed by PostgREST; `usage` revoked from anon/authenticated), read **only** through
   SECURITY DEFINER RPCs `public.ops_rpc_*` that raise `42501` unless `ops.is_owner()` (auth.uid() == the id
   in `ops.app_owner`). No service_role, no per-user RLS trickery — the owner's own JWT is the sole key.
3. **Dashboard (§5).** A Next.js app (`ops-dashboard/`, Vercel project `lanesight-ops`) that signs the owner
   in with **Supabase Auth** and calls the RPCs with their JWT. Two-layer owner gate: Next middleware
   (`user.id === OPS_OWNER_ID`, else **403**) + the DB RPC check. Renders `HEALTHY / NO DATA / NO ACCESS`
   per tile. Env is non-secret only (URL + publishable key + owner id).
4. **Validation (§1).** `validation/validate_definitions.py` (static: defs↔SQL, honesty + owner-RPC security
   invariants) + `validation/assertions.sql` (post-apply DB shape/security checks).

**Owner identity.** Single-sourced as `owner.py OWNER_USER_ID = 551bc775-dee4-41bd-a19c-116e8691d053`
(lafoonch@gmail.com), mirrored by `ops.app_owner` and the dashboard's `OPS_OWNER_ID`. Keep the three equal.

**Why.** We can report honestly on CV trust, reliability, latency and release regressions today from
`analysis_attempt`; no reason to gate that on PostHog/Sentry/FinOps. "No mock numbers" (CLAUDE.md) is
enforced in three places: `nullif` denominators in SQL (empty window → NULL → NO DATA, never 0), the
validator, and the UI states. Owner-only by construction — private schema + owner-checked RPCs + no
service_role in the app.

**Scope / honesty guarantees.** Staged `ls_*` accounts (DEC-063) excluded from every canonical view. `env`
is a selectable dimension (production = live+beta). The two uninstrumented domains — **Storage & DB** and
**Financial Operations** — are NO DATA via `ops.coverage_status`, never faked; Customer Journey / App-API /
Security are `partial`.

**Non-goals (now).** No new product events, cost metering, crash/Sentry, or storage metering — that is §2
instrumentation (`ops-dashboard/SECTION2_INSTRUMENTATION_PATCH_PLAN.md`, M1–M5), **held** because it edits
`app.py`/`store.py`/iOS, then built after this merge.

**Supersedes/limits.** None. Additive to DEC-086/092.
