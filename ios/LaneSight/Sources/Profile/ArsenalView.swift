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
        NavigationLink { BallSetupView(customName: trimmedQuery) } label: {
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
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(LS.textFaint)
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
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.bold()).foregroundStyle(LS.textPrimary)
                    if let mfr = ball?.manufacturer {
                        Text("\(mfr) · from catalog").font(.caption).foregroundStyle(LS.textSecondary)
                    } else {
                        Text("Custom ball").font(.caption).foregroundStyle(LS.textSecondary)
                    }
                }

                if let ball {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FACTORY SPECS").lsEyebrow()
                        specRow("Coverstock", ball.coverstock)
                        specRow("Core", ball.core_type)
                        specRow("Hook", ball.ls_hook?.value)
                        specRow("Length", ball.ls_length?.value)
                        specRow("Backend", ball.ls_backend?.value)
                    }
                    .lsCard()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR SETUP (OPTIONAL)").lsEyebrow()
                    field("Weight (lb)", text: $weight, keyboard: .decimalPad, placeholder: "15")
                    field("Layout system", text: $layoutSystem, placeholder: "dual_angle")
                    field("Layout", text: $layout, placeholder: "4.5 x 45 x 35")
                    field("Surface", text: $surface, placeholder: "2000 abralon")
                    Toggle(isOn: $makeCurrent) {
                        Text("Make this my current ball").font(.subheadline).foregroundStyle(LS.textPrimary)
                    }.tint(LS.blue)
                }
                .lsCard()

                if let saveError {
                    Text(saveError).font(.caption).foregroundStyle(LS.bestEffort)
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

    private func field(_ label: String, text: Binding<String>,
                       keyboard: UIKeyboardType = .default, placeholder: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(LS.textSecondary)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(LS.textPrimary)
                .frame(maxWidth: 170)
        }
    }

    private func specRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(LS.textSecondary)
            Spacer()
            Text(value ?? "—").font(.subheadline).foregroundStyle(value == nil ? LS.textFaint : LS.textPrimary)
        }
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
