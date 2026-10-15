# LaneSight Current State
Status: CANONICAL  
Version: 1.8  
Last Updated: 2026-10-15  
Owner: Shayne  
Supersedes: v1.7

## Where these docs live (DEC-025)
- **Source of truth:** GitHub `lafoonch-blip/LaneSight` (`main`). Edit here; read `AGENTS.md` first.
- **Mirrors (read-only):** the Google Drive LaneSight folder and the claude.ai LaneSight Project. Re-sync them after every change.
- **Code:** `lanesight-core/` in this repo (F-02 done 2026-10-14). On Shayne's Mac, `~/Documents/LaneSight/` is a clone of this repo; pull before working.
- The September 2026 local docs are archived in `99_ARCHIVE/2026-09-27_local_folder/`. Historical only.

## Building now
The back end (DEC-017), stage by stage: metrics engine → moving camera → scoring/stats → insights/adjustments → profile/arsenal/oil/sensor → replay payload. UI and cloud come after.

## Where things stand
- `lanesight-core` in `lanesight-core/` (50 tests passing, re-run 2026-10-15):
  - automatic video pipeline: tripod + handheld, pin reading, rev rate
  - scoring/stats, insights/adjustments, spare targeting
  - Postgres schema
  - shot record + replay
  - capture-tier and sensor capability engine
- At-lane local runner built (`lanesight-core/lanesight_runner/`, `03_ENGINEERING/LOCAL_RUNNER_SPEC.md` v1.2): AirDrop → Mac analysis → shot card + spoken adjustment, pin correction, Ruby entry, CSV export. **Verified end-to-end on the Mac (2026-10-14)**: IMG_8754/IMG_8751 run through the real server and reproduce the validation numbers within tolerance (speed ±0.1 mph, rev/pins exact, boards ≤1). The iPhone validation clips are HDR and this Mac's ffmpeg lacks zscale, so `convert_sdr` now has a portable numpy HLG→SDR fallback (no libzimg needed); recommended capture is still SDR (HDR Video off). **Shot-window trimming done (2026-10-14):** a motion pre-pass finds the ~6–9 s shot and trims the dead set-up time — IMG_8754 went 279 s → 81 s (3.4×), numbers preserved; the trimmed shot then replaces the stored clip (~102 MB → ~31 MB).
- **Runner v2 UI rebuilt (2026-10-15, `03_ENGINEERING/runner_v2/RUNNER_V2_SPEC.md`):** single-page dashboard (all panels full-width, no tabs) — Latest Shot (clip/lane view + oil toggle + board/arrow guides, Shot Metrics with vs-avg deltas, split What-went-well / What-to-watch analysis), Session Overview (5 KPIs, metrics chart, accuracy/consistency rings, shot-distribution scatter), Shots list, Lane Transition (status + trend rows). Full **Ruby sensor integration**: per-shot entry (axis tilt/rotation, PAP over/up, setup + pushaway/backswing/downswing/release timing, swing height; "Copy last shot") shown in the Rotation panel with an axis diagram and approach-breakdown bars, all labeled "Ruby" (see `01_PRODUCT/SENSOR_VS_VIDEO_METRICS.md`).
- **CV accuracy hardening (2026-10-15):** pale / low-contrast lanes now detect via a dark gutter-edge fallback; impact time is fixed to when the ball reaches the pins (its farthest tracked point), correcting an inflated distance scale; the post-shot trim tail was lengthened so pins settle in view, **decoupled** from the stabiliser so it never perturbs the shot metrics; and crash guards were added for off-frame foul lines and sparse tracks.
- **Pin reading is video-only and honest (DEC-026):** when the deck is blocked (bowler steps in) or the clip ends before the pins settle, the result is reported **unreadable** with a reason and excluded from strike/open/carry stats — never a guessed strike. Fix pins to record the real result.
- **First live lane session held 2026-10-15** (practice, ball + Ruby S2, ~21 shots recorded, 14 analyzed). Next: Ruby↔video shot matching by timestamp (M5-05), continued accuracy on marginal / off-angle clips, and staged results (fast metrics first).
- Validated against Ruby on 4 shots (pre-session baseline):
  - Speed is within 0.5% on 3 of 4 shots.
  - Loft is within ~1 frame.
  - Rev rate tracks Ruby at a stable ratio.
  - Pins: 14 of 14 runs correct (the live-session clips add real occlusion/framing cases — see pin honesty above).
- The capture-tier test (30/60 fps × 720/1080p) set provisional per-tier guarantees. See `01_PRODUCT/METRIC_CAPABILITIES.md` and DEC-023 (proposed).
- Details: `02_RESEARCH/VIDEO_VS_RUBY_VALIDATION.md`.

## Validation roadmap (`02_RESEARCH/VALIDATION_PLAN.md`)
- **Ruby:** in hand.
- **Witsee and F5 sensors:** Shayne plans to acquire both for cross-sensor validation of rev rate, axis tilt/rotation and release speed.
- **Specto center sessions:** planned, as ground truth for lane position (foul-line board, launch angle, entry board/angle, entry speed). Specto is the key reference for the Stage 1 gate.

## MVP (DEC-019)
- Shot metrics with confidence: speed, rev rate, loft, laydown, arrows, breakpoint board/distance, entry board/angle, pin leave; axis and PAP where feasible
- Fixed and moving camera (DEC-018)
- Virtual replay: trajectory, heatmap, key points
- Insights and next-shot adjustments from the shot + pins; spare targeting
- LaneTalk-parity stats: strike %, spare %, conversion by leave, opens, first-ball average, pocket/carry
- Bowler profile, arsenal with drilling/layout, ball per shot/session
- Session and all-time trends
- Oil pattern library
- Optional sensor pairing with variance display (DEC-021)
- UI, then cloud storage and instant at-lane analysis

## Not MVP
- League integration/registration
- League management
- USBC membership connection
- Team Lane Management
- Center scoring integrations (assumed later via `ScoringAdapter`; DEC-020)
- Payments

## Current blockers / discovery
- Seed Dataset v1: 30–50 varied shots with sensor data, some at 240 fps (~21 captured in the 2026-10-15 live session with Ruby S2, varied camera distance; none at 240 fps yet)
- Ruby export: no confirmed file export; Ruby data is hand-entered today. Confirm what the app can export (R-02) so shot-matching (M5-05) can be automated
- Specto session(s): find a local Specto center and confirm data access/export
- Witsee + F5 purchase; confirm what data each app exports
- Meta glasses test clips, native recording + live stream. Third-party live stream is reportedly capped at 720p/30.
- Decision on DEC-023 (minimum capture requirements)

## Latest major strategic decision
Back end first, with moving-camera measurement and coaching/stats in MVP (DEC-017/018/019).

## Brand
- Master brand: LaneSight
- Preferred mark: LS Monogram with lane/trajectory motif
- Tagline: See More. Bowl Smarter.
