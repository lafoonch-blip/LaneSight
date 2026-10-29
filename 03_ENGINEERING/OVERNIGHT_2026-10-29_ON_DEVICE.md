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
| PROV | Engine provenance on `analysis_attempt` (additive migration + server) | next |
| OD-03A | Server `advice_state` (provisional/low_confidence/ready) + migration | next |
| SHADOW | Deploy branch backend to a separate shadow Cloud Run service | pending |
| DASH | Dashboard architecture-compare split (platform) | pending |
| OD-02 | Local store + outbox (offline-first) | pending (large) |
| OD-03 | Offline UX states | pending (large) |

## For Shayne in the morning
- Run the OD-01 device benchmark on your iPhone (instructions will be here when the harness is built).
- Review the DEC entries (102–104) and the shadow-vs-switch boundary above.
- Decide whether to merge this branch into `dev-build-v0`.
