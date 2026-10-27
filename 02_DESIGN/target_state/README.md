# Target-state (MVP) designs — v3.7
Status: APPROVED FOR HANDOFF · Version: 3.7.9 · Last Updated: 2026-10-27 · Owner: Shayne

## Where they live
- **Figma:** "Lanesight - Product UX - Design" (`k6F8iHTtl2ZHvnXlHmYPnd`), page "01 — Home & Foundation", section **Target state – v3.7**.
- **Parked:** section "Parked · Sensor partnership (post-MVP)" (DEC-070).
- **Archived:** page **archived** holds superseded sections, old screens and removed parts (nothing deleted).
- **PNG export:** `LaneSight_v3.7_target_state_screens_2026-10-26.zip` (63 frames), shared in the claude.ai chat; not committed (binary).
- **Dev Build v0** screens are separate: `02_DESIGN/dev_build_v0/` (Claude Design canvas). Target-state decisions apply there only when a DEC says so.

## Prototype (Figma › Present)
Flow starts: **Shot session (live)** · **Form session (live)** · **Onboarding → first use** · **Stats**. 245 links, none broken (audited 2026-10-27).
- Shot loop (DEC-080): Setup → Record → Analyzing (blocking, screen stays on) → Shot card → **Record next shot**, or Close → Active Session → End → score popup → Session summary → feedback.
- Form loop (DEC-081): Setup (no ball/oil; camera-view guidance) → Record delivery (side or behind, detected) → Analyzing → Form results (side or rear example) → Record next delivery, or Close → Form session → End → Form summary.
- Uploads (DEC-069): Lab → Shot or Form → Live session / Upload video → result (not counted in Stats or Score).

## Screen inventory (69)
Row 1: nav component · Home · Lab · choose source (Shot, Form) · Setup (Shot, Form) · ball / oil sheets · Record (Shot, Form) · Analyzing (Shot, Form).
Row 2: Active Session · Shot card (DEC-088) + states "off throw → no move" and "far lane not read" · next-shot states board · Next-shot card component · connection & clip problems · session & data states board.
Row 3: Session summary · feedback sheet · score popup · Form results (rear, side) · key position full frame · Form session (active, summary) · uploads (Shot, Form) and upload results.
Row 4: Stats (Score, Shot, Form, Equipment) · nine metric detail screens · achievements (overview, collection, unlock, new tier).
Row 5: Welcome · Sign in · Create account · onboarding (2 steps) · Under 13 · Profile · Settings · Delete account · Ball setup (add, edit).
Row 6: camera permission (ask, denied) · first-use Home, Lab, Stats › Score, Stats › Form, Stats › Equipment, Achievements · metric detail screens.

## Decisions reflected
DEC-061, DEC-066–077, DEC-079–085, DEC-088, DEC-090 (DEC-078 withdrawn). Metric placement: `01_PRODUCT/METRIC_TO_SCREEN_SPEC.md` v0.2. Score: DEC-077 (DEC-048 formula, labeled provisional).

## Build rules
- **Sample numbers are illustrative.** `[Bracketed text]` is user data.
- **Status chips:** MEASURED / BEST EFFORT / UNAVAILABLE (never a number without a status; UNAVAILABLE never shows a number).
- **Text:** minimum 11 pt for anything a user reads (raised from 9–10 pt in the 2026-10-26 pass). Chart axis and lane-diagram labels may be smaller.
- **Contrast:** text ≥ 4.5:1 on its background (≥ 3:1 at 18 pt+). Timing purple was lightened to pass.
- **Tap targets:** every tappable element gets a **44 × 44 pt hit area**, even where the visible control is smaller (header icons 40 pt, Stats tabs 34 pt, text links).
- **Photos:** Shot/Form card images are LaneSight-generated; the Welcome hero is a placeholder (an AI-generated photo of Shayne will replace it). Form key positions and upload thumbnails are frames from the bowler's own clip (DEC-075, DEC-076).
- **Form key positions (DEC-082):** no video player. Thumbnails are captured during analysis; the app draws a line skeleton from stored pose landmarks (confident joints only) and one key measurement per position. Tapping opens the full frame with the angle drawn against a vertical reference. Low pose confidence = no overlay, labeled. The designs use real MediaPipe Pose output on IMG_8905 (side) and IMG_8907 (rear).
- **Tier badges:** current art is 4× AI-upscaled from 126 px originals (no higher-resolution source exists). Export at 3× from Figma.

