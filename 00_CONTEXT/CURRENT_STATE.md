# LaneSight Current State
Status: CANONICAL  
Version: 1.7  
Last Updated: 2026-10-14  
Owner: Shayne  
Supersedes: v1.6

## Where these docs live (DEC-025)
- **Source of truth:** GitHub `lafoonch-blip/LaneSight` (`main`). Edit here; read `AGENTS.md` first.
- **Mirrors (read-only):** the Google Drive LaneSight folder and the claude.ai LaneSight Project. Re-sync them after every change.
- **Code:** `lanesight-core/` in this repo (F-02 done 2026-10-14). On Shayne's Mac, `~/Documents/LaneSight/` is a clone of this repo; pull before working.
- The September 2026 local docs are archived in `99_ARCHIVE/2026-09-27_local_folder/`. Historical only.

## Building now
The back end (DEC-017), stage by stage: metrics engine → moving camera → scoring/stats → insights/adjustments → profile/arsenal/oil/sensor → replay payload. UI and cloud come after.

## Where things stand
- `lanesight-core` v0.6 in `lanesight-core/` (21 tests passing, re-run 2026-10-14):
  - automatic video pipeline: tripod + handheld, pin reading, rev rate
  - scoring/stats, insights/adjustments, spare targeting
  - Postgres schema
  - shot record + replay
  - capture-tier and sensor capability engine
- At-lane local runner built (`lanesight-core/lanesight_runner/`, `03_ENGINEERING/LOCAL_RUNNER_SPEC.md` v1.2): AirDrop → Mac analysis → shot card + spoken adjustment, pin correction, Ruby entry, CSV export. **Verified end-to-end on the Mac (2026-10-14)**: IMG_8754/IMG_8751 run through the real server and reproduce the validation numbers within tolerance (speed ±0.1 mph, rev/pins exact, boards ≤1). The iPhone validation clips are HDR and this Mac's ffmpeg lacks zscale, so `convert_sdr` now has a portable numpy HLG→SDR fallback (no libzimg needed); recommended capture is still SDR (HDR Video off). **Milestone 4 shot-window trimming done (2026-10-14):** a motion pre-pass finds the ~6–9 s shot and trims the dead set-up time before analysis — IMG_8754 went 279 s → 81 s (3.4×), SDR ~3×, numbers preserved; the trimmed shot then replaces the stored clip (~102 MB → ~31 MB). Next: first live lane session, then Milestone 4 staged results (fast metrics first).
- Validated against Ruby on 4 shots:
  - Speed is within 0.5% on 3 of 4 shots.
  - Loft is within ~1 frame.
  - Rev rate tracks Ruby at a stable ratio.
  - Pins: 14 of 14 runs correct.
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
- Seed Dataset v1: 30–50 varied shots with sensor data, some at 240 fps
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
