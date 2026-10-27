import SwiftUI

@main
struct LaneSightApp: App {
    @StateObject private var model = AppModel()

    init() {
        LSAppearance.apply()
        #if DEBUG
        LSFontCheck.log()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let screen = ProcessInfo.processInfo.environment["LS_PREVIEW"], !screen.isEmpty {
                    PreviewHarness(screen: screen)
                } else {
                    gateView
                }
                #else
                gateView
                #endif
            }
            .environmentObject(model)
            .tint(LS.action)
            .lsAppFont()
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder private var gateView: some View {
        switch model.gate {
        case .unauthenticated: AuthFlow()
        case .needsProfile:    ProfileSetupFlow()
        case .ready:           RootTabs()
        }
    }
}

#if DEBUG
/// DEBUG-only screen renderer for design verification against Figma. Launched with env vars
/// (SIMCTL_CHILD_LS_PREVIEW=<screen> [+ LS_PREVIEW_EMAIL/LS_PREVIEW_PW for real data]), it auto-signs-in and
/// renders one screen directly — no navigation (the simulator has no CLI tap). Never compiled into Release.
struct PreviewHarness: View {
    @EnvironmentObject var model: AppModel
    let screen: String
    @State private var ready = false
    @State private var note: String?
    @State private var previewBall: CatalogBall?

    var body: some View {
        Group {
            if !ready {
                ProgressView("Loading \(screen)…").tint(LS.action)
            } else {
                switch screen.lowercased() {
                case "home":  RootTabs()
                case "setup": NavigationStack { SetupView(initialMode: ProcessInfo.processInfo.environment["LS_PREVIEW_MODE"]) }
                case "stats": StatsView()
                case "lab":   LabView()
                case "shotcard":
                    if let r = model.result {
                        NavigationStack { if r.isForm { FormCardView(result: r) } else { ShotCardView(result: r) } }
                    }
                    else { Text("no shot result (set LS_PREVIEW_ID)").foregroundStyle(LS.textPrimary) }
                case "activesession":
                    if let id = ProcessInfo.processInfo.environment["LS_PREVIEW_ID"] {
                        NavigationStack { SessionView(reviewSessionId: id, readOnly: false) }
                    } else { Text("set LS_PREVIEW_ID").foregroundStyle(LS.textPrimary) }
                case "metricdetail":
                    NavigationStack {
                        MetricDetailView(metric: ProcessInfo.processInfo.environment["LS_PREVIEW_ID"] ?? "ball_speed")
                    }
                case "welcome": AuthFlow()
                case "signin": NavigationStack { SignInStep() }
                case "createaccount": NavigationStack { CreateAccountStep() }
                case "profilesetup": ProfileSetupFlow()
                case "addball": NavigationStack { AddBallStep() }
                case "ballsetup":
                    if let b = previewBall { NavigationStack { BallSetupView(ball: b) } }
                    else { Text("loading catalog ball…").foregroundStyle(LS.textPrimary) }
                case "balledit":
                    if let b = model.arsenal.first { NavigationStack { BallSetupView(arsenalBall: b) } }
                    else { Text("no arsenal ball for this account").foregroundStyle(LS.textPrimary) }
                case "formsession":
                    if let id = ProcessInfo.processInfo.environment["LS_PREVIEW_ID"] {
                        NavigationStack { FormSessionView(sessionId: id, readOnly: false) }
                    } else { Text("set LS_PREVIEW_ID").foregroundStyle(LS.textPrimary) }
                case "formsummary":
                    if let id = ProcessInfo.processInfo.environment["LS_PREVIEW_ID"] {
                        NavigationStack { FormSessionView(sessionId: id, readOnly: true) }
                    } else { Text("set LS_PREVIEW_ID").foregroundStyle(LS.textPrimary) }
                case "settings": NavigationStack { SettingsView() }
                case "deleteaccount": NavigationStack { DeleteAccountView() }
                case "choosesource":
                    LSBackground().sheet(isPresented: .constant(true)) {
                        ChooseSourceSheet(mode: ProcessInfo.processInfo.environment["LS_PREVIEW_MODE"] ?? "shot",
                                          onLive: {}, onUpload: {})
                            .presentationDetents([.height(340)])
                    }
                case "profile":  NavigationStack { ProfileView() }
                case "achievements": NavigationStack { AchievementsView() }
                case "sessionsummary":
                    if let id = ProcessInfo.processInfo.environment["LS_PREVIEW_ID"] {
                        NavigationStack { SessionSummaryView(sessionId: id) }
                    } else { Text("set LS_PREVIEW_ID").foregroundStyle(LS.textPrimary) }
                case "analyzing":
                    ProcessingCover(busy: .constant(true))
                        .onAppear { model.pipeline = .analyzing(state: "cv", timings: [:]) }
                case "unlock":
                    if let n = PreviewHarness.sampleNotification(unlock: true) { NavigationStack { CelebrationRouter(notification: n) } }
                    else { Text("sample decode failed").foregroundStyle(LS.textPrimary) }
                case "tierup":
                    if let n = PreviewHarness.sampleNotification(unlock: false) { NavigationStack { CelebrationRouter(notification: n) } }
                    else { Text("sample decode failed").foregroundStyle(LS.textPrimary) }
                case "camprompt": CameraPermissionView(mode: .prompt)
                case "camdenied": CameraPermissionView(mode: .denied)
                case "feedback": FeedbackView(onFinish: {})
                case "scorepopup": ScoreUpdatePopup(sessionId: ProcessInfo.processInfo.environment["LS_PREVIEW_ID"])
                default:      Text("unknown preview screen: \(screen)").foregroundStyle(LS.textPrimary)
                }
            }
        }
        .task {
            let env = ProcessInfo.processInfo.environment
            if let e = env["LS_PREVIEW_EMAIL"], let p = env["LS_PREVIEW_PW"] {
                // Force a fresh sign-in: the Simulator keychain survives `simctl uninstall`, so a stale
                // token from a previous account would otherwise be reused and render the wrong data.
                model.signOut()
                do { try await model.signIn(email: e, password: p) }
                catch { note = "auto-login failed: \(error)" }
            }
            if screen.lowercased() == "shotcard", let id = env["LS_PREVIEW_ID"] {
                _ = await model.loadShotResult(shotId: id, captureModeHint: "shot")
            }
            if screen.lowercased() == "ballsetup" {
                let q = env["LS_PREVIEW_QUERY"] ?? ""
                previewBall = (try? await model.makeClient().catalogBalls(query: q))?.first
            }
            if screen.lowercased() == "balledit" { await model.syncArsenal() }
            ready = true
        }
    }

