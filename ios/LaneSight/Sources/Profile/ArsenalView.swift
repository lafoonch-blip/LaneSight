import SwiftUI

/// Add ball from the catalog (AddBall.dc.html). Searches GET /catalog/balls?q=.
struct AddBallView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: Loadable<[CatalogBall]> = .idle
    @State private var searchTask: Task<Void, Never>?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(LS.textSecondary)
                    TextField("Search the ball catalog", text: $query)
                        .foregroundStyle(LS.textPrimary)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, _ in scheduleSearch() }
                }
                .padding(12)
                .background(LS.card, in: RoundedRectangle(cornerRadius: 12))

                LoadableView(state: results, retry: { Task { await search() } }) { balls in
                    if balls.isEmpty {
                        Text(trimmedQuery.isEmpty
                             ? "Type to search the ball catalog. Photos and specs come from the manufacturer's published data."
                             : "No catalog balls matched “\(trimmedQuery)”.")
                            .font(.callout).foregroundStyle(LS.textSecondary)
                    } else {
                        Text("RESULTS · \(balls.count)").lsEyebrow()
                        ForEach(balls) { ball in
                            NavigationLink { BallSetupView(ball: ball) } label: { ballRow(ball) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                // Custom ball: let the bowler add a free-text name when it isn't in the catalog
                // (e.g. older balls), so they're never blocked from logging shots.
                if !trimmedQuery.isEmpty {
                    customBallButton
                }
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Add ball")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { if case .idle = results { await search() } }
    }

    private var customBallButton: some View {
        Button {
            model.currentBallName = trimmedQuery
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(LS.cyan)
                    .frame(width: 40, height: 40).background(LS.cyan.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add “\(trimmedQuery)” as a custom ball")
                        .font(.subheadline.bold()).foregroundStyle(LS.textPrimary)
                    Text("Not in the catalog? Use your own name.")
                        .font(.caption).foregroundStyle(LS.textSecondary)
                }
                Spacer()
            }
            .lsCard(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private func ballRow(_ ball: CatalogBall) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.circle").font(.title2).foregroundStyle(LS.blue)
                .frame(width: 40, height: 40).background(LS.blue.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(ball.name ?? "Ball").font(.subheadline.bold()).foregroundStyle(LS.textPrimary)
                Text([ball.manufacturer, ball.core_type, ball.coverstock].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(LS.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(LS.textFaint)
        }
        .lsCard(padding: 12)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await search()
        }
    }

    private func search() async {
        results = .loading
        do {
            results = .loaded(try await model.makeClient().catalogBalls(query: query))
        } catch { results = .failed(error.localizedDescription) }
    }
}

/// Ball setup (BallSetup.dc.html): factory specs from the catalog + "Add to arsenal".
/// Saving a personal arsenal isn't backed yet, so adding records the selection locally (dev).
struct BallSetupView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let ball: CatalogBall

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ball.name ?? "Ball").font(.title3.bold()).foregroundStyle(LS.textPrimary)
                    if let mfr = ball.manufacturer {
                        Text("\(mfr) · from catalog").font(.caption).foregroundStyle(LS.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("FACTORY SPECS").lsEyebrow()
                    specRow("Coverstock", ball.coverstock)
                    specRow("Core", ball.core_type)
                    specRow("Hook", ball.ls_hook?.value)
                    specRow("Length", ball.ls_length?.value)
                    specRow("Backend", ball.ls_backend?.value)
                }
                .lsCard()

                Text("Expected reaction and your drilling/surface setup update as you log shots with this ball. Layout-aware reaction is coming soon.")
                    .font(.caption).foregroundStyle(LS.textFaint)

                Button("Add to arsenal") {
                    model.currentBallName = ball.name
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Ball setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func specRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(LS.textSecondary)
            Spacer()
            Text(value ?? "—").font(.subheadline).foregroundStyle(value == nil ? LS.textFaint : LS.textPrimary)
        }
    }
}
