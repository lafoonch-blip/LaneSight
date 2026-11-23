# Server measurement retirement plan (DEC-133)

Status: ACTIVE · Version: 1.0 · Last Updated: 2026-11-23 · Owner: Shayne
Decision: **DEC-133** (one product engine: on-device; retire the server measurement path **per metric** as each ships
on device and passes its DEC-118 gate). **No server code or services are removed in this pass** — this is the plan +
the ordering. The Python reference engine **stays** as the dev/validation harness (DEC-106). The Supabase backend
(auth, data, sync, server-authoritative Score/tiers/achievements/coaching) and DEC-103 submission validation stay.

## How to read this
- **On-device status** — where the on-device engine is today (ships / partial / not yet). The authority for the Shot
  metrics is Session 1's DEC-132 coverage work + the live numbers in `STATUS.md` (22 labeled clips, ±0.5 mph gate),
  not this file; update here when that moves.
- **Gate** — the metric's DEC-118 bar it must clear on device before the server path is retired for it.
- **Server role today** — what the server still computes for this metric in the product flow.
- **Retire-when** — the condition that lets us turn the server path off **for that metric**. Until then the metric
  shows on-device where it passes and is `unavailable` + reason where it doesn't — never a server-fallback number
  (DEC-133 removes the fallback) and never an estimate (DEC-026/027).

## MVP metrics (DEC-118)

### Shot
| Metric | On-device status | Gate (DEC-118) | Server role today | Retire-when |
|---|---|---|---|---|
| Ball speed (60 ft avg) | Partial — iPhone 4/22 within ±0.5 mph, 0 wrong (STATUS) | ±0.5 mph vs truth on the 22-clip set; <30 s | Production classical engine (8/22) as reference/shadow only | On-device ≥ server coverage on the 22-clip gate with 0 wrong |
| Rev rate | best_effort both engines — no ground truth | Blind-validate the 1.12 factor at 120/240 (DEC-094 §4) or remove | Reference/shadow | A validated rev factor + a ground-truth source; else stays best_effort on-device and server path is dropped too |
| Entry board / breakpoint (far lane) | Not reliable on either engine (far-lane track) | Board accuracy that doesn't flip advice (±2 boards) | Reference/shadow | On-device far-lane track + board accuracy gate passes |
| Laydown / launch angle | Needs confirmation (Session 1) | DEC-118 angle tolerance | Server computes it today | On-device port passes the angle gate |
| Observed ball path | Partial (on-device trajectory) | Path within tolerance of the full-rate run (DEC-094) | Server computes the fitted path | On-device path matches within tolerance |
| Strike / not-strike (DEC-066) | Needs confirmation (Session 1) | Correct on the labeled set | Server classifies today | On-device classifier passes |
| Pin contact `t_pins` (DEC-132) | Shipping — on-device changepoint shipped; learned CoreML fallback finishing to a 22-clip parity gate | ≤4 frames median; ENGINE_DISAGREE guard (0 plausible-but-wrong) | Reference/shadow | On-device passes the 22-clip parity gate |

### Form (on-device via MediaPipe, DEC-129 / DEC-131)
| Metric | On-device status | Gate (DEC-118) | Server role today | Retire-when |
|---|---|---|---|---|
| Step count | Ships — best_effort, plausibility-bounded | ±1 step on the Form label set | — (on-device) | Blind Form set confirms (next 60 fps clips) |
| Approach duration | Ships | timing within tolerance | — | Blind Form set confirms |
| Swing-timing events (E2–E8) + release-vs-slide | Ships — plausibility-bounded; delivery-isolation gate | event frames within ±2 of labels | — | Blind Form set confirms |
| Tempo / rhythm consistency | Ships | ratio within tolerance | — | Blind Form set confirms |
| Timing checkpoints + swing-timing baseline comparison | On-device engine submits events/metrics; **server still computes the checkpoint/baseline math on `/shots/metrics`** | n/a (derived, baseline-dependent) | Server computes checkpoints + baseline deltas | Port the checkpoint/baseline math on device (or keep it as server-authoritative derivation like Score — decide per DEC-133) |

> Note: the Form **Score, tiers and coaching policy stay server-authoritative** (like all of LaneSight's scoring) — that
> is NOT measurement and is out of scope for retirement. Only the *measurement* of the raw metrics moves/stays on device.

## Removal order (when the last MVP metric has shipped + passed its gate — NOT this pass)
1. **App flow:** stop routing capture to upload-for-analysis; the on-device result is the only measurement path.
   (On-device primary is already the default — DEC-126 — so this is removing the fallback branch, not adding a path.)
2. **API:** retire the `/jobs` analysis + upload-for-analysis endpoints for measurement. Keep `/shots/metrics`
   (submission of on-device results), auth, data, Score/coaching, and DEC-103 validation.
3. **Cloud Run:** decommission the analysis service once no client calls it. (Irreversible — Shayne's call; only
   Session 1 deploys/decommissions.)
4. **Retention:** diagnostic clip retention (DEC-100) is already opt-in consented upload of failed/flagged clips
   under DEC-133/DEC-104 — keep that path for debugging, it is not "server measurement".

## Withdrawn from the queue (DEC-133 extends the DEC-117 freeze to all metrics)
- Any in-progress **server-only** CV/perf measurement task (DEC-116 leftovers, anything labeled "server-speed").
  These are **withdrawn** — not because the problem is solved, but because the product no longer measures on the
  server. The equivalent accuracy work continues **on device** (developed/graded first in the Python harness per
  DEC-106, then ported — Session 1's coverage stream).
