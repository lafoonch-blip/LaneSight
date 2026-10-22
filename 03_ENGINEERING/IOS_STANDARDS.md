# iOS Engineering Standards — LaneSight
Status: DRAFT (for Shayne's review)
Version: 0.1
Last Updated: 2026-10-22
Owner: Shayne
Source reviewed: Apple "Get started with iOS" pathway (developer.apple.com/ios/get-started), plus linked HIG, privacy, security, accessibility, localization, performance and App Review pages
Applies to: Dev Build v0 onward (`ios/LaneSight`), DEC-029
Proposed home: `03_ENGINEERING/IOS_STANDARDS.md`

## 1. What Apple's pathway asks for, and what it means for LaneSight

| Apple practice | LaneSight standard | When |
|---|---|---|
| **Xcode + Swift + SwiftUI** | Latest stable Xcode, Swift 6 language mode with strict concurrency, SwiftUI-first; UIKit only where SwiftUI lacks an API (camera preview layer). Minimum iOS = current major − 1 | Dev v0 |
| **Human Interface Guidelines** | Tab bar + navigation stacks per HIG; SF Symbols for icons; system controls before custom ones; 44×44 pt minimum tap targets (bigger on capture screens, used with bowling-hand fingers); Dynamic Type; light/dark from DEC-016 tokens as asset-catalog colors | Dev v0 (functional), full in designed screens |
| **Apple Design Resources** | Use the iOS UI kit in Figma as the base for the LaneSight components, so designed screens map to native controls | Design track |
| **Privacy: informed consent, transparency, privacy statement** | Ask for camera (and mic only if audio is recorded) and Photos (read for upload) **at the moment of use**, with clear purpose strings. Privacy policy URL in-app and in App Store Connect. Privacy manifest (`PrivacyInfo.xcprivacy`) listing data collected and required-reason APIs. App Privacy "nutrition label" filled from the same list. No tracking; no ad SDKs | Purpose strings + manifest: Dev v0. Policy: before TestFlight external / Beta |
| **Security: passkeys, Keychain** | Sign in with Apple + email via Supabase; passkeys when Supabase supports them. Session tokens in the **Keychain**, never `UserDefaults`. Supabase service key never in the app (Mac service only). HTTPS only; App Transport Security on (Tailscale HTTPS certs for the dev host) | Dev v0 |
| **Accessibility** | Every metric card, pin diagram and chart has VoiceOver labels with value + status ("Ball speed 17.4 mph, measured"); status never shown by color alone; Dynamic Type up to accessibility sizes on result screens; Reduce Motion respected; the spoken cue also appears as text | Dev v0 basics; audit before Beta |
| **Localization / internationalization** | English only at launch, but all strings in a String Catalog; units/numbers/dates via Foundation formatters (`Measurement`, `FormatStyle`); mph/km/h and ft/m from user settings; RTL-safe layouts (leading/trailing, not left/right). Note: lane "boards" and left/right-handed geometry stay physical, not mirrored for RTL | Dev v0 (catalog + formatters) |
| **Inclusion** | Neutral, encouraging coaching language; style options are delivery types (one-handed with thumb / no thumb / two-handed), not skill labels; no gendered defaults | Rules/cue review |
| **Testing and debugging** | Unit tests (Swift Testing) for models, API client and upload queue; UI tests for the capture → result loop; snapshot/preview fixtures from **real recorded API responses** (no fabricated metrics in shipped code paths); crash and error logging in the dev panel | Dev v0 |
| **Performance (Instruments)** | Profile capture (dropped frames at 120 fps), memory during upload, energy use over a 3-game session, app launch time. Targets: no dropped frames while recording; upload in background without blocking the UI | Before first live session |
| **Multi-platform (iPad, Mac)** | iPhone only for MVP; keep views size-class aware so iPad comes cheaply later. Don't offer the iOS app on Apple-silicon Macs until tested | Post-MVP |
| **Distribution and business model** | Free at launch (decided). Builds via Xcode → TestFlight internal (dev) → TestFlight external (friends Beta) → App Store | Dev v0 → Beta |

## 2. App Review items that affect our design now
These come from the App Review Guidelines linked from the pathway. Verify against the current guidelines before submission.
- **Account deletion in the app** is required when the app supports account creation. Already in MVP scope.
- **Sign in with Apple** must be offered when other third-party social logins are offered. We offer Apple + email.
- **Age rating and age gate:** the 13+ gate is in MVP; set the App Store age rating to match.
- **Video of other people:** bowlers on neighboring lanes can appear in clips. State this in the privacy policy, keep retention short, and never build profiles of non-enrolled bowlers (MASTER_CONTEXT).
- **No placeholder or demo content in a submitted build:** disabled tiles (Compare to a PBA Pro, Leagues, Tournaments) must be clearly "Coming soon" and must not open an empty view.
- **Accurate claims:** metrics are labeled Measured / Best effort / Unavailable. Don't market unvalidated metrics as validated (DEC-034).

## 3. Project conventions
- **Structure:** `ios/LaneSight` Xcode project; feature folders (Capture, Session, Shot, Arsenal, Profile, DevPanel); shared `LaneSightKit` Swift package for models + API client.
- **Architecture:** SwiftUI + Observation (`@Observable`) view models; async/await networking; no third-party UI frameworks. Dependencies allowed: Supabase Swift SDK only, unless approved.
- **Models:** Codable types generated from the `lanesight-api` OpenAPI spec / `ShotRecord`; one source of truth for metric status and reason codes.
- **Capture:** AVFoundation, 1080p120 SDR default, real per-frame timestamps written to the upload metadata (DEC-028); refuse silently-degraded formats and show why.
- **Config:** server URL, Beta/Prod toggle and feature flags in an xcconfig per scheme (Dev, Beta, Prod); no secrets in the repo.
- **Versioning:** app version + build number + `lanesight-core` algorithm version + rules version shown in the dev panel and stored on every shot.
- **Code quality:** SwiftLint/swift-format in CI (F-06); warnings treated as errors in Beta/Prod schemes.

## 4. Dev Build v0 checklist (adds to DEV_BUILD_PLAN Phase 2)
- [ ] Swift 6 strict concurrency, iOS minimum set, schemes Dev/Beta/Prod
- [ ] Info.plist purpose strings: camera, Photos (read), microphone only if used, local network (if the hotspot fallback is used)
- [ ] `PrivacyInfo.xcprivacy` privacy manifest
- [ ] Keychain token storage; Sign in with Apple + email; in-app account deletion
- [ ] VoiceOver labels on shot card, pins and adjustments; Dynamic Type check
- [ ] String Catalog + Foundation formatters + unit setting
- [ ] Swift Testing unit tests + one UI test of capture → upload → result using a real clip against the Mac service
- [ ] Instruments pass: 120 fps capture with no dropped frames; background upload memory/energy
