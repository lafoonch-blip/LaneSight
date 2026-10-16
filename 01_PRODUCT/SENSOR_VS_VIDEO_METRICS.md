# Sensor vs Video Metrics (Ruby reference)
Status: DRAFT
Version: 1.3
Last Updated: 2026-10-16
Owner: Shayne
Source: 18 Ruby app screenshots (IMG_8787–8804, `~/Documents/Ruby Screenshots`), league session 10/13/2026 (23 shots, ball S2); `lanesight_core/sensors.py`; `01_PRODUCT/METRIC_CAPABILITIES.md`.

Purpose: decide which metrics LaneSight calculates from video alone, which come only from a Ruby (or other sensor), and which both produce. Every Ruby value in LaneSight is labeled "Ruby" and today is entered by hand; Ruby has no confirmed export (R-02).

## What the Ruby app shows
- **Per shot (Shot detail):** rev rate, ball speed, setup time, swing height, downswing, backswing, approach time, loft distance, release score; Ball Phases (skid length, breakpoint ft, hook length, roll); PAP (over/up, needs ball specs); axis tilt; axis rotation; tags: ignore shot, shot type (strike/spare/gutter), ball.
- **Approach breakdown:** start, pushaway, backswing, downswing, release (seconds).
- **Setup hand position:** ball orientation at setup (top/side sphere view).
- **Session:** consistency score 0–100 from strike shots, with the biggest lever ("improving rev rate consistency…"); per-metric rating (High / Fast / Slow / Med) and tag (Steady, Average, Above/Below Avg, Increasing); Lane Transition = Ruby breakpoint distance per shot over time; per-metric time-series charts (rev rate, speed, loft, setup, swing, backswing, downswing).
- **Sessions list:** time, breakpoint bar, rev rate, speed, tilt, rotation, PAP, ball, setup, approach, loft.
- **Trends (1W–1Y):** rev rate, speed, loft, PAP, axis tilt + rotation, setup time, approach.
- **Arsenal:** sensors and balls with saved specs (needed for PAP).

## 1. LaneSight from video, no sensor
| Metric | Status today | Notes |
|---|---|---|
| Ball speed (release→impact) | Validated | Ruby-comparable definition |
| Early speed, pocket (late) speed | Validated at ≥60 fps | Ruby gives one speed only |
| Loft distance | Validated at ≥60 fps | ±0.45 ft |
| Laydown, arrows, breakpoint **board** | Validated | Ruby has no board positions |
| Entry board, entry angle | Validated (path reaches pins) | Ruby has none |
| Launch angle | Estimate | Low confidence so far |
| Breakpoint **distance** (geometric) | Estimate | Not Ruby's breakpoint (see §2) |
| Rev rate (video) | Estimate **with a precision band**; **unavailable** when the spin period can't be read | Reports `value ± band`, band = `rev²/(60·fps)` ≈ ±40 rpm at 60 fps, halving at 120 (DEC-028). At 60 fps the whole-frame-lag quantum limits resolution — distinct throws (Ruby 378–444) can collapse to one value, so the band, not the centre, is the honest part. Rail landing → unavailable, never the ceiling (DEC-027). Blind-validate the factor; real gain needs 120 fps |
| Pins / leave / strike / split | Validated; **unreadable** when the deck can't be seen | Ruby can't see pins. Read from video only; reported unreadable (never guessed) when the bowler blocks the deck or the clip ends too soon — DEC-026 |
| Power | Estimate | Proposed DEC-024 |
| Strike %, spare %, pocket %, carry %, game score | Calculated | From pins + order |
| Lane transition (board-based: breakpoint + entry drift) | Calculated | Ruby's is distance-only |
| Consistency (boards, speed, revs) + target accuracy | Calculated | Our own score; needs a DEC for the formula |
| Next-shot adjustments, spare targeting | Calculated | Ruby gives none |
| Ratings + trend tags (High/Steady/Increasing…) | Calculated | Same idea as Ruby, our thresholds |

## 2. Both (LaneSight shows the difference when Ruby is entered)
| Metric | Comparable? | Notes |
|---|---|---|
| Ball speed | Yes | Within 0.5% on 3 of 4 validation shots |
| Rev rate | Yes | Video reads ~11% lower before the sensor factor |
| Loft distance | Yes | |
| Breakpoint distance | **No** | Ruby = where skid ends and hook starts (rotational). LaneSight = where the path turns (geometric). Show side by side, never as a difference |
| Lane transition | Partly | Ruby tracks breakpoint ft; LaneSight tracks boards. Show both when Ruby data exists |
| Consistency score | No | Different inputs; don't compare numbers |

## 3. Ruby only (labeled "Ruby", manual entry for now)
| Metric | Could video do it later? |
|---|---|
| Axis tilt, axis rotation | Possibly with 120–240 fps (planned, M1-10/11) |

### Why enter axis tilt + rotation (worth the manual typing)
Video gives LaneSight **what the ball did** — boards, breakpoint, entry angle, speed. Axis tilt (roller ↔ spinner) and axis rotation (forward-roll ↔ side-roll) are **why it did it**, and that is what makes a recommendation correct:
- **Separates the lane from the release.** Two shots with identical speed and rev can read completely differently down-lane if the axis differs. Without axis, when the breakpoint moves the adjustment engine (M4-03/05) can't tell "you changed your hand" from "the lane transitioned" — the difference between a feet move and no move.
- **Makes rev rate actionable.** 400 rpm at 60° rotation hooks nothing like 400 at 20°; axis is the context that turns the rev number into advice (hand-position change vs. ball/surface change).
- **A directly coachable consistency metric.** Axis SD across a session isolates release repeatability — Ruby's usual "biggest lever" — which path data alone can't separate from lane effects.
- **Ground truth for M1-10.** The planned video-based axis estimate (period-lag surface flow at 120–240 fps) can't be blind-validated without paired Ruby axis data. Entering tilt/rotation on validation shots now builds that labeled set.

Cost: manual entry, labeled "Ruby," one more field per shot. Worth it on calibration shots and when diagnosing a release problem; skip it on casual shots.
| PAP (over/up) | Possibly at 240 fps (finger-hole tracking) or from your layout entry |
| Skid / hook / roll lengths (Ball Phases) | No: needs spin vs speed. Video's geometric turn point is a different thing |
| Setup time | Only with bowler tracking (scoped out; possible tripod-only extra) |
| Approach time; pushaway / backswing / downswing / release splits | Same as above |
| Swing height | Same as above |
| Setup hand position | No |
| Release score | No (Ruby's own score) |

## 4. From your input (either way)
Ball used + specs (arsenal), oil pattern, target line, hit your mark, shot tags (ignore shot), pin corrections.

## Implications
- **Without a Ruby**, every screen works on §1 alone.
- **With a Ruby**, the Rotation tab, approach/swing timing and Ball Phases fill in, all labeled "Ruby".
- Manual Ruby entry **implemented in the runner** (Rotation panel, grouped Release-&-axis / Swing-&-approach / Compare-to-video, with "Copy last shot"): axis tilt, axis rotation, PAP over, PAP up, setup s, pushaway s, backswing s, downswing s, release s, swing height ft, plus speed/rev/loft for the video-vs-Ruby variance. Still to add when wanted: breakpoint ft, skid/hook/roll (Ball Phases), release score, approach-total. (`sensors.py` maps the core set; add any missing keys it needs.)
- Ruby's best ideas worth matching from our own data: a session consistency score with "biggest lever" advice, ratings + trend tags on every metric card, per-metric time-series cards, and multi-session Trends.