## Components rebuilt 2026-10-26
Back, Edit, Form/Field, Control/Segment option, Row/List item, Tile/Stat were orphaned (main components lost). Rebuilt in Design Components › "LaneSight / Core controls (rebuilt 2026-10-26)" and all 94 instances relinked. Also new: `Sessions / Next-shot card` (6 states); Result badge gained Not a strike / Not read; Metric status row gained Best effort.

## Changelog
- **3.7.9 (2026-10-27):** lane view camera pulled back so the **foul line, approach dots and pins** are all in frame; new **Laydown** label (board + distance past the foul line); target and ball lines thinned to ~1 board with minimal glow so they stay readable when they overlap.
- **3.7.8 (2026-10-27):** DEC-090 — lane view gets Entry point, Breakpoint and Arrows data labels with dots on the path (markers drawn on top; pin glow reduced); "Target" ring → **Accuracy**; Lane & pins rings → **Entry point, Entry angle, Power** (Impact Energy, J). Breakpoint moves to the lane view and All metrics.
- **3.7.7 (2026-10-27):** DEC-088 — new Shot card: 3D lane view rendered from the shot data (fitted ball path, target band, Entry/Breakpoint labels, true-scale pins), core rings split into **Your throw** (speed, revs, target vs your normal) and **Lane & pins** (breakpoint, entry board, entry angle vs target), one **Coach** takeaway, All metrics / notes collapsed, button "Record next shot". New state frames "off throw → no move" and "far lane not read"; Upload result rebuilt on the same layout (Done). Old Shot card, old Upload result and redesign options A–D moved to "archived". The lane images in Figma are renders from `02_DESIGN/target_state/lane_render/` (Three.js); the app draws the same view live.
- **3.7.6 (2026-10-27):** DEC-085 — Stats tabs Shot · Form · Score · Arsenal (Equipment renamed; Stats opens on Shot). New building-state screens built from the real ones: "Stats · Shot · building", "Stats · Score · building", "Stats · Arsenal · building" (small-sample labels); Form keeps its empty state.
- **3.7.5 (2026-10-27):** DEC-084 — nav is Home · Stats · Lab · Coaching (Leagues/Tournaments removed; new "Active tab=Coaching" variant); new screen "Coaching · coming soon" with Notify me. 257 prototype links, none broken.
- **3.7.4 (2026-10-27):** DEC-083 — Home while the score is building uses the real card (greyed, blurred badge; "—", BUILDING, hint, "Score unlocks · N%" bar). Score-part tiles show the part score and its 30-day change; weights only in score details. Frame: "Home · score building (first use)".
- **3.7.3 (2026-10-26):** approvals recorded; Shot/Form cards equal height on Home and Lab; empty states for Stats › Form, Stats › Equipment and Achievements; notes on full-frame pattern, screen sizes and Dynamic Type; MVP engineering handoff.
- **3.7.2 (2026-10-26):** Form video player removed (DEC-082); key-position thumbnails get measured skeleton overlays and a key measurement; new screen "Key position · full frame (Release, side view)" (64 screens).
- **3.7.1 (2026-10-26):** design review (DEC-079), shot flow (DEC-080), Form flow, first-use and permission screens, metric detail screens (DEC-081), rebuilt components, accessibility pass (11 pt minimum, contrast, 44 pt hit areas), file cleanup (archived page).
- **3.7 (2026-10-26):** target state aligned to Dev Build v0 workflows (DEC-066–076), passes 1–7.

## Notes added 2026-10-26 (approval pass)
- **Key position full frame:** only Release (side view) is drawn. Every other position and the rear view follow the same pattern: full frame, confident-joint skeleton, one measured angle against a vertical reference, the measurements available at that position, ‹ › to step between positions. Low confidence → frame without overlay and a label.
- **Empty states:** Home, Lab, Stats › Score, Stats › Form, Stats › Equipment and Achievements have first-use versions (row 6).
- **Screen sizes and text size:** designed at 390 pt. 375 pt: rings stay 3 across and shrink. 430 pt: content widens, no extra columns. Dynamic Type to at least AX1: cards grow, tiles wrap, numbers never truncate.
- **Engineering handoff:** `03_ENGINEERING/MVP_HANDOFF.md`.
