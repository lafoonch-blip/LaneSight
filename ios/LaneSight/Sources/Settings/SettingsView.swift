import SwiftUI

/// Settings (v3.7 Figma 434:6174): unit toggles, capture quality, save-to-phone (DEC-099) and the account
/// rows, in the dark card style. Unimplemented items (Face ID lock, the legal pages) are shown honestly
/// as "Coming later" rather than fake-working.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("ls.distanceUnit") private var distanceUnit = "feet"
    @State private var photosNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Units") {
                    VStack(spacing: 10) {
                        SegToggle(options: [("mph", "mph"), ("km/h", "kmh")], selection: $model.speedUnit)
                        SegToggle(options: [("feet", "feet"), ("meters", "meters")], selection: $distanceUnit)
                    }
                }

                section("Capture", footer: "Records at 120 fps when the phone supports it, then 60, then 30.") {
                    card {
                        pickerRow("Recording quality", value: "Highest available") {
                            Picker("", selection: $model.preferredFPS) {
                                Text("Highest available").tag(120); Text("60 fps").tag(60); Text("30 fps").tag(30)
                            }
                        }
                    }
                }

                // DEC-099: the bowler chooses only whether recordings are ALSO saved on their phone. How long video
                // stays on LaneSight's servers is set by LaneSight (plan-based), so it isn't a user setting.
                section("Videos", footer: photosNote ?? "LaneSight stores your recordings securely for analysis; your shot results are always kept. Turn this on to also save a copy of each recording to Photos on this iPhone.") {
                    card {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save recordings to my phone").font(.system(size: 15)).foregroundStyle(LS.textPrimary)
                                Text("Adds each live recording to Photos").font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { model.saveVideosToPhone },
                                set: { on in
                                    guard on else { model.saveVideosToPhone = false; photosNote = nil; return }
                                    Task {
                                        if await AppModel.requestPhotosAddAccess() {
                                            model.saveVideosToPhone = true; photosNote = nil
                                        } else {
                                            model.saveVideosToPhone = false
                                            photosNote = "LaneSight can't add to Photos. Allow it in iPhone Settings › LaneSight › Photos, then turn this on again."
                                        }
                                    }
                                }))
                            .labelsHidden().tint(LS.action)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 60)
                    }
                }

                section("Account") {
                    card {
                        valueRow("Face ID unlock", "Coming later")
                        divider
                        linkRow("Terms of Service")
                        divider
                        linkRow("Privacy Policy")
                        divider
                        Button { model.signOut() } label: {
                            rowLabel("Sign out", color: LS.textPrimary, chevron: false)
                        }.buttonStyle(.plain)
                        divider
                        NavigationLink { DeleteAccountView() } label: {
                            rowLabel("Delete account", color: LS.dataOrange, chevron: false)
                        }.buttonStyle(.plain)
                    }
                }

                section("Developer") {
                    card {
                        NavigationLink { DevPanelView() } label: {
                            rowLabel("Dev build", color: LS.textPrimary, chevron: true)
                        }.buttonStyle(.plain)
                    }
                }

                Text("LaneSight \(appVersion) · MVP")
                    .font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                    .frame(maxWidth: .infinity).padding(.top, 4)
                Spacer(minLength: 8)
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .lsHidesTabBar()      // DEC-099: only Home · Stats · Lab · Coaching show the tab bar
    }

    // MARK: building blocks

    private func section<Content: View>(_ title: String, footer: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(LS.textPrimary)
            content()
            if let footer {
                Text(footer).font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private var divider: some View { Divider().overlay(LS.border).padding(.leading, 16) }

    private func rowLabel(_ title: String, color: Color, chevron: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundStyle(color)
            Spacer()
            if chevron { Text("›").font(.system(size: 18)).foregroundStyle(LS.textSecondary) }
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundStyle(LS.textPrimary)
            Spacer()
            Text(value).font(.system(size: 14)).foregroundStyle(LS.textSecondary)
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    private func linkRow(_ title: String) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundStyle(LS.textPrimary)
            Spacer()
            Text("›").font(.system(size: 18)).foregroundStyle(LS.textSecondary)
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    private func pickerRow<P: View>(_ title: String, value: String, @ViewBuilder _ picker: () -> P) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundStyle(LS.textPrimary)
            Spacer()
            picker().tint(LS.textSecondary).labelsHidden()
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }
}

/// A segmented pill group (cyan selected). Shared by Settings' unit toggles and the Profile toggles.
struct SegToggle: View {
    let options: [(label: String, value: String)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.value) { opt in
                Button { selection = opt.value } label: {
                    Text(opt.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selection == opt.value ? LS.onAction : LS.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(selection == opt.value ? LS.action : LS.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(selection == opt.value ? .clear : LS.cardStrokeBright, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
