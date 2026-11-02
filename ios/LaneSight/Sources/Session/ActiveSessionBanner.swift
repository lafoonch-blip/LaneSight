import SwiftUI

/// DEC-119 "Session in progress · Return" banner, shown on Home and Lab while a session is active. Tapping it
/// opens the Active Session (with the tab bar visible — amends DEC-099). The caller supplies the navigation.
struct ActiveSessionBanner: View {
    let startedAt: Double
    let shotCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LS.measured.opacity(0.18)).frame(width: 34, height: 34)
                    Image(systemName: "figure.bowling").font(.system(size: 15)).foregroundStyle(LS.measured)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session in progress").font(.lsSubheadline.bold()).foregroundStyle(LS.textPrimary)
                    Text(subtitle).font(.lsCaption).foregroundStyle(LS.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("Return").font(.system(size: 13, weight: .semibold)).foregroundStyle(LS.link)
                Image(systemName: "chevron.right").font(.lsFootnote).foregroundStyle(LS.textFaint)
            }
            .lsCard(padding: 14)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.measured.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        let time = Date(timeIntervalSince1970: startedAt).formatted(date: .omitted, time: .shortened)
        let n = shotCount
        return "Started \(time) · \(n) shot\(n == 1 ? "" : "s") · tap to return"
    }
}

/// The live Active Session screen for the current active session (shot or form). Reads the active session from
/// AppModel so a banner tap / resume-prompt "Continue" lands on the right hub.
struct ActiveSessionScreen: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.activeSession?.mode == "form" {
            FormSessionView(sessionId: model.activeSessionId ?? "")
        } else {
            SessionView()
        }
    }
}
