# Performance, Reliability & SLA Requirements (Proposal)
Status: ACCEPTED AS TARGET STATE (DEC-043) — not a dev, testing or beta gate
Version: 1.1
Last Updated: 2026-10-19
Owner: LaneSight Product / Engineering

## Phase applicability (DEC-043, 2026-10-19)
| Requirement group | Dev / testing | Private beta | Public launch / scale |
|---|---|---|---|
| Latency / responsiveness tables below | Measure + report | Measure + report | **Target** |
| Availability, upload, job-resolution SLOs | — | Measure + report | **Target** |
| Honesty: explicit unavailable, no placeholder numbers | **Required** | **Required** | **Required** |
| No silent loss of accepted shots; 0 cross-user access | **Required** | **Required** | **Required** |
| Stage 1 / DEC-034 accuracy gates | Unchanged | Unchanged | Unchanged |
| Cost caps: ≤$100/mo beta infra; ≤$5 per 1,000 analyzed shots (alert $25) | Track | **Required** | **Required** (re-set by DEC as scale grows) |

- **Upload Video to Analyze is MVP.** An uploaded clip is analyzed as one shot until M1-13 delivery segmentation exists; the multi-shot upload row below depends on M1-13.
- **One analysis at a time per session.** The next shot's analysis starts when the current one finishes; no in-session concurrency or backlog SLO in MVP.
- **Cost caps bound performance work.** Any latency improvement (GPU, higher fps, more workers, on-device CV) is checked against the caps with measured cost before adoption; the cap wins unless a later DEC changes it.
- **Today's baseline:** 35–80 s per clip on the Mac after shot-window trimming; Stage A/B split not built. All latency rows are **not met**. Review: `03_ENGINEERING/PERFORMANCE_RELIABILITY_SLO_REVIEW.md`.

## Purpose and governance
Define measurable user-experience targets, internal service objectives, and release gates for Performance Lab live capture, video uploads, analytics and future PBA comparison. **These are proposed targets, not achieved measurements or customer contractual SLAs.** Read AGENTS.md, CURRENT_STATE.md, DECISIONS.md, BUILD_PLAN.md first; do not override DEC-017/018/028/029/035/040/041 or existing Stage 1 accuracy gates.

### Terms
- **SLI** = measured indicator; **SLO** = internal target over a defined observation window; **SLA** = external contractual commitment with scope, exceptions and remedies. Do not promise a public uptime guarantee during private beta.
- Timings are p50/p95 end-to-end wall-clock unless specified; segment by device, clip duration, camera type, shot/form mode, supported capture tier and connection quality.
- Analysis success means **completed OR explicit honest unavailable with reason**; measure *valid metric yield* separately. A graceful calibration failure must not count as successful metric output.
- Distinguish device capture, upload/queue, service processing and result rendering. An offline device may retain jobs until connected.

## Proposed product responsiveness (reference scenarios, not guarantees)
Reference: supported iPhone, 1080p at available recommended fps (target 120 per DEC-028), typical single-shot clip <=15s, adequate framing, Wi-Fi or good LTE/5G. Benchmark actual hardware and adjust.

| User journey / SLI | Beta goal | Scale target | Definition / notes |
|---|---:|---:|---|
| Performance Lab opens | p95 <=2s | p95 <=1.5s | navigation tap→interactive content; cached offline |
| Start live capture | p95 <=3s | p95 <=2s | start tap→recording confirmed; permission flows excluded and measured separately |
| Recording integrity | >=99% sessions without app-caused loss | >=99.9% | captured user shots not lost; OS termination separately logged |
| Shot/event detected after pin impact | p95 <=5s | p95 <=3s | when clip/frame locally available; false detections tracked |
| First usable shot feedback (live) | p50 <=15s, p95 <=30s | p50 <=8s, p95 <=15s | impact→first *validated available* metrics/clear failure; online, reference condition |
| Full supported shot analysis (live) | p95 <=60s | p95 <=30s | impact→full metric set and analysis status; no promise to deliver unavailable metrics |
| Single uploaded 15s video | p95 <=90s | p95 <=45s | upload submission→result over reference connection |
| Uploaded multi-shot session | first shot p95 <=90s; progress continuously | first shot <=45s | job queue, percentage/shot count and partial results; no blanket completion target without duration limits |
| Returning to active session | p95 <=2s | p95 <=1.5s | session and persisted result tiles |
| Stats page render | p95 <=3s | p95 <=2s | 90-day default, cached aggregates |
| Compare with PBA bowler | p95 <=3s for catalog, <=5s for cached comparison | <=2s / <=3s | comparison excludes first-time user processing; show loading/progress otherwise |

