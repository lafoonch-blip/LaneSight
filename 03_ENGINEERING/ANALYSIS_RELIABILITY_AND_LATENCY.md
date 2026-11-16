# Analysis reliability + latency — measured plan
Version: 1.0 · 2026-10-29 · Owner: Shayne
Goal: cut the failure rate and the per-shot analysis time, **measured from real production traffic** (DEC-092: measure before changing the CV; every change passes the ±0.2 mph / ±0.5 board regression gate on the validation clips, no new failures). Complements `CLOUD_RUN_PERF_INVESTIGATION.md` (the vCPU/decode gap) with the **per-stage** picture.

## Measured today (server, `analysis_attempt`, rev ≤00050)
### Latency — a typical analyzed clip (14.7 s / 7131 frames), ~166 s of CV:
| Stage | Time | Share | Lever |
|-------|------|-------|-------|
| **stabilize** | **~107 s** | **~65%** | **skip registration on static (tripod) clips — DONE below** |
| extract_blobs (ball) | ~25 s | 15% | downscale / ROI to the lane strip |
| decode (9 passes) | ~35 s | — | **cache is OFF** (`cache_mb=0`): full-res 1080p frames exceed the 1000 MB budget → re-decodes 9×. Cache at WORKING resolution instead. |
| read_pins | ~11 s | 7% | only the settle-tail frames need it |
| refine / detect_impact / link / extend / rev_rate | ~3–6 s each | — | — |
| window/trim detect | ~8 s | — | **trim finds no window** (`window=null`) on these clips → the WHOLE clip is processed. Robust trim ≈ halves everything. |

### Failures — ~48% of attempts (13/27 all-time):
| code | n | avg_s | note |
|------|---|-------|------|
| (analyzed) | 14 | 174 | even successes are slow; max 371 s |
| FOUL_LINE_NOT_IN_VIEW | 3 | 124 | **now fast-rejected** by the enforced precheck (2026-10-29) |
| BALL_TRACK_NOT_FOUND | 2 | **327** | slow failure — the ball track robustness frontier |
| PIN_IMPACT_NOT_DETECTED | 2 | 178 | far/foreshortened views |
| LANE_NOT_DETECTED_NO_EDGES | 2 | 38 | fast fail (good) |
| TRACK_TOO_SPARSE_FOR_SPEED | 1 | 209 | ball track too short |
| LANE_GEOMETRY_UNUSABLE / FORM_* / INTERNAL_ERROR | 1 each | — | — |

**Two problems:** (1) latency is dominated by stabilization; (2) ~half of attempts fail, mostly ball-track / framing, and failures are often SLOW (fail late).

## Priorities (by measured impact)
1. **Latency P0 — stabilize (65%). DONE (2026-10-29).** Static-camera shortcut: a ~0.5 s probe (register ~30 frames against the reference with the real registrar) measures true camera motion; a tripod (<1 px) skips the per-frame ORB registration entirely (identity homographies, sub-pixel no-op warps). On Cloud Run a ~3-min tripod analysis → ~1 min. Gated: 8751/8752/8754 skip within ±0.13 mph, no new failures; handheld clips unchanged. `cv/stabilize.py` `STATIC_CAM_PX`.
2. **Latency P1 — decode cache at working resolution.** The decode-once cache (`LANESIGHT_FRAME_CACHE_MB=1000`) never engages because full-res 1080p frames are too big (~6 MB each). Cache the DOWNSCALED frames the passes actually use → the 9 passes decode once (~35 s → ~5 s). Gated.
3. **Latency P1 — fail fast.** BALL_TRACK_NOT_FOUND / TRACK_TOO_SPARSE currently burn 200–330 s before failing. Detect "no usable ball track" early (after the first track pass) and fail in <60 s with the honest reason. Pure UX + cost win, no accuracy risk.
4. **Latency P2 — robust trim.** `detect_window` returns None on the real clips (`window=null`) so the whole clip is analyzed. A trim that reliably finds the shot window ≈ halves frames → halves every stage. Gated on `ops/precheck_vs_pipeline` + the benchmark.
5. **Reliability — ball track + pin impact.** The real failure frontier (DEC-062/065 robustness): far/foreshortened ball tracking and pin-impact detection. This is CV research, measured against the DEC-094 ground-truth set (needs the labels + Specto). Tracks with the on-device engine maturation (DEC-106).

## Gate for every change (DEC-092)
Faster AND: ball_speed within ±0.2 mph, boards within ±0.5, same pin read, no new failures, cost/shot not up out of line with the gain. Validation clips IMG_8751–8754 (Ruby) + the framing-failure clips. The post-deploy smoke (`ops/smoke_deploy.py`) guards drift on IMG_8753 (±0.2 mph) on every deploy, with auto-rollback.

## Progress
- **2026-10-29:** stabilize static-camera shortcut (P0) shipped. Precheck enforced (fast framing rejections). Measured breakdown + this plan recorded.
- Next: decode cache at working resolution (P1), then fail-fast on dead ball tracks (P1).
