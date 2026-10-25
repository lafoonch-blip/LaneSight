# Video Architecture & Cost Review (response to the handoff)
Status: PROPOSAL FOR REVIEW. Nothing here changes an accepted decision or starts implementation.
Version: 0.1
Last Updated: 2026-10-19
Owner: Shayne
Reviews: `00_CONTEXT/VIDEO_ARCHITECTURE_COST_STRATEGY_HANDOFF.md` v1.0
Against:
- DECISIONS (DEC-014…041 in GitHub; DEC-042 exists only in the Project mirror)
- CURRENT_STATE v1.17, BUILD_PLAN, COST_PLAN v1.0, ROLLOUT_STRATEGY v1.0
- `lanesight-core` v0.6.0 at GitHub `main`

> Repo note (2026-10-25): moved here from the claude.ai Project so all context lives in the repo. The DEC numbers proposed in §11 (DEC-043…046) were drafts; those numbers were later used for other decisions. See `00_CONTEXT/DECISIONS.md` for what was actually accepted.

## 1. Bottom line
1. **The pipeline is CPU-only.** `lanesight-core` depends only on numpy, OpenCV (headless) and matplotlib. It has no GPU code path, so a GPU adds cost without adding speed. COST_PLAN and ROLLOUT budget for scale-to-zero L4 GPUs; that should be CPU workers instead. On today's pipeline, CPU is about 5× cheaper per shot than the GPU line in COST_PLAN.
2. **Measured cost today:** one shot takes about **4 minutes of wall time on a 2-vCPU worker** (220–255 s, ~330–370 CPU-seconds; §2).
   - That is **$0.8–6 per 1,000 shots** in compute, depending on the host.
   - It already beats COST_PLAN's "unoptimized" case by a wide margin.
   - **Latency is the real problem, not cost.** DEC-033's ≤30 s fast pass is 8× away.
3. **Two quick wins remove about 40% of the work without touching metric code:**
   - **Record SDR, not HDR.** HDR conversion takes 37–44 s per shot.
   - **Make shot-window detection cheap.** It takes 52–62 s per shot because it decodes every full-resolution frame.
4. **Video storage moves out of Supabase once there is real volume.** The cost driver is not GB stored; it is the analysis worker downloading every raw clip.
   - That download counts as Supabase egress: $0.09/GB beyond 250 GB a month.
   - 250 GB/month ≈ 35 active bowlers at moderate use.
   - R2 egress is free.
5. **Recommended launch stack (minimal change):**

   | Layer | Choice |
   |---|---|
   | App | iPhone native capture → presigned upload |
   | Video blobs | **Cloudflare R2** behind a `VideoStore` interface (lifecycle rules handle retention) |
   | Auth, DB, small images | **Supabase Pro** |
   | API | **FastAPI** service wrapping the existing `core.analyze_clip` |
   | Analysis workers | Scale-to-zero CPU (**Modal**) for beta; then a small flat CPU fleet once volume is steady |
   | Recommendations | Existing deterministic rules engine; no per-shot LLM or paid vision API |

   - **Beta:** about $35/month all-in.
   - **1k active bowlers:** about $170–650/month.
   - **10k active bowlers:** about $0.9k–6k/month.
   - In each range the spread is pipeline efficiency and host choice (§10).

## 2. Measured baseline (2026-10-19)
**Setup:** `lanesight_runner.core.analyze_clip`, the production path, unchanged code. 2-vCPU / 8 GB Linux container. Four live-session clips from 2026-10-15, iPhone 1080p60 HEVC with HDR (HLG), ~13 Mbps.

| Clip | Size | Duration → window | Window detect | HDR→SDR | Analyze | **Wall** | **CPU-s** | Result |
|---|---|---|---|---|---|---|---|---|
| IMG_8807 | 32.7 MB | 18.9 s → 9.8 s | 52.4 s | 44.5 s | 156.6 s | **254 s** | 368 | ✓ 17.97 mph, entry 19.4 |
| IMG_8813 | 41.7 MB | 24.0 s → 9.1 s | 57.8 s | 41.4 s | 146.7 s | **246 s** | 360 | ✓ 17.85 mph, entry 18.4 |
| IMG_8818 | 44.9 MB | 26.0 s → 8.0 s | 61.5 s | 37.3 s | 123.6 s | **223 s** | 330 | ✓ 17.35 mph, entry 9.1 |
| IMG_8751 | 96.5 MB | 34.9 s → 8.2 s | 91.4 s | 38.2 s | 145.3 s | **275 s** | 392 | ✓ 17.33 mph, entry 19.1 |

Window detection grows with the length of the uploaded clip (~2.6 s per clip-second), while the analyze step stays roughly flat at ~125–157 s. That makes the cheaper detector (S2) and shorter uploads more valuable on longer tap-to-stop clips.

