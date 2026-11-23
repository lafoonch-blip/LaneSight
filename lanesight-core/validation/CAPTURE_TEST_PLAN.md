# Capture test plan — paired-fps / format validation (DEC-133)

Status: ACTIVE · Version: 1.0 · Last Updated: 2026-11-23 · Owner: Shayne
Purpose: the clips needed to decide whether to **promote the in-app recording default above 1080p120 SDR** (DEC-133
work items 12/15/16). Until these pass the DEC-118 Shot + Form gates at a higher format, the shipped default stays
**1080p120 SDR (Form floor 60)**. These are **not recorded yet** — this is the capture recipe for Shayne.

## How to shoot it
- **Same position, same day, same lane, same ball, same line** for every scenario, so the only variable is the
  capture format. Camera behind the approach, square to the lane, foul line + pins in frame.
- **~6 shots per scenario** (enough for a mean + spread), plus **2–3 Form deliveries** per scenario where the frame
  rate supports Form (≥60). Label each clip with its scenario id.
- **Specto** reference where available for ball speed / rev / axis (Ruby removed — DEC-105). Note when Specto is on.
- Keep the phone **plugged in or full**, and note **thermal state** (Settings battery / a visible warning) after the
  last scenario — heat is a real limit at high fps (DEC-133 §1.2).

## Scenarios
| Id | Format | Dynamic range | What it answers |
|----|--------|---------------|-----------------|
| S1 | 1080p **60** | SDR | Baseline (today's validation + the 1.12 rev factor live here) |
| S2 | 1080p **120** | SDR | The proposed default. Rev precision gain (±40→±20 rpm); loft/axis/PAP become possible |
| S3 | 1080p **240** | SDR | Rev precision ceiling (±10 rpm); device-load worst case |
| S4a | 1080p120 | **HDR on (HLG)** | HDR→SDR tone-map vs the SDR baseline — DEC-113 showed a bad tone-map breaks ball tracking |
| S4b | 1080p120 | SDR (HDR off) | The paired SDR control for S4a |
| S5 | **4K 60** (and 4K120 if the phone offers it) | SDR | Does 4K add measured accuracy? (cost review said no; confirm on device) |

## What each scenario feeds
- **Item 12 (device benchmark):** for every scenario — time per shot, peak memory, battery drain, heat over a full
  ~30-shot session on the target iPhone. Gate: DEC-118 **< 30 s** per shot, no thermal throttle mid-session.
- **Item 15 (rev factor):** re-measure the 1.12 rev-rate factor at **120 and 240** vs Specto; DEC-094 §4 — blind-
  validate or remove. Record the factor + spread per fps.
- **Item 16 (promotion gate):** a higher default ships **only if** the DEC-118 Shot gate (±0.5 mph speed, board
  accuracy) **and** the Form gate hold at that format. Otherwise the default stays 1080p120 SDR. Record the decision
  + the numbers in the promotion commit (DEC-133 §2C).
- **Item 9 (HDR set):** S4a/S4b (plus the existing HDR clips IMG_8751, IMG_8754, IMG_8831) go into the on-device
  HDR validation set; check ball tracking on the tone-mapped SDR against the native-SDR baseline.

## Where the clips go
- Under `~/LaneSightData/` (never the repo). Add a `capture_test/<date>/<scenario>/` layout; label clips + Specto
  readings in a sidecar `truth.json` per scenario (same shape the 22-clip gate uses).
- Report the results back by updating this file's status + the DEC-133 report; the promotion itself is a separate
  commit with the numbers.
