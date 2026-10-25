# Claude Code Handoff — LaneSight Dev Build v0 (iPhone)
Status: READY FOR BUILD
Version: 1.2
Last Updated: 2026-10-25
Owner: Shayne
Prepared in: claude.ai LaneSight Project session (design + spec work, 2026-10-21/22)
Location: `03_ENGINEERING/dev_build_v0/HANDOFF.md`

## 0. Read this first
1. Follow `CLAUDE.md` and `AGENTS.md` as usual:
   - Read order: DECISIONS → CURRENT_STATE → BUILD_PLAN …
   - No mock numbers.
   - `pytest` passes before every commit.
   - Commit locally; push only when Shayne says.
2. Then read, in this order:

| Doc | What it is |
|---|---|
| `00_CONTEXT/DECISIONS.md` | DEC-045…053 (recorded; the staging file `DECISIONS_TO_ADD.md` was removed 2026-10-25). |
| `03_ENGINEERING/DEV_BUILD_PLAN.md` | Goal, architecture, screen scope, dev score formula `L-dev-0` (§8) |
| `01_PRODUCT/SCORE_TIERS_ACHIEVEMENTS_SPEC.md` | Score/tier/achievement engine, migration 006 SQL draft, API, display rules |
| `01_PRODUCT/BENCHMARKS_AND_RECOMMENDATIONS_SPEC.md` | Benchmark layers, form rules, prioritizer, owner-only rules admin |
| `01_PRODUCT/FORM_ANALYSIS_SPEC.md` | Form event model and metrics (P1 set is in scope) |
| `03_ENGINEERING/IOS_STANDARDS.md` | Swift/SwiftUI, privacy, security, accessibility standards and checklist |
| `01_PRODUCT/MVP_READINESS_PLAN.md` | Context only: how this dev build fits the MVP |
| `02_DESIGN/dev_build_v0/` | The **approved** screens (24 `.dc.html` files + `canvas.json` + `README.md`) |

3. Where docs conflict:
   - DEC-045…053 in `DECISIONS.md` win over older docs.
   - Otherwise follow `AGENTS.md`: DECISIONS and CURRENT_STATE win.
   - Ask Shayne about anything still ambiguous; don't guess.

## 1. What we're building
A **developer build of the LaneSight iOS app** on Shayne's iPhone, used live while he practices. Every core feature is exercised end to end against the **real** `lanesight-core` pipeline running on his Mac. The build has three purposes:
1. Test all core functionality and workflows.
2. Collect results for **feasibility tests** of every core metric and output: coverage, failure reasons, timings.
3. Capture his feedback after every session.

**In scope:**
- Shot + Form analysis, with live capture and video upload.
- Recommendations and benchmarks (owner-only rules).
- LaneSight Score (`L-dev-0`), tiers and badges.
- Achievements.
- Stats: Score / Throw / Form.
- Profile, arsenal (211-ball catalog), sensors, settings, account deletion.
- Session feedback.
- Dev panel and CSV export.

**Out of scope:**
- pinfall / game scoring / strikes / spares
- league and tournament features (tabs disabled, no label)
- PBA comparison (disabled tile)
- cloud workers and R2 storage
- smart glasses
- replay playback
- coach sharing
- Ruby references in app screens
- payments

## 2. Architecture
```
iPhone: SwiftUI app (ios/LaneSight, bundle id com.lanesight.app)
  AVFoundation capture 1080p120 SDR, real frame timestamps → background upload queue
  Supabase Auth (Apple, Google, email) — JWT sent to the API
        │ HTTPS over Tailscale (tailscale serve → localhost)
        ▼
Mac: lanesight_api (FastAPI, launchd, Mac kept awake)
  serial job queue → lanesight_runner.core.analyze_clip (Shot) / analyze_form_clip (Form)
  → rules/benchmarks engine → recommendation (existing M4 + form rules)
  → score L-dev-0 recompute → tier evaluation (session end) → achievement engine
  → Supabase (service key, Mac only); video stays on the Mac (~/LaneSightData)
```
- **New package:** `lanesight-core/lanesight_api/`. Reuse `lanesight_runner/core.py` (`analyze_clip`); don't fork the pipeline. The existing local runner keeps working.
- **Auth:** verify the Supabase JWT on every request. Bind the API to localhost and expose it **only** via `tailscale serve` (HTTPS).
- **Untracked folder:** `lanesight-core/tailscale/` exists in the working tree but isn't tracked. Ask Shayne what it is before using or deleting it.
- **Supabase target:** confirm the LaneSight project with Shayne or via the Supabase tools before any migration. BUILD_PLAN names project `europwryibstnmipbvam`, and the project was being moved between orgs. **Never touch other projects** in the org (e.g. vendhub).
- **Migrations:**
  - Repo has `002`/`003`; Supabase also has `004` (RLS hardening), which isn't in the repo.
  - **Reconcile first:** pull `004` into `lanesight_core/models/migrations/`, then number new ones from `005`.

