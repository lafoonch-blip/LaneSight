# Dev Build v0 — Screen designs (SOURCE OF TRUTH)
Status: APPROVED · kept in sync with the build
Version: 3.2
Last Updated: 2026-10-25

## Role of this folder
- **This folder is the single source of truth for the Dev Build v0 screens.** Claude Code builds the iOS UI from these files.
- **Editing:** Shayne edits the screens in the Claude Design canvas "LaneSight Dev Build v0 Screens" (claude.ai, LaneSight Project). Claude (claude.ai) writes every approved change into this folder, so the canvas and this folder always match.
- **Claude Code never edits files here.** If a build change makes the UI differ from a screen, Claude Code lists the screen and the difference in its report, and the design is updated here first.
- **Figma** (`Lanesight - Product UX - Design`) holds the **target-state** designs for later versions. It is not used for Dev Build v0.

## Files
- One `.dc.html` per screen; open it in a browser to view (the `support.js` line can be ignored).
- `canvas.json` gives the title and order of every screen.
- Screen → API map: `03_ENGINEERING/dev_build_v0/HANDOFF.md` §4. New since v1: `TargetSheet.dc.html` (4a, edit target between shots) and `Analyzing.dc.html` (4b, trim/upload/analyze progress + failure state).

## Rules for reading the designs
- **Sample numbers are illustrative. Never hardcode them.** `[Bracketed text]` stands for real user data.
- **Visual standards:** Figma "01 - Design Standards" (colors, Roboto Condensed type scale, 4 px spacing, radii 8/12/pill, 44 pt targets, dark text on cyan). **Logos and icons:** `02_DESIGN/brand/` (official pack; README there). Screens reference `../brand/logo/…`.
- The welcome hero photo and ball photos are placeholders. Ball photos come from catalog URLs.
- Font is **Roboto Condensed** (bundle it in the app); drawn icons become SF Symbols. App icon and logo images come from `02_DESIGN/brand/ios/Assets.xcassets`.

## Changelog
- **3.2 (2026-10-25):** shot and form metrics split by mode (DEC-056).
  - **Shot card** (Shot Analysis): the "Form from this clip" section is removed; subtitle says "Shot Analysis". Frame shortened to 1420 px.
  - **Form results** (Form Analysis) already show form metrics only; unchanged.
  - **Session summary** (Shot session): "3 form deliveries", the Form focus card and the form-based achievement are removed. Frame shortened to 1060 px.
- **3.1 (2026-10-25):** uploads, recent activity, tabs, setup button (DEC-055).
  - **Upload is not a session.** Upload video no longer has an "Add to session" row; the screen says uploads aren't saved as a session. An uploaded clip never appears in Recent sessions or Recent activity, and never counts toward Stats, the LaneSight Score, tiers or achievements (so its shot card shows no score/achievement nudges). Past uploads are listed under **Lab › Uploads**, below Sessions.
  - **Home Recent activity** shows only practice sessions, achievements and LaneSight tier (rank) changes. The sample "Consistency up 6 this week" row became a tier change.
  - **Leagues and Tourneys tabs** are disabled (dimmed, not tappable) with no "Soon" label (Home, Stats, Lab).
  - **Session setup** (Lab › Start Live Session) bottom button reads **Start session** (was "Set up camera"); it still opens the camera.
- **3.0 (2026-10-25):** every screen restyled to the Figma 01 - Design Standards.
  - Colors: canvas #001018, card #031B29, raised #062132, selected/border #0C2B40, strong border #153B51, text #F5F6FA/#BFCBDD, action #00A8F5 with #001018 text, success #00EB92 on #003D28.
  - Data colors (orange/yellow/purple) are used for data only. There is no error color in v1, so failures use neutral surfaces and plain text. The record button keeps iOS red.
  - Type is Roboto Condensed, 13 px minimum, 400/600 weights. Corners are 8 px on controls, 12 px on cards, pill on chips.
  - Official stacked logo on Welcome, Sign in and the Home header.
  - **Tab headers:** every main tab (Home, Stats, Lab) has Settings (left) and Profile (right) at 44 pt. Home shows the logo in the center; other tabs show the tab name (Stats, Lab). Leagues/Tourneys stay disabled (dimmed, no label; 3.1); when built, they use the same header with their tab name.
  - The cropped concept-logo images from 2.1 are superseded; delete `assets/`.
- **2.1 (2026-10-25):** logo. Welcome uses the primary stacked logo (mark + LANESIGHT + "See More. Bowl Smarter.") on Midnight Navy #0B1320. The Home header uses the LS mark + LANESIGHT wordmark (LANE white, SIGHT Lane Blue). Images are in `assets/`, cropped from `02_DESIGN/logo/LaneSight_Brand_System_Concept.png`. For the shipping app, use a clean vector or 3× export of the same lockups.
- **2.0 (2026-10-25):** synced to build `dev-build-v0@2490b09` and Shayne's device feedback.
  - Lane picker removed (Setup, Session, Shot).
  - Target moved to Setup, with a carry-forward target chip and ball chip on Capture; new Edit-target sheet.
  - "Apply this move" plus suggested breakpoint on the Shot card.
  - Sensor answer is "Yes · pick sensor".
  - New Analyzing screen.
  - Onboarding is 2 steps (first/last name, DOB, hand, delivery style; approach-steps and sensors removed), then an optional add-ball step with Skip.
  - Create account is email/password; Apple/Google are disabled until the paid team is active; "Read the Terms" button added.
  - "Mac online" removed from Lab.
  - Approach steps removed from Profile.
  - Capture keeps the advisory spot-check tip (DEC-045); **the build doesn't show it yet**.
- **1.0 (2026-10-22):** initial approved set.
