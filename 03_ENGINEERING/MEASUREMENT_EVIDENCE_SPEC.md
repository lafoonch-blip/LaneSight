# MeasurementEvidence v1 — spec (OD-00B)
Status: **DRAFT for Shayne's review** · 2026-10-29 · Branch `feat/on-device-analysis` · DEC-102/103
Spec only — **no code until reviewed.** Realizes DEC-092 P3's "timestamped observation interface" combined with
DEC-094 §5's uncertainty contract. It is **one** interface, not a second one.

## 1. Why it exists
Today the pipeline goes `video → measurements (ShotRecord)` and the raw observations are discarded. To run
measurement on-device *and* keep the server as the reference and validator (DEC-102), we need the **observations
layer** to be an explicit, versioned, portable contract that either engine (server Python or device Swift) can
emit and the server can validate, re-score and reprocess. `MeasurementEvidence` is that layer.

```
Capture → MeasurementEvidence → ShotRecord (measurements) → Bowling intelligence → Coaching → Score
 device        device | server          device | server            server            server     server
```

`MeasurementEvidence` sits **under** `ShotRecord`. It does not replace `Measurement` (which already carries
`value / unit / confidence / status / uncertainty / algorithm_version` — DEC-094 §5). It is the *evidence those
measurements were derived from*.

## 2. Core principle (carried from DEC-026/061)
**Observed and predicted are kept strictly separate. A predicted position never counts as an observation.**
The single additive coverage field is **`observed_fraction`** (DEC-094 §5) — the fraction of the trajectory that
was actually observed vs interpolated/extrapolated. No other coverage field may be assumed; any new one must be
explicitly added here and implemented.

## 3. Shape (v1)
A versioned, engine-agnostic record. (Field names are the proposal; exact JSON keys finalized on review.)

```
MeasurementEvidence {
  evidence_version: "1"
  engine: { platform: "ios" | "server", version: <algorithm_version>, build: <api_revision|ios build> }

  coordinate_system: { origin, axes, units, lane_frame_ref }      // how to read every coordinate below

  ball_observations: [ { t, x, y, observed: true,  conf } ... ]   // OBSERVED points only
  ball_predicted:    [ { t, x, y, observed: false } ... ]         // interpolated/extrapolated, NEVER merged in
  observed_fraction: 0..1                                          // the one additive coverage field

  lane: { calibration_source, focal_source, arrows/foul/pins provenance (DEC-065), validity }

  pose: [ { frame, landmarks: [ {x,y,conf} x33 ], model_version } ]  // confidence-gated (DEC-095)

  capture: { fps_nominal, fps_measured, timestamps_real: bool, hdr, bit_depth, vfr, camera_motion }

  sensor: { vendor, observations } | null                          // when present (DEC-021/070)

  eligibility: { <metric>: { eligible: bool, reason } }            // metric-availability, not coaching policy
  uncertainty: { <metric>: ± band }                               // DEC-094 §5; mirrors Measurement.uncertainty
}
```

Each `Measurement` in the `ShotRecord` references the evidence it came from (same `engine` provenance), so a
value can always be traced to observed (not predicted) support and its coverage/uncertainty.

## 4. Device-validity vs server-coaching boundary (DEC-046 — the hard line)
The device may compute **measurement validity**. It must **never** hold coaching policy, owner thresholds, or
verdicts. This table is normative for v1.

| On device: measurement validity (may ship) | Server only: coaching intelligence (never ships) |
|---|---|
| Ball-detection reliability / track confidence | Next-shot moves & lane-transition rules (DEC-061) |
| Lane calibration validity (DEC-065) | Delivery-style expectations, personal baselines |
| Observational sufficiency (`observed_fraction`) | Recommendations, drills, form findings |
| Physical plausibility gates (DEC-061/095) | **Form timing windows → early/on-time/late verdict** (DEC-057) |
| Metric eligibility + unavailable reasons | LaneSight Score formulas, tiers, achievement qualification |
| Uncertainty bands (DEC-094 §5) | Advice finalization state (provisional/low_confidence/ready) |

**Ambiguous case (resolved):** owner-editable form timing windows (DEC-057) are coaching policy → server. The
device reports **raw timings** inside `pose`/`events`; the server issues the early/on-time/late verdict.

## 5. Validation (two separate gates — DEC-103)
1. **Ground truth** — metrics derived from evidence meet the applicable DEC-034 accuracy gates vs Specto where
   available, with the server as the reference engine (DEC-105: Ruby removed from the validation process).
2. **Parity** — device vs server evidence/metrics agree within metric-specific tolerances; status/unavailable
   disagreements are reviewed; reason codes are semantically equivalent (not byte-identical).

The server **re-derives or validates** from submitted evidence before anything counts (auth, ownership, schema,
plausibility, accepted engine version). A client-reported `engine` is for tracing, **not proof** (DEC-103 risk #5).

## 6. Versioning & migration (DEC-103 §6.7)
`evidence_version` is independent of `ShotRecord.schema_version`. The server keeps a compatibility policy:
supported versions, deprecated fields, recalculation where evidence/clips were retained (DEC-100), and quarantine
of outdated/rejected engines so long-term stats never silently mix incompatible measurements.

## 7. Explicitly out of scope for v1 (do not build yet)
- Sensor fusion math (the shape reserves `sensor` so it won't need a breaking change later).
- Smart-glasses capture (the coordinate-system indirection is the only accommodation).
- Any on-device coaching/threshold logic (forbidden — §4).

## 8. Open questions for Shayne
1. Persist full evidence for every shot, or only on failure / low `observed_fraction` / sampling? (storage cost)
2. Is `observed_fraction` per-metric or per-shot? (proposal says one field; per-metric may be needed for form)
3. Retention of evidence vs clips (DEC-100): same 7-day window, or longer for the validation set?
