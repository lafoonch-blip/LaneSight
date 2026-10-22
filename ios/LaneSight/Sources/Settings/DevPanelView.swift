import SwiftUI

/// Dev panel (Dev.dc.html): server URL + health, versions, timings, server config. Keeps the
/// pre-filled tailnet URL and X-Dev-User editable here (the app's HTTP-over-tailnet dev config).
struct DevPanelView: View {
    @EnvironmentObject var model: AppModel
    @State private var checking = false
    @State private var health: HealthResponse?
    @State private var latencyMs: Int?
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                TextField("http://<mac>.<tailnet>.ts.net:8787", text: $model.apiBaseURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("Dev user id (X-Dev-User)", text: $model.devUser)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button {
                    Task { await test() }
                } label: {
                    HStack { Text("Test connection"); if checking { Spacer(); ProgressView() } }
                }
                .disabled(checking || model.apiBaseURL.isEmpty)
                if let latencyMs, errorText == nil {
                    Label("Healthy · \(latencyMs) ms", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.footnote)
                }
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                }
            } header: {
                Text("Analysis host")
            } footer: {
                Text("GET /health has no auth. Every other request sends the X-Dev-User header (dev mode — no OAuth yet).")
            }

            if let versions = health?.versions, !versions.isEmpty {
                Section("Versions") {
                    ForEach(versions.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                        HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary).font(.callout.monospaced()) }
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