Additional measurements:
- A re-run with the stabilization and blob caches warm took 22.6 s. So ~125 of the ~150 s "analyze" step is the repeated full-resolution decode passes (stabilize, blob extraction, refine, pins, rev crops), not the math.
- **ShotRecord JSON:** 29 KB per shot, 5 KB gzipped. The trajectory is 18 KB. The `metrics` map duplicates `measurements` (~4.7 KB).
- **Working files:**
  - The trimmed clip (stream copy) is 15–17 MB.
  - The SDR re-encode is 25–33 MB.
  - Caches are 6.3 MB (`_stab.pkl`) + 2.4 MB (`_blobs.pkl`). They must stay on the worker and never be persisted.

**Bitrates measured on Shayne's phone:**

| Format | Bitrate | Per second |
|---|---|---|
| 1080p60 HEVC | 13–24 Mbps | — |
| 1080p120 HEVC (IMG_8831/8832) | ~25 Mbps | ≈3.1 MB/s |
| 4K120 | not measured; assume ≥3–4× 1080p120 | — |

**Caveats:**
- These are 4 clips on one machine type. An Apple-silicon Mac or a dedicated-vCPU host will be faster.
- Re-run the benchmark on the chosen host before budgeting.

## 3. Contradictions and stale assumptions found
| # | Where | Conflict | Proposed resolution |
|---|---|---|---|
| C1 | COST_PLAN §2–5, ROLLOUT Ph1–4, BUILD_PLAN C-02 ("GPU when needed") | Cost model is GPU-seconds (L4 $0.80/h). Pipeline has no GPU path | Re-base on CPU-seconds (§10). GPU only as a future option when a learned model exists |
| C2 | DEC-042 (Project mirror) vs GitHub `DECISIONS.md` | DEC-042 (native capture, per-metric status, manual logging) is **missing from the source of truth** (DEC-025) | Commit DEC-042 to GitHub before any architecture DEC references it |
| C3 | DEC-029 + BUILD_PLAN U-04 ("locked 60 fps + 240 slo-mo") vs DEC-028 (highest, target 120) vs DEC-042 ("e.g. 4K · 120 fps") | Three different capture defaults | New DEC: analysis default **1080p120 SDR**; 4K is opt-in until validation shows a metric gain (§6, DEC-043) |
| C4 | ROLLOUT §4 / DEC-023 / DEC-033 ("check framing before upload / refuse before GPU") vs DEC-042 ("judged after upload") | Under DEC-042 bad clips reach the worker and cost full compute | Keep DEC-042 UX. Add a **server-side fail-fast precheck** (§6) so unusable clips cost seconds, not minutes |
| C5 | COST_PLAN §8 ("R2 engineering default") vs handoff ("R2 is a candidate") | Not decided anywhere | Recommendation in §7; needs a DEC (DEC-044) |
| C6 | DEC-033 fast pass ≤30 s; BUILD_PLAN C-03 ≤10 s cloud / ≤5 s edge | Two latency targets; measured ~240 s | Keep both as targets. MVP promise = async ("results in a few minutes") until the optimization milestone passes |
| C7 | ROLLOUT "~$0.005/clip at target"; COST_PLAN "$0.50/bowler/mo at target" | Built on unmeasured GPU-seconds | Replace with measured CPU numbers (§10) |
| C8 | Handoff "store compressed time-indexed tracking observations" vs ShotRecord | Already stored as `trajectory.lane/pixel/smoothed` (18 KB). No new store needed | Keep; drop the duplicate `metrics` map at persist time |
| C9 | `schema.sql measurements` vs `models/shot.py Measurement` | DB lacks `uncertainty` (DEC-028) and a reason code (DEC-042) | Additive columns (§8) |

The handoff is otherwise consistent with accepted decisions: DEC-018 moving camera in MVP, DEC-029/033 server-side async, DEC-035 per-shot capture, DEC-026/027 honesty gates.

