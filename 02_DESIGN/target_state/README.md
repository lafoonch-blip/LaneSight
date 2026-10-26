# Target-state (MVP) designs — v3.7
Status: APPROVED FOR HANDOFF · Version: 3.7.1 · Last Updated: 2026-10-26 · Owner: Shayne

## Where they live
- **Figma:** "Lanesight - Product UX - Design" (`k6F8iHTtl2ZHvnXlHmYPnd`), page "01 — Home & Foundation", section **Target state – v3.7**.
- **Parked:** section "Parked · Sensor partnership (post-MVP)" (DEC-070).
- **Archived:** page **archived** holds superseded sections, old screens and removed parts (nothing deleted).
- **PNG export:** `LaneSight_v3.7_target_state_screens_2026-10-26.zip` (63 frames), shared in the claude.ai chat; not committed (binary).
- **Dev Build v0** screens are separate: `02_DESIGN/dev_build_v0/` (Claude Design canvas). Target-state decisions apply there only when a DEC says so.

## Prototype (Figma › Present)
Flow starts: **Shot session (live)** · **Form session (live)** · **Onboarding → first use** · **Stats**. 204 links, none broken (audited 2026-10-26).
- Shot loop (DEC-080): Setup → Record → Analyzing (blocking, screen stays on) → Shot card → Record next shot, or Close → Active Session → End → score popup → Session summary → feedback.
- Form loop (DEC-081): Setup (no ball/oil; camera-view guidance) → Record delivery (side or behind, detected) → Analyzing → Form results (side or rear example) → Record next delivery, or Close → Form session → End → Form summary.
- Uploads (DEC-069): Lab → Shot or Form → Live session / Upload video → result (not counted in Stats or Score).

## Screen inventory (63)
Row 1: nav component · Home · Lab · choose source (Shot, Form) · Setup (Shot, Form) · ball / oil sheets · Record (Shot, Form) · Analyzing (Shot, Form).
Row 2: Active Session · Shot card · next-shot states board · Next-shot card component · connection & clip problems · session & data states board.
Row 3: Session summary · feedback sheet · score popup · Form results (rear, side) · Form session (active, summary) · uploads (Shot, Form) and upload results.
Row 4: Stats (Score, Shot, Form, Equipment) · nine metric detail screens · achievements (overview, collection, unlock, new tier).
Row 5: Welcome · Sign in · Create account · onboarding (2 steps) · Under 13 · Profile · Settings · Delete account · Ball setup (add, edit).
Row 6: camera permission (ask, denied) · first-use Home, Lab, Stats.

## Decisions reflected
DEC-061, DEC-066–077, DEC-079–081 (DEC-078 withdrawn). Metric placement: `01_PRODUCT/METRIC_TO_SCREEN_SPEC.md` v0.2. Score: DEC-077 (DEC-048 formula, labeled provisional).

## Build rules
- **Sample numbers are illustrative.** `[Bracketed text]` is user data.
- **Status chips:** MEASURED / BEST EFFORT / UNAVAILABLE (never a number without a status; UNAVAILABLE never shows a number).
- **Text:** minimum 11 pt for anything a user reads (raised from 9–10 pt in the 2026-10-26 pass). Chart axis and lane-diagram labels may be smaller.
- **Contrast:** text ≥ 4.5:1 on its background (≥ 3:1 at 18 pt+). Timing purple was lightened to pass.
- **Tap targets:** every tappable element gets a **44 × 44 pt hit area**, even where the visible control is smaller (header icons 40 pt, Stats tabs 34 pt, text links).
- **Photos:** Shot/Form card images are LaneSight-generated; the Welcome hero is a placeholder (an AI-generated photo of Shayne will replace it). Form key positions and upload thumbnails are frames from the bowler's own clip (DEC-075, DEC-076).
- **Tier badges:** current art is 4× AI-upscaled from 126 px originals (no higher-resolution source exists). Export at 3× from Figma.

## Components rebuilt 2026-10-26
Back, Edit, Form/Field, Control/Segment option, Row/List item, Tile/Stat were orphaned (main components lost). Rebuilt in Design Components › "LaneSight / Core controls (rebuilt 2026-10-26)" and all 94 instances relinked. Also new: `Sessions / Next-shot card` (6 states); Result badge gained Not a strike / Not read; Metric status row gained Best effort.

## Changelog
- **3.7.1 (2026-10-26):** design review (DEC-079), shot flow (DEC-080), Form flow, first-use and permission screens, metric detail screens (DEC-081), rebuilt components, accessibility pass (11 pt minimum, contrast, 44 pt hit areas), file cleanup (archived page).
- **3.7 (2026-10-26):** target state aligned to Dev Build v0 workflows (DEC-066–076), passes 1–7.
