import SwiftUI

/// DEC-123: one-screen Friends & Family consent, shown once on an F&F (TestFlight) build after sign-up and
/// before the app. Plain English: it's an early test build whose numbers may be wrong or missing; recordings
/// are analyzed and clips are kept on the server for 7 days (DEC-099/104); clips and feedback are used to
/// improve LaneSight. Accepting stores the consent version + timestamp on the account (migration 036).
struct FFConsentView: View {
    @EnvironmentObject var model: AppModel
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 6) {
                    Image("LaneSightLogo").resizable().scaledToFit().frame(maxWidth: 150)
                        .accessibilityLabel("LaneSight")
                    Text("FRIENDS & FAMILY TEST").font(.lsCaption2).tracking(2).foregroundStyle(LS.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(.top, 8)

                Text("Thanks for helping test LaneSight")
                    .font(.lsTitle.bold()).foregroundStyle(LS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Before you start, a few things to know:")
                    .font(.lsSubheadline).foregroundStyle(LS.textSecondary)

                VStack(alignment: .leading, spacing: 16) {
                    bullet("This is an early test build.",
                           "Some numbers may be wrong, and some may be missing. When we can't measure something, we'll say so rather than guess.")
                    bullet("Your shots are analyzed on our server.",
                           "When your phone sends a clip for analysis, we keep it on the server for 7 days to check and improve the analysis, then it's deleted.")
                    bullet("Your clips and feedback help us improve.",
                           "We use the clips you send and the feedback you leave to make LaneSight's measurements and coaching better.")
                }

                Text("You can delete your account and its data any time from Settings → Delete account.")
                    .font(.lsCaption).foregroundStyle(LS.textFaint)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { busy = true; await model.recordFFConsent(); busy = false }
                } label: {
                    LoadingLabel("I understand — let's go", busy: busy)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 40)
        }
        .background(LSBackground(auth: true))
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(true)
    }

    private func bullet(_ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(LS.positive).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.lsSubheadline.bold()).foregroundStyle(LS.textPrimary)
                Text(body).font(.lsCallout).foregroundStyle(LS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
