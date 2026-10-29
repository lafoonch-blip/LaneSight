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
- Branch + worktree created off `dev-build-v0 @ 30d34f2`.
- OD-00 server-latency baseline: running `ops/perf_benchmark.py` over 24 real clips (reuses DEC-092 P0 timers).

## Task ledger
| ID | Task | State |
|----|------|-------|
| SETUP | Branch, worktree, DECs 102–104, progress log | in progress |
| OD-00 | Server per-stage latency baseline (≥20 clips) | running |
| OD-00A | Audit pipeline for redundant decodes / passes | pending |
| OD-00B | `MeasurementEvidence` spec | pending |
| OD-01 | iOS device benchmark harness (Shayne runs on iPhone) | pending |
| DASH | Dashboard env/source architecture-compare split | pending |
| OD-03A | Server `advice_state` (provisional/low_confidence/ready) + additive migration | pending |
| OD-02 | Local store + outbox (offline-first) | pending |
| OD-03 | Offline UX states | pending |
| SPIKE | Isolated on-device CV spike (non-production) | pending |

## For Shayne in the morning
- Run the OD-01 device benchmark on your iPhone (instructions will be here when the harness is built).
- Review the DEC entries (102–104) and the shadow-vs-switch boundary above.
- Decide whether to merge this branch into `dev-build-v0`.