## 3. Phases, tasks and acceptance criteria
Work in order. Each phase ends with tests green, a short report to Shayne (numbers, not claims), and a local commit.

### Phase 0 — Record and reconcile (docs)
- [x] DEC-045…053 recorded in `00_CONTEXT/DECISIONS.md`.
- [ ] Update `CURRENT_STATE.md` and `BUILD_PLAN.md`:
  - new "Dev Build v0" stage, task IDs `DV-xx`, mirroring the phases below
  - fix BUILD_PLAN "MVP exit" per DEC-047
- [ ] Update `METRIC_AND_SCORING_LOGIC.md` with `L-dev-0` (DEC-048), clearly marked dev/Beta only.
- [ ] Bump Version / Last Updated on every doc you touch.

**Done when:** docs are consistent and Shayne has reviewed the diff.

### Phase 1 — Database (Supabase migrations)
- [ ] **005 rules & benchmarks** (BENCHMARKS spec §6, §8):
  - tables: `benchmark_reference`, `style_template`, `form_rule`, `drill`, `engine_config`, `personal_baseline`, `finding`
  - extend `recommendation` with `engine`, `rule_id`, `rule_version`, `cue`, `drill_ref`
  - add `recommendation_outcome`
  - RLS: rules tables are readable/writable by `rules_admin` only; no client role can select them
- [ ] **006 score, tiers, achievements:** as drafted in SCORE_TIERS spec §7, including the RLS notes and the user-facing `achievement_definition` view without `params`.
- [ ] **007 dev-build fields:**
  - `bowler_profile`: `dob`, `handedness`, `delivery_style` (`one_handed_thumb` | `one_handed_no_thumb` | `two_handed`), `approach_steps`
  - `user_sensor` (user-entered name, default flag)
  - `shot`:
    - `intent_feet_board`, `intent_arrows_board`, `intent_breakpoint_board`
    - `sensor_used`, `sensor_id`
    - `capture_mode` (`shot` | `form`), `bowler_in_view`
    - `source` (`live` | `upload`)
  - `session_feedback`: `session_id`, `user_id`, `rating` 1–5, `tags[]`, `text`, `diagnostics` jsonb, versions, `created_at`
  - account deletion cascade check
- [ ] **008 oil patterns:** a library table for published patterns (`name`, `length`, `volume`, `ratio`, `source_url`, `source`, `fetched_at`). Seed House shot / Unknown, plus an importer stub with a refresh job **design**. Source research and import can follow, but the Setup screen needs the table and seeds.
- [ ] Seed the `L-dev-0` formula version, the achievement definitions (SCORE_TIERS §4; FORM-001/002 active, per DEC-051) and the starter rules (BENCHMARKS §3.1, §5.2) from YAML in `lanesight-core/rules/`.
- [ ] Apply to a **Supabase branch first**, run the security advisor, then apply to the LaneSight project.

**Done when:**
- migrations apply cleanly
- the security advisor is clean
- an RLS test shows a normal user can't read rules or `params`
- a test user can only see their own rows

### Phase 2 — Engines in `lanesight-core`
- [ ] **Rules/benchmarks engine** (`lanesight_core/benchmarks/`):
  - resolve benchmark L3 → L2 → L1 → L0
  - Within / Watch / Outside, level + consistency
  - personal baseline at N=10 per view (DEC-046)
  - prioritizer: one primary focus
  - template cues only; no LLM
- [ ] **Recommendations:**
  - feed form findings into M4 execution routing (an execution miss gets a form cue, never a lane move)
  - add the secondary option
  - store the reason, evidence window and version
