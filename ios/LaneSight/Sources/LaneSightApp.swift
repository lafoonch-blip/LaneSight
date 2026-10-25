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
                switch model.gate {
                case .unauthenticated: AuthFlow()
                case .needsProfile:    ProfileSetupFlow()
                case .ready:           RootTabs()
                }
            }
            .environmentObject(model)
            .tint(LS.action)
            .lsAppFont()
            .preferredColorScheme(.dark)
        }
    }
}

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
