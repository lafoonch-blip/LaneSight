# lanesight-core v0.6.0

The LaneSight back end, Stages 1–6 of Build Plan v2. It's pure Python with no UI and no cloud. Everything here is meant to run unchanged behind the FastAPI service later.

```
python -m lanesight_core.cv.pipeline VIDEO.mov OUT [--handed R|L] [--sensor sensor.json] [--pattern-length 41]
python examples/demo_session.py        # 4 validation shots as one session (needs the cached shot JSONs)
python -m pytest                       # 36 tests: core + runner
```

## Layout
| Module | What it does |
|---|---|
| `cv/stabilize.py` | Registers every frame to the lane plane: tripod, handheld, head-mounted |
| `cv/lanes.py` | Finds lane edges, the shared vanishing point and the foul line automatically |
| `cv/track.py` | Ball candidates, RANSAC trajectory linking, airborne extension, impact and touchdown |
| `cv/refine.py` | Re-measures the ball with a per-video color model |
| `cv/metrics.py` | Lane homography; speed, loft, boards (absolute: 1 = right gutter), breakpoint, entry |
| `cv/pins.py` | Pin reading: standing / uncertain (hidden behind a front pin) / strike |
| `cv/revrate.py` | Rev rate from surface-pattern periodicity |
| `cv/pipeline.py` | Video → `ShotRecord`, plus insights, spare plan and sensor variance |
| `models/shot.py` | The `ShotRecord` contract (schema `shot-1.0`); every value is a Measurement with source, confidence and status |
| `models/schema.sql` | Postgres/Supabase schema: profile, arsenal + versioned drilling, oil patterns, sessions/games/frames/rolls, shots, measurements, pins, sensors, variance view, recommendations, row-level security |
| `scoring/` | Game scoring, splits, leaves, LaneTalk-parity stats (strike/spare/conversion by leave, pocket/carry, strings, clean games...), grouping by session/ball/pattern/lane |
| `insights/` | Hit reading, leave diagnosis, execution vs intent, strike moves (2-and-1), lane transition, spare targeting (straight-line + 3-6-9), session summary/consistency/heatmap |
| `replay/render.py` | Top-down replay PNG and session heatmap |

## Validation (4 shots vs Ruby)
- **Speed:** −0.5% to +3.3%.
- **Loft:** within 0.13–0.73 ft.
- **Rev rate:** within ±3%, using a sensor factor fitted on these same shots. It needs blind validation.
- **Pin reading:** 4 of 4 correct (one 3-6-10 leave, three strikes).
- **Not yet measured from video:** axis tilt/rotation and PAP. They come back as `unavailable`, never a made-up number.

Details are in the project doc `02_RESEARCH/VIDEO_VS_RUBY_VALIDATION.md`.

## Where this came from / reproducing
Built in a cloud Claude session (2026-10-13/14). Under git in `lafoonch-blip/LaneSight` since 2026-10-14. The validation inputs are your original iPhone clips IMG_8751–IMG_8754 (60 fps, Ruby shots #14/#16/#17/#18). Their outputs are in `validation/`: `*_shot.json` is the pipeline result, `*_ruby.json` is the Ruby app values, and `capture_tier_scores.json` is the 30/60 fps × 720/1080p test.

```
cd lanesight-core
python3 -m pip install -e '.[dev]'      # numpy, opencv-python-headless, matplotlib, pytest; also needs ffmpeg/ffprobe (brew install ffmpeg)
python3 -m pytest                       # 36 tests
python3 -m lanesight_core.cv.pipeline /path/to/IMG_8754.MOV out/IMG_8754 --sensor validation/IMG_8754_ruby.json
```
Each shot takes a few minutes on CPU (stabilization dominates).

## At-lane runner (`lanesight_runner/`)
A local web app on your Mac: the iPhone records, you AirDrop the clip, and the Mac analyzes it, shows the shot card and reads the adjustment aloud. Spec: `03_ENGINEERING/LOCAL_RUNNER_SPEC.md`.

**One-time setup (Terminal):**
```
brew install ffmpeg                                  # if you don't have it
cd ~/Documents/LaneSight && git pull
cd lanesight-core
brew install python@3.12                             # macOS's built-in python3 is 3.9: too old
python3.12 -m venv .venv && source .venv/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install -e '.[runner,dev]'
python3 -m pytest                                    # 36 tests should pass
```
The first time it reads `~/Downloads`, macOS asks whether Terminal may access Downloads. Allow it (or later: System Settings > Privacy & Security > Files and Folders > Terminal).

**Each session:**
```
cd ~/Documents/LaneSight/lanesight-core && source .venv/bin/activate
python3 -m lanesight_runner          # opens http://127.0.0.1:8765
```
1. Start a session: type, ball, weight (needed for Power), pattern.
2. iPhone on a tripod behind the approach, 1080p at 60 fps, one clip per shot. Not Slo-mo: a slo-mo clip shared as a slowed video would make speeds wrong.
   **Turn off HDR video:** Settings > Camera > Record Video > HDR Video off. HDR clips decode with washed-out colors, so the runner has to tone-map them to SDR first (it does this automatically, but it adds time to every shot).
3. AirDrop each clip to the Mac. The runner picks up new videos in `~/Downloads` once the file stops growing, says "Shot N received", analyzes it and speaks the result. You can also drag a clip onto the page.
4. Between shots: target line (applies to the next shots), hit your mark (keys Y / N / U), pin corrections, Ruby values, thumbs up/down on the adjustment.
5. Export the session CSV for the eval harness.

**Notes**
- Data goes to `~/LaneSightData` (clips, results, `lanesight_runner.db`), not the repo: Documents may sync to iCloud. Change with `--data`.
- Options: `--watch DIR`, `--port N`, `--no-speech`, `--no-open`.
- A clip is rejected, never guessed at, if its frame timestamps are broken or OpenCV decodes a different number of frames than the file has. If OpenCV can't decode HEVC, set iPhone Settings > Camera > Formats > Most Compatible.
- Speed: analysis takes a few minutes per clip on CPU today (stabilization dominates). Each card shows the time taken; the per-step times are stored for Milestone 4 (speed-up).
- Badges: ✓ = validated at this capture tier, EST = estimate, N/A = unavailable with the reason. Power is a proposed metric (DEC-024), always an estimate, and not a carry score.
