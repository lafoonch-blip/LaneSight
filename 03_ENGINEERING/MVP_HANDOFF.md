# Engineering Handoff — LaneSight MVP (target-state v3.7 designs)
Status: READY FOR PLANNING · Version: 1.7 · Last Updated: 2026-10-27 · Owner: Shayne
Designs: Figma "Lanesight - Product UX - Design" › section **Target state – v3.7** (guide: `02_DESIGN/target_state/README.md`, v3.7.2+)
Decisions: DEC-061, DEC-066–077, DEC-079–085, DEC-088, DEC-090 (DEC-078 withdrawn). Metric placement: `01_PRODUCT/METRIC_TO_SCREEN_SPEC.md` v1.0 (approved).

## 0. Read this first
- **Build queue (DEC-091):** design changes after this doc are tracked as build items in `03_ENGINEERING/APP_DESIGN_CHANGES.md` (NOT BUILT → BUILT). Start there.
- This builds on Dev Build v0 (`03_ENGINEERING/dev_build_v0/HANDOFF.md`, designs `02_DESIGN/dev_build_v0/` 3.8). Reuse its API, auth, upload queue and engines; this doc lists **what the MVP designs add or change**.
- Backend is Cloud Run + Supabase (Storage for uploads); the Mac runner is no longer in the loop.
- **Sample numbers in Figma are illustrative.** Never hardcode them. `[Bracketed]` = user data.
- **Status chips everywhere** (DEC-061): MEASURED / BEST EFFORT / UNAVAILABLE. UNAVAILABLE never shows a number; it shows the reason or the view it needs.
- Commit locally; push only when Shayne says. Ask Shayne about anything ambiguous; don't guess.

## 1. Flows (match the Figma prototype; 4 flow starts)
1. **Shot session (DEC-080):** Lab › Shot Analysis › Live session → Setup (last-used ball, oil, target; "Ready to bowl") → Record (tap to start/stop) → **Analyzing (blocking, controls locked, screen kept awake)** → **Shot card opens automatically** → *Record next shot* or *Close* → Active Session → End → score popup → Session summary → feedback.
2. **Form session (DEC-081):** Lab › Form Analysis › Live session → Setup (no ball/oil; camera-view guidance) → Record delivery (side or behind; view detected) → Analyzing → Form results → *Record next delivery* or *Close* → Form session → End → Form summary.
3. **Uploads (DEC-069):** Lab › Shot/Form › Upload video → (Shot: ball, oil, optional target; Form: nothing) → result. Not a session; never counts toward Stats, Score, tiers or achievements.
4. **Navigation (DEC-084):** four tabs — Home · Stats · Lab · Coaching. Coaching opens a coming-soon screen with Notify me.
5. **First use (DEC-081):** Welcome → Sign in / Create account → profile (2 steps) → Home (building state). Camera access is explained before the iOS prompt; denied state offers Open Settings or Upload. No Photos permission (PHPicker).

