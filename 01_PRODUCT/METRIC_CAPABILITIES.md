# Metric Contract — status, evidence, display and coaching eligibility
Status: CANONICAL
Version: 2.0
Last Updated: 2026-11-23
Owner: Shayne
Supersedes: v1.0 "Metric Capabilities: capture tiers and sensor pairing" (the 4-shot "Guaranteed/Best effort" capture-tier matrix, retired). The capture-tier framing is history; the live truth is the contract below.

**Purpose.** One contract for **every MVP metric**: its runtime **status**, the **evidence** behind it, whether it may be **displayed**, and whether coaching/insight logic may **act on it**. This replaces the old capability matrix. It is the honesty backstop referenced by the design README build rules and `03_ENGINEERING/APP_DESIGN_CHANGES.md`.

**Authority.** Formulas and governing decisions live in `01_PRODUCT/METRIC_AND_SCORING_LOGIC.md` and `00_CONTEXT/DECISIONS.md` (highest DEC wins). This table states eligibility, not formulas; where they disagree, the DEC wins and this page is fixed. Live product/engine status is `STATUS.md` on the `context` branch.

---

## Status vocabulary (one set, used in every doc and in the UI)
There are exactly four statuses. Do not invent others; "Guaranteed" is retired everywhere.

- **measured** — produced from *this shot's own data* with a plausible, internally-consistent result (engine status `ok`). Per DEC-127, honesty is a per-shot property, not a validation-against-truth property: a measured metric counts toward the LaneSight Score exactly like a server-measured one. "Measured" does **not** mean "validated against ground truth" — that is a developer build gate (DEC-127), tracked separately in the **Evidence** column.
- **best_effort** — produced, but the method is known to approximate (e.g. the foul→pins *average* speed approximates the impact frame, DEC-112) or the scale/conversion is not yet independently validated (e.g. the rev-rate conversion factor). Always shown with a caveat; excluded from any Score component whose precision gate it fails (DEC-028/038).
- **unavailable** — could not be measured on *this* shot (track too short, foul crossing extrapolated > 6 ft, far lane not read, implausible value). Carries a `reason_code` + the failing stage (DEC-122). **Never a number.**
- **disabled** — intentionally gated **off by policy** for *every* shot pending validation (e.g. far-lane metrics while `FAR_LANE_VALIDATED=False`, DEC-065). Distinct from per-shot `unavailable`. **Surfaces to the user as the UNAVAILABLE treatment** with a policy reason — the UI still shows only three chips (MEASURED / BEST EFFORT / UNAVAILABLE); `disabled` is the documentation/engine status that maps to UNAVAILABLE.

