# Performance Lab: Compare to a PBA Pro — Feature Proposal
Status: PROPOSED — not approved/shipped
Version: 1.0
Last Updated: 2026-10-19
Owner: LaneSight Product

## Goal
Introduce **third Performance Lab entry tile** for comparing a bowler's validated form and (where data exists) shot metrics to a reference performance from a professional PBA bowler. Make this educational, motivating, permissioned and transparent about comparability. Avoid implying there is one universally correct form.

## Performance Lab entry UX
1. **Start Live Session** — Practice / League / Tournament activity type, then select **Shot Analysis** or **Form Analysis** according to DEC-040.
2. **Upload Video to Analyze** — choose Shot/Form mode, existing session or new session, single or multiple uploads.
3. **Compare to a PBA Pro** — select pro reference, then reuse eligible previously analyzed video/shot OR record/upload a new **Form Analysis** clip; optional Shot Analysis/compatible sensor telemetry for speed/rev comparison.

Preserve activity type separate from analysis mode. One perspective per recording; do not require synchronized dual cameras. Active live session opens back to in-progress activity instead of gating every tap with a choice.

## Compare flow
- Performance Lab → Compare to PBA Pro → browse/search pro reference catalog (style, handedness, one-/two-handed, profile and available reference angles; do not assert partnership) → pick validated reference clip.
- Choose "My latest comparable form session", another session, or "Record / Upload". Offer camera-placement guidance to match reference angle; explicitly flag when an angle mismatch undermines numerical interpretation.
- Side-by-side synchronized (by common event landmarks: approach start, pushaway, top of swing, slide, release, follow-through) user/pro clips where rights permit. Speed controls and optional annotated keypoints / skeletal overlays, only if pose validation supports it.
- Metric rows: Pro / Me / Delta / quality/source / conditions; show available pose metrics (approach duration, cadence, step timing, pushaway-to-release, swing timing, posture, knee angle, slide timing) and speed/revs **only when independently measured with comparable definitions and context**.
- Insights focus on differences and trade-offs ("Your pushaway starts later relative to step 2"), not superiority or a prescribed imitation. Personal baseline and coach-set goals remain distinct; a pro comparison is an optional reference, **never a scoring baseline**.
- Save comparison snapshots, selected pro/reference clip and analysis version in progress history; prompt "Make this a practice goal" with user review or coach approval.

## Candidate catalog approach
- Curated small pilot catalog (3–5 distinct style archetypes) rather than ranking all top PBA bowlers. Candidate examples to assess licensing and availability: EJ Tackett, Jason Belmonte, Anthony Simonsen, Chris Via, and other willing professionals; **no rights or quantitative biomechanical stats assumed**.
- A public player profile is not a grant to copy, host, modify, annotate or commercially reuse footage, portraits, voice, official PBA marks, or imply endorsement.
- Rights-first preferred: direct opt-in player/agent/coaching collaborations licensing specific form clips and analysis usage. If not obtained, use own filmed consenting coaches or volunteer advanced bowlers; show "Compare to Elite Bowler" rather than mislabel as licensed PBA content.
- For official PBA brand/marks and footage, investigate appropriate league/broadcast/rights-owner license. PBA states it controls its name, trademarks and logos; video broadcasts may have separate rights holders. Never scrape and rehost third-party video without permission.
- Link to original externally hosted video where permitted is not equivalent to possessing annotation/reprocessing rights.

## Minimum ProReference data contract
`pro_id`, display_name, handedness, delivery_style, consent/licensing status, authorized portrait/reference-video asset IDs, rightsholder, territory, expiration, permitted uses, clip version, source URL, camera angle, fps, timestamps, distance/calibration, lane context (when known), ball/sensor and metric provenance, pose/shot observations, event landmarks, metric definitions, confidence/uncertainty, sample count, analysis model version and QA approval.
Require rights+quality checks at publishing time and unpublish/expire assets when license ends.

## Metrics / comparability
| Comparison | Input required | Ship status |
|---|---|---|
| Approach total duration / step count | both videos, visible full body, frame timestamps | pilot candidate; validate |
| Cadence, step timing, pushaway, swing timing, release timing | compatible full-approach angles, event detection | planned; no fabricated values |
| Posture, shoulder alignment, knee flex, slide timing | calibrated views + validated pose landmarks | planned / angle-conditional |
| Ball speed | shot video or supported sensor for both, same headline definition (DEC-036 60-ft average; release speed explicitly separate) | optional only where defensible |
| Rev rate | observable pattern or supported sensor, uncertainty and source disclosed | optional; no public pro rev claims without measured evidence |
| Axis tilt/rotation and PAP | authorized sensor data or specialized validated capture | later optional |
| Score or LaneSight Score against pros | not comparable across datasets | **do not offer as head-to-head score** |

For style variance, compare normalized event timings (% approach duration) as well as absolute seconds. Allow left/right mirrored display but clearly label mirroring. Match one- versus two-handed and approach step count as filters, not mandatory exclusions.

## Feedback, safety and privacy
- Compare-to-pro is a **diagnostic learning reference**, not proof a user's delivery is objectively deficient. Emphasize functional outcomes, comfort, and personal/coach targets.
- Do not automatically alter the one LaneSight Score (DEC-041) based on similarity to a pro; no new Improvement Score.
- Users retain opt-in ownership/controls for shared video; pro reference video and derived landmarks follow licenses; minimize face/biometric retention and avoid unauthorized recognition of bystanders.
- Each unavailable or estimated metric must explain why. No pro synthetic stat or misleading coach endorsement.

## MVP / phases
**Design MVP (uncommitted):** third tile; small rights-cleared catalog; own-session selection; side-by-side playback, event synchronization, a limited validated form-metric subset, source badges and manually curated coaching observations.
**MVP+ candidate:** annotated pose overlays, reliable normalized timing comparisons, saved comparison history, personal/coach goal links.
**Later:** opt-in paid athlete collaborations, broader pro inventory, speed/rev comparisons from vetted sensor+video references, multi-angle views.

This feature is **new proposal** and must not be assumed to supersede DEC-035 Practice-only capture limits or distract from approved MVP shot accuracy, nor silently alter DEC-040's two analysis modes. If accepted, add a new DEC and new BUILD_PLAN tasks while preserving history.

## Acceptance checklist
- Reference clip licensed/owned for intended display, analysis and distribution.
- Both recordings clearly identify camera quality and comparability; mismatch degrades to qualitative/disabled metrics.
- Reproducible synchronization (<100 ms median event offset proposed; establish validation ground truth).
- No fabricated metrics; every metric shows provenance, confidence and common units.
- Correct side-by-side playback and user controls; deletion/unpublishing handles license expiry.
- Device/connection performance meets approved SLO document.
- Accessibility: readable charts, clear color-independent differences, captions and playback speed.
- User study: comparisons are understandable and produce useful coaching questions rather than inappropriate imitation.

## Legal / rights starting references (review with counsel)
- https://www.pba.com/faqs — PBA's stated control of name/trademarks/logos.
- https://www.pba.com/players — official player directory/reference discovery; **not an authorized quantitative pose feed**.

## Claude handoff
Prototype the third Performance Lab tile and full comparison workflow in Figma; inspect existing UX/components. Review the current form tracking implementation/validation gaps, rights feasibility and realistic reference production costs. Present proposed DEC and build-plan impact **before implementation**.
