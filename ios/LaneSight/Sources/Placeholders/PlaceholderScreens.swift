import SwiftUI

/// Delete account (DeleteAccount.dc.html). Real DELETE /me behind a type-DELETE confirm step.
/// On success the account + its videos are removed on the Mac and the app signs out.
struct DeleteAccountView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmText = ""
    @State private var deleting = false
    @State private var errorText: String?

    private var canDelete: Bool { confirmText.trimmingCharacters(in: .whitespaces).uppercased() == "DELETE" && !deleting }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Delete your account?").font(.title2.bold()).foregroundStyle(LS.textPrimary)
                Text("This permanently deletes your account and everything in it. It can't be undone.")
                    .font(.callout).foregroundStyle(LS.textSecondary)
                VStack(alignment: .leading, spacing: 6) {
                    bullet("Profile, arsenal and sensors")
                    bullet("All sessions, shots, videos and stats")
                    bullet("LaneSight Score history, tier and achievements")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LS.card, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    Text("TYPE DELETE TO CONFIRM").lsEyebrow()
                    TextField("DELETE", text: $confirmText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(12).background(LS.card, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(LS.textPrimary)
                }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(LS.bestEffort)
                }

                Button {
                    Task { await deleteAccount() }
                } label: {
                    HStack {
                        Text("Delete account")
                        if deleting { ProgressView().tint(.white) }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .tint(.red)
                .disabled(!canDelete)
                .opacity(canDelete ? 1 : 0.5)

                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(LS.textSecondary)
            Text(text).font(.callout).foregroundStyle(LS.textSecondary)
        }
    }

    private func deleteAccount() async {
        deleting = true
        errorText = nil
        do {
            try await model.deleteAccount()      // flips onboarded=false → app returns to onboarding
        } catch {
            errorText = "Couldn't delete the account: \(error.localizedDescription)"
            deleting = false
        }
    }
}
