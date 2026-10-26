# Metric-to-Screen Spec (MVP target state)
Status: APPROVED (Shayne, 2026-10-26) · Version: 1.0 · Last Updated: 2026-10-26 · Owner: Shayne
Decisions: DEC-073 (this hierarchy), DEC-061 (status chips, moves), DEC-066 (strike only), DEC-070 (no sensors), DEC-072 (session end).

## Rules
1. **Show a metric only where it explains performance or drives a decision.** Everything else stays in the data and in expanded details.
2. **Variation next to averages.** Session and Stats views show spread (± robust SD, DEC-032) beside every average.
3. **Every summary ends in one takeaway** from the rules engine (template text, DEC-046), never a generic paragraph.
4. **Status chips everywhere:** MEASURED / BEST EFFORT / UNAVAILABLE (DEC-061). UNAVAILABLE never shows a number.
5. **No invented composites.** No Session Score, no Form score, no carry until each is defined in a DEC.
6. **Comparable shots only** for session accuracy and consistency (same ball config and target line, DEC-032).

## Priority by moment
P = primary (always visible) · S = secondary (expanded or lower on the screen) · — = not shown

| Metric | Shot card | Shot session summary | Form results | Form session summary | Stats tab |
|---|---|---|---|---|---|
| Strike / not strike / not read (DEC-066) | P | P (strike %) | — | — | Shot (strike %) |
| Lane picture: target vs actual line | P | S (lane transition) | — | — | — |
| Next move (boards) / next-shot state | P | — | — | — | — |
| Speed (60 ft avg) | P | P (avg ± spread) | — | — | Shot |
| Rev rate | P (best effort) | P (avg ± spread) | — | — | Shot |
| Accuracy (DEC-031) | P (when target set) | P | — | — | Score, Shot |
| Consistency (DEC-032) | — | P | — | — | Score |
| Pocket % (entry board 16–19) | S | P | — | — | Shot, Equipment |
| Entry angle | S | S (early vs late) | — | — | Shot |
| Entry board | S | S | — | — | Shot (distribution) |
| Breakpoint board + distance | S | S | — | — | Shot |
| Laydown, arrows board | S | S | — | — | — |
| Loft | S | — | — | — | Shot |
| Impact energy (DEC-024) | S (best effort) | — | — | — | Shot |
| Early vs late trend per metric | — | P (sparklines) | — | P | — |
| By ball / by oil pattern | — | S (when 2+ balls) | — | — | Equipment |
| LaneSight Score + tier | — | S (compact row → popup) | — | — | Score |
| Score parts (4 pillars) | — | popup only | — | — | Score |
| Focus + drill (one) | — | P (takeaway) | P | P (takeaway) | Form (history) |
| Timing checkpoints (pushaway, top of swing, release) | — | — | P | P (release timing ± spread) | Form |
| Approach time, steps, ball-start step | — | — | P | P (± spread) | Form |
| Swing time vs baseline | — | — | P | P | Form (phases by session) |
| Foul line distance | — | — | S | S | — |
| Spine tilt, follow-through | — | — | S (best effort) | S | Form |
| Drift, balance arm, shoulders | — | — | S (needs rear/front view) | — | — |
| Metric coverage (% measured) | — | S (shots measured) | — | — | Shot |

## Data and fallback
| Metric group | Needs | Fallback |
|---|---|---|
| Far-lane (breakpoint, entry board/angle, late speed) | Validated far-lane geometry (DEC-065) | UNAVAILABLE with camera tip; no move given |
| Rev rate | Readable surface period (DEC-027) | BEST EFFORT with ± band, or UNAVAILABLE |
| Accuracy | Target line set at setup or on the session screen (DEC-071) | "Set a target to measure accuracy" (never 0) |
| Consistency | 5+ comparable shots (provisional), 10 normal | "Building consistency" |
| Strike result | Settled deck visible | "Not read"; bowler can mark Strike / Not a strike |
| Form timing | Side view, full bowler in frame | UNAVAILABLE + camera tip |
| By ball / pattern | 20+ shots per row | Shown with "small sample" |

## Not in MVP
Carry, game scores, spares, leaves (DEC-066) · sensor metrics and variance (DEC-070) · knee flexion · shot↔form "intelligence layer" (post-MVP, worded as association, not cause) · Session Score · Form score.

## Updates in v0.2 (approved in v1.0) (DEC-076, DEC-077, DEC-079, DEC-080, DEC-081)
- **Shot flow (DEC-080):** stop recording → Analyzing screen → Shot card. The Shot card offers Close (to Active Session) or Record next shot.
- **Active Session (DEC-079):** latest shot first (lane picture with pin result, target, pocket entry and lane reaction labeled separately; recap and next shot), then Speed · Rev rate · Accuracy · Consistency, target line, and collapsed Shot history and Lane transition. The second ring row moved to Stats.
- **Recommendations:** move → Why (evidence) → Expected effect.
- **LaneSight Score (DEC-077):** MVP uses the DEC-048 formula, labeled provisional. Performance shows pocket % and entry angle in 4–6°; Power shows entry speed, rev rate, entry angle and ball weight.
- **Session summary:** What went well / What to improve / Next practice focus, then "This session vs your typical" (only with enough comparable shots).
- **Metric detail screens (DEC-081):** every Stats › Shot tile opens average, spread, range, coverage, trend by session, by ball and by oil pattern; small samples labeled.
- **Form (DEC-076, DEC-081):** the view is detected (side or behind) and the metric set follows it; metrics the view can't see show the view they need. No ball or oil for Form. Timing is judged against the bowler's baseline.
