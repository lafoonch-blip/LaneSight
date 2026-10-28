# §2 Instrumentation — Ready Patch Plan (HELD)

Status: PLAN (worktree `ops-dashboard`) — **do not build yet**
Version: 1.0
Last Updated: 2026-10-28
Owner: Shayne
Related: `01_PRODUCT/PRODUCTION_MONITORING_OBSERVABILITY_CONTEXT.md` (§4 event model, §5 catalogue, §8 FinOps), DEC-086 (`analysis_attempt`), DEC-092 (latency P0), `ops-dashboard/` (§1/§3/§4/§5).

> **Why held.** §2 edits `lanesight_api/app.py`, `lanesight_api/store.py` and the iOS app — the exact files the other session is changing during the live run. Building it now would collide. This is the ready patch plan; apply it **after that run merges**, rebase onto the merged `app.py`/`store.py`, then build the matching views + light up the dashboard panels that are `partial`/`no_data` today.

## What the dashboard is waiting for

The §5 dashboard reports fully on the domains `analysis_attempt` already feeds (Video/CV Trust, Release & Regression) and partially on three more. Each item below upgrades a domain and has a view slot ready in the §4 pattern. When you build an item you MUST also: add its view to `0YY_ops_reporting_p2.sql` (new placeholder migration — do not reopen `0XX`), add the view + any metric to `definitions.json`, and extend `validation/validate_definitions.py` coverage (the validator fails on any drift).

Current anchor in `app.py` — the attempt dict built in `_analyze_job.run` (≈ lines 120–149):

```python
attempt = {'user_id': user_id, 'shot_id': shot_id, 'session_id': session_id,
           'source': ..., 'capture_mode': mode, 'content_hash': content_hash,
           'algorithm_version': ALGO_VERSION, 'api_revision': os.environ.get('K_REVISION'),
           'env': 'live' if os.environ.get('K_REVISION') else 'dev',
           'clip': {**_probe_clip(src), 'cold_start': ...}}
...
store.log_analysis_attempt({**attempt, 'status': status, 'failure_code': ..., 'diagnostics': ...,
                            'duration_ms': int((time.monotonic()-t0)*1000), 'step_timings': {...}})
```

`store.log_analysis_attempt` (PgStore ≈ line 962) already drops `None`s and POSTs to `analysis_attempt`.

---

## M1 — Per-attempt cost metering → FinOps (domain 06, `no_data` → `available`)

**Goal.** An honest, *labeled* estimate of compute + egress cost per attempt, so `cost per successful shot` (strategy §8) stops being NO DATA. Estimate, never invoice — tag `status: 'best_effort'` and record the formula inputs, per CLAUDE.md.

- **`app.py`** — in `_log`, compute from values already in hand (no new measurement): `compute_s = duration_ms/1000`; vCPU/GiB from env (Cloud Run is 4 vCPU / 4 GiB per CURRENT_STATE — read from `LANESIGHT_VCPU`/`LANESIGHT_GIB` with those defaults, not hard-coded magic); `egress_mb` from `clip.bytes`. Attach:
  ```python
  'cost': {'basis': 'best_effort', 'compute_s': compute_s, 'vcpu': vcpu, 'gib': gib,
           'vcpu_s': compute_s*vcpu, 'gib_s': compute_s*gib, 'egress_mb': egress_mb,
           'rate_ref': 'cloud_run_us_east1_2026Q4'}   # rates in a committed table, not inline
  ```
  Keep the USD figure OUT of the row; compute it in the view from a committed rate table so a rate change re-prices history. **No fabricated $ when a rate is unknown** → the view returns NULL (NO DATA).
- **`0YY` migration** — `analysis_attempt` already has no `cost` column; ride in the existing `diagnostics`/add a `cost jsonb` column (additive). Add `ops_cost_daily` (day × env: vcpu_s, gib_s, egress_mb, est_usd via rate table `/ nullif(successful_shots,0)` for cost-per-success). Add a small `ops_cost_rates` table (provider, resource, usd_per_unit, effective_from).
- **Risk.** Low — additive, best-effort labeled. **Validation.** `assertions.sql`: est_usd is NULL when no rate row matches; cost-per-success denominator uses nullif.

