# iPhone-primary switch for live shots (DEC-126)

Status: PLAN + increment 1 · Date: 2026-11-02 · Owner: Shayne

## Decision (DEC-126)
The on-device iPhone engine becomes the PRIMARY measurement path for **live** shots; the server becomes the
shadow/reference. The switch is gated on **usability only** — a crash or a result slower than **30 s** — never on
accuracy or iPhone↔server parity (those are tuned after the switch). Honesty rules (DEC-086/122) still apply
on-device: an unmeasured metric is `unavailable` + reason + failing stage, never fabricated.

## What the on-device engine produces today (`OnDeviceShadow.run`)
`ball_speed`, `speed_avg_foul_to_pins`, `rev_rate` (+ sigma) as `best_effort`; a `basis` (best_effort|unavailable);
a `note` (honest reason when unavailable); `latency_s` (the 30 s guardrail signal); and a per-stage diag
(`first_failing_stage`, stage_ms). It does NOT produce: the LaneSight Score, insights/coaching, boards/entry
angle/loft, or the lane render. Those are server-authoritative (DEC-102/092) and stay so.

## Target live-shot flow (flag `ls.ondevice_primary`, default OFF until shipped)
1. Capture → trim (unchanged).
2. **Run the on-device engine on the trimmed clip FIRST**, with the DEC-126 guardrail:
   - **crash** (engine throws) → fall back to the server-primary flow (today's path).
   - **latency > 30 s** → fall back to the server-primary flow.
   - otherwise → the on-device result is PRIMARY.
3. Show the on-device measurements **immediately** (speed / rev rings), with the honest `basis`/`note` for anything
   unavailable. Provenance: the result is tagged `engine: iphone`.
4. In the background, still upload the clip to the server. The server (a) computes the **Score + insights +
   coaching** (today these are session-level + record-driven; near-term they are computed from the SERVER
   analysis, which also serves as the **shadow/reference** for parity), and (b) stores the DEC-122 outcome rows
   for BOTH engines. When the server result returns, the card fills in Score/coaching around the on-device
   measurements — the measurement rings do NOT change (iPhone is primary).
5. Offline / server-unreachable: the on-device measurements still show (primary); Score/coaching show "pending"
   and backfill when connectivity returns. A shot is never blocked on the server.

## The one open fork (flag the choice; default = B)
How do Score/coaching get the measurement when iPhone is primary?
- **A — server re-analyzes (current):** the server runs its own CV and scores from THAT. Simplest (no API change),
  but the Score can disagree with the displayed on-device measurement until parity work lands. Server CV = shadow.
- **B — server scores from the on-device measurement:** the app posts the on-device metrics; the server scores
  from them (the displayed number and the Score agree) and still runs its own CV as the shadow/reference. Needs a
  small server endpoint change. **Recommended** (the user sees one consistent number), but a follow-up.
Increment 1 ships with **A** (no server change; on-device measurement is displayed, server scores from its own CV
as today) so the switch is testable immediately; increment 3 moves to **B**.

## Increments
1. **Foundation (this change):** `AppModel.onDevicePrimary` flag (default off; TestFlight/dev overridable) +
   the 30 s / crash guardrail constants + engine-provenance plumbing. No behavior change for real users (flag off).
2. **Primary routing:** when the flag is on + guardrail passes, run on-device first and drive the ShotResult's
   displayed measurement metrics from it (server still provides Score/coaching = option A). Pipeline state +
   ResultView badge show "measured on iPhone". Fallback to server-primary on crash/>30 s.
3. **Server scores from on-device (option B):** post the on-device measurement; server scores from it + keeps its
   own CV as the shadow. One consistent number.
4. **Parity tuning (post-switch, DEC-126):** use the DEC-122 `ops.engine_metric_agreement` view + the 11/1 /
   validation sets to close iPhone↔server speed/rev deltas IN PLACE. No gate blocked the switch; this is the
   follow-on accuracy work.
5. **Per-session lane setup (DEC-126 item 3, queued):** 4-tap lane calibration stored on the session, used by
   both engines instead of auto-detection — validated on the 7 centered-behind-ball-return clips (12/6 split) via
   a new Labeler `lane_setup` task. Do NOT start before the switch ships.

## Guardrail constants
`ONDEVICE_PRIMARY_MAX_LATENCY_S = 30.0`. Crash = any throw from the engine. Both → silent fallback to server
-primary (logged as `ondevice_fallback` with the reason, so fallbacks are countable). No accuracy threshold.
