import SwiftUI

@main
struct LaneSightApp: App {
    @StateObject private var model = AppModel()

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
            .tint(LS.blue)
            .preferredColorScheme(.dark)
        }
    }
}

/// Bottom tabs per HANDOFF §4/§5: Home · Stats · Lab · Leagues (Soon) · Tourneys (Soon).
/// Capture is reached via Lab → Start Live Session → Setup.
struct RootTabs: View {
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
            ComingSoonTab(title: "Leagues", symbol: "person.3.fill")
                .tag(3)
                .tabItem { Label("Leagues", systemImage: "person.3.fill") }
            ComingSoonTab(title: "Tourneys", symbol: "trophy.fill")
                .tag(4)
                .tabItem { Label("Tourneys", systemImage: "trophy.fill") }
        }
    }
}

/// Disabled "Soon" tabs (Leagues / Tournaments) — reachable but clearly not available yet, never empty.
struct ComingSoonTab: View {
    let title: String
    let symbol: String
    var body: some View {
        NavigationStack {
            ComingSoonView(title,
                           message: "\(title) are out of scope for this dev build. They'll arrive in a later release.",
                           symbol: symbol)
                .navigationTitle(title)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
