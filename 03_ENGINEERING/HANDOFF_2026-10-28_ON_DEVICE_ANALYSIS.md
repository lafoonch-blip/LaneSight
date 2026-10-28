# Claude Code handoff: On-device analysis — Phase 0 + Phase 1 (offline-first)
Status: READY (start when Shayne says so) · Version: 1.0 · Last Updated: 2026-10-28 · Owner: Shayne
Spec: `03_ENGINEERING/ON_DEVICE_ANALYSIS_PROPOSAL.md` v0.3. Read all of it, especially §5, §6, §8, §9 and §13.
Branch for this doc: `claude/on-device-analysis-handoff` (off `main` @ `56d71e9`). Do the work on a **new branch you create** off the latest line that holds DEC-099 or later.

## What was decided (Shayne, 2026-10-28)
1. **Offline-first, hybrid measurement.**
   - Shot and Form metrics are computed on the iPhone wherever validated device capability allows.
   - The cloud engine stays as the fallback and reference.
   - Coaching, insights, moves, form findings, scoring, tiers and achievements stay server-authoritative and need a connection.
   - Losing the connection never blocks the rest of the app.
2. **Advice states.** Every move or insight carries a server-decided **Provisional / Low confidence / Ready** state (DEC-061 + DEC-094 §5).
3. **Video.**
   - DEC-099 stands: LaneSight sets server retention, and the bowler only chooses "Save recordings to my phone".
   - Using clips for model improvement is a separate disclosed consent.
   - Server-fallback uploads are disclosed before processing.
4. **Port language is deferred.** Swift vs shared C++ is decided by benchmark (Phase 2.5). No C++ work now.

## Your job
Run continuously to the end and give one report. Commit locally. Push only when Shayne says so.

### 0. Freshness and DEC entry
1. `git fetch --all`. Find the newest `00_CONTEXT/DECISIONS.md` across `main`, `dev-build-v0` and any `fix/*` branch (2026-10-28: DEC-099, v1.60, on `fix/ux-batch-2026-10-28`).
2. Create your own branch off that line. **Don't commit to branches you didn't create.** Other sessions are active.
3. Enter the three accepted DECs from proposal §12 as the **next free numbers** (DEC-100…102 if still free). Use the log's format:
   - Decision / Why / Date 2026-10-28 / Status ACCEPTED / Supersedes.
   - Wording comes from proposal §12 with §11 resolved.
   - **DEC-A amends DEC-029, DEC-033 and the long-term scope of DEC-092.** DEC-092's near-term order and its "metric math stays on the server" rule stay in force until the DEC-B gates pass.
4. Add the matching lines to "Superseded decisions", bump the version, and update `CURRENT_STATE.md` ("Building now" + a pointer to the proposal).
5. Change the proposal header to "ACCEPTED as DEC-xxx–yyy".

### 1. Phase 0 — measure (approved)
| ID | Do | Done when |
|---|---|---|
| OD-00 | **Reuse DEC-092 P0** (per-stage timings). Don't build a second timer. Make sure stages cover upload, cold start, Storage download, decode, trim/window, geometry, stabilize, track, rev, pins, form pose, metrics, insights and DB write, and that they persist. | Timing breakdown for ≥20 real clips in `02_RESEARCH/ANALYSIS_TIMINGS_<date>.md`, split by success vs failure (DEC-092 reporting rule) |
| OD-00A | Audit the pipeline for repeated decodes (~9 today), redundant passes and staged-measurement chances. **No production CV changes** (DEC-062). | Ranked findings with estimated savings, appended to `ANALYSIS_LATENCY_SPLIT_PROPOSAL.md` |
| OD-00B | Spec `MeasurementEvidence` v1 = DEC-092 P3 observation interface + DEC-094 §5 uncertainty contract (proposal §6.3–6.4). Keep observed vs predicted separate; `observed_fraction` stays the one additive field; include the device-validity vs server-coaching boundary table. | `03_ENGINEERING/MEASUREMENT_EVIDENCE_SPEC.md`, marked for Shayne's review. **Spec only, no code.** |
| OD-01 | iOS benchmark harness (dev panel or a test target): 120 fps HEVC decode throughput, one native processing step (lane mask via Vision/Accelerate or OpenCV-iOS, behind a debug flag), peak memory, and a sustained 30-clip run logging `ProcessInfo.thermalState`, battery and per-clip time | Harness builds and runs; **Shayne runs it on his iPhone**; results go to `02_RESEARCH/DEVICE_BENCHMARK_<date>.md` |