## 4. Status matrix
| Item | Already implemented | Approved, not implemented | New proposal | Future option |
|---|---|---|---|---|
| CPU OpenCV pipeline, tripod + handheld stabilization | ✓ `lanesight_core.cv` | | | |
| Shot-window pre-pass + stream-copy trim | ✓ `runner/trim.py` | | Faster detector (§6) | On-device window detection |
| Keep only the trimmed shot after analysis | ✓ `_keep_only_trimmed` | | Becomes the retained cloud clip | |
| HDR→SDR conversion | ✓ `probe.convert_sdr` | | Capture SDR so it never runs (DEC-043) | |
| Per-metric value / confidence / status / source / algorithm version / uncertainty | ✓ `models/shot.py` | DEC-042 Processing/Unavailable-with-reason in app | `reason_code`, `observed_fraction` (§8) | |
| Honest unavailable for pins and rev | ✓ DEC-026/027 | | | |
| Deterministic insights / adjustments / spares | ✓ `insights/` | | | LLM phrasing only, if ever justified |
| ShotRecord contract + Postgres schema | ✓ `schema.sql` (not applied) | C-01 apply in Supabase | Additive columns (§8) | |
| FastAPI service + job queue | Runner is a single-user dev tool | C-02 | Thin API + queue design (§5) | |
| Native capture + upload | | U-04, DEC-042 | 1080p120 SDR default, presigned upload | Resumable multipart |
| Object storage for video | | DEC-033 ("object storage") | R2 + `VideoStore` (§7) | |
| Retention controls | `video_assets.retain_until` column | C-04 | Policy in §8 | Paid longer retention |
| Faster pipeline (≤30 s fast pass) | | DEC-033 target, C-03 | Optimization milestone (§6) | On-device stage A (Core ML) |
| Form Analysis pose | | DEC-040 | | Apple Vision on-device pose |
| GPU inference | | | | Only with a learned detector |

## 5. Recommended architecture (minimal change)
```
iPhone (SwiftUI/AVFoundation, DEC-029/042)
  └─ record 1080p120 SDR, real PTS ─▶ POST /shots (FastAPI) ─▶ presigned PUT URL
  └─ PUT clip ─▶ R2 raw/  ─▶ POST /shots/{id}/uploaded
FastAPI (small always-on instance or serverless)  ── Supabase Postgres (jobs, shots, measurements, RLS)
  └─ enqueue job (Postgres table / pgmq; no extra broker)
Worker (scale-to-zero CPU; later small fleet)
  1. download raw clip from R2 (free egress)
  2. probe + FAIL-FAST precheck (lane/foul line on a few frames)  → Unavailable with reason, stop
  3. detect_window + trim (existing)
  4. core.analyze_clip (existing, unchanged metrics)
  5. write ShotRecord + measurements to Postgres; upload trimmed clip to R2 clips/; delete raw
  6. Supabase Realtime pushes "shot.analysis.completed" (C-05)
```
- **The worker is the existing code.** New code is a thin job loop, a `VideoStore` adapter (R2 / Supabase / local), and the precheck.
- **Queue:** a Postgres jobs table (or Supabase `pgmq`) avoids another vendor. `SELECT … FOR UPDATE SKIP LOCKED` is enough at this scale.
- **Interchangeable modules:** `VideoStore`, `Analyzer`, `JobQueue`, and later `SensorAdapter` / `ScoringAdapter`. Codecs stay native HEVC/H.264 with no server re-encode, except the existing HDR fallback until DEC-043 lands.
- **The Mac runner stays the development and validation path.** Same `analyze_clip`, so results match the cloud.

## 6. Cost savings, ranked
| # | Change | Effort | Saves | Risk |
|---|---|---|---|---|
| S1 | **Capture SDR** (AVFoundation HDR off; capture guidance already says SDR) | S (app setting) | −37–44 s/shot (~17%) and removes the re-encode file | None to metrics; CURRENT_STATE already recommends SDR |
| S2 | **Cheaper window detection:** decode at reduced resolution (ffmpeg `scale` / skip non-key frames) or use phone-reported tap times | S–M | −40–50 s/shot (~20%) | Re-validate burst detection on the 21-clip set |
| S3 | **Fail-fast precheck** before stabilize: lane/foul line on ~5 sampled frames | M | Failed clips (43% of the live session) drop from ~4 min to <10 s | Must not reject clips the full pipeline would pass; tune on the 21-clip set |
| S4 | **1080p120 default, not 4K** (DEC-043) | S | Avoids ~3–4× upload, storage and decode cost | Far-lane ball size; 4K can stay opt-in for validation |
| S5 | **Single decode pass:** cache downscaled frames for stabilize / blobs / refine / pins / rev | M–L | Analyze ~150 s → ~40–60 s (est.); needed for the DEC-033 fast pass | Highest engineering effort; regression-test every metric |
| S6 | **Retention:** delete raw after success; keep the trimmed clip 14 days; derived data for the account's lifetime | S | Storage ÷2–4 vs 30–60 days (§10) | Need opt-in "keep" for validation clips |
| S7 | **Drop the duplicate `metrics` map** at persist; gzip trajectory if needed | S | −30% jsonb | None (rebuild on read) |
| S8 | **Rev rate and other deep metrics as a second job** | M | Fast pass returns sooner; deep pass can be capped for free users | Matches DEC-033 staging |
| S9 | **On-device trim/window** (later) | M–L | Upload bytes −50–70% | Future option |

