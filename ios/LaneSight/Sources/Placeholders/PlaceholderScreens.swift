import SwiftUI

/// Delete account (DeleteAccount.dc.html). DELETE /me isn't implemented in this slice, so the
/// destructive action is disabled with an honest note rather than faking success.
struct DeleteAccountView: View {
    @State private var confirmText = ""

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
                VStack(alignment: .leading, spacing: 6) {
                    Text("TYPE DELETE TO CONFIRM").lsEyebrow()
                    TextField("DELETE", text: $confirmText)
                        .textInputAutocapitalization(.characters)
                        .padding(10).background(LS.card, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(LS.textPrimary)
                }
                Label("Account deletion (DELETE /me) isn't available in this dev build yet.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(LS.bestEffort)
                Button("Delete account") { }
                    .buttonStyle(PrimaryButtonStyle())
                    .tint(.red)
                    .disabled(true)   // not backed yet
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
}

/// Achievements (Achievements.dc.html). GET /me/achievements isn't in this slice — honest placeholder.
struct AchievementsView: View {
    var body: some View {
        ComingSoonView("Achievements",
                       message: "Your badges, showcase and progress appear here once the achievements endpoint is live. Nothing is shown until it returns real data.",
                       symbol: "rosette")
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// Upload a video (Upload.dc.html). POST /uploads isn't in this slice — honest placeholder.
struct UploadView: View {
    var body: some View {
        ComingSoonView("Upload a clip",
                       message: "Analyzing a clip from Photos needs the uploads endpoint, which isn't in this dev build yet. Use Start Live Session to record and analyze in real time.",
                       symbol: "square.and.arrow.up")
        .navigationTitle("Upload video")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
