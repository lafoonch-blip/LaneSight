# Uncovered 11/1 clips — first-failing-stage classification (DEC-132 task 2)

Status: FINDING · 2026-11-18 · engine: server production (`ops/production_engine` → `analyze_learned` + classical)

## Scope
The 13 clips **no engine covers** (neither the on-device v17 engine nor the server production engine) from the 11/1
camera-position set (IMG_8963–8981): **8964, 8965, 8968, 8970, 8971, 8972, 8973, 8974, 8975, 8977, 8978, 8979, 8981.**
(8963 on-device, 8966/8967 both, 8969/8976 server — are covered and excluded.)

## First-failing stage on the server production engine (grouped by cause)
| group | n | clips | signal |
|---|---|---|---|
| **pins/contact** | **7** | 8964, 8965, 8970, 8973, 8975, 8977, 8981 | ball track OK (tpts 14–68), `PIN_IMPACT_NOT_DETECTED`, `npins=None/1` |
| track | 5 | 8971, 8972, 8974, 8978, 8979 | `BALL_TRACK_NOT_FOUND`, tpts=0 (no ball track at all) |
| foul | 1 | 8968 | foul-cross / contact mis-timed |

**Classical find_lanes succeeds on all of them** (VP consistent, foul ±≈1 px) — the failures are all DOWNSTREAM of
geometry (ball track, then the pin deck). The classical path emits a speed on several but the production engine
withholds via ENGINE_DISAGREE (it disagrees with the learned best-effort) — correctly, they are not trustworthy.

## Shared root cause — the DEC-118 UNSUPPORTED camera position (contact sheet)
The contact sheet (`/tmp/ls_contact_sheet.png`, regenerable via `scratchpad/classify_uncovered.py`) shows one framing
across all 13: the camera sits **low, behind/beside the ball return** (the red return rack + a rack of colored balls
fill the foreground), **off-axis**, looking down a lane that the **bowler's body frequently occludes**, with the **pin
deck far and small**. This is the `behind-ball-return-offset` / `mounted-centered-POV` class that
`CAMERA_POSITION_SUPPORT_2026-11-02.md` already graded **UNSUPPORTED** (DEC-118: mounted-centered 0/7, behind-ball-return
1/6). The varying first-failing stage is a symptom; the upstream cause is the capture geometry.

## Biggest group (pins/contact, 7) — is it tunable server-side? NO, marginally.
Pins-channel peak score on an early frame (`MCDetector.detect(..,'pins',thr)`), vs the supported reference 8751:
| clip | max pins score | peaks @0.18 | @0.10 | @0.02 |
|---|---|---|---|---|
| **8751 (supported)** | **0.56** | 2 | 3 | 30 (noise) |
| 8970 | 0.40 | 1 | 3 | 30 |
| 8965 | 0.35 | 2 | 2 | 30 |
| 8964 | 0.16 | 0 | 1 | 30 |

The deck is **weakly detectable** (0.16–0.40 vs 0.56). Dropping the threshold to ~0.10 recovers only 1–3 weak pins on
8965/8970 (barely 8964); 0.02 floods to 30 spurious peaks. Too few/weak pins to define a reliable deck ROI, and even
with one the contact timing faces the same raw-frame/occlusion problems (cf. task-1 handheld finding). The 5 `track`
clips fail earlier still (the ball itself is too occluded/far to detect).

## Recommendation
These 13 are a **capture-position limitation (DEC-118 unsupported)**, not a CV detector bug. The highest-value action
is **capture guidance** (rear-centered, square to one lane, foul line + pins in frame — the IMG_8751-54 framing), which
the app already surfaces. Server-side pins-threshold tuning could *marginally* recover 8965/8970 (lower thr + a deck
sanity gate) but it is low value, risks spurious peaks, and chases an unsupported framing — so it is deferred pending a
decision, consistent with "accuracy beats coverage." The real coverage frontier for *supported* clips remains
**on-device frame stabilization** (task-1 note: unblocks 8969/8976/8754 at zero-wrong).