S1 + S2 + S3 + S7 are the "quick wins" case in §10. S5 is the "optimized" case.

## 7. Video storage: Supabase Storage vs Cloudflare R2
| Factor | Supabase Storage | Cloudflare R2 |
|---|---|---|
| Storage | 100 GB in Pro, then $0.0213/GB-mo | 10 GB free, then $0.015/GB-mo |
| **Egress (worker reads every raw clip)** | 250 GB in Pro, then **$0.09/GB** | **$0** |
| Requests | included | Class A $4.50/M, Class B $0.36/M (≈$1/mo at 100k shots) |
| Auth | RLS with Supabase JWT; Swift SDK | Presigned URLs signed by FastAPI after JWT check (GET/PUT/DELETE, ≤7 days) |
| Resumable upload | TUS built in (6 MB chunks) | Multipart via presigned part URLs (more client code); single PUT is fine for ≤~100 MB clips |
| Retention | Lifecycle can't expire current objects; needs cron / edge function | **Native lifecycle rules by prefix/age** |
| Vendors | one | +1 account |

At 1k active bowlers on moderate use, the worker pulls ~6.3 TB/month. On Supabase that is ≈$560/month in egress alone, vs $0 on R2.

**Recommendation:**
- Put **analysis video in R2 from the first cloud deployment.** Keep Supabase for auth, DB and small images (avatars, replay PNGs).
- Hide R2 behind the `VideoStore` interface so Supabase Storage or S3 stay drop-in alternatives.
- If beta must ship before the presign code is written, Supabase Storage is acceptable **only below ~250 GB/month of reads** (~3.5k shots/month). Treat it as temporary.
- Effort: ~1–2 days (boto3 presign in FastAPI, lifecycle rules, Swift `URLSession` PUT). That is less than a later migration.

## 8. Metric confidence, schema, retention, clip boundaries
**Metric-level results (no metric redefinitions):**
- Keep `Measurement` as is.
- Add `reason_code` (enum: e.g. `ball_lost_far`, `deck_blocked`, `rev_no_period`, `lane_not_found`, `fps_too_low`, `camera_motion`) next to the human `note`, so DEC-042 telemetry can aggregate failures.
- Add `observed_fraction`: the share of the metric's span that was observed vs interpolated (handoff occlusion rule).
- Add `processing` to `status` for staged results.

**Schema (additive only):**
- `measurements`: + `uncertainty numeric`, `reason_code text`, `observed_fraction numeric`, `capture_view text`.
- `video_assets`: + `kind` (`raw` | `analyzed_clip` | `highlight` | `form`), `bytes`, `codec`, `width`, `height`, `hdr`, `sha256`, `storage_provider`, `storage_key`, `perspective`, `analysis_mode` (PL-02), `consent_scope`, `deleted_at`. Keep `retain_until`.
- **New `analysis_jobs`:** `id`, `shot_id`, `stage` (`fast` | `deep`), `status`, `attempts`, `worker`, `cpu_s`, `wall_s`, `bytes_in`, `algorithm_version`, `error_code`, `created`/`started`/`finished`. This is the cost-per-shot ledger the handoff asks for.
- Persist `ShotRecord` without the derived `metrics` map. The algorithm version is already stored per measurement and per shot.

**Retention (proposal for a DEC):**

| Asset | Default | Notes |
|---|---|---|
| Raw upload (`raw/`) | Deleted after successful analysis; R2 lifecycle hard-deletes at **72 h** regardless | Covers retries and failures |
| Analyzed shot clip (`clips/`, trimmed stream copy) | **14 days** | Supports Fix pins, re-analysis after algorithm updates, support. Shot replay video is post-MVP (DEC-035), so long retention buys little today |
| User-saved highlights / validation clips | Until the user deletes them; opt-in | Validation clips need research consent |
| ShotRecord + measurements + replay PNG | Account lifetime; deleted with the account (App Store rule) | ~15–30 KB per shot |
| Worker caches (`_stab.pkl`, `_blobs.pkl`, SDR copies) | Never persisted | |

- Audio is stripped on upload (`-an` already in the HDR path; add it to trim) or disabled at capture.

**Clip boundaries:**
- **Shot Analysis:** keep the existing tuned window — **4.0 s before the ball-roll burst, 2.6 s after** (`trim.py`). It preserves release, track and the settled deck, and only the first 1.8 s of the tail feeds the metrics.
- **Form Analysis** (later): setup −2 s to finish hold +2 s, per the Form spec draft.

