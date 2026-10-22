import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac API") {
                    TextField("http://<mac>.<tailnet>.ts.net:8787", text: $model.apiBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Dev user id", text: $model.devUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Delivery") {
                    Picker("Handed", selection: $model.handed) {
                        Text("Right").tag("R")
                        Text("Left").tag("L")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        Task { checking = true; await model.checkConnection(); checking = false }
                    } label: {
                        HStack {
                            Text("Check connection")
                            if checking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(checking || model.apiBaseURL.isEmpty)

                    if let text = model.healthText {
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(model.healthIsError ? .red : .green)
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text("Calls GET /health (no auth). Every other request sends X-Dev-User.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
