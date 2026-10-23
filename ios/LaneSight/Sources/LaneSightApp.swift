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
///
/// Leagues/Tourneys are not built yet. A TabView tab can't be made un-tappable, so tapping either
/// is intercepted: selection never moves to them (the current working tab stays selected) and a
/// clearly-labeled "Coming soon" sheet appears — they can never be mistaken for working, empty screens.
struct RootTabs: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0
    @State private var comingSoon: ComingSoonItem?

    private var selection: Binding<Int> {
        Binding(
            get: { tab },
            set: { newValue in
                switch newValue {
                case 3: comingSoon = ComingSoonItem(title: "Leagues", symbol: "person.3.fill")
                case 4: comingSoon = ComingSoonItem(title: "Tourneys", symbol: "trophy.fill")
                default: tab = newValue
                }
            }
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
            // Placeholder content — never actually shown because selection is intercepted above.
            ComingSoonView("Leagues", symbol: "person.3.fill")
                .tag(3)
                .tabItem { Label("Leagues · Soon", systemImage: "lock.fill") }
            ComingSoonView("Tourneys", symbol: "trophy.fill")
                .tag(4)
                .tabItem { Label("Tourneys · Soon", systemImage: "lock.fill") }
        }
        .sheet(item: $comingSoon) { item in
            ComingSoonSheet(item: item)
        }
        // Make the server the source of truth for the arsenal on authed load (also runs the one-time
        // migration of any locally-stored ball). Harmless in dev-user mode.
        .task { await model.syncArsenal() }
    }
}

struct ComingSoonItem: Identifiable {
    let title: String
    let symbol: String
    var id: String { title }
}

/// The unmistakable "Coming soon" state shown when a locked tab (Leagues / Tourneys) is tapped.
private struct ComingSoonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ComingSoonItem
    var body: some View {
        NavigationStack {
            ComingSoonView(item.title,
                           message: "\(item.title) aren't available in this dev build yet. They'll arrive in a later release.",
                           symbol: item.symbol)
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}
