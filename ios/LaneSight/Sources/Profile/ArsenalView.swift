import SwiftUI

/// Add ball from the catalog (AddBall.dc.html). Searches GET /catalog/balls?q=. A catalog result or a
/// custom name routes to BallSetupView, which collects weight/layout/surface and POSTs to /me/arsenal.
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
                            .font(.lsCallout).foregroundStyle(LS.textSecondary)
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
        NavigationLink { BallSetupView(customName: trimmedQuery) } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill").font(.lsTitle2).foregroundStyle(LS.cyan)
                    .frame(width: 40, height: 40).background(LS.cyan.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add “\(trimmedQuery)” as a custom ball")
                        .font(.lsSubheadline.bold()).foregroundStyle(LS.textPrimary)
                    Text("Not in the catalog? Use your own name.")
                        .font(.lsCaption).foregroundStyle(LS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.lsFootnote).foregroundStyle(LS.textFaint)
            }
            .lsCard(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private func ballRow(_ ball: CatalogBall) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.circle").font(.lsTitle2).foregroundStyle(LS.blue)
                .frame(width: 40, height: 40).background(LS.blue.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(ball.name ?? "Ball").font(.lsSubheadline.bold()).foregroundStyle(LS.textPrimary)
                Text([ball.manufacturer, ball.core_type, ball.coverstock].compactMap { $0 }.joined(separator: " · "))
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.lsFootnote).foregroundStyle(LS.textFaint)
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

/// Ball setup (BallSetup.dc.html): factory specs for a catalog ball, plus the bowler's own
/// weight / layout / surface and "make current". "Add to arsenal" POSTs to /me/arsenal and re-syncs.
/// Works for a catalog ball (`ball`) or a custom free-text ball (`customName`).
struct BallSetupView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let ball: CatalogBall?
    let customName: String?

    @State private var weight = ""
    @State private var layoutSystem = ""
    @State private var layout = ""
    @State private var surface = ""
    @State private var makeCurrent = true
    @State private var saving = false
    @State private var saveError: String?

    init(ball: CatalogBall) { self.ball = ball; self.customName = nil }
    init(customName: String) { self.ball = nil; self.customName = customName }

    private var title: String { ball?.name ?? customName ?? "Ball" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow

                // Factory specs (read-only, from the catalog). Custom balls have no factory data.
                if let ball {
                    cardSection(title: "Factory specs", trailing: "From catalog") {
                        specRow("Coverstock", ball.coverstock)
                        specRow("Core", ball.core_type)
                        specRow("RG / Differential", ball.rgDiff)
                    }
                }

                // Drilling (optional): the bowler's own weight / finish / layout for this ball.
                cardSection(title: "Drilling (optional)", trailing: nil) {
                    weightRow
                    inlineEditRow("Finish", text: $surface, placeholder: ball?.factory_finish ?? "e.g. 1500 grit")
                    inlineEditRow("Layout", text: $layout, placeholder: "e.g. 4.5 x 45 x 35")
                }

                if let saveError {
                    Text(saveError).font(.lsCaption).foregroundStyle(LS.bestEffort)
                }

                Button {
                    Task { await addToArsenal() }
                } label: {
                    LoadingLabel("Add to arsenal", busy: saving)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(saving)
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Ball setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // Header: round ball thumbnail + name + "{mfr} · from catalog" (Figma 437:6000).
    private var headerRow: some View {
        HStack(spacing: 12) {
            ballThumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(LS.textPrimary)
                Text(ball?.manufacturer.map { "\($0) · from catalog" } ?? "Custom ball")
                    .font(.system(size: 13)).foregroundStyle(LS.textSecondary)
            }
            Spacer()
        }
    }

    @ViewBuilder private var ballThumbnail: some View {
        let url = ball?.image_url.flatMap { URL(string: $0) }
        ZStack {
            Circle().fill(LS.raised).frame(width: 54, height: 54)
            if let url {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "circle.circle").foregroundStyle(LS.blue)
                }
                .frame(width: 54, height: 54).clipShape(Circle())
            } else {
                Image(systemName: "circle.circle").font(.system(size: 26)).foregroundStyle(LS.blue)
            }
        }
        .overlay(Circle().strokeBorder(LS.borderStrong, lineWidth: 1))
    }

    private var weightRow: some View {
        HStack {
            Text("Weight").font(.system(size: 15)).foregroundStyle(LS.textPrimary)
            Spacer()
            Menu {
                ForEach(Array(stride(from: 10, through: 16, by: 1)), id: \.self) { w in
                    Button("\(w) lb") { weight = String(w) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(weight.isEmpty ? "Select" : "\(weight) lb")
                        .foregroundStyle(weight.isEmpty ? LS.textSecondary : LS.textPrimary)
                    Image(systemName: "chevron.down").font(.system(size: 11)).foregroundStyle(LS.textSecondary)
                }.font(.system(size: 15))
            }
        }
        .frame(minHeight: 30)
    }

    private func inlineEditRow(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(LS.textPrimary)
            Spacer()
            TextField(placeholder, text: text)
                .font(.system(size: 15)).multilineTextAlignment(.trailing)
                .foregroundStyle(LS.textPrimary).autocorrectionDisabled()
                .frame(maxWidth: 190)
        }
        .frame(minHeight: 30)
    }

    /// A v3.7 card section: title (+ optional trailing tag) above a raised card of rows separated by hairlines.
    private func cardSection<Content: View>(title: String, trailing: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
                if let trailing {
                    Text(trailing).font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                }
            }
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(LS.raised, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.borderStrong, lineWidth: 1))
        }
    }

    private func specRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(LS.textPrimary)
            Spacer()
            Text(value ?? "—").font(.system(size: 15)).foregroundStyle(value == nil ? LS.textFaint : LS.textSecondary)
        }
        .frame(minHeight: 34)
    }

    private func addToArsenal() async {
        saving = true
        saveError = nil
        func clean(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t
        }
        do {
            try await model.addBall(
                ballModelId: ball?.id,
                name: ball == nil ? customName : nil,
                weightLb: Double(weight.trimmingCharacters(in: .whitespaces)),
                layoutSystem: clean(layoutSystem),
                layout: clean(layout),
                surface: clean(surface),
                makeCurrent: makeCurrent)
            dismiss()
        } catch {
            saveError = "Couldn't add ball: \(error.localizedDescription)"
            saving = false
        }
    }
}
