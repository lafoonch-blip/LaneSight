# Performance Lab — Product & Measurement Strategy
Status: APPROVED DIRECTION / REQUIREMENTS DRAFT
Version: 1.0
Last Updated: 2026-10-18
Owner: Shayne
Governing: DEC-040, DEC-041, DEC-038, DEC-039, DEC-034, DEC-035

## Positioning and moat
LaneSight aims to be the most comprehensive trustworthy bowling metrics, statistics and performance-improvement platform for serious bowlers. Differentiate through validated measurement depth, vendor-neutral sensor data, longitudinal shot/form history, explainable insights and coach-validated feedback—not generic scoring parity or unsupported AI claims.

## UX / capture contract
- **Performance Lab** is the primary analytics destination on Home; two prominent CTAs: **Shot Analysis** and **Form Analysis**.
- User chooses **one analysis focus per recording**; no simultaneous two-camera requirement. Allow phone capture and uploaded existing video. Each mode provides framing instructions and quality checks appropriate to its perspective.
- Session activity type (Practice, League, Tournament) is orthogonal to analysis mode. Existing Sessions screen and session history stay intact; sessions show analysis-mode badges and eligible metrics.
- Shot Analysis: rear/lane view; trajectory, speed, rev (when measurable), boards, breakpoint, entry, pinfall, accuracy/consistency, lane transition and equipment context.
- Form Analysis: side/rear bowler view; approach and mechanics. First validate step count, cadence, total approach duration, finish stability; evaluate drift, slide, timing, swing, posture and release in progressively harder phases. Do not promise metrics invisible from the chosen angle or frame rate.
- Session/shot cards label measurement confidence, source, and unavailable reasons; optional sensor connection does not gate video-only usage.

## Unified data / provenance
- Session: `activity_type`, `analysis_mode`, capture metadata; allow later multi-analysis association without demanding synchronized video.
- VideoAsset: perspective, fps, frame timestamps, framing/calibration, consent/retention, original and derivative linkage.
- Measurement: metric, value, units, source (video/sensor/score/coach), confidence/uncertainty, algorithm version, capture view, timestamp, validation state.
- DeliveryEvent/Shot: session identity and time alignment; don't assert one-to-one match between unrelated form and shot clips.
- SensorAdapter: per-vendor optional capabilities and raw-to-normalized provenance. Ruby currently supports manual runner data; SDK/API and commercial access must be verified. Investigate Storm F5, Specto and scoring systems separately.
- ScoringAdapter: center-authorized events, pins, frames, identity and provenance; permissions, licensing and shot-level field access require verification.

## Coaching workflow (post Shot MVP)
1. Bowler records/uploads Form Analysis video.
2. Engine produces only validated measurements plus annotated replay, confidence and limitations.
3. Bowler explicitly shares a selected video/report with coach; controls access/revocation.
4. Coach comments at timestamps, annotates frames, corrects interpretations, assigns drills/goals.
5. Bowler uploads follow-up; compare to own baseline with aligned event landmarks and comparable camera perspective.
6. Evaluate coach feedback and recommendation outcomes; use as training data only with separate explicit consent.

## Single LaneSight Score and achievements
- **One overall score, 0–1000**, no separate Improvement Score. DEC-038: Performance 40%, Accuracy 25%, Consistency 25%, Power & Carry 10%. Form diagnostics do not add a fifth pillar.
- Preserve spec-only state until Power & Carry normalization and all eligibility gates are validated. No fabricated composite/tier or silent missing-data reweighting.
- Historical score line (30d/90d/6mo/1y/all), qualified delta and personal best reflect evolving demonstrated ability. Smooth with recency-weighted performance after separate formula validation; uploads/paid sensors/achievements must not increase score.
- Keep DEC-038 tier thresholds: Bronze, Silver, Gold, Platinum, Onyx (850–1000). Legend remains unapproved. Keep achievements independent per DEC-039; emphasize performance, development and verified accomplishments rather than activity-only awards.

## Roadmap and validation gates
| Stage | Deliverable | Gate |
|---|---|---|
| Current Shot MVP | Stable lane video, honest metrics, sessions and shot record | DEC-034 accuracy/availability and DEC-035 scope |
| Parallel research | Ruby data access, F5/vendor interfaces, center scoring permissions | Documented legal/technical access; no unverified API claims |
| Form prototype | Single-camera pose/approach metrics on uploaded clips | Annotated ground truth, camera-view/fps strata, error and failure rates |
| Performance Lab MVP+ | Mode picker, form session cards, video/baseline comparison | User-tested flow; no dual-camera dependency |
| Coach collaboration | Share permissions, timestamped annotations, feedback/drills | Consent, revocation, privacy and audit checks |
| Advanced intelligence | Measured coaching outcomes, cross-session trends, sensor fusion | Coach review, prospective validation and no unsupported causal claims |
| Growth | Tournament director tools and authorized scoring integrations | Pilot partner approval and actual data contract |

## Design implications
Home hierarchy: compact LaneSight Score + trend and four component breakdowns; **Performance Lab** two equally clear mode cards; development insights; events and recent sessions. Maintain existing brand tokens and familiar session filters. Never present mock score values as implemented results.

## Open decisions
- Form capture framing (side vs rear) and supported metrics by view.
- Metric accuracy targets, test-set splits and minimum clips for form.
- Video retention, sharing permissions, youth/coaching safeguards.
- Sensor import formats/partner terms and shot alignment tolerances.
- Power & Carry normalized formula and recency smoothing for overall L.
