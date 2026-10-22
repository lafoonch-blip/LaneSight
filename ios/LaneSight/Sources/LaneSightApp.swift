import SwiftUI

@main
struct LaneSightApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            CaptureView()
                .tag(0)
                .tabItem { Label("Capture", systemImage: "camera.fill") }
            SettingsView()
                .tag(1)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .onAppear {
            // First run (no API URL yet): land on Settings so you can configure + Check connection
            // before the full-screen camera. Once a URL is saved, open on Capture.
            if model.apiBaseURL.trimmingCharacters(in: .whitespaces).isEmpty { tab = 1 }
        }
    }
}
