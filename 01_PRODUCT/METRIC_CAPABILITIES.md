# Metric Capabilities: capture tiers and sensor pairing
Status: DRAFT (pending decision on DEC-023)  
Version: 1.0  
Last Updated: 2026-10-14  
Owner: Shayne

What LaneSight can promise a user depends on two things: **how the shot was recorded**, and **whether a sensor is paired**. The back end decides this automatically for every shot (`lanesight_core/capabilities.py`). Each metric gets one of four labels:
- **Guaranteed:** validated at this tier; shown normally.
- **Best effort:** runs, shown with a confidence badge.
- **Sensor:** comes from the paired sensor, labeled with the source.
- **Unavailable:** never a guessed number.

> Evidence base: 4 Ruby-paired shots, each re-encoded at 60 fps/720p, 30 fps/1080p and 30 fps/720p (15 analysis runs). These "guarantees" are provisional until the 30–50 shot Seed Dataset passes the Stage 1 gate.

---

## 1. Capture tiers

| Tier | Requirement | Typical devices |
|---|---|---|
| **Unsupported** | <24 fps, ball <20 px at the foul line, or lane/pins not fully in frame | Old webcams; zoomed-in clips |
| **Base** | ≥30 fps, ≥720p, whole lane + pins in frame, steady camera | Any phone at default video settings; Ray-Ban Display (30 fps) |
| **Standard (recommended)** | ≥60 fps, ≥1080p | Most phones from the last several years (1080p60 setting); Ray-Ban Meta Gen 2 (up to 60 fps) |
| **High frame rate (HFR)** | ≥120 fps slo-mo, ≥1080p | iPhone/Android slo-mo modes |
| **Moving camera** (handheld, head-mounted, glasses) | Same metrics, but guarantees require ≥60 fps | A handheld clip at 30 fps/1080p failed lane detection; at 60 fps it worked |

### Recommended minimum requirement (decision needed: DEC-023, proposed)
- **Hard minimum:** Base (30 fps, 720p, full lane + pins visible). Below this, LaneSight refuses with a clear "can't analyze" message.
- **Recommended setting:** Standard (1080p, 60 fps). The app should default the camera to 1080p60 and nudge users who record at 30 fps ("switch to 60 fps to unlock loft, entry angle and speed profile").
- **Slo-mo (≥120 fps):** reserved for axis and PAP once built, as an opt-in "deep analysis" capture.

## 2. Video-only metrics by tier

Errors are mean absolute error (MAE) vs Ruby, or vs the full-quality 60 fps/1080p run where Ruby has no equivalent.