    /// Sample notification payloads for previewing the celebration surfaces (layout only — never shipped).
    static func sampleNotification(unlock: Bool) -> AppNotification? {
        let json = unlock
            ? #"{"id":"s","kind":"achievement_popup","priority":1,"payload":{"category":"streak","name":"Line Locked","description":"10 shots in a row within 1 board of your target at the arrows","value":"SHOTS 32–41"}}"#
            : #"{"id":"s","kind":"tier_celebration","priority":1,"payload":{"to_tier":"platinum","score":706,"next_tier":"onyx","points":144}}"#
        return try? JSONDecoder().decode(AppNotification.self, from: Data(json.utf8))
    }
}
#endif

/// Bottom tabs per HANDOFF §4/§5 + DEC-055: Home · Stats · Lab · Leagues · Tourneys.
/// Capture is reached via Lab → Start Live Session → Setup.
///
/// Leagues/Tourneys are not built yet. Per DEC-055 they are shown disabled: dimmed, not tappable, with
/// NO "Soon" / "Coming soon" label and no sheet. A system TabView tab can't be made un-tappable, so
/// tapping either is intercepted — selection never moves to them (the current working tab stays
/// selected) — and because they can never become selected they always render in the muted, unselected
/// (dimmed) state. No navigation happens and nothing is presented.
struct RootTabs: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0

    private var selection: Binding<Int> {
        Binding(
            get: { tab },
            // Taps on the disabled Leagues (3) / Tourneys (4) tabs are a no-op: selection stays put.
            set: { newValue in if newValue < 3 { tab = newValue } }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            HomeView()
                .tag(0)
                .tabItem { Label("Home", systemImage: "house.fill") }
            StatsView()
                .tag(1)
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
            LabView()
                .tag(2)
                .tabItem { Label("Lab", systemImage: "flask.fill") }
            // Disabled tabs (DEC-055): dimmed + not tappable, no label. Content is never shown because
            // selection can never move here. No "Soon" badge, no coming-soon sheet.
            Color.clear
                .tag(3)
                .tabItem { Label("Leagues", systemImage: "person.3.fill") }
            Color.clear
                .tag(4)
                .tabItem { Label("Tourneys", systemImage: "trophy.fill") }
        }
        // Make the server the source of truth for the arsenal on authed load (also runs the one-time
        // migration of any locally-stored ball). Harmless in dev-user mode.
        .task { await model.syncArsenal() }
    }
}
