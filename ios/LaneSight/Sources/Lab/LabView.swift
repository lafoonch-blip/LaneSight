import SwiftUI

struct LabView: View {
    @EnvironmentObject var model: AppModel
    @State private var sessions: Loadable<[SessionRow]> = .idle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NavigationLink { SetupView() } label: {
                        actionTile("Start Live Session", "Shot or Form · record each delivery",
                                   symbol: "record.circle", tint: LS.blue)
                    }

                    NavigationLink { UploadView() } label: {
                        actionTile("Upload Video", "Analyze a clip from Photos",
                                   symbol: "square.and.arrow.up", tint: LS.cyan)
                    }

                    // Disabled per design — must not open an empty view (App Review).
                    actionTile("Compare to a PBA Pro", "COMING SOON", symbol: "person.2.fill", tint: LS.textFaint)
                        .opacity(0.5)

                    sessionsList
                    Spacer(minLength: 8)
                }
                .padding(16)
            }
            .background(LSBackground())
            .navigationTitle("Performance Lab")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await loadSessions() }
            .refreshable { await loadSessions() }
        }
    }

    private func actionTile(_ title: String, _ subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(LS.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(LS.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(LS.textFaint)
        }
        .lsCard()
    }

    private var sessionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SESSIONS").lsEyebrow()
            LoadableView(state: sessions, retry: { Task { await loadSessions() } }) { rows in
                if rows.isEmpty {
                    Text("No sessions yet.").font(.callout).foregroundStyle(LS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).lsCard()
                } else {
                    VStack(spacing: 10) {
                        ForEach(rows.sorted(by: { ($0.started_at ?? 0) > ($1.started_at ?? 0) })) { s in
                            SessionRowCard(session: s)
                        }
                    }
                }
            }
        }
    }

    private func loadSessions() async {
        sessions = .loading
        do {
            sessions = .loaded(try await model.makeClient().listSessions())
        } catch { sessions = .failed(error.localizedDescription) }
    }
}
