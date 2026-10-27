# Engineering Handoff — LaneSight MVP (target-state v3.7 designs)
Status: READY FOR PLANNING · Version: 1.1 · Last Updated: 2026-10-27 · Owner: Shayne
Designs: Figma "Lanesight - Product UX - Design" › section **Target state – v3.7** (guide: `02_DESIGN/target_state/README.md`, v3.7.2+)
Decisions: DEC-061, DEC-066–077, DEC-079–082 (DEC-078 withdrawn). Metric placement: `01_PRODUCT/METRIC_TO_SCREEN_SPEC.md` v1.0 (approved).

## 0. Read this first
- This builds on Dev Build v0 (`03_ENGINEERING/dev_build_v0/HANDOFF.md`, designs `02_DESIGN/dev_build_v0/` 3.8). Reuse its API, auth, upload queue and engines; this doc lists **what the MVP designs add or change**.
- Backend is Cloud Run + Supabase (Storage for uploads); the Mac runner is no longer in the loop.
- **Sample numbers in Figma are illustrative.** Never hardcode them. `[Bracketed]` = user data.
- **Status chips everywhere** (DEC-061): MEASURED / BEST EFFORT / UNAVAILABLE. UNAVAILABLE never shows a number; it shows the reason or the view it needs.
- Commit locally; push only when Shayne says. Ask Shayne about anything ambiguous; don't guess.

## 1. Flows (match the Figma prototype; 4 flow starts)
1. **Shot session (DEC-080):** Lab › Shot Analysis › Live session → Setup (last-used ball, oil, target; "Ready to bowl") → Record (tap to start/stop) → **Analyzing (blocking, controls locked, screen kept awake)** → **Shot card opens automatically** → *Record shot N+1* or *Close* → Active Session → End → score popup → Session summary → feedback.
2. **Form session (DEC-081):** Lab › Form Analysis › Live session → Setup (no ball/oil; camera-view guidance) → Record delivery (side or behind; view detected) → Analyzing → Form results → *Record next delivery* or *Close* → Form session → End → Form summary.
3. **Uploads (DEC-069):** Lab › Shot/Form › Upload video → (Shot: ball, oil, optional target; Form: nothing) → result. Not a session; never counts toward Stats, Score, tiers or achievements.
4. **First use (DEC-081):** Welcome → Sign in / Create account → profile (2 steps) → Home (building state). Camera access is explained before the iOS prompt; denied state offers Open Settings or Upload. No Photos permission (PHPicker).

## 2. Screen → data map (new or changed vs Dev Build v0)
| Figma frame (v3.7) | Data it needs | API / source |
|---|---|---|
| Home | score L (provisional), 4 parts each with **score + 30-day change** (no weights on Home, DEC-083), tier, 90-day delta, **next focus**, recent activity | `/me/score` (+ `parts[].delta_30d`), `/me/activity`, **NEW** `/me/focus` |
| Home · score building (DEC-083) / Lab / Stats · first use | per-part eligibility (shots so far vs floor, ready flag), overall unlock %, shots still needed by the slowest part and whether it needs a target | **NEW** fields on `/me/score` (`eligibility`, `unlock_pct`, `shots_needed`, `needs_target`) |
| Lab | sessions (Shot/Form), uploads | `/sessions`, `/uploads` |
| Setup · Shot / Form | last-used ball, oil, target; health; camera checks | `/me/last-setup` (**NEW**), `/health` |
| Record · Shot / Form | spot check; Form: detected view + framing | `/spot-check` (+ `view` for Form) |
| Analyzing (Shot, Form) | job progress, failure reason, retry | `/jobs/{id}` |
| Shot card | result (strike/not/not read), lane picture, next move with **why + expected effect**, rings, metrics with status, notes | `/shots/{id}` (+ `insights.why`, `insights.expected`) |
| Active Session · Shot | latest shot, session KPIs (4), target, history (collapsed) | `/sessions/{id}` |
| Session summary | takeaway **(went well / improve / next focus)**, early vs late, averages ± spread, by ball, **vs your typical**, shots | `/sessions/{id}/summary` (+ `typical`) |
| Score popup | score/tier change, core metrics vs average | `/sessions/{id}/end` |
| Form results (side / rear) | detected view, focus + drill, **key-position thumbnails + landmarks + one measurement each**, timing vs baseline, metrics by view | `/shots/{id}` (form) + **NEW** `key_positions[]` |
| Key position · full frame | full frame, landmarks (confident only), angle + vertical reference, measurements at that position | **NEW** `/shots/{id}/key_positions/{event}` |
| Active Session · Form / Form summary | deliveries, repeatability ± spread, early vs late | `/sessions/{id}` |
| Stats › Score | L (provisional) + parts with inputs (DEC-077) | `/me/score`, `/me/score/history` |
| Stats › Shot + 9 detail screens | avg, spread, range, coverage, trend by session, by ball, by pattern, small-sample flags | **NEW** `/me/stats/metric/{metric}` |
| Stats › Form / Equipment | form trends; by ball / by pattern (≥20 shots) | `/me/stats` |
| States board | upload failed (saved on phone, retry), analysis failed (retry), small samples | client queue + `/jobs` |

