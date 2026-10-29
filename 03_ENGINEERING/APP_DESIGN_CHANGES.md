# App design changes: build queue
Status: ACTIVE · Version: 1.2 · Last Updated: 2026-10-29 · Owner: Shayne
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
| 1 | Form: no video player; key-position thumbnails with skeleton overlay + full-frame view (v3.7.2) | DEC-082 | BUILT (2026-10-28): `FormCardView` has no video player; key-position tiles fetch the bowler-cropped frame (missing → "not found" tile, never a guessed frame); `KeyPositionFullView` overlays `SkeletonOverlay` on the full frame. **Correction:** the earlier "VERIFIED BUILT" note was wrong — the design's skeleton overlay on the **thumbnails** had never been built (only the full view had it). Now added: `KeyPositionTile` renders `SkeletonOverlay` over the still (scaledToFit so the aspect-fit mapping aligns), drawn only when the pose found confident joints for that still. |
| 2 | Approval pass: Shot/Form cards equal height on Home and Lab; empty states for Stats › Form, Stats › Arsenal, Achievements; 11 pt minimum text; 44 pt hit areas (v3.7.3) | DEC-079/081 | BUILT (this commit): Analyze cards now equal-height with bottom-aligned CTAs (`AnalyzeCards.swift`). Stats › Form + Stats › Arsenal empty cards present; Achievements shows a populated "0/N + catalog" building state (not blank). Hit areas on the audited chooser/sheets are ≥44 pt; remaining typography is handled by the Shot-card rebuild (entry A). |
| 3 | Home while the LaneSight Score is building; score tiles show 30-day change (v3.7.4) | DEC-083 | BUILT (0cf7c01, e6b0fb3) |
| 4 | Coaching tab replaces Leagues/Tournaments; coming-soon screen (v3.7.5) | DEC-084 | BUILT (4fc2d80) |
| 5 | Stats tabs Shot · Form · Score · Arsenal; building states (v3.7.6) | DEC-085 | BUILT (ce1077b) |
| 6 | **Shot card redesign**: 3D lane view, Your throw / Lane & pins, Coach (v3.7.7–3.7.9) | DEC-088, DEC-090 | **BUILT** (shot-card commits) — see 2026-10-27-A |
| 7 | **Shot card states**: off throw → no move; far lane not read | DEC-088, DEC-090 | **BUILT** — see 2026-10-27-B |
| 8 | **Upload result (Shot)** on the same layout | DEC-088 | **BUILT** — see 2026-10-27-C |
| 9 | Primary button "Record next shot" | DEC-088 | **BUILT** (ResultView now shows "Record next shot") |
| 10 | **Shot card: design-parity + data-honesty correction** — the live card (upload 2026-10-29) doesn't match `upload_result_shot.png`/`shot_card.png` and shows gated far-lane metrics + a coach move from them | DEC-065/088/090/094 | **NOT BUILT** — see 2026-10-29-A |

---

## 2026-10-27-A · Shot card (Shot Analysis result): full redesign
**Status:** BUILT (ShotLaneView.swift live SceneKit lane view; ShotReadCard.swift rings + coach; ResultView ball-shot layout swapped; backend coach engine + path_fit/impact_energy_j/baseline on /shots/{id}).
**DIFFERS:** (1) the pinned glass labels are projected from the live 3D scene and styled as glass cards, but leader lines to the dots are not drawn yet (label sits just above its dot). (2) The Accuracy ring shows the arrows-board-vs-target (the executable signal) rather than a per-shot DEC-031 0–100 score — that per-shot score isn't computed server-side yet; shown honestly rather than fabricated. (3) "All metrics" and "Your notes" are a DisclosureGroup + the existing notes view rather than the exact Figma rows. Ring arc/colors follow the 68 pt / 270°-from-135° spec.
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
**Status:** BUILT. Off-throw → coach `no_move` + orange throw badge (ShotReadCard). Far-lane-not-read → ShotLaneView dims the far lane + note, drops the breakpoint/entry labels, result chip "Result not read"; Lane & pins rings show "—"/Not read (no arc); coach "No move yet". **DIFFERS:** the "See camera setup ›" link isn't wired yet (camera-guide screen is out of scope / not approved).
- **Off throw → no move:** Figma `564:66`, PNG `shot_card_state_off_throw.png`. Same layout. Throw badge orange "Off · faster than usual"; Speed ring orange "↑0.9 vs avg"; Coach "No move": "That was the throw, not the lane. Stay where you are and repeat your normal speed."
- **Far lane not read (DEC-065):** Figma `568:4511`, PNG `shot_card_state_far_lane_not_read.png`.
  - **Lane view:** draw the path only to the last measured distance and dim the lane beyond it. Center note: "Not visible from this camera spot / Breakpoint, entry and pins need the full lane". Labels: Arrows and Laydown only. Result chip "Result not read".
  - **Lane & pins:** badge "Not read" (grey). All three rings show "—" / "Not read" with no progress arc (Power needs entry speed).
  - **Coach:** "No move yet", "Keep the same line. Move the tripod so your next shot gets a full read.", plus a "See camera setup ›" row (opens camera guidance).
  - This replaces the current "This camera spot limits far-lane numbers" warning card and the metric list shown on top.