- [ ] **Target vs actual:** compute per-shot misses at arrows and breakpoint (boards) and the execution class from the three intent points. **No "did you hit your mark" prompt** (DEC-049).
- [ ] **Score `L-dev-0`** (DEV_BUILD_PLAN §8):
  - S' (pocket % + angle-in-range %), A (DEC-031), C (DEC-032), P' (power from ball data; reference ranges in `engine_config`)
  - eligibility floors 20/20/10/10
  - 90-day window
  - a snapshot on every recompute, with inputs
- [ ] **Tiers:** evaluate at session end. Hysteresis is 15 points × 2 sessions. Track first-time vs regained, plus personal best and baseline.
- [ ] **Achievements** (`lanesight_core/achievements/`):
  - rule types from SCORE_TIERS §5
  - idempotent unlocks, plus activity items and notifications
  - revocation on correction
  - an unanalyzable shot never breaks a streak
- [ ] **Form P1** (`analyze_form_clip`):
  - swing phase splits, swing time, approach time, step count, ball-start step, rhythm, finish hold, backswing height (relative)
  - drift (rear view, best effort)
  - per-metric status + reason; capture view classifier
- [ ] **Bowler-in-view on shot clips:** detect when the bowler is in a Shot clip and run the Form P1 metrics that angle supports. If detection or a metric isn't reliable, return Unavailable with a reason; never a guess.
- [ ] **Spot check (advisory only):** a fast framing check that returns a tip ("raise the phone ~1 ft", "move back ~3 ft"). It **never blocks** recording (DEC-045). The same tip comes back with failed/degraded results.
- [ ] **Owner reset:** archive + clear score/tier/achievement/activity/notification data for chosen users (DEC-051).

**Done when:**
- unit tests cover each rule type, the score formula, tier hysteresis and idempotency
- the existing validation clips (IMG_8751–8754) still reproduce their numbers
- form metrics run on the 2026-10-17 and 2026-10-20 training clips, with the results reported next to `TRAINING_VIDEOS_2026-10-20_ANALYSIS` values

### Phase 3 — `lanesight_api` (Mac service)
- [ ] FastAPI with an **OpenAPI spec committed** at `lanesight-core/lanesight_api/openapi.json`. That spec is the contract the iOS app is generated from.
- [ ] Endpoints:

| Area | Endpoints |
|---|---|
| Health | `GET /health` (versions: app-compat, core, rules, formula) |
| Profile | `GET`/`PUT /me/profile` · `GET`/`POST`/`DELETE /me/sensors` |
| Arsenal | `GET /catalog/balls?q=` · `GET`/`POST`/`PUT /me/arsenal` · `POST /me/arsenal/{id}/surface` |
| Oil | `GET /oil-patterns` |
| Sessions | `POST /sessions` · `GET /sessions` · `GET /sessions/{id}` · `POST /sessions/{id}/end` → returns summary + pending notifications |
| Shots | `POST /sessions/{id}/shots` (multipart upload + metadata: mode, intent, sensor, capture fps, frame-timestamp sidecar) · `POST /uploads` (Photos clip) · `GET /jobs/{id}` · `GET /shots/{id}` · `PATCH /shots/{id}` (sensor answer, feedback 👍/👎) |
| Spot check | `POST /spot-check` (single frame or short clip → advisory tip) |
| Score | `GET /me/score` · `GET /me/score/history?range=` |
| Achievements | `GET /me/achievements` · `GET /me/achievements/{id}` · `PUT /me/achievements/pins` |
| Notifications | `GET /me/notifications?undelivered=1` · `POST /me/notifications/{id}/delivered` · `POST /me/notifications/{id}/dismiss` |
| Activity | `GET /me/activity` |
| Stats | `GET /me/stats?view=score|throw|form&range=` (includes metric coverage + top failure reasons) |
| Feedback | `POST /sessions/{id}/feedback` |
| Export | `GET /sessions/{id}/export.csv` (all metrics, statuses, reasons, timings, sensor flag, feedback) |
| Account | `DELETE /me` (full deletion incl. videos on the Mac) |
| Admin | `/admin/*` rules, references, achievements, formula params, replay-test, publish, reset: **owner only**, never used by the app |

- [ ] Serial job queue (DEC-043). Job states: `queued` / `running` / `done` / `failed` + `reason`. Log per-step timings (OPS-01).
- [ ] Verify frame timestamps from the sidecar against decoded video; mismatched timing fails visibly.
- [ ] launchd plist, `tailscale serve` setup notes, and a health check. A README section shows Shayne how to start/stop and check the service.

