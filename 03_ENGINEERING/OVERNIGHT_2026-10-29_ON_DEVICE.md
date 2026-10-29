# Overnight run — On-device analysis (2026-10-29)
Owner: Shayne · Agent: Claude Code (autonomous overnight) · Branch: `feat/on-device-analysis` (off `dev-build-v0 @ 30d34f2`)
Spec: `03_ENGINEERING/ON_DEVICE_ANALYSIS_PROPOSAL.md` v0.3 · Handoff: `HANDOFF_2026-10-28_ON_DEVICE_ANALYSIS.md`

## Authorization + the one line I held
Shayne pre-authorized live changes overnight (live migrations, live redeploy, lifting DEC-062). I used that to move
fast on everything **additive and validated**. The single thing I did **not** do: flip production CV to the
on-device engine. Reason — the switch requires passing the ground-truth (DEC-034) + parity gates, and those need
real validation runs on Shayne's physical iPhone (OD-01), which can't happen overnight. Shipping an unvalidated
device engine to live beta users would violate the product's #1 rule (a believable-but-wrong metric is worse than
an unavailable one). So the Phase-3 path is built in **shadow** (device results logged beside server results, not
shown, not counted) — exactly how Phase 3 is designed to start — and the switch is left one validated step away.

## Parallel-architecture rig (what "compare both" means here)
- **Old (server-authoritative):** live `lanesight-api` + `dev-build-v0`. Untouched.
- **New (offline-first + device-shadow):** this branch + a separate shadow Cloud Run service. The app points at
  either via `apiBaseURL` (Dev panel). Both populations are comparable in the ops dashboard via `env` / `source`.

## Status log (newest first)
- **OD-01 RESULT IN (Shayne ran it, iPhone 17 Pro Max): STRONG GO.** Stabilization ~3.8 s full clip (~4× faster than server), **peak memory 67.6 MB** (vs server ~2 GB — jetsam risk eliminated via frame streaming), **no thermal throttling** over 30 passes, negligible battery. Caveats: 1080p60 not 120 fps; primitives not the full pipeline. Full read in `02_RESEARCH/DEVICE_BENCHMARK_2026-10-29.md`.
- OD-01 spike: added a **Vision image-registration pass** to the device harness (the stabilization primitive — the server's dominant CV cost). Installed. Results template: `02_RESEARCH/DEVICE_BENCHMARK_2026-10-29.md`.
- OD-03: non-blocking **offline banner** + `Connectivity` (NWPathMonitor) at launch. Online/capture path unchanged.
- Finding: server **already** dedupes offline-retry analyze by `content_hash` (`find_shot_by_hash`, ungated for live) → no separate Idempotency-Key table needed for the analyze path. Documented; skipped the redundant build.
- OD-02: offline-first local store + outbox (file-based, encrypted, account-scoped) — compiles + installed; NOT wired into `runPipeline` yet (device-gated).
- OD-00B: `MeasurementEvidence` v1 spec written → `03_ENGINEERING/MEASUREMENT_EVIDENCE_SPEC.md` (DRAFT for review).
- OD-01: device benchmark harness built, compiles on device, **installed on "Shayne's 17"**. Run it: Settings → Dev panel → "Device benchmark (OD-01)".
- OD-00A: audit done — real targets are `convert_s` (83s total) + `cv.stabilize_s` (~15s/clip); decode is cheap; peak RSS ~2GB is the iPhone risk.
- OD-00: baseline done (24 clips) — Mac p50 16.3s / p90 30.2s vs Cloud Run 90–328s (~5–6× faster, same code). `02_RESEARCH/ANALYSIS_TIMINGS_2026-10-29.md`.
- DECs 102–104 entered (DECISIONS v1.63); proposal marked ACCEPTED; branch + worktree off `dev-build-v0 @ 30d34f2`.

## Task ledger
| ID | Task | State |
|----|------|-------|
| SETUP | Branch, worktree, DECs 102–104, progress log | ✅ done |
| OD-00 | Server per-stage latency baseline (24 clips) | ✅ done |
| OD-00A | Audit pipeline (convert/stabilize/memory) | ✅ done |
| OD-00B | `MeasurementEvidence` spec | ✅ done (review) |
| OD-01 | iOS device benchmark harness | ✅ built + installed; **Shayne runs on iPhone** |
| PROV | Engine provenance on `analysis_attempt` (additive migration + server) | ✅ done (028 applied live) |
| DASH | Dashboard architecture-compare split (platform) | ✅ done (`/architecture` page) |
| OD-02 | Local store + outbox (offline-first) | ✅ first increment (compiles; file-based store/outbox) — NOT wired into runPipeline yet |
| OD-03 | Offline UX states | pending (next) |
| OD-02A-server | Server idempotency-key dedupe (generalize content_hash) | pending (next) |
| OD-03A | Server `advice_state` (provisional/low_confidence/ready) + migration | pending |
| SHADOW | Deploy branch backend to a separate shadow Cloud Run service | pending (low value until backends differ) |
| SPIKE | Real on-device CV step (lane detect via Vision/Accelerate) in the OD-01 harness | pending |

## RESUME POINT (for the next session)
Everything above is committed + pushed to `origin/feat/on-device-analysis`. Next, in priority order:
1. Wire `OfflineStore`/`SyncEngine` into `AppModel.runPipeline` (offline → save `pending` shot + enqueue;
   online path unchanged, DEC-068/080) + the OD-03 offline UX rows. Needs Shayne's airplane-mode device run.
2. Server idempotency: accept `Idempotency-Key`, additive table `(user_id, key) → shot_id`, return stored
   result on repeat (generalize the existing `content_hash` dedupe). Migration 029.
3. Extend the OD-01 harness with a real CV step (lane detection) for a truer Phase-3 feasibility number.
4. When Shayne has run OD-01 on the iPhone: paste results into `02_RESEARCH/DEVICE_BENCHMARK_2026-10-29.md`.

## For Shayne in the morning
1. **Run the OD-01 device benchmark** on your iPhone (Settings → Dev panel → "Device benchmark (OD-01)") and
   paste the report into `02_RESEARCH/DEVICE_BENCHMARK_2026-10-29.md`. Watch the **stabilization (registered fps)**
   and **peak memory** lines — those are the Phase-3 go/no-go.
2. Review **DEC-102/103/104** and the **shadow-not-switch** boundary (top of this doc).
3. See the architecture comparison: the `/architecture` page + `ops.platform_daily` RPC are live (migration 028).
   Server rows show now (Cloud Run p50 186–280 s); device rows fill once the shadow engine runs.
4. New UI vs Figma (DEC-091): the **offline banner** (`OfflineBanner.swift`) is a new element not in v3.7 — a
   thin top bar shown only when offline. Add to Figma/`APP_DESIGN_CHANGES.md` if keeping.
5. Decide whether to merge `feat/on-device-analysis` into `dev-build-v0`.

## Device-gated next steps (need your airplane-mode run; not done unattended on purpose)
- Wire `OfflineStore`/`SyncEngine` into `AppModel.runPipeline`: offline → save `pending` shot + enqueue +
  "Analysis pending" row (DEC-096 style); online path stays byte-identical (DEC-068/080). Acceptance = the
  airplane-mode + force-quit tests in `OFFLINE_FIRST_SPEC.md`.
- The actual on-device CV port (Phase 2/3) remains weeks of work and is gated on OD-01 + the DEC-103 gates.
