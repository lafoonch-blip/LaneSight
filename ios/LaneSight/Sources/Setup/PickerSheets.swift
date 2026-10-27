import SwiftUI

/// Current-ball picker sheet (v3.7 Figma 411:3675): the arsenal as selectable rows + Use this ball.
struct BallPickerSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?

    private var balls: [ArsenalBall] { model.arsenal.filter { $0.retired != true } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current ball").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            Text("Used for this shot and the next until you change it.")
                .font(.system(size: 12)).foregroundStyle(LS.textSecondary)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(balls) { ball in
                        row(selected: selection == ball.id, title: ball.displayName, subtitle: ballSubtitle(ball)) {
                            withAnimation(.none) { selection = ball.id }
                        }
                    }
                    NavigationLink { AddBallView() } label: {
                        Text("Add a ball from the catalog")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(LS.textPrimary)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            Button("Use this ball") {
                if let id = selection { Task { try? await model.setCurrentBall(id: id); dismiss() } } else { dismiss() }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LSBackground())
        .onAppear { selection = model.currentBall?.id ?? balls.first?.id }
    }

    private func ballSubtitle(_ b: ArsenalBall) -> String {
        [b.surface, b.weight_lb.map { "\(Int($0.rounded())) lb" }].compactMap { $0 }.joined(separator: " · ")
    }

    private func row(selected: Bool, title: String, subtitle: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Circle().fill(LS.raised).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11)).foregroundStyle(LS.textSecondary) }
                }
                Spacer()
                if selected { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(LS.action) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? LS.action : LS.cardStrokeBright, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// Oil-pattern picker sheet (v3.7 Figma 411:3754): searchable pattern list + Use this pattern.
struct OilPatternSheet: View {
    @Environment(\.dismiss) private var dismiss
    let patterns: [OilPattern]
    @Binding var selectedName: String?
    @Binding var selectedId: String?
    @State private var query = ""
    @State private var pickName: String?
    @State private var pickId: String?

    private var filtered: [OilPattern] {
        guard !query.isEmpty else { return patterns }
        return patterns.filter { ($0.name ?? "").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Oil pattern").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            Text("Shapes lane-read advice only; it doesn't change measurements.")
                .font(.system(size: 12)).foregroundStyle(LS.textSecondary)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                TextField("Search patterns by name or length", text: $query)
                    .font(.system(size: 14)).foregroundStyle(.white)
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LS.border, lineWidth: 1))
            ScrollView {
                VStack(spacing: 10) {
                    row(selected: pickName == nil && pickId == nil && query.isEmpty ? false : (pickName == "__none__"),
                        title: "I don't know", subtitle: "No pattern used for advice") { pickName = "__none__"; pickId = nil }
                    ForEach(filtered, id: \.identity) { p in
                        row(selected: pickId == p.id || pickName == p.name,
                            title: p.name ?? "Unnamed", subtitle: patternSubtitle(p)) { pickName = p.name; pickId = p.id }
                    }
                }
            }
            Text("Patterns come from published pattern sheets and refresh automatically.")
                .font(.system(size: 11)).foregroundStyle(LS.textFaint)
            Button("Use this pattern") {
                if pickName == "__none__" { selectedName = nil; selectedId = nil }
                else { selectedName = pickName; selectedId = pickId }
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LSBackground())
        .onAppear { pickName = selectedName; pickId = selectedId }
    }

    private func patternSubtitle(_ p: OilPattern) -> String {
        [p.length.map { "\(Int($0.rounded())) ft" }, p.volume.map { "\(Fmt.number($0)) ml" }, p.source]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func row(selected: Bool, title: String, subtitle: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11)).foregroundStyle(LS.textSecondary) }
                }
                Spacer()
                if selected { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(LS.action) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? LS.action : LS.cardStrokeBright, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}
