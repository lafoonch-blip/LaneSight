import SwiftUI

/// Branded launch splash shown over the app from cold start until Home finishes its first data load
/// (`model.homeLoaded`). Keeps the Welcome logo + background on screen so the jump into a populated Home
/// is seamless instead of flashing empty loading cards.
struct LaunchSplash: View {
    var body: some View {
        ZStack {
            LSBackground(auth: true).ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer()
                Image("LaneSightLogo")
                    .resizable().scaledToFit().frame(maxWidth: 240)
                    .accessibilityLabel("LaneSight")
                Text("SEE MORE. BOWL SMARTER.")
                    .font(.lsSubheadline).tracking(3).foregroundStyle(LS.textSecondary)
                Spacer()
                ProgressView().tint(LS.action)
                Spacer().frame(height: 72)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading LaneSight")
    }
}
