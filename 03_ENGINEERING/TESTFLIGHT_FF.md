# Friends & Family TestFlight — Shayne's checklist (DEC-123)

Status: READY FOR SHAYNE · Date: 2026-11-02 · Owner: Shayne

The F&F build is a **pre-Beta** external TestFlight test to gather real-world clips and feedback. It is NOT
gated by the DEC-118 Beta accuracy/coverage/<30 s gates. Bundle `com.lanesight.app`, team `GK3N928748`
(personal, lafoonch@gmail.com). The app is built and verified in this branch; everything below is the part
only you can do (App Store Connect + the archive upload).

---

## 0. One-time code/config facts (already done in this branch)
- Version/build: `MARKETING_VERSION 0.9.0`, `CURRENT_PROJECT_VERSION 1` (project.yml). **Bump the build number
  on every upload** — each TestFlight build number must be unique (0.9.0 (1), then (2), …).
- Export compliance key: `ITSAppUsesNonExemptEncryption = NO` is in Info.plist (HTTPS only, no custom crypto),
  so App Store Connect won't ask the per-build export-compliance question.
- Build phase: the Release configuration sets `LS_APP_PHASE = ff` → the app runs as the F&F cohort (shows the
  one-screen consent, tags all feedback `ff`, hides owner-only dev screens). Your own account stays `dev`
  (the server forces the owner + staged accounts to `dev`, migration 037).

## 1. App Store Connect — app record
1. App Store Connect → **Apps → +** → **New App**. Platform iOS, name **LaneSight**, primary language English,
   bundle ID **com.lanesight.app** (register it under Certificates/Identifiers first if it isn't listed), SKU
   `lanesight-app`.
2. You do **not** need to complete the App Store listing for TestFlight — only the TestFlight tab.

## 2. Export compliance
With `ITSAppUsesNonExemptEncryption = NO` in the build, TestFlight shows the build as ready with no compliance
prompt. If App Store Connect ever asks: the app uses only standard HTTPS/TLS → "No" to proprietary encryption,
exempt.

## 3. TestFlight — Test Information (do this once)
- **Beta App Description** (paste):
  > LaneSight analyzes your bowling delivery from a short video — ball speed, rev rate, ball path, and form
  > timing — and suggests your next move. This is an early Friends & Family test build: some numbers may be
  > wrong or missing, and we're gathering real clips and feedback to make it better.
- **What to Test** (paste):
  > Record a few shots (and a Form video if you like) when you bowl. Check whether the result screen and the
  > numbers make sense. Use the Feedback button on the Home screen to report anything wrong, confusing, or
  > missing, or any idea — one tap, pick a category, type a note. Try the full flow including creating an
  > account and, if you want, deleting it from Settings → Delete account.
- **Feedback email**: set to the address you monitor (e.g. `lafoonch@gmail.com`). Testers' TestFlight
  feedback and screenshots go here; in-app feedback goes to the server feedback store (owner dashboard).
- **Beta App Review — Sign-in required: YES.** Provide the demo login from §5.

## 4. External "Friends & Family" group + public link
1. TestFlight → **Groups → +** → name **Friends & Family** → **External** group.
2. Add the build to the group (first external build triggers a short Beta App Review by Apple — the demo login
   in §5 is for that review).
3. Turn on **Public Link**. Share that link with your friends/family — anyone with the link can install
   (iPhone only). Set a tester limit if you want to keep it small.

## 5. Demo login for Apple's Beta App Review
Apple's reviewer needs a working account. Use a **staged** account (cohort forced to `dev`, so its data never
mixes into F&F stats) with a seeded history so the app looks populated.

- **Create it (Shayne — live write, not done for you):**
  ```
  cd lanesight-core && source .venv/bin/activate
  python -m ops.seed_staged_accounts --account active --target live
  ```
  This creates/updates the staged `active` account against live Supabase and stores a generated password in
  the macOS **Keychain** (service `com.lanesight.staged`, account = the email). It is never printed or
  committed.
- **Record here (fill in after creating it):**
  - Demo account email: `<base_email>+ls_active@<domain>` — the exact value is `accounts.active.email` (or
    `base_email` + `+ls_active`) in `lanesight-core/ops/staged_accounts.toml`.
  - Password location: macOS **Keychain**, service **`com.lanesight.staged`**, account = the demo email.
    Retrieve with: `security find-generic-password -s com.lanesight.staged -a '<email>' -w`.
  - **Do NOT write the password in this file or anywhere in the repo.**
- Put the email + password into App Store Connect → TestFlight → **Test Information → Sign-In** (and App
  Review → Demo Account if asked).

## 6. Archive & upload (from this Mac)
```
cd ios/LaneSight
xcodegen generate                                   # regenerate the project from project.yml
open LaneSight.xcodeproj                             # -> Xcode
```
In Xcode:
1. Select the **LaneSight** scheme, destination **Any iOS Device (arm64)**.
2. Bump the build number if this isn't the first upload (Target → General, or CURRENT_PROJECT_VERSION in
   project.yml then re-run `xcodegen generate`).
3. **Product → Archive**. When it finishes, the Organizer opens.
4. **Distribute App → App Store Connect → Upload** → automatic signing (team GK3N928748) → Upload.

Command-line alternative (if you prefer): archive then upload with an App Store Connect API key —
```
xcodebuild -project LaneSight.xcodeproj -scheme LaneSight -configuration Release \
  -archivePath build/LaneSight.xcarchive -destination 'generic/platform=iOS' archive
xcodebuild -exportArchive -archivePath build/LaneSight.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export     # method: app-store-connect
xcrun notarytool  # not needed for App Store; App Store upload is via Organizer or Transporter
```
(The Organizer path is simplest; the CLI needs an `ExportOptions.plist` with `method = app-store-connect` and
an App Store Connect API key.)

## 7. After upload
- The build appears in TestFlight in a few minutes (processing). Add it to the Friends & Family group.
- First external build → wait for Apple's Beta App Review (usually < 24 h) → then the public link works.
- Watch feedback: in-app feedback lands in the server feedback store and the **ops dashboard → Feedback** and
  **Insights** pages, filtered by phase (`ff`). TestFlight's own feedback/screenshots go to your feedback
  email.

## Related
- Consent copy + cohort: DEC-123; account cohort/consent fields: migration 037.
- Feedback button: DEC-124 / HANDOFF_2026-11-02_FEEDBACK_BUTTON.md.
- Account deletion (App Store 5.1.1(v)): Settings → Delete account → `DELETE /me` (anonymizes feedback,
  deletes the account + its clips/sessions). Verified end-to-end (see report).
