import SwiftUI

/// In-session ball switcher (DEC-097). One tap on a ball makes it the current ball and closes the sheet — no
/// separate "Use this ball" step. Failures are shown, never swallowed. Applies to the NEXT shot only.
struct QuickBallSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var saving: String?
    @State private var error: String?
    @State private var syncing = false

    private var balls: [ArsenalBall] { model.arsenal.filter { $0.retired != true } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Switch ball").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            Text("Tap a ball to use it from your next shot on.")
                .font(.system(size: 14)).foregroundStyle(LS.textSecondary)
            if let error {
                Text(error).font(.system(size: 13)).foregroundStyle(LS.bestEffort)
            }
            ScrollView {
                VStack(spacing: 10) {
                    if balls.isEmpty && syncing {
                        ProgressView().tint(LS.action).frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                    ForEach(balls) { ball in
                        pickRow(selected: ball.is_current == true, busy: saving == ball.id,
                                title: ball.displayName, subtitle: subtitle(ball)) { pick(ball) }
                    }
                    NavigationLink { AddBallView() } label: {
                        Label("Add a ball from the catalog", systemImage: "plus")
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(LS.link)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LSBackground())
        .task {
            syncing = true
            await model.syncArsenal()
            syncing = false
        }
    }

    private func pick(_ ball: ArsenalBall) {
        guard saving == nil else { return }
        if ball.is_current == true { dismiss(); return }
        saving = ball.id
        error = nil
        Task {
            do {
                try await model.setCurrentBall(id: ball.id)
                saving = nil
                dismiss()
            } catch {
                saving = nil
                self.error = "Couldn't switch ball: \(error.localizedDescription)"
            }
        }
    }

    private func subtitle(_ b: ArsenalBall) -> String {
        [b.is_default == true ? "Default" : nil, b.surface, b.weight_lb.map { "\(Int($0.rounded())) lb" }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// In-session oil pattern switcher (DEC-097). Searchable; one tap applies and closes. Loads the pattern list
/// itself if the screen hadn't got it yet, and shows a retry instead of an empty list when that fails.
struct QuickOilSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var patterns: [OilPattern]
    @Binding var selectedName: String?
    @Binding var selectedId: String?
    @State private var query = ""
    @State private var loading = false
    @State private var error: String?

    private var filtered: [OilPattern] {
        guard !query.isEmpty else { return patterns }
        return patterns.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(query)
                || ($0.length.map { "\(Int($0.rounded()))" } ?? "").contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Oil pattern").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            Text("Tap a pattern to use it. It shapes lane-read advice; it doesn't change measurements.")
                .font(.system(size: 14)).foregroundStyle(LS.textSecondary)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(LS.textSecondary)
                TextField("Search by name or length", text: $query)
                    .font(.system(size: 15)).foregroundStyle(.white)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12).frame(height: 46)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LS.border, lineWidth: 1))

            ScrollView {
                VStack(spacing: 10) {
                    if query.isEmpty {
                        pickRow(selected: selectedName == nil && selectedId == nil, busy: false,
                                title: "I don't know", subtitle: "No pattern used for advice") {
                            selectedName = nil; selectedId = nil; dismiss()
                        }
                    }
                    if loading {
                        ProgressView().tint(LS.action).frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else if let error {
                        VStack(spacing: 8) {
                            Text(error).font(.system(size: 13)).foregroundStyle(LS.bestEffort)
                            Button("Try again") { Task { await load() } }
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(LS.link)
                        }.frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    ForEach(filtered, id: \.identity) { p in
                        pickRow(selected: (p.id != nil && p.id == selectedId) || (selectedId == nil && p.name == selectedName),
                                busy: false, title: p.name ?? "Unnamed", subtitle: subtitle(p)) {
                            selectedName = p.name; selectedId = p.id; dismiss()
                        }
                    }
                }
            }
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LSBackground())
        .task { if patterns.isEmpty { await load() } }
    }

    private func load() async {
        loading = true; error = nil
        do { patterns = try await model.makeClient().oilPatterns() }
        catch { self.error = "Couldn't load patterns: \(error.localizedDescription)" }
        loading = false
    }

    private func subtitle(_ p: OilPattern) -> String {
        [p.length.map { "\(Int($0.rounded())) ft" }, p.volume.map { "\(Fmt.number($0)) ml" }, p.source]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// Shared big-target row for the quick pickers.
private func pickRow(selected: Bool, busy: Bool, title: String, subtitle: String,
                     _ tap: @escaping () -> Void) -> some View {
    Button(action: tap) {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 13)).foregroundStyle(LS.textSecondary) }
            }
            Spacer()
            if busy { ProgressView().tint(LS.action) }
            else if selected {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(LS.action)
            }
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(selected ? LS.action : LS.cardStrokeBright, lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}