## M2 — API request metering → App/API Performance (domain 04, `partial` → `available`)

**Goal.** 4xx/5xx rates, p50/p95 API latency, upload-failure rate *distinct from analysis failure* (strategy §5 dashboard 04). `analysis_attempt` only covers the analyze job, not the HTTP surface.

- **`app.py`** — add one FastAPI `@app.middleware("http")` that records `{path_template, method, status, duration_ms, env, api_revision, user_ref}` per request (exclude `/health`; never log bodies/tokens — strategy §4 exclusions). Buffer + best-effort flush so it can never fail a request (same discipline as `log_analysis_attempt`).
- **`store.py`** — `log_api_request(row)` mirroring `log_analysis_attempt` (retained table, no FK).
- **`0YY` migration** — `api_request` table (retained, no FK, owner-RLS like `analysis_attempt`) + `ops_api_daily` view (day × env × status_class: count, error_rate with nullif, p50/p95 duration).
- **Risk.** Medium — a middleware touches every request; keep it allocation-cheap and wrapped in try/except. **Validation.** fault-injection: a middleware exception must not 500 the underlying request.

## M3 — Product events → Customer Journey (domain 02, `partial` → `available`)

**Goal.** Signup → first successful shot funnel, sessions, screen flow (strategy §5 dashboard 02). Today only shot/session *counts* exist.

- **iOS** — a tiny `Analytics.event(name, props)` → `APIClient.postEvent`. Emit a minimal, **consent-aware** set first: `app_opened`, `session_started`, `first_shot_analyzed`, `screen_view{screen}`. Mask per strategy §4/§6: no raw email/phone, no video frames, pseudonymous id only.
- **`app.py`** — `POST /events` (batched, idempotent by client event id, offline-buffer friendly). Validate against the canonical envelope (strategy §4): `event_name, occurred_at, env, anonymous_user_id, app_version, feature, flow_step, status, ...`.
- **`store.py`** — `log_events(rows)` → `product_event` retained table.
- **`0YY` migration** — `product_event` table + `ops_funnel` / `ops_event_daily` views (real accounts only; staged excluded).
- **Risk.** Medium (new client surface + consent). **Validation.** schema-registry test (reject unknown event_name), dedupe on client id, consent gating.

## M4 — Pseudonymise user on attempts (privacy, strategy §4/§6)

- **`store.py`** — in `log_analysis_attempt` (and M2/M3 writers) derive `user_ref = hmac(server_salt, user_id)` and store `user_ref` alongside (or instead of, long-term) raw `user_id`, so the ops layer and any export key on the pseudonym. `feedback` already has `user_ref`; match it.
- **`0YY` migration** — add `user_ref text` to `analysis_attempt`; backfill from `user_id` via the same salt; index it. Update the §4 ops views to group/join on `user_ref`.
- **Risk.** Low. **Validation.** `user_ref` stable across a user's rows; raw `user_id` never leaves the owner boundary in any export.

## M5 — Storage & DB size snapshot → Storage (domain 05, `no_data` → `available`)

**Goal.** Bytes by bucket, growth, aged/orphan media, DB size (strategy §5 dashboard 05, §8 controls). This is **not** per-request — it is a periodic metering job.

- **`store.py` / `ops/`** — a scheduled task (reuse the existing cron/worker pattern) that records Supabase Storage bucket bytes + object ages + DB size into `ops_storage_snapshot(captured_at, bucket, bytes, objects, aged_objects, db_bytes)`.
- **`0YY` migration** — `ops_storage_snapshot` table + `ops_storage_latest` view.
- **Risk.** Low (read-only metering). **Validation.** snapshot cadence recorded; dashboard shows last-captured via `ops_freshness`.

---

## Build order when unheld

1. Rebase this plan onto the merged `app.py`/`store.py`.
2. M4 (pseudonymise) first — cheap, and M1–M3/M5 should write `user_ref` from the start.
3. M1 (cost) and M2 (API) — highest owner value, additive.
4. M3 (product events) — larger; needs iOS + consent review.
5. M5 (storage) — periodic job.
6. For each: new `0YY_ops_reporting_p2.sql` views + `definitions.json` entries + validator coverage + a `CoverageGrid` flip from `no_data`/`partial` to `available` in `ops_coverage_status`.
