# LaneSight Capture Test Plan v1 — Bowling Center Session
Status: DRAFT
Version: 1.0
Last Updated: 2026-10-19
Owner: Shayne
Feeds:
- Evaluation set v1 (roadmap F1)
- SDR vs HDR validation (P1)
- fail-fast precheck (P2)
- camera-position envelope (X1–X4)
- near-field scale (A1)
- rev rate / loft at 120 fps (A3, A6)
- Form Analysis prototype (X6)

## Before you go
**Equipment**
- iPhone on a tripod or clamp mount, and a phone you can hold by hand.
- Ruby sensor, charged and paired.
- Tape measure (25 ft).
- Optional extras:
  - a second phone, for the Form scenarios
  - a removable white vinyl tape strip for the ball (ask the pro shop or center first; peel it off right after)

**Phone settings** (Settings → Camera)

| Setting | Value |
|---|---|
| Formats | **High Efficiency** (HEVC) |
| Record Video | 1080p HD at 60 fps (changed per scenario below) |
| Record Slo-mo | 1080p at 120 fps (switch to 240 where a scenario says so) |
| **HDR Video** | **Off**, except scenario S4 |
| Auto FPS, Enhanced Stabilization, Action Mode, Lock White Balance | Off |
| Camera mode for 60 fps | **Video** |
| Camera mode for 120 / 240 fps | **Slo-mo** (the file keeps the real frame timestamps) |

**Session sheet.** Write these down once:
- phone model and iOS version
- center, lane pair and lane number
- oil pattern if known
- ball(s): name and cover color
- lighting notes

**Lane etiquette**
- Tripod stays **off the approach and lane bed**.
- Ask the desk before filming.
- Avoid filming other bowlers. Use an end lane pair if you can.

## For every clip
1. Start recording before you pick up the ball. Stop **3 s after the pins settle**, except scenario S14.
2. One shot per clip. Second balls (spares) count; record them too.
3. Keep Ruby running the whole session.
4. Log each shot in the shot log (below): time, scenario, ball, where you aimed (arrow board), hit your mark (y/n), pins left.
5. **After each scenario block:**
   - screenshot the Ruby shot list (rev, speed, loft, tilt, rotation)
   - photograph the scoreboard (pin ground truth)
6. **For every tripod position, measure:**
   - distance behind the foul line (ft)
   - lens height above the approach (ft)
   - lateral position (which board or lane it lines up with)
   - one photo of the setup taken from behind the tripod

## Scenarios
Shot counts are minimums. **Must-have** comes first. If time runs short, stop after Must-have.

### Must-have (~60 shots): Shot Analysis baseline and the capture decisions
| ID | Camera position | Format | Shots | Tests |
|---|---|---|---|---|
| S1 | **Rear-centered tripod:** behind the approach, centered on your lane, ~15–20 ft behind the foul line, lens ~5 ft high. Full lane + pin deck in frame, foul line visible near the bottom | Video 1080p60, HDR off | 12 | Baseline (all metrics) |
| S2 | Same spot as S1 | Slo-mo **1080p120**, HDR off | 12 | 120 fps vs 60 (rev, loft, speed); proposed capture default |
| S3 | Same spot | Slo-mo **1080p240** | 8 | Rev / axis research, decode cost |
| S4 | Same spot | Video 1080p60, **HDR on** | 8 | Paired HDR vs SDR (same position, same day) |
| S5 | Same spot | **4K60** (and **4K120** if your phone offers it) | 6 + 6 | Does 4K add accuracy for its ~3–4× cost? |
| S6 | Same spot, **ball with tape strip** (thumb hole toward PAP) | Slo-mo 1080p120 | 8 | Marker-based rev rate |