## 2026-10-27-C · Upload result (Shot Analysis)
**Status:** BUILT. Uploads render the same ShotLaneView + ShotReadCard; subtitle "Uploaded clip · Shot Analysis", the not-counted footer note, and no "Record next shot" (Done via the nav bar returns to Lab). Throw rings use the live baseline; the upload never joins it.
**Figma:** "Upload result · Shot Analysis · v3.7" (`568:4665`) · PNG `upload_result_shot.png`
- **Same layout as 2026-10-27-A**, except:
  - Title "Shot", subtitle "Uploaded clip · Shot Analysis".
  - A note row under the Shot read card: "Uploaded clip · analyzed on its own. Doesn't count toward Stats, your LaneSight Score or achievements."
  - The primary button is **Done**. Done and ✕ return to Lab.
- Throw comparisons still use the bowler's baseline when one exists. The upload is never added to it.

---

## Active Session — flow + ball/oil rows (DEC-096, DEC-097) — needs Figma update

The Active Session (Figma 413:3804 Shot / 464:7377 Form) is now the live hub every analysis returns to
(DEC-096), and it carries editable **Ball** and **Oil pattern** rows next to the Target Line (DEC-097). The
v3.7 Figma should be updated to reflect:
- The Active Session is reached from Setup on **Start session** (no longer lands on the camera first), and every
  shot/form analysis returns here until **End session**. Removed the "Change → Setup" arrow (the session never
  returns to Setup). **No other v3.7 flow arrow pointed back to Setup after an analysis.**
- Failure state gains **Retry** (no re-recording) + **Back to session**.
- New **Ball** and **Oil pattern** rows under Target Line, each with a **Change** control (same picker views as
  Setup). A change applies to the next shot only.
- **Not yet built (flagged):** shot-list dividers "Switched to <ball>" / "Oil: <pattern>" and per-row/shot-card
  ball display.


## 2026-10-28 · Usability batch (DEC-099) — BUILT in code; needs Figma update
Built from Shayne's 2026-10-28 test notes (no new Figma frames yet). The v3.7 Figma should be updated to match:
- **Bottom tab bar** only on Home · Stats · Lab · Coaching; hidden on every pushed screen (Profile, Settings, Setup, Active Session, Upload, metric detail, achievements, ball setup, Form baseline, summaries).
- **Settings (434:6174):** "Privacy · Raw video retention 30 days" row removed → new **Videos** section with a **"Save recordings to my phone"** toggle (default off) and footer copy about server storage.
- **Ball setup (437:6000 add / 437:6083 edit):** new **"Make this my default ball"** checkbox row under the header (add: on when no default exists; edit: saves on tap). **Profile › Arsenal** cards and the **ball picker** show a "Default" tag.
- **Profile (434:5981):** "Form baseline" row now opens a new **Form baseline** screen (Use my average / Enter my timing with Pushaway · Backswing · Downswing · Release + total / No baseline; Save). Editable text rows show a pencil.
- **Form result:** swing-timing card gains **"Use this delivery as my baseline"**.
- **Upload screen:** the "What's in this clip? Shot / Form" picker is removed (title shows the chosen mode; Form uploads have no target fields). Lab header upload shortcut removed.
- **Loading:** a tab's first load shows one page-level spinner, then the whole page; revisits never show spinners.
Status: **BUILT** (branch `fix/ux-batch-2026-10-28`). DIFFERS: no Figma frames exist yet for the new Form baseline screen and the default-ball row — built in the existing card style.

---

