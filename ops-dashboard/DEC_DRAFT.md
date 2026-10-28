# DEC draft — number at merge (next free is DEC-098)

> Paste into `00_CONTEXT/DECISIONS.md` at merge, assign the next number, and replace `DEC-0NN` throughout
> the `ops-dashboard/` tree (migration header, SQL comments, this file). Do NOT edit DECISIONS.md from this
> worktree (parallel-work rule).

---

### DEC-0NN — Owner-only ops reporting layer: honest views + a Next.js dashboard over the data we already record; instrumentation held

**Decision (2026-10-28).** Build production ops reporting as a thin, honest layer over the signals LaneSight
*already* records — the retained `analysis_attempt` log (DEC-086/092) plus `feedback`/`shots`/`sessions`/
`profiles` — rather than waiting on the full observability stack in
`01_PRODUCT/PRODUCTION_MONITORING_OBSERVABILITY_CONTEXT.md`. Four parts ship now; instrumentation is held.

1. **Definitions (§3).** A canonical metric registry: `ops-dashboard/definitions.json` (machine-readable,
   the single source of truth) + `OPS_REPORTING_DEFINITIONS.md` (human). Every metric names its real source
   column, formula, denominator, honesty rule, and the observability domain it serves.
2. **Owner-only views (§4).** Migration `0XX_ops_reporting.sql` — ten additive, read-only aggregate views
   (`ops_attempt`, `ops_analysis_daily`, `ops_failure_breakdown`, `ops_cv_coverage`, `ops_latency_stages`,
   `ops_release_health`, `ops_feedback_summary`, `ops_usage_daily`, `ops_freshness`, `ops_coverage_status`).
   Cross-user aggregates, **owner-only**: revoked from `authenticated`, granted to `rules_admin`; the real
   read path is the `service_role` (bypassrls). Deliberately NOT `security_invoker` — unlike the per-user
   `analysis_attempt_summary` (022/023) — because ops needs all users, visible only to the owner.
3. **Dashboard (§5).** A Next.js app in `ops-dashboard/` that reads those views via the `service_role` key
   **server-side only** and renders `HEALTHY / NO DATA / NO ACCESS` per tile. Owner-gated (interim shared
   token, fails closed).
4. **Validation (§1).** `validation/validate_definitions.py` (static: keeps `definitions.json` and the SQL
   in sync, enforces the honesty invariants) + `validation/assertions.sql` (post-apply DB checks).

**Why.**
- We can report honestly on CV trust, analysis reliability, latency and release regressions *today* from
  `analysis_attempt`; there is no reason to gate that on PostHog/Sentry/FinOps integration.
- The non-negotiable "no mock numbers" (CLAUDE.md) is enforced in three places: `nullif` denominators in
  the SQL (empty window → NULL → NO DATA, never 0), the validator, and the UI's explicit states.
- Owner-only by construction: the dashboard is the only reader, over `service_role`, never exposed to a
  logged-in bowler.

**Scope / honesty guarantees.**
- Staged `ls_*` accounts (DEC-063) are excluded from every canonical view (they MAY hold fabricated data).
- `env` (dev|beta|live) is a selectable dimension; production scope is live+beta.
- The two uninstrumented domains — **Storage & DB** and **Financial Operations** — are reported as NO DATA
  (via `ops_coverage_status`), never faked. Customer Journey / App-API / Security are `partial` today.

**Non-goals (now).** No new product events, no cost metering, no crash/Sentry, no storage metering — that is
§2 instrumentation (`SECTION2_INSTRUMENTATION_PATCH_PLAN.md`), **held** because it edits `app.py`/`store.py`/
iOS, which a parallel session is changing. It is written up as a ready patch plan (M1–M5) to build after
that run merges.

**Pending (owner steps — not done here; no apply, no deploy).**
1. Renumber `0XX_ops_reporting.sql` to the next migration number and apply to live `europwryibstnmipbvam`
   (additive, creates views only).
2. Run `validation/assertions.sql` against that DB.
3. Configure `ops-dashboard/.env.local` (live `SUPABASE_URL` + `service_role`; owner token/secret) and host
   the dashboard privately.
4. Build §2 per the patch plan after the parallel run merges.

**Supersedes/limits.** None. Additive to DEC-086/092; a concrete first slice of the
PRODUCTION_MONITORING_OBSERVABILITY strategy (does not replace it).