### Should-have (~45 shots): flexibility envelope and failure handling
| ID | Camera position | Format | Shots | Tests |
|---|---|---|---|---|
| S7 | **Rear-oblique, 1 lane over** (tripod behind the next approach) | 1080p120 | 8 | Multi-lane separation (X1) |
| S8 | **Rear-oblique, 2 lanes over** | 1080p120 | 5 | Edge of the envelope |
| S9 | **Low** S1 spot, lens ~2.5 ft high | 1080p120 | 5 | Camera height |
| S10 | **High** S1 spot, lens ~6.5 ft (arms up or tall tripod) | 1080p120 | 5 | Camera height |
| S11 | **Far:** back by the settee / concourse, ~30+ ft behind the foul line | 1080p120 | 5 | Small ball, far view |
| S12 | **Handheld** by a friend standing behind the approach, held steady, no tripod | 1080p120 | 8 | Moving camera (DEC-018) |
| S13 | **Occlusion:** S1 spot; once per shot a friend walks across behind the bowler, or you stay at the line blocking the deck | 1080p120 | 4 | Honest "unreadable" / interpolation (A4, A7) |
| S14 | S1 spot; **stop recording ~1 s after the ball hits** (pins not settled) | 1080p120 | 3 | Pins must report "unreadable" |
| S15 | **Bad framing on purpose:** 1 shot with the foul line off the bottom, 1 tilted ~20°, 1 zoomed in so the deck is cut off | 1080p120 | 3 | Fail-fast precheck tuning (P2) |

### Nice-to-have (~25 shots): Form Analysis and calibration extras
| ID | Camera position | Format | Shots | Tests |
|---|---|---|---|---|
| F1 | **Side view:** perpendicular to your approach, 1.5–2.5 lanes away, lens at hip height (~3 ft), landscape, aimed at your last two steps + foul line. **You fill ≥40% of the frame height** | Slo-mo 1080p120 | 10 | Steps, timing, swing (Form spec P1 metrics) |
| F2 | **Rear form view:** behind you, slightly to your bowling-arm side, chest height, landscape, whole approach + foul line | 1080p120 | 5 | Drift, swing plane |
| F3 | With a second phone, record **S2 and F1 at the same time** | both 1080p120 | 6 | Shot ↔ form time alignment (optional) |
| C1 | **Near-field calibration still:** from the S1 spot, take a photo of the empty lane. If you have a LiDAR iPhone, also capture a quick 3D scan from the tripod spot of the approach + first 15 ft (e.g. a free LiDAR scanning app). Tape-measure the camera position | photo / scan | — | Near-field scale (A1); LiDAR feasibility |
| L1 | **Lighting**, if the center has dim / cosmic lighting: S1 spot under it | 1080p120 | 4 | Lighting robustness (X5) |

**Spares:** shoot second balls naturally inside the blocks. Note "spare" and the leave in the log.

## Shot log
Columns, one row per clip:

`clip_file, scenario, shot_no, time, ball, first_or_spare, target_arrow_board, hit_mark(y/n), pins_standing, ruby_speed, ruby_rev, ruby_loft, ruby_tilt, ruby_rot, notes`

- The Ruby columns can be filled in afterwards from the screenshots.
- Time to the minute is enough; clips are matched to Ruby by timestamp.

## Getting the files to me
- **AirDrop to the Mac** with **Options → "All Photos Data"** on, so the originals keep their frame-rate and HDR metadata.
- Or import with Image Capture.
- **Don't** trim, edit or export from Photos. Slo-mo clips must stay as the originals.
- **Folder:** `~/LaneSightData/<date>_<center>/`, with subfolders per scenario (`S1/`, `S2/` …), plus the shot log, Ruby screenshots, scoreboard photos and setup photos.
- When it's ready, tell me, and connect `LaneSightData` in the desktop app.

## What I'll do with it
1. Build evaluation set v1 and a fresh baseline on `main`. Metrics compared to Ruby and the scoreboard, plus success rate and time per shot by scenario.
2. Answer the capture questions with paired data: SDR vs HDR (S1 vs S4), 60 vs 120 vs 240 fps (S1–S3), 4K's value (S5), tape marker (S6).
3. Map the supported camera envelope (S7–S12), and tune the quick-reject check and the "unreadable" handling (S13–S15).
4. Run the first Form Analysis test on F1/F2 and near-field calibration from C1.