## 2026-10-29-A · Shot card: design parity + data honesty (correction pass on 2026-10-27-A)
**Status:** NOT BUILT. The live Shot card (Shayne's upload 2026-10-29 12:35, Storm Bionic) diverges from the approved design AND surfaces gated/low-confidence metrics as measured. This entry supersedes the open DIFFERS on 2026-10-27-A.
**Design source:** Figma "Target state – v3.7" Shot card + Upload result. PNGs `02_DESIGN/target_state/screens/2026-10-27/` (`shot_card.png`, `upload_result_shot.png`, `shot_card_state_far_lane_not_read.png`, `shot_card_state_off_throw.png`). Lane render ref `02_DESIGN/target_state/lane_render/`.
**Decisions:** DEC-065 (far-lane metrics unavailable until Phase-2 validation — confirm no later DEC lifted it), DEC-088/090 (card), DEC-094 item 5 (uncertainty contract: no move from unavailable/low-confidence/gated metrics), DEC-024 (Power), DEC-031/090 (Accuracy = 0–100 score), DEC-097 (ball name on live shots, not uploads).

### A. Data honesty (do first — wrong results are reaching the user)
1. **Far-lane metrics shown as measured.** Entry point 6.9, entry angle −0.0°, breakpoint 10 all render and the coach recommends a move from them. Enforce DEC-065 (entry board/angle, breakpoint `unavailable` until Phase-2 validation) in BOTH the API response and the app — unless a later DEC lifted it (check). This is the 10.51 s / 26.25 mph upload; the speed is now gate-withheld but the lateral metrics come from the SAME broken geometry.
2. **Propagate the geometry withhold.** When the speed-consistency gate withholds speed for geometry inconsistency, mark EVERY metric derived from that geometry (entry board/angle, breakpoint, laydown, arrows, launch) low-confidence or unavailable too (they share the compromised depth scale / homography).
3. **Coach / Lane move obeys the uncertainty contract (DEC-094 #5).** No move from unavailable/low-confidence/gated metrics; show the design's **"far lane not read"** state (`shot_card_state_far_lane_not_read.png`) instead.
4. **No bare "—".** Unavailable metrics use the UNAVAILABLE treatment with a one-line reason (status chip, never a number without a status). **"−0.0°" must never render** — round to 0.0 or hide if an artifact.

### B. Visual parity with `upload_result_shot.png` / `shot_card.png`
1. **Lane view** — use the 3D render (`lane_render/`): wood/boards/arrows/approach dots/true-scale pins/foul line, curved fitted ball path, blue target line (not the flat trapezoid). Data labels (Entry point, Breakpoint, Arrows, Laydown) in **right-side callouts with leader lines** to dots on the path — not on the centerline; the current Entry label is clipped at top. Legend bottom-left must not overlap approach dots. Far-lane-unavailable → `shot_card_state_far_lane_not_read.png`.
2. **Header** — ✕ close top-LEFT + grab handle; subtitle **"Uploaded clip · Shot Analysis"** for uploads (ball name on live shots only, DEC-097 — confirm placement in the design); Done at the BOTTOM, not a top-right pill.
3. **Section headers** use status chips (Your throw: "Good · your normal throw"/"Off your normal"/building per DEC-083/085; Lane & pins: "Lane held it · light", etc.) + a one-sentence summary under each.
4. **Rings** — label above, value+unit inside, colored arc (green on-normal/target, orange off), comparison line below ("= your avg", "2.2 light", "tgt 5.5°"). **Accuracy = 0–100 score shown as "12.2 vs 12"** (per METRIC_TO_SCREEN_SPEC / DEC-090), NOT "10.5 bd".
5. **Coach card** — "COACH" + "Lane move" chip; specific move (feet/eyes/arrow numbers, before→after) + the escalation line.
6. **Below the card** — upload notice (doesn't count toward Stats/Score), All metrics row, Your notes row, full-width **Done** button.
7. **Build rules** — 11 pt min, contrast, 44 pt hit areas.

### C. Verify (done-when)
- Render in the simulator with THIS shot's real data AND a good-throw fixture; screenshots side-by-side with the PNG exports.
- List every remaining difference + anything the design wants that the data can't support yet (show unavailable, never a placeholder number).
- Update this file + report docs changed for the Project re-sync.

**Notes for the builder:** the speed-consistency gate + far-lane withhold live in `lanesight-core/lanesight_core/cv/pipeline.py` (2026-10-29). The ring/lane iOS is `ShotReadCard.swift` / `ShotLaneView.swift` / `ResultView.swift`. Accuracy-score definition: check `METRIC_TO_SCREEN_SPEC` / DEC-031 (a per-shot 0–100 score may still be unbuilt server-side — if so, that's a prerequisite, flag it, don't fabricate).