## Two binding rules (also in the design README)
1. **Coaching acts only on metrics marked coaching-eligible below.** Next-shot moves, insights, form cues and Score inputs never derive from an `unavailable`, `disabled`, low-confidence, or non-coaching-eligible metric (DEC-094 #5 uncertainty contract).
2. **The lane path is drawn only where the ball was observed.** Fitted/smoothed/extrapolated segments must never look measured; when the far lane is not read, the path stops at the last measured distance and the lane beyond it is dimmed (DEC-065, APP_DESIGN_CHANGES 2026-11-02(b)).

## Fail-closed eligibility
A metric with **no documented validation evidence**, or with **ambiguous eligibility**, is **NOT coaching-eligible** — full stop. "Implemented in the engine" is never sufficient; there must be documented evidence it is reliable enough to act on, and it must not be gated. Display eligibility is separate and more permissive (an honest `best_effort` value may be shown with its caveat even when it is not coaching-eligible).

> **Measured ≠ coaching-eligible.** DEC-127 makes a *measured* on-device metric a Score input; the fail-closed bar here governs whether the **coach/insight engine** may act on it. Where today's coaching or Accuracy logic acts on a metric this contract marks not-coaching-eligible, that conflict is logged as an OPEN item on the `context` branch INBOX for Shayne to reconcile (see "Open conflicts" at the bottom) — this doc does not change engine behavior.

---

## 1. Shot (ball / lane) metrics
Live engine = on-device (DEC-126/127); the Python server engine is the non-production dev/validation harness (DEC-106). On-device accuracy is graded against Shayne's labels (foul-cross → first pin contact); the server engine is **not** a benchmark (no ground-truth guarantee) — do not compare on-device to server/Ruby.

| Metric | Status | Evidence (reference method · sample · error) | Display-eligible | Coaching-eligible |
|---|---|---|---|---|
| **Ball speed — foul→pins average** (headline) | **best_effort** (method approximates the impact frame, DEC-112) | On-device vs labeled truth, 22 clips: **5/22 within ±0.5 mph, 0 plausible-but-wrong, MAE 0.166**; the other 17 honestly withheld (DEC-118 capture-position limit). Server dev harness: median 0.52 mph at the ±0.5 gate. | Yes, with best_effort caveat | **Relative only** — coach may compare to the bowler's own baseline (not an absolute-accuracy claim). Not a Score input (DEC-127). |
| **Speed — release / early (skid)** | **best_effort** | No independent ground truth (STATUS: early-lane speed best_effort). Server reference reads ~9% low from a near-field Z-scale residual. | Secondary, with caveat | **No** (fail-closed: no validated truth). |
| **Entry / pocket speed** (`speed_late`) | **disabled** (far lane, DEC-065) | Far-lane read gated off until Phase-2 validation (`FAR_LANE_VALIDATED=False`). | No → UNAVAILABLE ("Not read") | No |
| **Rev rate** | **best_effort** (DEC-027/028) | No ground truth. Conversion factor `REV_SENSOR_FACTOR=1.12` fitted on 4 shots; **blind validation pending**. Reports a ±band; `unavailable` at the search-band rail. Server reference median 14 rpm at the ±30 gate (not independent). | Yes, with ±band, best_effort | **No** (fail-closed: conversion factor not blind-validated). ⚠ Conflict with the shot-card coach matrix — see Open conflicts. |
| **Entry board** | **disabled** (DEC-065) | Far-lane gated off until Phase-2. | No → "Not read" | No |
| **Entry angle** | **disabled** (DEC-065) | Far-lane gated off until Phase-2. | No → "Not read" | No |
| **Breakpoint board + distance** | **disabled** (DEC-065) | Far-lane gated off; geometric only, **never** equated to a sensor rotational breakpoint. | No → "Not read" | No |
| **Laydown board (+ distance past foul)** | **measured** when near-lane geometry is consistent, else **unavailable** | Near-lane recovery; **no Specto board-accuracy gate yet** (DEC-034 pending). | Yes (near lane) / UNAVAILABLE + reason | **No** (fail-closed: board accuracy not yet validated, DEC-034). |
| **7 ft board** | **measured** / **unavailable** | As laydown; DEC-034 pending. | Yes / UNAVAILABLE | **No** (DEC-034 pending). |
| **Arrows board (15 ft)** | **measured** / **unavailable** | Near-lane; feeds Accuracy (DEC-031). **Board-accuracy gate pending Specto (DEC-034).** | Yes / UNAVAILABLE | **No** (fail-closed, DEC-034 pending). ⚠ Accuracy pillar + lane-move coach act on it today — see Open conflicts. |
| **Launch angle** | **best_effort** (low confidence) | Low confidence everywhere so far. | Secondary, with caveat | No |
| **Loft** | **unavailable / disabled** for MVP | Needs ≥60 fps per-frame touchdown; server reference ±0.45 ft at 60 fps. Not in the DEC-118 on-device MVP metric set. | No unless produced + validated | No |
| **Pins / strike / leave** | **disabled** on the live far-lane-gated path ("Result not read"); **measured** only when the deck is readable and validated | DEC-026 reads the settled deck, `unreadable` (not guessed) when occluded or clipped early. Pins sit at the far lane, so they are gated with the far lane today. | "Result not read" while gated | No (while gated) |
| **Pin contact time** (`t_pins`, DEC-132) | **measured** — internal timing input, **visual** temporal classifier, never audio | On-device PinContactDetector ported (v17): 5 covered / 0 wrong on the 11/1 set. | Not displayed (internal input to speed) | n/a (an input, not a coached metric) |

## 2. Composite scores and derived pillars
| Metric | Status | Evidence | Display-eligible | Coaching-eligible |
|---|---|---|---|---|
| **LaneSight Score** `L` / dev `L-dev-0` | **disabled** (spec-only) | DEC-038 Power & Carry `P` normalization **undefined**; dev formula `L-dev-0` (DEC-048/077) is spec-only, not built. Never fabricate an `L`. | "Building your LaneSight Score" / provisional label only | n/a (it is the score, not an input) |
| **Performance** `S` / `S'` | **spec-only / unavailable** | DEC-037/038; `S` needs game scores not collected in MVP; `S'` (DEC-048) spec-only. | Building / unavailable | n/a |
| **Accuracy** `A` | **best_effort** (arrows-only, low-confidence while breakpoint is gated) | DEC-031; 5-/8-board scales + 60/40 weights **provisional, validate before release**; breakpoint far-lane gated → arrows-only, low-confidence. No target → "Set a target line", never 0. | Ring shown (muted when low-confidence) | Depends on arrows board, which is not yet board-accuracy-validated (DEC-034) → **fail-closed** until reconciled (Open conflicts). |
| **Consistency** `C` | **measured** on available components | DEC-032; excludes any component whose precision misses its target (e.g. rev at 60 fps), never counts it as zero spread; <5 comparable shots → "Building consistency". | Shown at ≥5 comparable shots | Repeatability signal; acts only on the measured components. |
| **Power & Carry** `P` | **disabled** (undefined) | DEC-038 formula not approved; **never** substitute Impact Energy joules, `P=0`, or a reweight. | Unavailable | No |
| **Power → Impact Energy** `E` (joules) | **best_effort** | DEC-024 `E=½mv²` from ball weight + entry (pocket) speed; entry speed is far-lane-gated today, so `E` is often unavailable. Translational KE only. | Shown when both inputs present | Tooltip/context only; **never** "more power = more strikes". |
| **Session Score** | **disabled** (spec-only) | DEC-038 aggregation TBD; never grants an overall tier. | Unavailable | No |

## 3. Form metrics (DEC-118 / 121 / 129 / 131)
Live engine = on-device MediaPipe Pose (DEC-129); plausibility-bounded (DEC-131); directional, not exact (DEC-086).

| Metric | Status | Evidence | Display-eligible | Coaching-eligible |
|---|---|---|---|---|
| **Swing events** (E2 ball start, E4 top of backswing, E7 release, E8 slide stop) | **measured** where detected, else **unavailable** | On-device parity gate vs human labels **±2 frames**; 8825 (side) + 8846 (rear) fully pass; **E2 null on all labeled clips** (reference ceiling, DEC-120); plausibility-bounded (DEC-131). | Shown per position | Event-timing cues eligible **only where within tolerance**; E2 / mis-segmented cases → unavailable. |
| **Swing timing / rhythm** (backswing, downswing) | **measured** / **best_effort** | Derived from events; compared to the bowler's baseline. | Shown vs baseline | Eligible where the underlying events are measured. |
| **Step count** | **best_effort** (DEC-121) | ±1–2 on labeled clips; exact on 0–2/6; phone-pose foot-landmark signal floor; **not validated to exact on either view**. | Shown as BEST EFFORT | **No** (fail-closed: not validated). |
| **Approach duration / timing** | **best_effort** | Derived from events. | Shown | Eligible where events measured. |
| **Drift** | **unavailable** | No floor calibration. | UNAVAILABLE + reason | No |
| **Slide length** | **unavailable** | No floor calibration. | UNAVAILABLE + reason | No |
| **Posture / finish, balance, key-position angles** | **best_effort** (DEC-086: directional, not exact) | MediaPipe pose; confident joints only; low confidence → no overlay, labeled. | Shown with the "directional, not exact" disclaimer | Directional coaching only (DEC-086). |

## 4. Game / scoring stats (DEC-020)
| Metric | Status | Evidence | Display-eligible | Coaching-eligible |
|---|---|---|---|---|
| **Strike %, spare %, average, high, 9-or-better %** | **measured** from pin reading + manual correction, where pins are readable | DEC-020 (all sessions, not league-only). Pins sit at the far lane, so while the far lane is gated (DEC-065) these may be unavailable until the user corrects them. | Shown when available / correctable | Stats surface, not a per-shot coached metric; feed `S`/`S'` once pinfall exists (spec-only today). |

---

## Open conflicts (logged on the `context` branch INBOX, 2026-11-23)
These are places where current coaching/Score logic acts on a metric this fail-closed contract marks not-coaching-eligible. They are **decisions for Shayne**, not changes made here.
1. **Rev rate** — contract: not coaching-eligible (factor not blind-validated). Shot-card coach matrix (APP_DESIGN_CHANGES 2026-10-27-A) uses revs as a throw-classification input. Reconcile: blind-validate rev before it drives coaching, or document that the coach's rev use is relative-to-own-baseline only.
2. **Near-lane boards (arrows/laydown)** — contract: not coaching-eligible until the Specto board-accuracy gate (DEC-034) passes. The Accuracy pillar (DEC-031) and the lane-move coach already act on the arrows board, and DEC-127 makes measured on-device boards Score-eligible. Reconcile the DEC-127 (measured = Score-eligible) vs fail-closed-coaching tension.
3. **Headline speed definition** — DEC-030 (release) vs DEC-064 (60 ft foul→pins average) headline conflict is still open (tracked in METRIC_AND_SCORING_LOGIC / CURRENT_STATE); Phase-2 Specto settles it.

## Notes / next steps
- Replace the remaining provisional parameters (Accuracy 5/8-board scales + 60/40 weights; rev conversion factor) with blind-validated values before any "validated" claim reaches users (DEC-034).
- Far-lane metrics stay `disabled` until DEC-065 lifts (`FAR_LANE_VALIDATED` → true) after Phase-2 validation; when it lifts, flip entry board/angle, breakpoint, entry speed and pins here in lockstep.
- Sensor pairing (release physics from Ruby/F5/Witsee) is **parked post-MVP** (DEC-070); its metric mapping, when it returns, is additive and carries the same four statuses + a source label.