| Metric | Base (30 fps / 720p) | Standard (60 fps / 1080p) | HFR (120–240 fps) | Evidence |
|---|---|---|---|---|
| Ball speed (Ruby-comparable) | **Guaranteed** | **Guaranteed** | Guaranteed | MAE vs Ruby: 0.17 (full), 0.21 (60/720), 0.22 (30/1080), 0.28 mph (30/720) |
| Pin result / leave / strike | **Guaranteed** | **Guaranteed** | Guaranteed | 14 of 14 runs correct. A pin hidden behind a standing front pin is flagged as uncertain |
| Game stats (strike %, spare %, conversion…) | **Guaranteed** | **Guaranteed** | Guaranteed | Derived from pin reading + manual correction |
| Trajectory / replay / heatmap | **Guaranteed** | **Guaranteed** | Guaranteed | |
| Laydown board | **Guaranteed** | **Guaranteed** | Guaranteed | ≤0.5 board (needs the foul-line area visible) |
| Arrows board (15 ft) | **Guaranteed** | **Guaranteed** | Guaranteed | ≤0.15 board |
| Breakpoint board | Best effort | **Guaranteed** | Guaranteed | 0.2 board (60/720, 30/1080); 0.8 board (30/720) |
| Entry board | Best effort | **Guaranteed** | Guaranteed | 0.6–0.7 board (60/720, 30/1080); 1.7 board (30/720) |
| Entry angle | Best effort | **Guaranteed** | Guaranteed | 0.25° (60/720); 0.74° (30/720) |
| Speed profile (early/late) | Best effort | **Guaranteed** | Guaranteed | Late speed off 0.7–1.4 mph below 60 fps |
| Loft | Unavailable | **Guaranteed** | Guaranteed | Needs per-frame touchdown (1 frame = 0.9 ft at 30 fps); MAE 0.37 ft vs Ruby at 60 fps |
| Breakpoint distance (geometric) | Best effort | Best effort | Best effort | Varies ±1.3–2.6 ft between captures; shown as a range |
| Launch angle | Best effort | Best effort | Best effort | Low confidence everywhere so far |
| Rev rate | Best effort | Best effort | Best effort → target guaranteed | Within ~5–8 rpm of Ruby even at 30 fps, but the conversion factor was fitted on these same shots. Needs blind validation |
| Axis tilt / axis rotation | Unavailable | Unavailable | Planned | Spin-axis fit from surface motion; needs ≥120 fps |
| PAP | Unavailable | Unavailable | Planned | Needs a grip reference: finger-hole tracking at 240 fps, a marker, or profile entry |
| Approach timing, swing height | Unavailable | Unavailable | Unavailable | Out of scope (the bowler isn't tracked; DEC from 2026-10-13) |

What changes below 60 fps: the last ~0.2 s before impact and the touchdown moment are sampled too coarsely. Timing metrics (speed, impact, pins) barely move. Far-end geometry (entry, late speed) and loft are what degrade.

## 3. Sensor-enabled metrics

Pairing a sensor adds release-physics metrics video can't measure, and enables variance views on overlapping metrics (DEC-021). Sensor field mapping lives in `lanesight_core/sensors.py`.

| Metric | Video | Ruby | F5 (Storm) | Witsee | Compare / note |
|---|---|---|---|---|---|
| Ball speed | ✓ release→impact avg | ✓ (timing-based) | ✓ *release* speed | ✓ release speed | Ruby is directly comparable. F5/Witsee release speed is compared to video **early speed**, not the average |
| Rev rate | ✓ best effort | ✓ | ✓ | ✓ | Variance shown |
| Loft | ✓ (≥60 fps) | ✓ | — | — | Variance shown |
| Axis tilt | planned (HFR) | ✓ | ✓ | ✓ | Sensor-sourced today |
| Axis rotation | planned (HFR) | ✓ | ✓ | ✓ | Sensor-sourced today |
| PAP | planned | ✓ (once configured) | — | — | |
| Breakpoint / skid / hook / roll lengths | Geometric breakpoint only | ✓ rotational phases | — | — | **Not the same metric** as the video breakpoint. Shown side by side, never merged |
| Track flare | — | — | ✓ | — | Sensor only |
| Rev-to-speed ratio | derivable | derivable | ✓ | derivable | |
| Swing height | — | ✓ | — | ✓ | Approach metric |
| Approach timing (setup, pushaway, backswing, downswing, release) | — | ✓ | — | partial ("free swing") | Approach metrics |
| Release score, setup hand position | — | ✓ | — | — | Vendor-specific |
| Laydown, arrows, breakpoint board, entry board/angle, pin result, game stats | ✓ | — | — | — | **Video only**: sensors in the ball don't see the lane |

**Sources:**
- Ruby: what the Ruby app showed on 2026-10-13 (vendor not confirmed publicly).
- F5: stormbowling.com/f5-bowling-sensor.
- Witsee: bowlinglife.eu (2026-06-25).
- **Data access is unverified for all three.** None publicly documents an API or export, so pairing may start as manual or screenshot entry until a partnership exists (R-02).

## 4. How this shows up in the product
- Before analysis, the app reads the clip's fps, resolution, steadiness and framing and assigns a tier.
- Metric cards show **Guaranteed** normally, **Best effort** with a confidence badge, and **Unavailable** with the reason ("record at 60 fps to unlock loft").
- With a sensor paired, sensor-only metrics carry a source label (e.g. "Ruby"), and overlapping metrics show "LaneSight vs Ruby: +0.1 mph".

## 5. Caveats and next steps
- 4 shots is not a guarantee. Re-run this matrix on the Seed Dataset (M1-14/15) before any accuracy claim reaches users.
- Moving camera: only one handheld clip has been tested. A head-mounted/glasses clip is needed (M2-05).
- Pin-rack alignment ("snap") sometimes reaches its search limit. Results were correct in all 14 runs, but this needs a better objective before beta.
- Rev-rate conversion factor: needs blind validation, plus a test of how motion blur at 30 fps affects it.
