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
            // First launch ever: land on Settings so you can confirm the (pre-filled) API URL and tap
            // Check connection before the full-screen camera. Subsequent launches open on Capture.
            let d = UserDefaults.standard
            if !d.bool(forKey: "ls.launchedBefore") {
                tab = 1
                d.set(true, forKey: "ls.launchedBefore")
            }
        }
    }
}