## 9. Recommendation for compute hosting
| Phase | Host | Why |
|---|---|---|
| Dev / validation | Mac runner (existing) | $0; same code path |
| Beta (≤25 bowlers) | **Modal CPU functions**, scale-to-zero | $30/mo free credit covers ~5–6k shots at today's speed; no idle cost; autoscaling hides the 4-min latency across a session |
| ≥~20k shots/month steady | **Flat CPU fleet** (e.g. Hetzner CX/CAX boxes at $10–25/mo for 4–8 vCPU) + Modal for burst | 4–7× cheaper per shot than per-second serverless at steady load |
| Revenue-funded | Dedicated vCPU or GPU only if a learned model is adopted; on-device stage A | |

Hetzner caveats:
- Its cheap CX/CAX plans are EU-only; US plans cost ~7× more.
- Its plan pages currently show plans as unavailable.
- EU hosting of US users' video needs a privacy-policy note.

A US flat-rate alternative would need its own quote. The cost tables give the range between flat EU pricing (low) and Modal (high).

## 10. Operating cost estimates
**Assumptions:**
- **Shot volume:** active bowler = films in the month. Conservative 40, moderate 100, heavy 240 shots/month (COST_PLAN uses 100/240).
- **Upload size:** 1080p120 SDR HEVC ~25 Mbps; a ~20 s tap-to-stop clip ≈ **65 MB**.
- **Retention:** trimmed clip ≈30 MB kept 30 days; raw kept ≤3 days. (14-day retention roughly halves storage.)
- **DB:** ~15 KB per shot after TOAST compression. Supabase Pro $25 + compute add-on as load grows.
- **Fixed:** Apple $99/yr. Sentry and logging free in beta, ~$46/month at scale.
- **Compute:** a 2-vCPU / 4 GB job; wall time per shot from §2:
  - **Today:** 240 s (measured)
  - **Quick wins:** 150 s (S1–S3)
  - **Optimized:** 60 s (S5; *unproven target*)
- Prices verified 2026-10-19 (§12).

**Compute only, $ per 1,000 analyzed shots:**

| Pipeline | Hetzner EU flat (60% util) | Modal CPU | Fly perf-2x | Cloud Run | *COST_PLAN GPU L4 @120 s* |
|---|---|---|---|---|---|
| Today, 240 s | $0.77 | $5.28 | $6.11 | $10.56 | *$26.64* |
| Quick wins, 150 s | $0.48 | $3.30 | $3.82 | $6.60 | — |
| Optimized, 60 s | $0.19 | $1.32 | $1.53 | $2.64 | — |

**All-in monthly run-rate** (compute + R2 + Supabase + fixed). The range is flat fleet (low) to Modal (high). Beta uses Modal only.

| Active bowlers | Usage | Shots/mo | Today | Quick wins | Optimized | $/1k shots (quick wins) |
|---|---|---|---|---|---|---|
| Beta 25 | 40 / 100 / 240 | 1k / 2.5k / 6k | $34 / $34 / $38 | $34 / $34 / $36 | $34 / $34 / $36 | $6–34 (fixed-cost dominated) |
| 1,000 | conservative 40 | 40k | $155–296 | $135–217 | $125–138 | $3.4–5.4 |
| 1,000 | moderate 100 | 100k | $228–645 | $198–447 | $168–250 | $2.0–4.5 |
| 1,000 | heavy 240 | 240k | $509–1,555 | $439–1,080 | $369–606 | $1.8–4.5 |
| 10,000 | conservative 40 | 400k | $717–2,487 | $607–1,696 | $487–905 | $1.5–4.2 |
| 10,000 | moderate 100 | 1.0M | $1,522–5,988 | $1,232–4,010 | $942–2,031 | $1.2–4.0 |
| 10,000 | heavy 240 | 2.4M | $3,483–14,255 | $2,784–9,508 | $2,094–4,760 | $1.2–4.0 |

**What the numbers say:**
- **Per active bowler per month:** about $0.17–0.65 at 1k moderate, and $0.09–0.20 at 10k moderate once optimized. COST_PLAN's target was ~$0.50.
- **Storage is the second line item:** R2 30-day clips are $53/month at 1k moderate and $544/month at 10k moderate. **14-day retention halves it.** Keeping clips forever grows it every month.
- **Same scenarios on Supabase Storage:** storage + egress would be ~$620/month at 1k moderate and ~$6.4k/month at 10k moderate. That is the argument for R2.
- **Uncertainty:**
  - Compute ±50% (3 clips, one container type; faster CPUs reduce it).
  - Clip bytes ±40% (phone, clip length, 4K).
  - Shots per bowler is the largest unknown; measure it in beta.
- **Not included:**
  - App Store commission
  - Staff and support
  - Legal (COST_PLAN §7 still applies)
  - Failed-clip retries: +~10% today, ~0 after S3