## 3. New engineering work items (not in Dev Build v0)
| ID | Work | Acceptance |
|---|---|---|
| MVP-01 | **Key-position capture** (DEC-075/082): during Form analysis, store a JPEG per event (ball start, end of pushaway, top of swing, release) cropped to the bowler, plus event time | 4 frames per delivery; missing event → `not_detected`, never a guessed frame |
| MVP-02 | **Store pose landmarks** per key frame (normalized x, y, visibility) and draw the skeleton client-side; only joints with visibility ≥ threshold | Overlay toggles; low confidence → no overlay + label |
| MVP-03 | **Camera-view detection** (side / rear / front) per Form clip (DEC-076); metric availability by view (FORM_ANALYSIS_SPEC §5.1) | View shown in results; unsupported metrics → UNAVAILABLE with the view they need |
| MVP-04 | **Key measurement per position** (e.g. spine tilt at release from the side, shoulder tilt at release from behind, arm angle at pushaway/top) | Measured from landmarks; status chip; ±1 frame timing noted |
| MVP-05 | **Provisional MVP score** = DEC-048 formula, labeled provisional (DEC-077); eligibility progress per part | Snapshot per recompute with inputs; no reweighting |
| MVP-06 | **Recommendation evidence**: `why` and `expected` text from the rules engine (template text, DEC-046) | Every move has both; no move when not trustworthy (DEC-061) |
| MVP-07 | **"Vs your typical"** comparison (same ball and pattern, last 5 sessions) | Hidden below 3 comparable sessions; labeled otherwise |
| MVP-08 | **Metric detail endpoint**: avg, robust spread, range, coverage, per-session trend, by ball, by pattern, small-sample flag (<20) | Matches Stats tiles |
| MVP-09 | **Last-used setup** (ball, oil, target) prefilled | Changing it updates last-used |
| MVP-10 | **Upload resilience**: failed upload stays on the phone, retries automatically and on demand; no re-recording | Survives app restart |
| MVP-11 | **Analyzing screen**: keep screen awake, lock settings for the clip, auto-open results (DEC-068/080) | Idle timer restored on finish/fail/cancel |
| MVP-12 | **Next focus** for Home from recent sessions (rules engine) | One focus at a time; template text |
| MVP-13 | **First-use states** and camera permission pre-prompt / denied state | Matches Figma row 6 |

## 4. UI rules (from the accessibility pass, 2026-10-26)
- Text ≥ 11 pt for anything a user reads (chart axes and lane-diagram labels may be smaller). Support Dynamic Type up to at least AX1: cards grow vertically, metric tiles wrap to two lines, never truncate numbers.
- Contrast ≥ 4.5:1 for text (3:1 at 18 pt+).
- **44 × 44 pt hit area** for every tappable element, even where the visible control is smaller.
- Layout is designed at 390 pt wide: on 375 pt (SE/mini) metric rings stay 3 across and shrink; on 430 pt (Max) content widens, no extra columns.
- Dark theme only for MVP.
- Shot and Form cards on Home and Lab are equal height (component stretches).

## 5. Open items for Shayne
- Pose model and confidence threshold for overlays (designs used MediaPipe Pose heavy, visibility ≥ 0.5).
- Retention of key-position JPEGs and landmarks (suggest: keep with the shot record; raw clip retention unchanged).
- Push the repo and decide when MVP work starts relative to Dev Build v0 feedback.
