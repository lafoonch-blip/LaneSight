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

/// Ball setup (v3.7 Figma 437:6000 add-from-catalog / 437:6083 view-edit). Three modes:
///  • `ball`        — a catalog pick being added → "Add to arsenal" (POST /me/arsenal).
///  • `customName`  — a free-text ball being added → "Add to arsenal".
///  • `arsenalBall` — an existing arsenal ball being viewed/edited → "Save" (PATCH /me/arsenal/{id})
///    plus a Performance section (per-ball rollup from GET /me/stats/equipment).
struct BallSetupView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let ball: CatalogBall?
    let customName: String?
    let arsenalBall: ArsenalBall?

    @State private var weight = ""
    @State private var layoutSystem = ""
    @State private var layout = ""
    @State private var surface = ""
    @State private var makeCurrent = true
    @State private var saving = false
    @State private var saveError: String?
    @State private var perf: EquipGroup?
    @State private var perfLoaded = false

    init(ball: CatalogBall) { self.ball = ball; self.customName = nil; self.arsenalBall = nil }
    init(customName: String) { self.ball = nil; self.customName = customName; self.arsenalBall = nil }
    init(arsenalBall: ArsenalBall) {
        self.ball = nil; self.customName = nil; self.arsenalBall = arsenalBall
        _weight = State(initialValue: arsenalBall.weight_lb.map { String(Int($0.rounded())) } ?? "")
        _surface = State(initialValue: arsenalBall.surface ?? "")
        _layout = State(initialValue: arsenalBall.layout ?? "")
    }

    private var isEdit: Bool { arsenalBall != nil }
    private var title: String { arsenalBall?.displayName ?? ball?.name ?? customName ?? "Ball" }
    private var subtitle: String {
        if let m = arsenalBall?.manufacturer ?? ball?.manufacturer { return "\(m) · from catalog" }
        return "Custom ball"
    }
    private var imageURL: URL? { (arsenalBall?.image_url ?? ball?.image_url).flatMap { URL(string: $0) } }
    private var hasFactorySpecs: Bool { arsenalBall != nil || ball != nil }
    private var coverstock: String? { arsenalBall?.coverstock ?? ball?.coverstock }
    private var coreType: String? { arsenalBall?.core_type ?? ball?.core_type }
    private var rgDiff: String? { arsenalBall?.rgDiff ?? ball?.rgDiff }
    private var factoryFinish: String? { arsenalBall?.factory_finish ?? ball?.factory_finish }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow

                // Factory specs (read-only, from the catalog). Custom balls have no factory data.
                if hasFactorySpecs {
                    cardSection(title: "Factory specs", trailing: "From catalog") {
                        specRow("Coverstock", coverstock)
                        specRow("Core", coreType)
                        specRow("RG / Differential", rgDiff)
                    }
                }

                // Drilling (optional): the bowler's own weight / finish / layout for this ball.
                cardSection(title: "Drilling (optional)", trailing: nil) {
                    weightRow
                    inlineEditRow("Finish", text: $surface, placeholder: factoryFinish ?? "e.g. 1500 grit")
                    inlineEditRow("Layout", text: $layout, placeholder: "e.g. 4.5 x 45 x 35")
                }

                // Performance (edit mode only): per-ball rollup. No pinfall in LaneSight, so there is no
                // Strike %/Impact tile (the Figma mock shows them; see report) — only measured metrics.
                if isEdit { performanceSection }

                if let saveError {
                    Text(saveError).font(.lsCaption).foregroundStyle(LS.bestEffort)
                }

                if !isEdit {
                    Button {
                        Task { await addToArsenal() }
                    } label: {
                        LoadingLabel("Add to arsenal", busy: saving)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(saving)
                }
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Ball setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if isEdit {
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await saveEdits() } }
                        .disabled(saving).foregroundStyle(LS.action)
                }
            }
        }
        .task {
            guard isEdit, !perfLoaded else { return }
            perfLoaded = true
            if let stats = try? await model.makeClient().equipmentStats() {
                let match = Set([arsenalBall?.ball_configuration_id, arsenalBall?.id].compactMap { $0 })
                perf = stats.by_ball?.first { g in (g.id.map(match.contains) ?? false) }
            }
        }
    }

    // Performance · N shots (Figma 437:6083). Measured-metric tiles only; honest-empty until shots exist.
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance\(perf?.n.map { " · \($0) shots" } ?? "")")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
            Text("Video-measured. Metrics appear once this ball has measured shots tagged to it.")
                .font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let g = perf, (g.n ?? 0) > 0 {
                let tiles: [(String, String, String)] = [
                    (g.pocket_pct.map { "\(Int(($0 * (($0 <= 1) ? 100 : 1)).rounded()))%" } ?? "—", "POCKET %", ""),
                    (g.entry_angle.map { String(format: "%.1f°", $0) } ?? "—", "ENTRY ANGLE", ""),
                    (g.speed.map { String(format: "%.1f", $0) } ?? "—", "SPEED (MPH)", ""),
                    (g.rev.map { String(Int($0.rounded())) } ?? "—", "REV RATE", "Best effort"),
                ]
                let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in metricTile(t.0, t.1, t.2) }
                }
            } else {
                Text("No measured shots for this ball yet. Tag this ball when you record a shot and its stats roll up here.")
                    .font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(LS.raised, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.borderStrong, lineWidth: 1))
            }
        }
    }

    private func metricTile(_ value: String, _ label: String, _ tag: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(LS.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 10, weight: .medium)).tracking(0.3).foregroundStyle(LS.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            if !tag.isEmpty {
                Text(tag).font(.system(size: 10, weight: .semibold)).foregroundStyle(LS.dataYellow)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(10)
        .background(LS.raised, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.borderStrong, lineWidth: 1))
    }

    // Header: round ball thumbnail + name + "{mfr} · from catalog" (Figma 437:6000).
    private var headerRow: some View {
        HStack(spacing: 12) {
            ballThumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(LS.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13)).foregroundStyle(LS.textSecondary)
            }
            Spacer()
        }
    }

    @ViewBuilder private var ballThumbnail: some View {
        ZStack {
            Circle().fill(LS.raised).frame(width: 54, height: 54)
            if let url = imageURL {
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

    /// Edit mode: PATCH the existing arsenal ball's drilling (weight / surface / layout).
    private func saveEdits() async {
        guard let id = arsenalBall?.id else { return }
        saving = true; saveError = nil
        func clean(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t
        }
        var patch: [String: Any] = [:]
        if let w = Double(weight.trimmingCharacters(in: .whitespaces)) { patch["weight_lb"] = w }
        if let s = clean(surface) { patch["surface"] = s }
        if let l = clean(layout) { patch["layout"] = l }
        do {
            try await model.updateBall(id: id, patch: patch)
            dismiss()
        } catch {
            saveError = "Couldn't save changes: \(error.localizedDescription)"
            saving = false
        }
    }
}