## 11. Proposed new DECs (drafts, for review; none applied)
- **DEC-043 — Analysis capture default.**
  - Shot and Form capture record **1080p120 SDR HEVC** with real PTS and audio off.
  - 4K and 240 fps are opt-in and remain validation arms until they show a measured metric gain.
  - Refines DEC-028; resolves the DEC-029/U-04 vs DEC-042 conflict.
- **DEC-044 — Video storage and retention.**
  - Analysis video in R2 behind `VideoStore`; Supabase for auth/DB/small images.
  - Retention per §8: raw ≤72 h, clips 14 days, opt-in keep, derived data for the account's lifetime.
- **DEC-045 — CPU-first analysis hosting and cost ledger.**
  - Workers are CPU; no GPU until a learned model needs one.
  - Modal (scale-to-zero) for beta; flat CPU fleet at steady load.
  - Every job records `cpu_s`, `wall_s` and bytes to `analysis_jobs`.
  - Cost per shot becomes a Stage 8 gate metric.
  - Supersedes the GPU basis in COST_PLAN/ROLLOUT (drafts, not DECs).
- **DEC-046 — Fail-fast precheck and staged jobs.**
  - Cheap server-side precheck before the full pipeline.
  - Fast pass (speed, boards, entry, pins) and deep pass (rev, loft) as separate jobs per DEC-033.
  - The deep pass can be capped for free users.
- **Housekeeping (not a DEC):** commit DEC-042 to GitHub; update U-04 text; re-base COST_PLAN/ROLLOUT on these numbers after review.

## 12. Verified pricing (2026-10-19, official pages)
| Item | Price |
|---|---|
| Supabase Pro | $25/mo; includes $10 compute credit, 8 GB DB, 100 GB storage, 250 GB uncached egress |
| Supabase overage | storage $0.0213/GB, uncached egress $0.09/GB, DB disk $0.125/GB |
| Supabase compute | Small $15, Medium $60, Large $110 |
| Supabase Storage limits | lifecycle can't expire current objects; TUS resumable supported |

Source: https://supabase.com/pricing · https://supabase.com/docs/reference/javascript/file-buckets-updatebucketlifecycle

| Item | Price |
|---|---|
| Cloudflare R2 | $0.015/GB-mo, Class A $4.50/M, Class B $0.36/M, egress $0; free 10 GB, 1M A, 10M B; lifecycle rules; presigned URLs ≤7 days |

Source: https://developers.cloudflare.com/r2/pricing/

| Item | Price |
|---|---|
| Modal CPU | $0.0000131 per physical core-s (= 2 vCPU) + $0.00000222/GiB-s; Starter includes $30/mo credit |
| Modal GPU | L4 $0.000222/s |

Source: https://modal.com/pricing

| Item | Price |
|---|---|
| Fly.io performance-2x 4 GB | $0.00002546/s ($66/mo) |
| Google Cloud Run (instance) | $0.000018/vCPU-s + $0.000002/GiB-s |

Sources: https://fly.io/docs/about/pricing/ · https://cloud.google.com/run/pricing

| Item | Price |
|---|---|
| Hetzner CX33 (4 vCPU, 8 GB, EU) | $9.99/mo |
| Hetzner CAX31 (8 vCPU ARM, EU) | $24.99/mo |
| Hetzner CPX31 (US) | $73.49/mo |

Hetzner prices are from its price-adjustment doc effective 2026-06-15, and plans are shown as currently unavailable. Source: https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/

| Item | Price |
|---|---|
| AWS S3 Standard | $0.023/GB-mo, egress $0.09/GB |
| Sentry Team | $26/mo (annual) |
| Apple Developer Program | $99/yr |

## 13. Follow-up measurements (2026-10-19, same 2-vCPU container, no repo code changed)
**SDR input.** The same four clips were converted to SDR as a stand-in for SDR capture (conversion not timed), then run through the unchanged `analyze_clip`:

| Clip | HDR wall (§2) | SDR wall | Window detect HDR → SDR | Speed HDR → SDR | Entry board HDR → SDR |
|---|---|---|---|---|---|
| IMG_8807 | 254 s | 147 s | 52 s → 6 s | 17.97 → 17.35 | 19.4 → 20.4 |
| IMG_8813 | 246 s | 159 s | 58 s → 8 s | 17.85 → 17.72 | 18.4 → 21.1 |
| IMG_8818 | 223 s | 144 s | 62 s → 9 s | 17.35 → 17.60 | 9.1 → 9.6 (pins unreadable) |
| IMG_8751 (Ruby 16.9 mph / 411 rpm) | 275 s | 166 s | 91 s → 10 s | 17.33 → 17.23 | 19.1 → 19.6 |

