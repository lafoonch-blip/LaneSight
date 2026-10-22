import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Units") {
                Picker("Speed", selection: $model.speedUnit) {
                    Text("mph").tag("mph")
                    Text("km/h").tag("kmh")
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Speak adjustments", isOn: $model.speakAdjustments)
                HStack { Text("Recording quality"); Spacer(); Text("Highest available").foregroundStyle(.secondary) }
            } header: {
                Text("Capture")
            } footer: {
                Text("Records at 120 fps when the phone supports it, then 60, then 30. HDR is off for analysis.")
            }

            Section {
                HStack { Text("Raw video retention"); Spacer(); Text("30 days").foregroundStyle(.secondary) }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Shot results are kept. Raw video is deleted after the retention period unless you save a clip.")
            }

            Section("Account") {
                HStack { Text("Terms of Service"); Spacer(); Text("Coming soon").font(.caption).foregroundStyle(.secondary) }
                HStack { Text("Privacy Policy"); Spacer(); Text("Coming soon").font(.caption).foregroundStyle(.secondary) }
                NavigationLink { DeleteAccountView() } label: {
                    Text("Delete account").foregroundStyle(.red)
                }
            }

            Section("Developer") {
                NavigationLink { DevPanelView() } label: {
                    Label("Dev build", systemImage: "hammer")
                }
            }

            Section {
                Button(role: .destructive) {
                    model.onboarded = false
                } label: {
                    Text("Sign out")
                }
            } footer: {
                Text("LaneSight \(appVersion) · Dev build")
            }
        }
        .scrollContentBackground(.hidden)
        .background(LSBackground())
        .navigationTitle("Settings")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
