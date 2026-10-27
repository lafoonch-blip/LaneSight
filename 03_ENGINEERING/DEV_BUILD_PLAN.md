# Dev Build v0 — LaneSight on Shayne's iPhone for Live Practice
Status: DRAFT (for Shayne's review)
Version: 0.3
Last Updated: 2026-10-22
Owner: Shayne
Builds on: MVP_READINESS_PLAN v0.2, DEC-029 (SwiftUI, Mac service first), DEC-033 (async server analysis), DEC-043 (serial analysis, cost caps), VIDEO_ARCHITECTURE_COST_REVIEW
Proposed home: `03_ENGINEERING/DEV_BUILD_PLAN.md`

## 1. Goal
**Purpose (2026-10-22):** test all core functionality end to end, collect results for feasibility tests on every core metric and output, and test the workflows. Every shot's results, statuses and failure reasons are kept and exportable.

Shayne records shots on his iPhone while practicing at the bowling center. Each shot is analyzed by the real `lanesight-core` pipeline, and the results, adjustment and spoken cue come back to the phone. Nothing is mocked: every number comes from the pipeline or shows Unavailable with a reason.

**Decisions (2026-10-22)**
- **Distribution:** Shayne enrolls in the Apple Developer Program ($99/yr). Builds go to his phone through Xcode and TestFlight (internal testing). The same account serves the friends Beta later.
- **Analysis host:** Shayne's Mac runs the analysis service and is reachable from anywhere over **Tailscale** (free personal plan). The Mac can be at home or in the bag; the phone uses the same address either way.
- **UI:** a functional dev UI in the approved Home style. Designed screens replace these screens as they are approved. The dev build does not wait for Figma.

## 2. Architecture (dev)
```
iPhone (SwiftUI dev build)
  ├─ AVFoundation capture: 1080p120 SDR, tap start/stop per shot, real frame timestamps
  ├─ Upload queue (background URLSession, retry, survives app restart)
  ├─ Polls job status → shows shot card, speaks cue (AVSpeechSynthesizer)
  └─ Supabase auth (Sign in with Apple / email)
        │  HTTPS over Tailscale (MagicDNS name, e.g. shaynes-mac.tailnet.ts.net)
        ▼
Mac: lanesight-api (FastAPI, launchd service, Mac kept awake)
  ├─ POST /sessions, POST /sessions/{id}/shots (upload), GET /jobs/{id}, GET /shots/{id}
  ├─ Serial job queue → core.analyze_clip (+ form analyzer, rules engine, adjustments)
  ├─ Video + working files stay on the Mac disk (no cloud video cost in dev)
  └─ Writes sessions, shots, measurements, findings and recommendations to Supabase (LaneSight project)
```
- Supabase is the system of record from day one, so moving analysis to a cloud worker later changes only the host, not the app or data.
- Results arrive asynchronously: about 1–4 min per shot today on Apple silicon, faster after the quick wins (§6). That fits the practice pace for v0.
- The owner-only Rules page stays in the Mac runner and is never in the app.

## 3. Dev Build v0 scope (the live-practice loop)
| # | Screen / function | Notes |
|---|---|---|
| 1 | Sign in | Supabase; 13+ age confirmation; only Shayne's account in dev |
| 2 | Home (Performance Lab) | Start Live Session · Upload Video · Compare to a PBA Pro (disabled, Coming Soon); recent sessions |
| 3 | Session setup | Mode (Shot / Form), lane #, current ball (from arsenal / catalog search), oil pattern, handedness/style from profile |
| 4 | Capture | **Record from anywhere; no required framing.** A live spot check is advisory only and suggests a better camera position when it would help (e.g. "raise the phone ~1 ft"); the same suggestion appears after a failed or degraded shot. fps/SDR check, tap to record per shot, optional intent (feet/arrows/breakpoint) |
| 5 | Shot card | Metrics with status (Measured / Unavailable + reason / ± band), pins with correction, primary + secondary adjustment, form finding/cue, "Hit your mark?" Y/N/?, 👍/👎 on the adjustment |
| 5b | Form results | Focus finding + cue/drill, key positions, swing timing splits vs baseline, steps/approach/rhythm/finish/ball start, Unavailable metrics with reasons, camera tip |
| 6 | Session view | Shot list, running strike/spare/pocket %, basic trend, change ball/surface mid-session |
| 6b | Stats | Session / 30 days / all time: strike, spare, pocket, carry, first-ball avg; speed + rev by shot; entry-board distribution; leaves; form summary; **metric coverage** (% of shots each metric was measured, top failure reasons) |
| 6c | Session feedback | **Shown every time a session ends**, before the summary: 1–5 rating, optional tags (Bug, Metric looked wrong, Advice, Camera/upload, Workflow, Idea), free text, "attach diagnostics" (on by default: timings, errors, versions, shot ids). Skip allowed. Stored in `session_feedback` (session_id, user_id, rating, tags[], text, diagnostics jsonb, app/core/rules versions, created_at); included in the CSV export and listed on the owner Rules/Dev page for review |
| 7 | Upload video | Pick a clip from Photos → analyzed as one shot |
| 8 | Arsenal (basic) | Add from the 211-ball catalog, layout + surface entry |
| 9 | Dev panel | Server URL + health, app/algorithm/rules versions, per-step timings, upload queue, error log, Beta/Prod toggle, **export session data (CSV + clip list)** for feasibility analysis |

**Later in v0.x:** achievements, LaneSight Score (Beta label), oil library browse.

**Mockups:** Claude Design canvas "LaneSight Dev Build v0 Screens" (8 screens). Figma is reserved for finalized user designs.

## 4. Steps and owners
**Phase 0 — Setup (Shayne, ~1 hour + Apple approval)**
- [x] Enroll in the Apple Developer Program (done 2026-10-22; confirm enrollment is active)
- [ ] Add the iPhone as a device (Xcode does this on first run); turn on Developer Mode on the iPhone
- [ ] Install or update Xcode on the Mac; sign in with the developer Apple ID
- [ ] Install Tailscale on the Mac and the iPhone (same account); turn on MagicDNS
- [ ] Mac power settings: prevent sleep when plugged in, start after power failure; keep the Mac plugged in
- [ ] iPhone camera settings: HDR Video **off**; check 1080p120 is available
- [ ] Get a phone tripod/clamp mount for the approach-side rear view

**Phase 1 — Mac analysis service (Claude Code)**
- [ ] `lanesight-api/` FastAPI app in the repo: endpoints in §2; OpenAPI spec committed (this becomes the frozen API contract)
- [ ] Serial job queue (one shot at a time, DEC-043); job states queued/running/done/failed with reason
- [ ] Wrap `core.analyze_clip`; per-step timings (OPS-01); fail-fast precheck for unusable clips
- [ ] Supabase writes with the service key on the Mac only; RLS for the app's user token
- [ ] Rules engine v0 + template cues (benchmarks spec) on top of the existing M4 adjustments
- [ ] `launchd` plist so the service starts on boot; a health endpoint
- [ ] Test end to end with existing clips (IMG_8751/8754 reproduce the validation numbers)

**Phase 2 — iOS dev app (Claude Code writes; built and signed on the Mac)**
- [ ] Xcode project `ios/LaneSight` next to `lanesight-core`; Codable models generated from the OpenAPI spec / `ShotRecord`
- [ ] Screens 1–9 in §3; AVFoundation capture with real timestamps; background upload queue
- [ ] Build to the phone over USB/Wi-Fi from Xcode; then TestFlight internal build once enrollment clears

**Phase 3 — First live practice session**
- [ ] Mac on, service healthy over Tailscale (check on cellular before leaving)
- [ ] 2–3 games of shots; note issues in the dev panel / thumbs-down notes
- [ ] Afterwards: review timings, failures and recommendation feedback; fix and ship the next build

## 5. Risks and mitigations
| Risk | Mitigation |
|---|---|
| Weak cell signal at the center; clips are 15–40 MB | Upload queue with retry; record short tap-to-stop clips; trim on the phone before upload (v0.1); center Wi-Fi if available; fallback: Mac in the bag + phone hotspot (same Tailscale address) |
| Mac asleep or offline at home | Health check on the session setup screen; clear "analysis host unreachable" state; clips queue and upload later |
| Results too slow between shots | Quick wins in §6; results show when ready, and the next shot never waits on the UI |
| Building/signing needs Xcode on the Mac | The SwiftUI code is written and committed by Claude Code; compiling, signing and installing happen on Shayne's Mac (Claude Code running on the Mac, or Shayne pressing Run). This cloud session can't run Xcode |
| Free-tier Supabase limits | Dev volume is tiny; video stays on the Mac |

## 6. Speed quick wins (before or alongside v0)
1. Capture SDR, not HDR: removes 37–44 s per shot.
2. Cheap shot-window detection (downscaled decode): saves ~50–60 s per shot.
3. Cache decoded frames across pipeline passes: most of the remaining ~125 s analyze step.
4. Stage results: speed, pins and adjustment first; rev and replay after (LOCAL_RUNNER_SPEC §4).

## 8. Dev-build LaneSight Score (formula `L-dev-0`, decided 2026-10-22)
The dev build has **no pinfall or game-score data** (no strike/spare/carry; pin reading not shown). DEC-038's Performance S (game average, strike %, spare %) and Power & Carry P (carry) can't be computed, so the dev build tests a pinfall-free variant. It keeps the DEC-038 weights and never reweights silently.

`L = round(10 × (0.40·S' + 0.25·A + 0.25·C + 0.10·P'))`
- **S' Performance (pocket):** from ball data only — `S' = 0.6 × pocket% + 0.4 × angle-in-range%`. Pocket = entry board in the pocket range (16–19 right-handed, mirrored for left); angle in range = entry angle 4–6°. Ranges and weights are owner-editable rules.
- **A Accuracy:** DEC-031 unchanged (needs intent).
- **C Consistency:** DEC-032 unchanged.
- **P' Power:** entry speed, rev rate (only when its band ≤ target), entry angle and ball weight, each normalized 0–100 against owner-editable reference ranges and averaged. Carry is excluded.
- Labeled **Beta · dev formula** everywhere. Each score snapshot stores the formula version and its inputs so it can be recomputed when the final formula is approved.
- Needs a DEC entry ("L-dev-0, dev/Beta only") before code; it does not replace DEC-038.

**UI changes from this decision:** Home matches the approved Figma Home (score card, four-part breakdown, recent sessions/activity). The former Home is now the **Lab** tab. Stats are split into **Score / Throw / Form** with trends over time and metric coverage. No pins, strikes, spares or leaves in any screen.

## 7. Out of scope for v0
Cloud workers, R2 video storage, multi-user, offline on-device analysis, glasses capture, replay playback, coach sharing, PBA comparison, Ruby references in app screens.
