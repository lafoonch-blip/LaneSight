# App design changes: build queue
Status: ACTIVE · Version: 1.0 · Last Updated: 2026-10-27 · Owner: Shayne
Decision: DEC-091 (Figma "Target state – v3.7" is the app's design source; every design change lands here as a build item).

## How this works
- **Designs:** Figma "Lanesight - Product UX - Design" (`k6F8iHTtl2ZHvnXlHmYPnd`), page "01 — Home & Foundation", section **Target state – v3.7**. Guide: `02_DESIGN/target_state/README.md` (changelog at the bottom).
- **Each design change = one entry below**: what changed, screens (Figma node + PNG in `02_DESIGN/target_state/screens/<date>/`), exact spec, data/API, done-when, and a **Status**.
- **Claude Code:** build every entry whose status is **NOT BUILT**, in order, then set it to **BUILT (commit)**. If the build has to differ from the design, note it under the entry as **DIFFERS:** and say why. Never defer an entry to a "later version".
- **Claude (claude.ai):** whenever Figma changes, add an entry here and export the PNGs in the same session.
- `02_DESIGN/dev_build_v0/` (Claude Design canvas) is **frozen** as of 2026-10-26 (v3.8) and is no longer updated. Where it disagrees with Figma, Figma wins.

## Catch-up: Figma changes since the canvas was last synced (2026-10-26)
| # | Change | Decision | Status |
|---|---|---|---|
| 1 | Form: no video player; key-position thumbnails with skeleton overlay + full-frame view (v3.7.2) | DEC-082 | VERIFIED BUILT (76a2735-era): `FormCardView` has no video player; key-position tiles fetch the bowler-cropped frame (missing → "not found" tile, never a guessed frame); `KeyPositionFullView` overlays `SkeletonOverlay` on the full frame. Matches DEC-082. |
| 2 | Approval pass: Shot/Form cards equal height on Home and Lab; empty states for Stats › Form, Stats › Arsenal, Achievements; 11 pt minimum text; 44 pt hit areas (v3.7.3) | DEC-079/081 | BUILT (this commit): Analyze cards now equal-height with bottom-aligned CTAs (`AnalyzeCards.swift`). Stats › Form + Stats › Arsenal empty cards present; Achievements shows a populated "0/N + catalog" building state (not blank). Hit areas on the audited chooser/sheets are ≥44 pt; remaining typography is handled by the Shot-card rebuild (entry A). |
| 3 | Home while the LaneSight Score is building; score tiles show 30-day change (v3.7.4) | DEC-083 | BUILT (0cf7c01, e6b0fb3) |
| 4 | Coaching tab replaces Leagues/Tournaments; coming-soon screen (v3.7.5) | DEC-084 | BUILT (4fc2d80) |
| 5 | Stats tabs Shot · Form · Score · Arsenal; building states (v3.7.6) | DEC-085 | BUILT (ce1077b) |
| 6 | **Shot card redesign**: 3D lane view, Your throw / Lane & pins, Coach (v3.7.7–3.7.9) | DEC-088, DEC-090 | **NOT BUILT**: see entry 2026-10-27-A |
| 7 | **Shot card states**: off throw → no move; far lane not read | DEC-088, DEC-090 | **NOT BUILT**: entry 2026-10-27-B |
| 8 | **Upload result (Shot)** on the same layout | DEC-088 | **NOT BUILT**: entry 2026-10-27-C |
| 9 | Primary button "Record next shot" (app still shows "Record Shot N", `Result/ResultView.swift:505`) | DEC-088 | **NOT BUILT**: part of 2026-10-27-A |

---

## 2026-10-27-A · Shot card (Shot Analysis result): full redesign
**Status:** NOT BUILT
**Decisions:** DEC-088, DEC-090 (+ README 3.7.9). **Replaces** the current result screen layout (old lane recreation, analysis card, metric list).
**Figma:** "Shot card · Shot Analysis · v3.7" (node `564:360`) · PNG `02_DESIGN/target_state/screens/2026-10-27/shot_card.png`
**Opens:** automatically after Analyzing (DEC-080). **Close (✕)** → Active Session. **Record next shot** → Record.

Layout top to bottom (390 pt screen, 16 pt side padding, 12 pt between blocks, background `background/canvas`):
1. **Sheet title bar** (existing): "Shot 14" / "Shot Analysis · Session 3 · House shot", ✕ on the left.
2. **Lane view** (344 × 360 pt, radius 20, 1 pt `border/strong`):
   - **Rendered live from the shot's data** (SceneKit/RealityKit or Metal), not an image. Reference: `02_DESIGN/target_state/lane_render/` (`lane3d.html` scene and `shots.json` camera) and the 3× renders in `screens/2026-10-27/lane_render_*.png`.
   - **Camera:** behind and above the approach (≈30 ft behind the foul line, 10 ft up, look-at 15.5 ft down the lane, 16° vertical FOV) so the **foul line, approach dots, arrows and pins are all in frame**. Neighbor lanes are dimmed.
   - **True scale:** 39 boards / 41.5 in lane, 60 ft to the head pin, USBC pin and ball sizes. Board 1 is on the bowler's right (mirror for left-handers).
   - **Your ball path:** green `#00eb92`, ≈1 board wide, minimal glow. It is a **smooth curve fitted through the tracked points** (robust LOESS lateral path sampled every 0.5 ft); **never** draw raw detections point to point. It starts at the laydown and ends at entry, or at the last measured distance.
   - **Target line:** blue `#1e7bff`, ≈1 board wide, minimal glow. The two lines often overlap, so keep both thin.
   - **Four pinned data labels** (glass card: `#001018` at 74 %, background blur 12, radius 12, 1 pt stroke in the label color; texts 11 / 20 bold / 11). Each has a leader line to a 4 pt dot on the path:
     - Entry point `#fa923c`: board · angle
     - Breakpoint `#f5cd31`: board · distance
     - Arrows `#00eb92`: board · target board
     - Laydown white: board · distance past the foul line
   - **Overlays:** result chip top-left ("Not a strike" / "Strike" / "Result not read"); legend bottom-left (Target / Your ball).
3. **"Shot read" card** (`surface/card`, radius 20, 16 pt padding), three parts:
   - **YOUR THROW** + status badge, three rings, one-line verdict:
     - Badges: "Good · your normal throw" green, "Off · faster than usual" orange, etc.
     - Rings: **Speed** (mph), **Rev rate** (rpm, best effort), **Accuracy** (DEC-031 score "/ 100"). Under each: the comparison with the bowler's **normal throw** ("= your avg", "↑0.9 vs avg", "12.2 vs 12").
   - Divider.
   - **LANE & PINS** + badge, three rings, one-line explanation:
     - Badges: "Lane held it · light", "Went long · light", etc.
     - Rings: **Entry point** (board, vs pocket 17.5), **Entry angle** (vs target), **Power** (Impact Energy J, DEC-024, vs your avg).
   - **COACH** box (`home/card-hero`, `home/hero-stroke`): sparkle icon, action tag ("Lane move" / "No move" / "No move yet" / "Keep it"), one sentence in 15 pt semibold.
   - **Ring spec:** tile `surface/raised`, radius 16; label 12 pt; ring 68 pt, 270° arc from 135° (inner radius 84 %), track `#153b51`; progress color by status (green ok, yellow watch, orange off, none when not read); value 18 bold (15 when longer than 4 characters) + unit 11; delta 12 semibold (status color, or secondary when ok).
4. **All metrics** row ("Breakpoint, laydown, launch, loft and more" ›) → existing full metric list. **Your notes** row ("Tap to add how it felt" ›) → existing notes UI.
5. **Dock:** primary button **"Record next shot"**.

**Coach logic (rules engine, M4-02).** Both parts are classified first:
- **Throw:** speed, revs and arrows board vs the personal baseline (median ± band, BENCHMARKS spec §3.3).
- **Lane:** entry board/angle vs the target line and power vs normal.

| Throw | Lane | Coach |
|---|---|---|
| Good | Good | **Keep** the line. |
| Good | Miss | **Lane move**: feet/eyes by the 2-and-1 / 3-and-2 rules. Ball change only if it keeps missing after moves. |
| Off | A miss the throw explains | **No move**: "That was the throw, not the lane. Repeat your normal [speed]." Never a ball or line change. |
| Off | Good | **Don't build on it** (keep the line, repeat the normal throw). |

- Until the baseline exists (fewer than 10 qualifying shots): throw rings show "Building your normal (n/10)", and the coach uses lane-only advice.

**Data/API:** `/shots/{id}` adds:
- `path_fit`: smoothed {z_ft, board} points + measured extent.
- `baseline`: median speed / revs / arrows board, n.
- `insights.throw`: {status, verdict}.
- `insights.lane`: {status, explanation}.
- `insights.coach`: {action: keep | lane_move | no_move | no_move_yet, text, move: {feet, eyes}}.
- `impact_energy_j`.

**Done when:**
- The screen matches the PNG.
- The lane view is drawn live from `path_fit` (no static image) with all four labels.
- The coach action follows the matrix above, with unit tests for all four rows.
- The button reads "Record next shot".

## 2026-10-27-B · Shot card states
**Status:** NOT BUILT
- **Off throw → no move:** Figma `564:66`, PNG `shot_card_state_off_throw.png`. Same layout. Throw badge orange "Off · faster than usual"; Speed ring orange "↑0.9 vs avg"; Coach "No move": "That was the throw, not the lane. Stay where you are and repeat your normal speed."
- **Far lane not read (DEC-065):** Figma `568:4511`, PNG `shot_card_state_far_lane_not_read.png`.
  - **Lane view:** draw the path only to the last measured distance and dim the lane beyond it. Center note: "Not visible from this camera spot / Breakpoint, entry and pins need the full lane". Labels: Arrows and Laydown only. Result chip "Result not read".
  - **Lane & pins:** badge "Not read" (grey). All three rings show "—" / "Not read" with no progress arc (Power needs entry speed).
  - **Coach:** "No move yet", "Keep the same line. Move the tripod so your next shot gets a full read.", plus a "See camera setup ›" row (opens camera guidance).
  - This replaces the current "This camera spot limits far-lane numbers" warning card and the metric list shown on top.

## 2026-10-27-C · Upload result (Shot Analysis)
**Status:** NOT BUILT
**Figma:** "Upload result · Shot Analysis · v3.7" (`568:4665`) · PNG `upload_result_shot.png`
- **Same layout as 2026-10-27-A**, except:
  - Title "Shot", subtitle "Uploaded clip · Shot Analysis".
  - A note row under the Shot read card: "Uploaded clip · analyzed on its own. Doesn't count toward Stats, your LaneSight Score or achievements."
  - The primary button is **Done**. Done and ✕ return to Lab.
- Throw comparisons still use the bowler's baseline when one exists. The upload is never added to it.
