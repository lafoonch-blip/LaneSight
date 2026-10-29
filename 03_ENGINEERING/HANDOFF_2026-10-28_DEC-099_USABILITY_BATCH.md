# Claude Code handoff: DEC-099 usability batch
Status: ACTIVE · Version: 1.0 · Last Updated: 2026-10-28 · Owner: Shayne
Branch: `fix/ux-batch-2026-10-28` (off `dev-build-v0` @ `9b95a28`) · PR: #4 (draft, into `dev-build-v0`)
Decision: DEC-099 in `00_CONTEXT/DECISIONS.md`

## Your job
Take this branch to a verified, shippable state in one continuous run. Don't stop between steps to check in. Commit locally as you go and give one report at the end.

1. **Freshness.** `git fetch`, check out `fix/ux-batch-2026-10-28`, rebase onto the latest `origin/dev-build-v0` and resolve any conflicts (other sessions are active on `dev-build-v0`; keep their changes). Re-read the last 5 DECs. If another session has already used **DEC-099**, renumber this one to the next free number everywhere it appears (DECISIONS.md, CURRENT_STATE.md, APP_DESIGN_CHANGES.md, FORM_BENCHMARKS.md, code comments, migration 026 header, tests).
2. **Backend.** `cd lanesight-core && source .venv/bin/activate && python3 -m pytest`. Expect 353+ to pass. `test_avatar_rejects_oversize_and_garbage` failed in the cloud sandbox because of the environment; it should pass on the Mac. If it doesn't, show the error.
3. **iOS build. This has NOT been done yet.** The Swift was only syntax-checked (`swiftc -parse`) on Linux; it has never been type-checked against the iOS SDK. Run `cd ios/LaneSight && xcodegen generate` (2 new files), then build for the simulator and a device. Fix every compile error and warning these changes introduced. Spots most likely to need attention (Swift 6, default MainActor isolation):
   - `Common/TabDataStore.swift`: `withTaskGroup` child tasks capturing `APIClient` and returning `SessionSummary`; the `Task { [weak self] … }` inside `load(_:model:)`; the `async let` with `try?`.
   - `AppModel.swift`: `PHPhotoLibrary.performChanges(photosAddVideo(url))`. The change block is built in a `nonisolated static` func so it isn't main-actor isolated. Photos runs it on a background queue, so keep it nonisolated.
   - `Profile/ProfileView.swift`: `async let ars: Void = model.syncArsenal()` and `async let av: Void = model.refreshAvatar()`.
   - `Profile/FormBaselineView.swift`: the `@State` tuple `error: (field:, message:)?` and the custom `init` that seeds `_mode` and `_values`.
4. **Run it in the simulator** (PreviewHarness screens: `home`, `stats`, `lab`, `settings`, `profile`, `balledit`, `addball`, `choosesource`) and walk the checklist below. Fix whatever doesn't behave.
5. **Live deploy is irreversible, so only do it with Shayne's go-ahead (CLAUDE.md).** Order matters:
   1. Apply `lanesight-core/lanesight_core/models/migrations/026_arsenal_default_ball.sql` to live Supabase `europwryibstnmipbvam`.
   2. Then redeploy Cloud Run (`03_ENGINEERING/DEPLOY_CLOUDRUN.md`).

   The arsenal select now reads `user_balls.is_default`, so deploying the API before the migration breaks `GET /me/arsenal`.
6. **Report:** test count, build result, every fix you made, each checklist item pass/fail, any screen that now differs from Figma, and deploy status.

## What changed and why (DEC-099)
Shayne's 2026-10-28 test notes, one item per complaint:

