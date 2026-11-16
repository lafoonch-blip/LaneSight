# Decode-once — bounded frame cache: implementation + findings (DEC-092 P1 / DEC-106 Phase 0)
Owner: Shayne · 2026-10-29 · Branch `dev-build-v0`
Outcome: **implemented a memory-bounded, byte-identical frame cache; it passes the regression gate and ships
enabled at a conservative budget — but on a 4 GiB instance it only speeds the subset of clips whose trimmed
window fits the budget.** A long 1080p60 window (~9 s ≈ 3.3 GB) exceeds any "well under 4 GiB" budget and
transparently falls back. Broad decode-once needs downscaled/ROI frames (accuracy-gated) or more memory /
on-device (DEC-106). Reported here rather than forcing a risky version.

## What the pipeline does today
`cv/stabilize.py:frames()` re-decodes the clip on every call, and it's called ~9× (4× in stabilize, plus
track×2, pins, refine, rev). The pipeline streams (never holds all frames) precisely to keep RSS ~2 GB.

## What was built (`cv/stabilize.py`)
A module-level **byte-budgeted frame cache** (`LANESIGHT_FRAME_CACHE_MB`, default 1000, `0` disables):
- The first full pass decodes **and** populates the cache up to the byte budget. If the whole clip fits, every
  later pass is served from the cache with **no decode**.
- Served frames are **independent copies of the decoded frames → byte-identical** to a fresh decode, so every
  metric is unchanged. Accuracy risk is zero by construction.
- **Hard RSS cap:** an upfront `frame_count × frame_bytes > budget` check skips caching for clips known too big
  (no wasted work); the incremental byte check frees any partial cache the moment it would exceed the budget.
  Peak ≈ working set (~2 GB) + budget (1 GB) ≈ **3 GB, well under the 4 GiB instance**.
- Cleared per analysis (`reset_decode_stats` → `reset_frame_cache`) so one shot's frames never leak into the next.
- `decode_stats()` now reports `cached_passes`, `cached_frames`, `cache_complete`, `cache_mb` for the gate.

## Verification
- **Unit test** (`test_decode_stats_counts_passes`): first pass decodes + populates; second pass served from
  cache (`passes==1`, `cached_passes==1`, `cache_complete`); served frames `np.array_equal` the decoded frames.
- **Regression gate** (`ops/perf_benchmark.py`, cache-off reference vs cache-on, ground-truth clips
  IMG_8751/52/53/54): **GATE PASS — every metric identical, pins parity held, no new failures.** Peak RSS
  ~1.9–2.0 GB. (These clips don't trim short, so the cache fell back — proving the fallback is byte-identical.)
- **End-to-end engage path** (a trimmed 501-frame window at a budget that fits): `cache_complete=true`,
  decode time 2.66 s → 0.84 s, and the pipeline logs are identical (same impact t, same STRIKE/conf) → metrics
  unchanged. Confirms the serve path works end-to-end and is byte-identical.

## The limit (measured)
A trimmed window = `LEAD_S 4.0 + burst + TAIL_S 2.6 ≈ 9 s`. At 1080p60 that's ~540 frames × 6.2 MB ≈ **3.3 GB** —
larger than any budget that stays well under 4 GiB. So:
- **Fits (cache engages, decode-once):** shorter shots, 30 fps clips (~9 s ≈ 1.7 GB), 720p clips (~1.4 GB), any
  clip whose window ≤ ~1 GB.
- **Falls back (safe, no benefit):** long 1080p60 windows.

So at a memory-safe budget the win is **real but partial** — the common 1080p60 long-window case does not benefit.

## Recommendation
1. **Shipped now:** the byte-identical cache, enabled at `LANESIGHT_FRAME_CACHE_MB=1000`. Zero accuracy risk,
   hard RSS cap, speeds the subset that fits, safe no-op otherwise. **Rollback:** set the env to `0` (instant,
   no redeploy needed) or redeploy the prior revision.
2. **Deferred (the real broad win), accuracy-gated:** a **downscaled / lane-ROI** cache — cache frames at reduced
   resolution (e.g. 0.5) or cropped to the lane so a full 1080p60 window fits ~1 GB. This changes the pixels fed
   to pin-reading and rev-rate (detail-sensitive) and to ORB, so it is **not** byte-identical and must clear the
   DEC-034 tolerance gate per metric. A focused effort with per-stage resolution choices; stop and keep full-res
   if any detail metric drifts out of tolerance.
3. **Alternatives:** an 8 GiB instance would let full-res caching hold a 1080p60 window (memory for ~3.3 GB cache
   + ~2 GB working), but see `CLOUD_RUN_PERF_INVESTIGATION.md` — more vCPU/memory is poor value and the server is
   being replaced. The decisive latency fix is the **on-device engine** (DEC-106): hardware decode means there is
   no repeated-decode cost to cache away.