**Done when:**
- a scripted end-to-end test (upload a real clip → job → shot result → score/achievement updates → summary → feedback → CSV) passes against the real Supabase project with a test user
- timings are logged and reported

### Phase 4 — iOS app (`ios/LaneSight`)
- [ ] Xcode project:
  - bundle id `com.lanesight.app`, team = Shayne's developer account
  - schemes: Dev / Beta / Prod (xcconfig)
  - Swift 6 strict concurrency
  - minimum iOS = current major − 1
  - `LaneSightKit` package holds models + API client **generated from the OpenAPI spec**
- [ ] Build every screen in `02_DESIGN/dev_build_v0/` (map in §4) to IOS_STANDARDS:
  - SF Symbols in place of the drawn icons
  - Dynamic Type, VoiceOver labels including metric status
  - 44 pt targets
  - String Catalog, Foundation formatters, unit setting
- [ ] Capture:
  - AVFoundation, 1080p120 SDR preferred (then 60, then 30), real per-frame timestamps written to a sidecar
  - tap start/stop per shot
  - live **advisory** spot check (never blocks)
  - intent entry
- [ ] Upload queue: background URLSession, retries, survives restarts, shows progress.
- [ ] Notifications:
  - pull pending ones when a shot result arrives or a session ends
  - at most one popup per shot, never while recording
  - first-tier celebration > achievement; extras batch into the summary
- [ ] Session end flow: End → **feedback sheet** (rating, tags, text, diagnostics on by default; Skip allowed) → summary.
- [ ] Auth:
  - Supabase Swift SDK; Sign in with Apple, Google and email
  - tokens in the Keychain
  - 13+ gate from DOB at onboarding
  - in-app account deletion
- [ ] Privacy:
  - purpose strings: camera, Photos (read), local network (only if used), microphone only if audio is kept
  - `PrivacyInfo.xcprivacy`
  - no third-party SDKs besides Supabase without Shayne's OK
- [ ] Dev panel: server URL + health, timings, versions, Beta/Prod toggle, speech toggle, keep raw clips, export, upload queue, error log.
- [ ] Tests:
  - Swift Testing for models/API client/upload queue/notification ordering
  - one UI test: capture → upload → result against the Mac service with a real clip
- [ ] Instruments pass: no dropped frames at 120 fps.

**Done when:**
- the app installs on Shayne's iPhone from Xcode
- every screen is reachable
- a real recorded shot shows real results, recommendation, score/achievement progress and the sensor question
- ending a session shows feedback → summary
- nothing on screen is hardcoded sample data

### Phase 5 — First live session
- [ ] Pre-flight: the Mac service is healthy over Tailscale, checked from cellular.
- [ ] Shayne bowls 2–3 games: Shot mode, a few Form deliveries, and one upload.
- [ ] Afterwards, review:
  - feedback entries
  - metric coverage and failure reasons
  - per-step timings
  - recommendation 👍/👎
  - any unlock/tier events
- [ ] Write a short findings note in `02_RESEARCH/`.
- [ ] Fix, rebuild, and send to TestFlight internal.

## 4. Screen map (`02_DESIGN/dev_build_v0/`)
Open the `.dc.html` files in a browser to view them; `canvas.json` gives titles and order. The designs are approved for this build.

**Sample values in the designs are illustrative only. Never hardcode them.** Bracketed text like `[Ball 1]` or `[My sensor]` is a placeholder for real user data.