- **SDR capture cuts wall time by ~38% (249 → 154 s mean; CPU 362 → 224 s).** It removes the HDR conversion step and most of the shot-window time.
- **The slow window detection was the cost of decoding 10-bit HDR HEVC, not the algorithm.** On SDR, the existing detector takes 6–10 s. A prototype low-res detector saved only ~1 s and chose different windows, so it is dropped. S2 in §6 becomes "covered by S1".
- **Metrics are sensitive to the input and the trim window.** Moves of 0.1–0.6 mph and up to 2.6 boards were seen (8813 entry; 8818 pins). Part of this is the prototype window. SDR must be re-validated on the full set before it becomes the default (§14, F2).
- **8-bit HEVC re-check (closer to native iPhone SDR):** the same clips re-encoded as HEVC 8-bit at 20 Mbps ran **189 s (8807) and 194 s (8813)** vs 254 / 246 s on HDR. That is **−23%**. Window detection took 14–18 s; HEVC decode makes the analyze step slower than with the H.264 stand-in. **Planning figure for SDR capture alone: ~190 s per shot (−23%)**; −38% was the H.264 upper bound. Metrics stayed within 0.1–0.75 mph and ~1 board of the HDR run (rev 403–446 rpm).
- **Fail-fast precheck prototype (P2):**
  - Method: decode keyframes only (5–12 frames), then run the existing `find_lanes` on their median and on the middle frame.
  - Speed: **1.4–1.6 s per clip.**
  - It passed all 5 clips the full pipeline completes (including oblique 8810 and the HEVC copy).
  - It **rejected IMG_8831 with the same "lane not detected" reason the full pipeline gave after 736 s.**
  - Six clips is not a tuning set. Validate on the F1 set (S15 in the capture plan) before relying on it.
- **IMG_8810** (oblique multi-lane, a failure in the 2026-10-15 evaluation) now finishes on `main`. The 57% finish-rate baseline is stale and should be re-run.
- **IMG_8831** (120 fps HDR, 24 s, foul line off the bottom of frame) **failed after 736 s wall / 1,152 CPU-s** with "lane not detected". It costs ~3× a successful 60 fps shot (120 fps HDR doubles the frames to decode and convert) and then produces nothing. This is the strongest case for the fail-fast precheck (P2) and for SDR at 120 fps.
- **Revised compute planning figure:**
  - **SDR capture + precheck ≈ 190 s wall per successful shot** on 2 vCPU, between the "today" and "quick wins" columns in §10. Use the quick-wins column as the target once P3 (static-camera fast path) lands.
  - **Failed clips cost ~2 s instead of 4–12 min.**

## 14. Iteration roadmap: flexibility, accuracy, performance
**Rule for every item:** change one thing, run the locked evaluation set, and keep the change only if accuracy holds and the target metric improves. Today's runs show why this matters: a different trim window alone moved entry board by up to 2.6 boards.

### Foundation (do first, enables everything else)
| ID | Step | Exit criterion |
|---|---|---|
| F1 | **Locked evaluation set v1.** The 21-clip live session plus new sessions, stratified by camera class (rear-centered, rear-oblique / multi-lane, handheld, far, low/foul-off-frame), fps (60/120/240), SDR/HDR and center/lane. Ground truth: Ruby (speed, rev); manual annotation of arrows board, entry board and pins; Specto when available. Separate tuning and test splits; never tune on test. | Versioned manifest + labels in `validation/`; ≥50 shots with ≥10 at 120 fps |
| F2 | **Regression gate.** `eval_session.py` + `score_vs_ruby.py` run in one command and report per-metric MAE / median / p90 / bias, finish rate, unavailable rate by reason, and wall/CPU per stage. Fail on regressions beyond tolerance. | Every pipeline PR attaches the report; baseline re-run on current `main` |
| F3 | **Per-stage timing.** Split `analyze_s` into stabilize passes A/B/C, blob extraction, refine, impact, pins, rev crops. | Profile table per clip in the F2 report |
| F4 | **Window-invariance test.** Re-run each clip with the trim window jittered ±0.5 s at both ends. | Speed spread ≤0.2 mph, boards ≤0.5, same pin read. Failures become accuracy bugs (A5) |

