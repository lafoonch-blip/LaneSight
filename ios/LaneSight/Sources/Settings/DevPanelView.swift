import SwiftUI

/// Dev panel (Dev.dc.html): server URL + health, versions, timings, server config. Keeps the
/// pre-filled tailnet URL and X-Dev-User editable here (the app's HTTP-over-tailnet dev config).
struct DevPanelView: View {
    @EnvironmentObject var model: AppModel
    @State private var checking = false
    @State private var health: HealthResponse?
    @State private var latencyMs: Int?
    @State private var errorText: String?

    /// True when the server is live but can't reach Supabase (or is degraded) — the app is NOT working.
    private var supabaseDown: Bool {
        guard let health else { return false }
        return health.status == "degraded" || health.supabase_reachable == false
    }

    var body: some View {
        Form {
            Section {
                TextField("https://lanesight-api-....run.app", text: $model.apiBaseURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button {
                    Task { await test() }
                } label: {
                    HStack { Text("Test connection"); if checking { Spacer(); ProgressView() } }
                }
                .disabled(checking || model.apiBaseURL.isEmpty)
                if let latencyMs, errorText == nil {
                    Label("Reached /health · \(latencyMs) ms", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.lsFootnote)
                }
                if let errorText {
                    Text(errorText).font(.lsFootnote).foregroundStyle(.red).textSelection(.enabled)
                }
            } header: {
                Text("Analysis host")
            } footer: {
                Text("GET /health and /auth/* carry no auth. Every other request sends a real Bearer token unless the dev-user toggle below is on.")
            }

            // Fail visibly: if the service can't reach the database, the app is not actually working.
            if supabaseDown {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Supabase unreachable", systemImage: "xmark.octagon.fill")
                            .font(.lsSubheadline.bold()).foregroundStyle(.white)
                        Text("The Mac service can't reach the database. The app is NOT working — sign-in and your data will fail. This is not a safe session; do not treat memory mode as OK.")
                            .font(.lsCaption).foregroundStyle(.white.opacity(0.95))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .listRowBackground(Color.red)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Supabase unreachable. The Mac service can't reach the database. The app is not working.")
                }
            }

            if let health {
                Section("Service status") {
                    HStack {
                        Text("Status"); Spacer()
                        Text((health.status ?? "?").uppercased())
                            .font(.lsCallout.bold())
                            .foregroundStyle(health.status == "ok" ? .green : .red)
                    }
                    HStack {
                        Text("Supabase reachable"); Spacer()
                        switch health.supabase_reachable {
                        case true: Text("Yes").foregroundStyle(.green)
                        case false: Text("No").foregroundStyle(.red)
                        default: Text("n/a (memory mode)").foregroundStyle(.red)
                        }
                    }
                }
            }

            Section {
                Toggle("Developer: use dev user (simulator)", isOn: $model.useDevUser)
                if model.useDevUser {
                    TextField("Dev user id (X-Dev-User)", text: $model.devUser)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Label("Bypasses real sign-in. Never use this for a real session.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.lsCaption).foregroundStyle(.orange)
                }
            } header: {
                Text("Developer auth override")
            } footer: {
                Text("OFF by default. When on, requests send X-Dev-User instead of a real Bearer token — simulator/testing only.")
            }

            if let versions = health?.versions, !versions.isEmpty {
                Section("Versions") {
                    ForEach(versions.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                        HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary).font(.lsCallout.monospaced()) }
                    }
                }
            }

            if let config = health?.config {
                Section("Server config") {
                    row("Mode", config.mode)
                    boolRow("DB configured", config.db_url_present)
                    boolRow("Service role", config.service_role_present)
                    boolRow("Dev insecure", config.dev_insecure)
                }
            }

            Section("Delivery") {
                Picker("Handed", selection: $model.handed) {
                    Text("Right").tag("R"); Text("Left").tag("L")
                }.pickerStyle(.segmented)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LSBackground())
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack { Text(label); Spacer(); Text(value ?? "—").foregroundStyle(.secondary) }
    }
    private func boolRow(_ label: String, _ value: Bool?) -> some View {
        HStack {
            Text(label); Spacer()
            Image(systemName: value == true ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(value == true ? .green : .secondary)
        }
    }

    private func test() async {
        checking = true
        errorText = nil
        let start = Date()
        do {
            let h = try await model.makeClient().health()
            latencyMs = Int(Date().timeIntervalSince(start) * 1000)
            health = h
        } catch {
            errorText = error.localizedDescription
            latencyMs = nil
        }
        checking = false
    }
}