## 2. Screen → data map (new or changed vs Dev Build v0)
| Figma frame (v3.7) | Data it needs | API / source |
|---|---|---|
| Home | score L (provisional), 4 parts each with **score + 30-day change** (no weights on Home, DEC-083), tier, 90-day delta, **next focus**, recent activity | `/me/score` (+ `parts[].delta_30d`), `/me/activity`, **NEW** `/me/focus` |
| Home · score building (DEC-083) / Lab / Stats · first use | per-part eligibility (shots so far vs floor, ready flag), overall unlock %, shots still needed by the slowest part and whether it needs a target | **NEW** fields on `/me/score` (`eligibility`, `unlock_pct`, `shots_needed`, `needs_target`) |
| Lab | sessions (Shot/Form), uploads | `/sessions`, `/uploads` |
| Setup · Shot / Form | last-used ball, oil, target; health; camera checks | `/me/last-setup` (**NEW**), `/health` |
| Record · Shot / Form | spot check; Form: detected view + framing | `/spot-check` (+ `view` for Form) |
| Analyzing (Shot, Form) | job progress, failure reason, retry | `/jobs/{id}` |
| Shot card (DEC-088) | result chip; **3D lane view** from the shot data (fitted path, target band, entry + breakpoint labels); lane labels Entry point / Breakpoint / Arrows (DEC-090); **Your throw** rings (speed, rev rate, Accuracy) vs the bowler's normal throw + verdict; **Lane & pins** rings (Entry point, Entry angle, Power = Impact Energy J) vs target / normal + explanation; one **Coach** takeaway; All metrics + notes collapsed; "Record next shot" | `/shots/{id}` + `baseline` (median speed/revs/arrows, n) + `insights.throw` {status, verdict}, `insights.lane` {status, explanation}, `insights.coach` {action: keep/lane_move/no_move/no_move_yet, text, move{feet,eyes}}, `path_fit` (smoothed lane points with the measured extent) |
| Active Session · Shot | latest shot, session KPIs (4), target, history (collapsed) | `/sessions/{id}` |
| Session summary | takeaway **(went well / improve / next focus)**, early vs late, averages ± spread, by ball, **vs your typical**, shots | `/sessions/{id}/summary` (+ `typical`) |
| Score popup | score/tier change, core metrics vs average | `/sessions/{id}/end` |
| Form results (side / rear) | detected view, focus + drill, **key-position thumbnails + landmarks + one measurement each**, timing vs baseline, metrics by view | `/shots/{id}` (form) + **NEW** `key_positions[]` |
| Key position · full frame | full frame, landmarks (confident only), angle + vertical reference, measurements at that position | **NEW** `/shots/{id}/key_positions/{event}` |
| Active Session · Form / Form summary | deliveries, repeatability ± spread, early vs late | `/sessions/{id}` |
| Stats › Score (3rd tab) | L (provisional) + parts with inputs (DEC-077) | `/me/score`, `/me/score/history` |
| Stats › Shot + 9 detail screens | avg, spread, range, coverage, trend by session, by ball, by pattern, small-sample flags | **NEW** `/me/stats/metric/{metric}` |
| Coaching · coming soon (DEC-084) | static copy; "Notify me" flag per user | **NEW** `PUT /me/notify` (`coaching_launch: true`) |
| Stats › Form / Arsenal | form trends; by ball / by pattern (≥20 shots, smaller marked small sample) | `/me/stats` |
| Stats tab order (DEC-085) | Shot · Form · Score · Arsenal; Stats opens on Shot. Building states reuse the real screens: Score shows part progress + unlock %; Shot/Arsenal show real values with a small-sample flag, 30-day change "new", trends from session 2 | `/me/score` (`eligibility`), `/me/stats` (`small_sample`, `sessions_count`) |
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
| MVP-14 | **Profile fields + autosave** (DEC-087): separate editable First/Last/Email/Phone/DOB and bowler-level **grip (middle pitch, span) + PAP (over, up)** in Profile › Advanced (inches, optional). No Save button — autosave with inline Saved / server validation (reject-not-clamp). DOB has no default; real-date + 13+ gate on create and edit; missing DOB at creation rejected. Email change via Supabase Auth confirmation (never written to `profiles`). Grip/PAP stored per bowler and passed to `configured_reaction(bowler=…)` | Round-trips every field; partial update preserves others; bad phone/measurement/under-13 rejected; email change shows "check your new email"; migration `020` |

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


## DEC-088 Shot card — build notes
- **Lane view:** render live (SceneKit/RealityKit or Metal) from `path_fit`; never draw raw detections point-to-point. Fit a smooth curve (e.g. the existing robust LOESS lateral path, sampled every 0.5 ft) and stop it at the last measured distance. Camera: well behind and above the approach (≈30 ft back, 10 ft up, 16° FOV) so the foul line, approach dots and pins are all in frame; true-scale lane, arrows, pins. Lines ≈1 board wide with minimal glow (target and ball paths usually overlap). Labels: Entry point, Breakpoint, Arrows, Laydown. Reference renders and parameters: `02_DESIGN/target_state/lane_render/`.
- **Throw vs lane classification** comes from the rules engine (M4-02). Throw = speed, revs, arrows board vs the personal baseline (median ± band, BENCHMARKS spec §3.3); lane = entry board, entry angle vs the target line and Power (Impact Energy, DEC-024) vs the bowler's normal; breakpoint is shown on the lane view and in All metrics (DEC-090). Coach matrix: good+good → keep; good+miss → lane move (ball change only after repeated misses with moves); off+miss explained by the throw → no move, "repeat your normal throw"; off+good → don't build on it. Until the baseline exists, show "Building your normal (n/10)" and only lane-based advice.
- **Far lane not read (DEC-065):** Lane & pins show "—" / Not read, coach "No move yet" + camera-setup link.
