# Review — Performance, Reliability & SLA Proposal
Status: RESOLVED — outcome recorded as DEC-043
Reviews: `03_ENGINEERING/PERFORMANCE_RELIABILITY_SLO_PROPOSAL.md` v1.0 (ChatGPT, 2026-10-19)
Checked against: BUILD_PLAN v3.2, DECISIONS (DEC-023/028/029/033/034/035/040/041/042), LOCAL_RUNNER_SPEC v1.3, CURRENT_STATE v1.16, COST_PLAN v1.0
Date: 2026-10-19
Author: Claude

---

## 1. Verdict
**Accept the framework. Don't accept the numbers yet.**

The structure is sound and fits LaneSight's honesty rules:
- SLI / SLO / SLA are kept separate.
- "Success" means completed **or** honestly unavailable, and valid-metric yield is measured separately.
- The event trace, idempotent jobs and resumable uploads are in place of an API contract.
- Security is private by default.
- There is no public uptime promise during beta.

The targets have three problems. They contradict a canonical target (C-03). They are far from what the pipeline does today. And they leave out the two numbers that actually decide whether a live session works: throughput and cost per shot. Six fixes are listed below, followed by a status audit.

---

## 2. Must fix before acceptance

### 2.1 Latency targets conflict with the canonical docs
| Source | Target |
|---|---|
| BUILD_PLAN C-03 (UI Spec §10) | **≤10 s cloud, ≤5 s edge** after pin impact |
| DEC-033 | Fast pass **≤30 s**; deeper metrics in background |
| LOCAL_RUNNER_SPEC §4 | Stage A ≤30 s |
| Proposal, beta | First feedback p50 ≤15 s, **p95 ≤30 s**; full p95 ≤60 s |
| Proposal, scale | First feedback **p95 ≤15 s**; full p95 ≤30 s |

The beta row agrees with DEC-033. The scale row is **looser** than C-03 (15 s vs 10 s), and C-03's ≤5 s edge target assumes on-device CV, which DEC-029 rules out for v1. Three docs now give three different launch numbers.

**Fix:** write one proposed DEC (next free number, DEC-043) that sets the ladder:
- Dev / private beta: Stage A p95 ≤30 s, full analysis p95 ≤90 s (DEC-033 as written).
- Public launch: Stage A p95 ≤10 s cloud (keep C-03).
- The ≤5 s edge target is deferred until an on-device DEC exists.

Then mark C-03 "see DEC-043" without rewriting its history.

### 2.2 Today's pipeline misses every latency row, so mark them all "not met"
Measured on the Mac (LOCAL_RUNNER_SPEC v1.3):
- **35–80 s per clip** after shot-window trimming. An untrimmed HDR clip took 279 s.
- The Stage A / Stage B split is **not built** (Milestone 4 is still open), so nothing comes back early.
- These numbers are for single clips. There are no p95 figures yet.

Even the beta goal for full analysis (p95 ≤60 s) isn't met reliably, and first feedback within 30 s depends on the Stage A split. Like the proposal itself (open choice 1), treat every timing row as a target, not a baseline.

### 2.3 120 fps capture vs latency and cost
The proposal's reference scenario is "1080p at 120 fps, clip ≤15 s" (per DEC-028). The pipeline is frame-bound:
- 120 fps means about **2× the frames** of 60 fps.
- A 15 s clip at 120 fps is about **4× the frames** of the COST_PLAN unit (8 s at 60 fps, 15 GPU-s, ~15 MB).

So the latency and cost targets in this proposal and in COST_PLAN rest on clips four times apart in size.

**Fix:**
- Set the reference clip to the **trimmed shot window (~6–9 s)**, which is what the runner already analyses.
- Report every latency number by fps.
- Evaluate running Stage A on frames decimated to 60 fps, keeping full 120 fps only for Stage B rev rate. That is a measured experiment, not a decision.

### 2.4 Upload video: decide whether it's MVP before giving it SLOs
- DEC-035 (and the Figma pass) says **importing clips from Photos is post-MVP**.
- DEC-042 makes **"Upload Video to Analyze"** a live MVP tile, and doesn't list DEC-035 as superseded.
- The proposal gives uploads MVP targets: single upload p95 ≤90 s, plus a multi-shot session row.
- Multi-shot uploads also need **M1-13, automatic delivery segmentation, which hasn't started**.

**Fix:** decide whether upload is MVP. If it is, limit MVP to **single-shot uploads** and move the multi-shot row to post-MVP behind M1-13. Either way, record which decision supersedes the other.

### 2.5 Missing SLI: throughput (backlog within a session)
The runner processes **one clip at a time** (spec §3), and today a clip takes 35–80 s. In practice a bowler throws every ~45–90 s. When processing time is longer than the gap between shots, the queue grows all session, and "first feedback" latency gets worse with each shot no matter what p95 the clip-level number shows.

**Add:**
- **Session backlog:** p95 shots waiting at the moment a new shot is accepted is ≤1.
- **Processing time / inter-shot interval:** below 1.0 at p95.
- Alert when the backlog is ≥2 for any live session.

### 2.6 The cost guardrail has no unit target
"Beta ≤$100/mo" is fine as a guardrail, but for 10–25 bowlers almost all of the variance comes from GPU or CPU seconds per clip:
- Fixed costs: Supabase Pro $25 + Vercel ~$20 + monitoring $0–26 ≈ $45–70.
- Compute: 25 bowlers × $0.50 (target) to $3.00 (unoptimized) ≈ $12–75.
- Total ≈ **$60–145/mo**, which only fits under $100 at target efficiency.