## Reliability / data SLOs (rolling 30 days; proposals)
| SLI | Private beta target | Public-launch target |
|---|---:|---:|
| API availability (health and authenticated core reads) | >=99.0% | >=99.9% |
| Successful upload completion on healthy network, resumable | >=98% | >=99.5% |
| Job eventually resolves success or explicit terminal error | >=99% in 24h | >=99.9% in 24h |
| Durable accepted ShotRecords not lost | 100% target | 100% target |
| Duplicate shot records on retry | <0.5% | <0.1% |
| Unauthorized cross-user video/metric access | 0 tolerated | 0 tolerated |
| Video deletion requests | visible immediately; object cleanup <=30 days | same or faster after policy/legal review |
| Monitoring | errors, queue age, latency, cost, device mix, metric yield | alerts + incident runbooks |

Do not conflate an internal 99.9% monthly API target with a signed SLA; downtime budget would be ~43 minutes in a 30-day month, before exclusions. For a future paid B2B SLA, require approved definitions, exclusion windows, third-party dependencies, support escalation and remedies.

## Accuracy, honesty and CV release gates
- Maintain existing BUILD_PLAN Stage 1 locked-set goals: speed ±0.5 mph, path/entry <=1 board median, strike/non-strike >=95% on readable clips, rev ±30 rpm where supported, >=90% valid clip pipeline finish; mark failures clearly. Confirm exact latest gates before implementation.
- Score metric coverage/availability separately from latency and uptime. Pin leaves cannot be inferred from obscured deck (DEC-026); rev unavailable when surface period unreadable (DEC-027).
- Track MAE, bias, p90 error, calibration failures, reference-ground-truth source and uncertainty calibration by fixed/moving camera, angle, lighting and fps. Do not call accuracy "guaranteed" based on four clips.
- Form metrics require independent pose/angle and repeatability validation; comparison to PBA must never invent unknown benchmark metrics.
- PBA comparison: each displayed metric needs comparable definition, camera perspective and capture metadata; label non-comparable values. When data insufficient, show video-only illustrative side-by-side without quantitative delta.

## Architecture and scaling constraints
- DEC-029 governs initial native SwiftUI+AVFoundation→FastAPI/Python pipeline→Supabase; local Mac processing first, then budgeted cloud service. On-device CV is a potential later improvement, not accepted v1 replacement.
- Preserve actual per-frame timestamps and capture-aware precision; aim up to 120 fps as supported (DEC-028).
- Idempotent job IDs, resumable uploads, exponential backoff, partial results, explicit quality statuses, versioned measurement results. Never drop records silently if cloud/network fails.
- Event-driven shot clip extraction; configurable device-only raw recording, cloud clip retention and user highlights. Separate encrypted object storage and durable structured observations; no unbounded permanent video default.
- Queue prioritization: live shots > interactive upload > bulk reprocessing. Admission controls and per-account storage/compute quotas; protect latency when busy.
- Track p50/p95/p99 compute seconds, peak concurrency, CPU/GPU hours, bytes in/out, R2/Supabase request costs, storage-by-retention tier, retries and $/1,000 analyzed shots. Target beta infrastructure <=$100/mo **only as a planning guardrail** under measured light load; never promise this at arbitrary scale.
- Security: authenticated scoped access, authorization/RLS tests, signed short-lived video URLs, private-by-default files, consent for coach sharing, restricted bystander footage, audio off by default.

## Operational definitions and alerts
- Define `shot_ready` as a new valid or explicit unavailable state persisted and reflected in UI.
- Product event trace: `record_started → candidate_shot → impact → clip_ready → upload_started → upload_accepted → queued → processing_started → first_metric_persisted → complete/unavailable → shown`.
- Alert on availability SLO burn, pending-job p95 age >30s live, p95 analysis > goal for two consecutive 15-min windows, abnormal error rate, runaway inference cost, storage near quota, ingestion orphan records or access violations.
- Weekly beta review and monthly release-gate scorecard. Use sampled opt-in clips for hard cases and an independently labeled evaluation set.

## Open choices for product review
1. Approve beta vs public targets only after profiling actual runner and mobile prototype.
2. Define reference-network thresholds, maximum upload size, multi-shot processing rate and offline sync UX.
3. Choose public SLA only when paid partner contracts justify it.
4. Confirm retention policy, capacity budget, observability provider and incident ownership.
5. Include PBA benchmark processing SLA only after rights/data acquisition and a repeatable measurement pipeline.

## Claude handoff
Audit real current latency and reliability against these proposed thresholds. Mark implemented/in progress/net new; recommend minimal-change instrumentation and build-plan tasks. Propose any new DEC for approved binding architectural changes; do not alter decision history.
