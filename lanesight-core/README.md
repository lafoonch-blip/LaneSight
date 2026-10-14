# lanesight-core v0.6.0

The LaneSight back end, Stages 1–6 of Build Plan v2. It's pure Python with no UI and no cloud. Everything here is meant to run unchanged behind the FastAPI service later.

```
python -m lanesight_core.cv.pipeline VIDEO.mov OUT [--handed R|L] [--sensor sensor.json] [--pattern-length 41]
python examples/demo_session.py        # 4 validation shots as one session (needs the cached shot JSONs)
python -m pytest                       # 21 tests: scoring, stats, splits, insights, spares, capabilities
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
python3 -m pytest                       # 21 tests
python3 -m lanesight_core.cv.pipeline /path/to/IMG_8754.MOV out/IMG_8754 --sensor validation/IMG_8754_ruby.json
```
Each shot takes a few minutes on CPU (stabilization dominates).