| # | Complaint | Fix | Files |
|---|---|---|---|
| 1 | Tabs load piece by piece | `TabDataStore` (injected at the app root) owns Home/Stats/Lab data. Each page fetches every section in parallel and publishes once. A revisit refreshes silently (stale-while-revalidate via `Loadable.keepingLoaded(over:)`; a failed refresh keeps the good data). The first load shows one `LSPageLoading` spinner. Stats and Lab prefetch after Home loads. Lab card rings come with the list (first 12; the rest fetch per card and are cached in the store). Profile no longer flashes a spinner on Back. The store is reset on sign-in/out. | `Common/TabDataStore.swift` (new), `Home/HomeView.swift`, `Stats/StatsView.swift`, `Lab/LabView.swift`, `LaneSightApp.swift`, `Common/Components.swift`, `Profile/ProfileView.swift` |
| 2 | Nav bar shows on pushed screens; Settings stays open under Home | `View.lsHidesTabBar()` (`.toolbar(.hidden, for: .tabBar)`) on every non-primary screen. Only Home · Stats · Lab · Coaching show the tab bar. Supersedes in part DEC-096: you can't switch tabs mid-session; End session is the way out. | every pushed screen (grep `lsHidesTabBar`) |
| 3 | Retention setting unclear, and it isn't the user's call | Removed "Raw video retention 30 days". New Settings › **Videos** › "Save recordings to my phone" (`AppModel.saveVideosToPhone`, default off). It asks for add-only Photos access when turned on and saves the original live clip **before** analysis. `NSPhotoLibraryAddUsageDescription` added. Server retention is LaneSight's, plan-based, TBD. | `Settings/SettingsView.swift`, `AppModel.swift`, `Info.plist` |
| 4 | No default ball | `user_balls.is_default` (migration 026, partial unique index: one per user). API takes `make_default` on POST and `is_default` true/false on PATCH; retiring a ball clears its default. iOS: "Make this my default ball" checkbox on Ball setup (add mode: on when there's no default yet; edit mode: saves on tap); "Default" tag in Profile › Arsenal and in the ball picker. `SetupView` calls `applyDefaultBallForNewSession()` so a new Shot session starts with the default; "From your last session" still overrides. Default ≠ current: current moves with every pick (DEC-097). | `store.py`, migration 026, `API/Models.swift`, `API/APIClient.swift`, `AppModel.swift`, `Profile/ArsenalView.swift`, `Profile/ProfileView.swift`, `Setup/PickerSheets.swift`, `Setup/SetupView.swift` |
| 5 | First/last name not editable | **Root cause (server):** the DEC-087 "DOB required" gate fired on every name edit, and Shayne's live profile has no DOB, so every save failed. The gate now fires only at creation (no first/last/display name stored yet). Phone was already editable. Editable rows show a pencil. | `profile_validation.py`, `Profile/ProfileView.swift` |
| 6 | Can't set a Form baseline | Values defined (FORM_BENCHMARKS §0.4), in seconds: Pushaway E2→E3, Backswing E3→E4, Downswing E4→E6, Release E6→E7; Total = sum (`swing_time`). New Profile › **Form baseline** screen: Use my average / Enter my timing / No baseline, then Save. "Use this delivery as my baseline" on the Form card saves that delivery's measured phases only. Server validates: mode `entered`\|`average`, each value 0 < t ≤ 3 s, at least one phase; `null` clears. | `Profile/FormBaselineView.swift` (new), `Profile/ProfileView.swift`, `Result/FormCardView.swift`, `profile_validation.py`, `store.py` |
| 7 | Shot Analysis still asks Shot vs Form | The question came from the **Upload** screen ("What's in this clip?"). `UploadView(mode:)` now takes the mode from the Shot/Form card; Form uploads drop the target fields. The Lab header upload shortcut is removed (it had no Shot/Form choice). | `Upload/UploadView.swift`, `Common/AnalyzeCards.swift`, `Lab/LabView.swift` |

Tests added: `test_api.py::test_arsenal_default_ball_is_separate_from_current`; `test_profile.py`: legacy-profile name edit, form-baseline round-trip/clear, 5 parametrized rejects.

## On-device checklist
- [ ] Cold launch → Home appears whole (splash, then the full page; nothing pops in after). Stats and Lab are instant on first tap.
- [ ] Switch tabs back and forth → no spinners; pull-to-refresh updates silently.
- [ ] Home → Settings: no tab bar. Back → tab bar returns. Same for Profile, Setup, Active Session, Upload, metric detail, achievements, ball setup, Form baseline.
- [ ] Settings › Videos toggle → Photos prompt (add only). Record a live shot → the clip appears in Photos even if the analysis fails. Deny access → toggle flips off with the "Allow in Settings" note.
- [ ] Profile: edit first name, last name, phone → "Saved" each time (on Shayne's real account, which has no DOB).
- [ ] Add a ball with "default" checked → Default tag. Pick a different ball in a session → the default doesn't move. New session → Setup shows the default ball. Uncheck on ball edit → tag gone.
- [ ] Profile › Form baseline: enter times → Save → the row shows the total. "Use my average" → "Your average". A Form result shows "Use this delivery as my baseline" → saved note; the next form delivery compares against it.
- [ ] Lab › Shot Analysis › Upload video → no Shot/Form picker; title "Upload · Shot Analysis". Form → no target fields.

## Not in scope / follow-ups
- Figma frames for the new Form baseline screen, the default-ball row and the Settings › Videos section don't exist yet (logged in `APP_DESIGN_CHANGES.md`, 2026-10-28).
- Server-side video retention policy (plan-based) and its Privacy Policy wording are undefined.
- Shayne's live profile has no DOB. The app no longer blocks name edits on that, but he should add one in Profile.