### 2. Phase 1 — offline-first app (approved, independent of the CV freeze)
| ID | Do | Done when |
|---|---|---|
| OD-02 | **Local store + outbox** (no local persistence exists today; `AppModel.runPipeline` is fully online). Pick SwiftData or GRDB and justify the choice in the report. Requirements:<br>• account-scoped (data separated per user; cleared on sign-out/delete per proposal §6.6)<br>• encrypted where appropriate (`NSFileProtectionComplete` minimum)<br>• sessions/shots/measurements immutable or revisioned<br>• arsenal changes revisioned (DEC-007/044)<br>• last-write-wins only for simple profile fields<br>• client UUID + idempotency key per record; retry with backoff<br>• survives the app being killed<br>• the server rejects duplicates by idempotency key | End-to-end in airplane mode: record → "Analysis pending" → reconnect → analyzed once, no duplicates. Survives a force-quit mid-sync. |
| OD-02A | Tests: offline→online recovery, account switch isolation, sign-out/delete purge, conflict rules, storage-full handling, an engine-version field present on every synced record | Tests green (Swift + `pytest` for server idempotency) |
| OD-03 | **Offline UX**:<br>• "Analysis pending" shot rows in the session list (like "Couldn't analyze", DEC-096)<br>• "Advice when you're back online" on the shot card<br>• score popup / Home: stored score + "latest session not yet included" (no local score, ever)<br>• a connectivity banner that never blocks navigation<br>• Provisional / Low confidence / Ready chip on advice<br>• Resume session works from the local store (DEC-096) | Matches proposal §5.2. **DEC-068/080 unchanged**: online, the blocking Analyzing screen → shot details flow is exactly as today. Offline, record → shot saved as pending → back to the Active Session. Every screen that differs from Figma "Target state – v3.7" is listed in the report (DEC-091: add rows to `APP_DESIGN_CHANGES.md`) |
| OD-03A | Server: advice responses carry `advice_state` (provisional / low_confidence / ready). Late advice for a past shot is generated with that shot's historical context and attached to it, never shown as the current move. | API test + one late-sync test |
| OD-07A | Ground-truth gate harness independent of parity: runs the locked validation set vs Ruby (Specto later). **Extend `validation/cv_eval/` (DEC-094); don't fork it.** | Report per metric vs DEC-034 gates |

### 3. Held: don't start these (proposal §9)
- OD-04: tighten and reuse the phone trim window. This is DEC-092 D5; do it there.
- OD-05: metrics-only advice API.
- OD-06: engine provenance columns.
- OD-07: device-vs-server parity.
- OD-08: on-device pose.
- OD-09: Swift vs C++ spike.
- OD-10: device shot engine.

Isolated non-production experiments are fine only if they're clearly flagged.

## Rules
- No production CV changes while DEC-062 stands. No fabricated metric to fill an offline or device gap (DEC-026/027/061).
- **No AGPL models** (DEC-094 §6), e.g. Ultralytics YOLO, including RT-DETR from Ultralytics.
- The device holds **no owner-only rules or thresholds** (DEC-046). Form early / on time / late verdicts stay server-side; the device reports raw timings.
- Failures use DEC-086 codes. Device and offline attempts still land in `analysis_attempt` on sync.
- Uploads stay standalone and never count (DEC-055).
- Migrations: write and validate locally. **Applying to live Supabase `europwryibstnmipbvam` and redeploying Cloud Run need Shayne's go-ahead.** Order: migration first, then API.
- Swift: type-check against the iOS SDK (Xcode build for simulator and device), not just `swiftc -parse`.

## Report
Include:
- DEC numbers used
- test counts
- build result
- Phase 0 numbers, or what Shayne needs to run
- the persistence choice and why
- each "done when" item, pass or fail
- Figma differences
- anything blocked or needing Shayne (live migration/deploy, the device benchmark run, legal review of the video consent wording)
