import SwiftUI

@main
struct LaneSightApp: App {
    @StateObject private var model = AppModel()
    /// DEC-099: shared Home/Stats/Lab data (parallel loads, one publish per page, silent revalidation).
    @StateObject private var tabData = TabDataStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LSAppearance.apply()
        #if DEBUG
        LSFontCheck.log()
        #endif
    }

    private var isPreview: Bool {
        #if DEBUG
        return !(ProcessInfo.processInfo.environment["LS_PREVIEW"] ?? "").isEmpty
        #else
        return false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
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
                // Seamless launch: keep the branded splash up until Home has loaded (real app only, not previews).
                // Not while the first-run intro is up (that precedes Home).
                if !isPreview, model.gate == .ready, model.hasSeenIntro, !model.homeLoaded {
                    LaunchSplash().transition(.opacity).zIndex(1)
                }
            }
            .environmentObject(model)
            .environmentObject(tabData)
            // Never show one account's data to the next: drop the tab cache on sign-in/out.
            .onChange(of: model.isAuthenticated) { _, _ in tabData.reset() }
            // §2 analytics (DEC-098 M3): one "app_opened" per launch (real app only, never previews).
            .task { if !isPreview { model.trackAppOpenedOnce() } }
            .tint(LS.action)
            .lsAppFont()
            .preferredColorScheme(.dark)
            .installGlobalKeyboardDismiss()     // tap outside a field anywhere dismisses the keyboard
            // DEC-086: an upload analysis blocks the whole app from the root so its result is never
            // orphaned by navigating away from Lab › Upload mid-analysis. Screen stays awake throughout.
            .fullScreenCover(isPresented: $model.uploadBusy) {
                ProcessingCover(busy: $model.uploadBusy, failButtonLabel: "Close")
                    .environmentObject(model)
                    .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
                    .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            }
            // Recover-on-resume: if an analysis was in flight when the app was backgrounded, the server
            // finishes it durably even though our request dropped — so on return to the foreground, fetch
            // that shot and present its result (or failure) instead of leaving the user stuck.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.reconcilePendingAnalysis() } }
            }
        }
    }

    @ViewBuilder private var gateView: some View {
        switch model.gate {
        case .unauthenticated: AuthFlow()
        case .needsProfile:    ProfileSetupFlow()
        // First-run: show the "how it works" intro once before Home.
        case .ready:           if model.hasSeenIntro { RootTabs() } else { HowItWorksFlow() }
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
                case "keyposition":
                    if let r = model.result {
                        NavigationStack { KeyPositionFullView(result: r, startKey: ProcessInfo.processInfo.environment["LS_PREVIEW_KEY"] ?? "release") }
                    } else { Text("no form result (set LS_PREVIEW_ID to a form shot)").foregroundStyle(LS.textPrimary) }
                case "metricdetail":
                    NavigationStack {
                        MetricDetailView(metric: ProcessInfo.processInfo.environment["LS_PREVIEW_ID"] ?? "ball_speed")
                    }
                case "welcome": AuthFlow()
                case "splash": LaunchSplash()
                case "howitworks": HowItWorksFlow()
                case "skeletonpreview":
                    if let ui = UIImage(named: "LabFormPhoto") {
                        Image(uiImage: ui).resizable().scaledToFit()
                            .overlay { SkeletonOverlay(joints: SkeletonOverlay.debugSample, imageSize: ui.size) }
                            .padding()
                    } else { Text("no asset").foregroundStyle(LS.textPrimary) }
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
                case "coaching": CoachingView()
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
            if screen.lowercased() == "keyposition", let id = env["LS_PREVIEW_ID"] {
                _ = await model.loadShotResult(shotId: id, captureModeHint: "form")
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

/// Bottom tabs (DEC-084): Home · Stats · Lab · Coaching. Capture is reached via Lab → Start Live Session →
/// Setup. The old disabled Leagues/Tourneys tabs are gone — a dimmed tab reads as broken; Coaching is a real,
/// tappable tab that opens a "coming soon" screen (sets expectations + measures interest).
struct RootTabs: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tag(0)
                .tabItem { Label("Home", systemImage: "house.fill") }
            StatsView()
                .tag(1)
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
            LabView()
                .tag(2)
                .tabItem { Label("Lab", systemImage: "flask.fill") }
            CoachingView()
                .tag(3)
                .tabItem { Label("Coaching", systemImage: "graduationcap.fill") }
        }
        // Make the server the source of truth for the arsenal on authed load (also runs the one-time
        // migration of any locally-stored ball). Harmless in dev-user mode.
        .task { await model.syncArsenal() }
    }
}