**Add a unit-cost SLO taken from COST_PLAN:** **≤$5 per 1,000 analyzed shots** (15 GPU-s per clip), with an alert at $25 per 1,000 (the unoptimized 120 s case). DEC-033 already says to benchmark CPU hosting before committing to GPU. Make that benchmark the source for this number.

---

## 3. Smaller corrections
| Item | Issue | Suggested change |
|---|---|---|
| PBA comparison rows | DEC-042 makes comparison post-MVP; MVP has only a disabled tile | Move them to a "Deferred SLOs" appendix |
| "Shot detected after pin impact ≤5 s" | MVP is tap-to-record / tap-to-stop per shot (DEC-035); there is no on-device event detection | Redefine as **stop tap → upload_accepted** (p95 ≤5 s on reference Wi-Fi) |
| "Recording integrity ≥99% of sessions" | Counted per session, so it hides lost shots | Count per shot: **≥99.5% of recorded shots reach upload_accepted or stay retained on the device** |
| Rev ±30 rpm gate | At 60 fps the band is ±40 (DEC-028), so the gate can't be met there; DEC-034 already ships rev as Best effort | State that the rev gate applies at **≥120 fps** only |
| Clip finish rate | The ≥90% gate is unchanged, but today's rate is **57%** (21-clip session; all failures are framing) | Add today's baseline so the gap is visible |
| Moving camera / glasses | The reference scenario leaves them out without saying so; the Meta third-party stream is reportedly capped at 720p/30 | Add "SLOs don't apply to moving-camera capture until the Stage 2 gate passes" |
| API availability 99.0% (beta) | DEC-033 says Mac in dev, cloud for external beta | Say outright that the external beta needs cloud processing; measure availability separately for the control plane (Supabase) and for processing |
| UI render SLIs (Lab opens, Stats render, etc.) | Fine, but there's no app yet | Keep as targets; don't use them as release gates before U-02 |
| 99.9% ≈ 43 min / 30 days | Checked: 43,200 min × 0.001 = 43.2 min | No change |

---

## 4. Status audit (what exists today)
| Proposal item | Status | Where |
|---|---|---|
| Per-step wall-clock timing logged per shot | **Implemented (local)** | Runner timing log (LOCAL_RUNNER_SPEC §4, Milestone 1) |
| Honest unavailable / unreadable states | **Implemented** | DEC-026/027, M1-12 `[~]` |
| MAE / median / p90 / bias per metric | **Implemented** | `examples/eval_session.py`, `score_vs_ruby.py` (M1-14 `[~]`) |
| Shot-window trimming (latency + storage) | **Implemented** | `lanesight_runner/trim.py` (279 s → 81 s; 102 MB → 31 MB) |
| Staged results (Stage A / B) | **In progress** | Milestone 4, open |
| Capture-adaptive precision | **Implemented for rev** | DEC-028 |
| RLS / scoped access | **In progress** | `models/schema.sql` has RLS; no auth tests |
| Event trace (record_started → shown) | **Partial** | Runner logs pipeline steps; capture and upload timestamps don't exist yet |
| Idempotent job IDs, resumable uploads, backoff | **Net new** | Stage 8 C-02/C-04 |
| Queue priority, quotas, admission control | **Net new** | Stage 8 |
| Signed short-lived URLs, R2 object storage | **Net new** | C-04; R2 is already the COST_PLAN default |
| Monitoring, alerts, runbooks | **Net new** | OPS-01 |
| Cost per 1,000 shots | **Net new** | OPS-01 |

---

## 5. Recommended next steps (smallest first)
1. **Get a baseline now with no new infrastructure.** Extend `eval_session.py` to print p50/p95/p99 wall-clock per pipeline step and in total, split by fps and HDR/SDR, over the 21-clip live session. This is the first slice of OPS-01, and it supplies the real numbers the proposal asks for.
2. **Finish the Stage A / B split** (Milestone 4). It's the only route to first feedback within 30 s.
3. **Write DEC-043 (proposed):** the latency ladder (§2.1), the throughput SLI (§2.5) and the unit-cost SLO (§2.6).
4. **Resolve DEC-035 vs DEC-042** on uploads (§2.4).
5. **Run the CPU vs GPU benchmark** on the validation set (DEC-033) and feed the result into COST_PLAN §2 and the unit-cost SLO.
6. Then revise the proposal to v1.1 with §2–3 applied and today's baselines filled in.

## 6. Note
The proposal is on GitHub `main` but wasn't in `~/Documents/LaneSight` because the local clone hadn't pulled it. Pull before working locally (CURRENT_STATE, "Where these docs live").

## 7. Outcome (Shayne, 2026-10-19) → DEC-043
- The SLOs are **target-state requirements**, not gates for dev, testing or beta (resolves §2.1–2.2; C-03 and DEC-033 targets kept as targets).
- **Upload is MVP** (resolves §2.4; DEC-035 Photos import partly superseded). Multi-shot uploads still depend on M1-13.
- **One analysis at a time:** the next shot's analysis waits for the current one, so the throughput SLI in §2.5 isn't needed for MVP.
- **Cost caps stay** (§2.6): ≤$100/mo beta infrastructure, ≤$5 per 1,000 analyzed shots. Every performance improvement is weighed against them.
- Still open: §2.3 (120 fps cost/latency: measure by fps) and the §3 corrections, to be folded into proposal v1.2 once baselines exist.

