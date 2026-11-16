import SwiftUI

/// OD-03 (DEC-102): a thin, non-blocking offline status bar shown at the top of the app when there is no
/// connection. It never blocks navigation or capture — offline shots are saved locally and analyzed on
/// reconnect. Dismisses itself automatically when connectivity returns.
struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline — shots are saved and will analyze when you’re back online")
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.92))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline. Shots are saved and will analyze when you are back online.")
    }
}
