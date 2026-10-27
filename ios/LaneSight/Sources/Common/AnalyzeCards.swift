import SwiftUI

/// The two "Analyze" entry cards (Shot / Form) shown on Home's Performance Lab and at the top of Lab.
/// Each is a photo + title + description + a Start pill that opens Setup pre-set to that mode.
struct AnalyzeCards: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            card(mode: "shot", title: "Shot Analysis", desc: "Track ball motion, lane reaction and results.",
                 photo: "LabShotPhoto", action: "Start Shot Analysis", accent: LS.action)
            card(mode: "form", title: "Form Analysis", desc: "Analyze approach, timing, release and mechanics.",
                 photo: "LabFormPhoto", action: "Start Form Analysis", accent: LS.dataPurple)
        }
    }

    private func card(mode: String, title: String, desc: String, photo: String, action: String, accent: Color) -> some View {
        NavigationLink { SetupView(initialMode: mode) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(photo).resizable().scaledToFill().frame(height: 120).frame(maxWidth: .infinity).clipped()
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(LS.textPrimary)
                    Text(desc).font(.system(size: 11)).lineSpacing(2).foregroundStyle(LS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) { Text(action); Text("›") }
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(LS.onAction)
                        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity)
                        .background(accent, in: Capsule())
                }
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LS.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