| # | File | Screen | Main API |
|---|---|---|---|
| 1 | `Main.dc.html` | Home: score card + badge + 4 parts, start practice, recent sessions/activity | `/me/score`, `/sessions`, `/me/activity` |
| 2 | `Lab.dc.html` | Performance Lab tab (Start Live Session, Upload, PBA disabled, sessions) | `/sessions` |
| 3 | `Setup.dc.html` | Session setup: mode, lane, ball, oil pattern, pre-flight | `/health`, `/me/arsenal`, `/oil-patterns`, `POST /sessions` |
| 4 | `Capture.dc.html` | Capture: free framing, advisory spot check, intent, record, queue status | `/spot-check`, `POST …/shots` |
| 5 | `Shot.dc.html` | Shot card: next-shot advice, target vs actual, ball metrics, form-from-clip, sensor question, score/achievement nudges | `/shots/{id}`, `PATCH /shots/{id}` |
| 6 | `Session.dc.html` | Live session: KPIs, current ball, shot rows with upload/analyze/fail states | `/sessions/{id}` |
| 7 | `Form.dc.html` | Form results: focus + drill, key positions, swing timing, approach/balance | `/shots/{id}` (form) |
| 8 | `Stats.dc.html` | Stats tabs Score / Throw / Form + metric coverage | `/me/stats`, `/me/score/history` |
| 9 | `Dev.dc.html` | Dev panel | `/health`, export |
| 10 | `Achievements.dc.html` | Achievements: showcase, close to unlocking, categories, coming later | `/me/achievements` |
| 11 | `Unlock.dc.html` | Achievement-unlocked popup | `/me/notifications` |
| 12 | `TierUp.dc.html` | New-tier full-screen celebration | `/me/notifications` |
| 13a | `Feedback.dc.html` | Session feedback sheet (every session end) | `POST /sessions/{id}/feedback` |
| 13 | `Summary.dc.html` | Session summary | `POST /sessions/{id}/end` |
| 14 | `Upload.dc.html` | Upload video | `POST /uploads` |
| 15 | `Welcome.dc.html` | Welcome | — |
| 16 | `SignIn.dc.html` | Sign in | Supabase Auth |
| 17 | `CreateAccount.dc.html` | Create account | Supabase Auth |
| 18 | `Onboarding.dc.html` | Bowler profile setup (DOB 13+, hand, style, steps, sensors) | `PUT /me/profile`, `/me/sensors` |
| 19 | `AddBall.dc.html` | Add ball from catalog | `/catalog/balls` |
| 20 | `BallSetup.dc.html` | Ball setup: specs, layout, surface, expected reaction | `/me/arsenal` |
| 21 | `Profile.dc.html` | Profile | `/me/profile`, `/me/arsenal`, `/me/sensors` |
| 22 | `Settings.dc.html` | Settings | local + `/me/profile` |
| 23 | `DeleteAccount.dc.html` | Delete account | `DELETE /me` |

**Navigation:**
- Bottom tabs: Home · Stats · Lab · Leagues · Tourneys. Leagues and Tourneys are disabled (dimmed, no "Soon" label).
- Upload Video is a standalone analysis, not a session. Home Recent activity shows only practice sessions, achievements and tier changes (DEC-055).
- The avatar on Home opens Profile; the gear opens Settings; Settings → Developer opens the Dev panel.
- Onboarding: Welcome → Create account → Profile setup → Add ball → Ball setup → Home.

**Visual style:**
- Dark navy (#060C1C / #020A14 on auth screens), cards #0D1830, blue accent #2F7DFF, cyan #38C6F4.
- Status colors: measured #3DDC97, best effort #FFB547, unavailable dashed grey.
- Inter in the mock → **SF Pro** in the app.
- Translate these to asset-catalog colors, plus DEC-016 tokens where they exist.

## 5. Non-negotiables
- **No mock, placeholder or fallback numbers** in shipped code paths. An unmeasurable metric shows Unavailable + reason; a best-effort metric shows its ± band.
- **No pinfall** anywhere in this build (DEC-050).
- **No sensor brand names** in app UI. Sensors are the user's own entries.
- **No Ruby references** in app screens.
- **Rules are owner-only:** rule data never ships in the app bundle or API responses.
- **Achievements never change the score.**
- **Analysis runs one shot at a time.**
- **Capture is never blocked** by framing.
- **Secrets:** the Supabase service key lives only on the Mac. Nothing secret goes in the repo or the app.

## 6. Shayne-side setup that may still be needed
- Google sign-in: OAuth client IDs (iOS + web) in Google Cloud, added to Supabase Auth.
- Sign in with Apple: enable the capability on the App ID, then configure Supabase Auth (Services ID + key).
- Confirm the Supabase project and give Claude Code access (CLI login or MCP).
- `tailscale serve` on the Mac (Claude Code provides the exact command).
- **Privacy policy URL:** needed before external TestFlight only.

## 7. Open items to raise with Shayne (don't decide alone)
- Oil pattern sources and their terms (DEC-052 says pull + scheduled refresh).
- Power P' reference ranges: start values for entry speed, rev, angle and weight. Propose them from his data, and keep them owner-editable.
- The `lanesight-core/tailscale/` folder's purpose.
