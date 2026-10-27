import SwiftUI

/// First-run "how it works" demo — a short paged intro shown once (before Home) after a new user finishes
/// profile setup. `model.markIntroSeen()` persists that it's been shown, so it never reappears.
struct HowItWorksFlow: View {
    @EnvironmentObject var model: AppModel
    @State private var page = 0

    private struct Slide: Identifiable { let id = UUID(); let icon: String; let tint: Color; let title: String; let body: String }
    private let slides: [Slide] = [
        Slide(icon: "video.fill", tint: LS.action, title: "Record your shot",
              body: "Set your phone down the lane and record. LaneSight reads the whole shot from the video — no sensors, no setup."),
        Slide(icon: "chart.bar.xaxis", tint: LS.dataPurple, title: "See every number",
              body: "Ball speed, rev rate, entry board, breakpoint and more — measured from your clip, with an honest note whenever the camera can’t see something."),
        Slide(icon: "scope", tint: LS.action, title: "Know your next move",
              body: "After each shot you get one clear adjustment, plus a LaneSight Score that grows as you dial your game in."),
        Slide(icon: "figure.bowling", tint: LS.success, title: "Shot and Form",
              body: "Analyze ball motion from down the lane, or switch to Form to break down your approach, timing and release from the side."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .font(.lsSubheadline).foregroundStyle(LS.textSecondary)
            }
            .padding(.horizontal, 20).padding(.top, 8)

            TabView(selection: $page) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { i, s in
                    slideView(s).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(slides.indices, id: \.self) { i in
                    Capsule().fill(i == page ? LS.action : LS.borderStrong)
                        .frame(width: i == page ? 22 : 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: page)
                }
            }
            .padding(.bottom, 14)

            Button(page == slides.count - 1 ? "Get started" : "Next") {
                if page == slides.count - 1 { finish() } else { withAnimation { page += 1 } }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24).padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LSBackground(auth: true))
        .preferredColorScheme(.dark)
    }

    private func slideView(_ s: Slide) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(s.tint.opacity(0.14)).frame(width: 128, height: 128)
                Image(systemName: s.icon).font(.system(size: 52)).foregroundStyle(s.tint)
            }
            Text(s.title).font(.system(size: 26, weight: .bold)).foregroundStyle(LS.textPrimary)
                .multilineTextAlignment(.center)
            Text(s.body).font(.system(size: 15)).foregroundStyle(LS.textSecondary)
                .multilineTextAlignment(.center).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
            Spacer(); Spacer()
        }
        .padding(.horizontal, 8)
    }

    private func finish() { withAnimation { model.markIntroSeen() } }
}