### Performance (target: fast pass ≤30 s, deep pass ≤90 s on 2 vCPU; DEC-033)
| ID | Step | Expected gain | Effort |
|---|---|---|---|
| P1 | **SDR capture default** (with DEC-043), validated on F1 | −38% measured | S |
| P2 | **Fail-fast precheck** (lane/foul line on sampled keyframes before stabilize) | Unusable clips: ~4 min → seconds | S–M |
| P3 | **Static-camera fast path.** Pass A already measures motion. When the camera is steady (tripod), skip per-frame ORB + RANSAC (pass B) and use identity or a few ECC refinements | Large on tripod clips (est. 30–50% of analyze) | M |
| P4 | **Decode once.** Cache frames at working resolution (or a lane-ROI crop) and share them across stabilize, blobs, refine, pins and rev, instead of 5+ full decodes | Est. analyze 150 → 60 s | M–L |
| P5 | **Lane-ROI processing.** After lanes are found, restrict blob extraction and background to the lane polygon | 2–4× fewer pixels | M |
| P6 | **Staged jobs.** Fast job (speed, boards, entry, pins) returns first; deep job (rev, loft) follows; deep can be capped for free users | First results sooner | M (with C-02) |
| P7 | **Hardware decode where available** (VideoToolbox on the Mac runner; evaluate on cloud hosts) and ffmpeg threading | Decode share ↓ | S–M |
| P8 | **Profile-guided micro-optimizations** (vectorize hot loops) only after P3–P5 | 10–20% | S |

### Accuracy (gate: DEC-034 launch bar)
| ID | Step | Ground truth |
|---|---|---|
| A1 | **Near-field scale.** Fit the homography with more landmarks (foul line, 7 ft dots, 15 ft arrows, 60 ft deck) to fix the ~9% `speed_release` residual (DEC-036) | Specto session |
| A2 | **Board accuracy.** Validate arrows and entry board vs manual annotation; report median and p90 per camera class | F1 annotations |
| A3 | **Rev rate at 120 fps.** Collect a 120 fps Ruby set; blind-validate the 1.12 factor; add tape-marker capture guidance | Ruby / F5 / Witsee |
| A4 | **Pin reading.** Track readable rate and correctness; handle the deck leaving frame or the bowler blocking it (8818 SDR read was unreadable) | Manual pin labels |
| A5 | **Window and input invariance.** Make reference-frame and background-median selection robust to trim length and codec (F4 failures) | F4 test |
| A6 | **Loft and launch angle at 120 fps** | Ruby loft |
| A7 | **Occlusion handling.** Report observed vs interpolated span per metric (`observed_fraction`) and gate metrics on it, per the BUILD_PLAN physics-constrained infill rule | Clips with bowlers or obstacles crossing |
| A8 | **Research (later):** axis/PAP at 240 fps | Ruby axis values |

### Flexibility (more cameras, angles and devices measurable)
| ID | Step | Exit criterion |
|---|---|---|
| X1 | **Multi-lane separation** for oblique views (stop the mask close bridging gutters; split merged tracks; relax gutter-fallback gates) | Oblique class finish rate ↑ with no regression on rear-centered |
| X2 | **Supported-envelope map.** From DEC-042 telemetry, publish per-metric availability by camera class / fps / device. Feeds METRIC_CAPABILITIES and the post-upload "two concrete fixes" messages | Auto-generated table from F2 / telemetry |
| X3 | **Moving camera.** More handheld clips and the first glasses clips (Meta 720p30 constraint); precision widens with motion (DEC-028) | Handheld class in F1 with error bands |
| X4 | **Device/format matrix.** iPhone models × 1080p60/120/240 × 4K × SDR/HDR × HEVC/H.264, checking PTS handling and decode cost | Matrix in F2 report; input to DEC-043 |
| X5 | **Lighting robustness.** Pale lanes, glare, low light; synthetic perturbation of F1 clips (brightness, blur, noise, crop) as a stress suite | Degradation curves per metric |
| X6 | **Form Analysis prototype** (side view, ball color + Apple Vision pose, timing events from the 2026-10-17 pilot) | Event timing ≤1 frame median at 120 fps (Form spec §8) |
| X7 | **Learned detector (future).** A small CPU/ONNX ball or pin detector only when F2 shows a classical failure class it would fix | Beats classical on the locked test split; cost per shot re-measured |

### Suggested order
1. **Sprint 1 (1–2 weeks):** F1–F4 and a fresh baseline on `main`. P1 validation (SDR on the whole set, plus the 8-bit HEVC check). P2 precheck prototype tuned on the failure clips.
2. **Sprint 2:** P3 static-camera fast path and A5 invariance. These are the two cheapest big wins that touch the core.
3. **Sprint 3:** P4/P5 decode-once + ROI, aiming at the ≤30 s fast pass. X1 multi-lane.
4. **With the Specto session:** A1/A2. **With the 120 fps Ruby set:** A3/A6.
5. **Ongoing:** X2 telemetry once the app uploads real shots. X3/X4 as devices and glasses arrive.

### Scorecard to track every iteration
- Finish rate on supported clips (target ≥90%)
- Speed MAE / bias (±0.5 mph) and board median (≤1)
- Pins correct on readable decks (≥95%)
- Unavailable rate by reason
- Wall and CPU seconds per shot (fast / deep)
- Bytes per shot
- $ per 1,000 shots
