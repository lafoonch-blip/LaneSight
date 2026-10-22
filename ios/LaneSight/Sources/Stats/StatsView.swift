import SwiftUI

struct StatsView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0
    @State private var score: Loadable<ScoreResponse> = .idle
    @State private var history: [ScoreResponse] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("View", selection: $tab) {
                        Text("Score").tag(0)
                        Text("Throw").tag(1)
                        Text("Form").tag(2)
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case 0: scoreTab
                    case 1: throwTab
                    default: formTab
                    }
                    Spacer(minLength: 8)
                }
                .padding(16)
            }
            .background(LSBackground())
            .navigationTitle("Stats")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var scoreTab: some View {
        LoadableView(state: score, retry: { Task { await load() } }) { s in
            VStack(alignment: .leading, spacing: 14) {
                ScoreCard(score: s, history: history)
                historyCard
            }
        }
    }

    private var historyCard: some View {
        let scored = history.compactMap { $0.eligible == true ? $0.score : nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text("SCORE HISTORY").lsEyebrow()
            if scored.isEmpty {
                Text("No eligible score snapshots yet. Your history fills in as you log shots.")
                    .font(.caption).foregroundStyle(LS.textSecondary)
            } else {
                HStack {
                    KPITile(label: "Snapshots", value: "\(history.count)")
                    KPITile(label: "Best", value: Fmt.intStr(scored.max()))
                    KPITile(label: "Latest", value: Fmt.intStr(scored.last))
                }
            }
        }
        .lsCard()
    }

    private var throwTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THROW")
                .lsEyebrow()
            Text("Per-shot throw stats (speed, rev rate, entry angle, breakpoint) with coverage and top failure reasons come from the stats endpoint, which isn't in this slice yet.")
                .font(.callout).foregroundStyle(LS.textSecondary)
            Label("Needs the /me/stats endpoint", systemImage: "hourglass").font(.caption).foregroundStyle(LS.textFaint)
        }
        .lsCard()
    }

    private var formTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FORM").lsEyebrow()
            Text("Form trends (swing timing, approach, finish hold, drift) with per-metric coverage come from the stats endpoint, which isn't in this slice yet. Form metrics for a single clip appear on that shot's card.")
                .font(.callout).foregroundStyle(LS.textSecondary)
            Label("Needs the /me/stats endpoint", systemImage: "hourglass").font(.caption).foregroundStyle(LS.textFaint)
        }
        .lsCard()
    }

    private func load() async {
        score = .loading
        do {
            let client = try model.makeClient()
            async let s = client.score()
            async let h = client.scoreHistory()
            let (sv, hv) = try await (s, h)
            history = hv
            score = .loaded(sv)
        } catch { score = .failed(error.localizedDescription) }
    }
}
