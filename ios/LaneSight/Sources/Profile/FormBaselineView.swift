import SwiftUI

/// Profile › Form baseline (DEC-099). The swing-timing baseline the Form card compares every delivery to
/// (FORM_BENCHMARKS §0.4). Three choices:
///  • Use my average — the median of the bowler's measured form deliveries (server, once established).
///  • Enter my timing — the four phase splits in seconds (total = their sum unless entered).
///  • Not set — only "this delivery" shows on the Form card, with a prompt.
/// The quickest way to set one is "Use this delivery as my baseline" on a Form result you like.
/// Saved with PUT /me/profile `form_baseline`; the server validates (0 < t ≤ 3 s) and the reason shows inline.
struct FormBaselineView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let initial: FormBaseline?
    var onSaved: (FormBaseline?) -> Void

    /// The baseline values a bowler sets — the engine's measured phase splits (pose.py events E2…E7).
    struct Phase: Identifiable {
        let key: String, label: String, detail: String
        var id: String { key }
    }
    static let phases: [Phase] = [
        Phase(key: "pushaway_time", label: "Pushaway", detail: "Ball starts moving → ball reaches your hip"),
        Phase(key: "backswing_time", label: "Backswing", detail: "Hip → top of your backswing"),
        Phase(key: "downswing_time", label: "Downswing", detail: "Top of the backswing → bottom of the swing"),
        Phase(key: "release_time", label: "Release", detail: "Bottom of the swing → the ball leaves your hand (usually under 0.10 s)"),
    ]

    enum Mode: String { case none, average, entered }
    @State private var mode: Mode = .none
    @State private var values: [String: String] = [:]
    @State private var saving = false
    @State private var error: (field: String, message: String)?

    init(initial: FormBaseline?, onSaved: @escaping (FormBaseline?) -> Void) {
        self.initial = initial
        self.onSaved = onSaved
        let m: Mode = initial?.mode == "average" ? .average : (initial?.mode == "entered" ? .entered : .none)
        _mode = State(initialValue: m)
        var v: [String: String] = [:]
        if let b = initial {
            let raw: [String: Double?] = ["pushaway_time": b.pushaway_time, "backswing_time": b.backswing_time,
                                          "downswing_time": b.downswing_time, "release_time": b.release_time]
            for (k, d) in raw { if let d { v[k] = String(format: "%.2f", d) } }
        }
        _values = State(initialValue: v)
    }

    private func seconds(_ key: String) -> Double? {
        Double((values[key] ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
    private var total: Double? {
        let parts = Self.phases.compactMap { seconds($0.key) }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }
    private var canSave: Bool { mode != .entered || total != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Form results compare each delivery's swing timing to this baseline, phase by phase, so you can see when your timing changes.")
                    .font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                option(.average, "Use my average",
                       "LaneSight uses the median of your measured form deliveries once it has enough of them.")
                option(.entered, "Enter my timing", "Type the time for each phase of your swing, in seconds.")
                if mode == .entered { entrySection }
                option(.none, "No baseline", "Form results show only the delivery you just threw.")

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb").foregroundStyle(LS.dataYellow)
                    Text("Quickest way: open a Form result you like and tap “Use this delivery as my baseline.”")
                        .font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error, error.field == "form_baseline" {
                    Text(error.message).font(.system(size: 12)).foregroundStyle(LS.bestEffort)
                }
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Form baseline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .lsHidesTabBar()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(saving || !canSave).foregroundStyle(LS.action)
            }
        }
    }

    private func option(_ m: Mode, _ title: String, _ detail: String) -> some View {
        Button { mode = m; error = nil } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mode == m ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20)).foregroundStyle(mode == m ? LS.action : LS.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(LS.textPrimary)
                    Text(detail).font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(mode == m ? LS.heroStroke : LS.cardStrokeBright, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var entrySection: some View {
        VStack(spacing: 0) {
            ForEach(Self.phases) { ph in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ph.label).font(.system(size: 15)).foregroundStyle(LS.textPrimary)
                            Text(ph.detail).font(.system(size: 11)).foregroundStyle(LS.textFaint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        TextField("—", text: Binding(get: { values[ph.key] ?? "" }, set: { values[ph.key] = $0 }))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .font(.system(size: 15)).foregroundStyle(LS.textPrimary)
                            .frame(width: 64)
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .background(LS.raised, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LS.borderStrong, lineWidth: 1))
                        Text("s").font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                    }
                    if let error, error.field == ph.key {
                        Text(error.message).font(.system(size: 11)).foregroundStyle(LS.bestEffort)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                Divider().overlay(LS.border).padding(.leading, 16)
            }
            HStack {
                Text("Total swing").font(.system(size: 15, weight: .semibold)).foregroundStyle(LS.textPrimary)
                Spacer()
                Text(total.map { String(format: "%.2f s", $0) } ?? "—")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(LS.textPrimary)
            }
            .padding(.horizontal, 16).frame(height: 50)
        }
        .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private func save() async {
        saving = true; error = nil
        let payload: Any
        var saved: FormBaseline?
        switch mode {
        case .none:
            payload = NSNull()
        case .average:
            payload = ["mode": "average"]
            saved = FormBaseline(mode: "average")
        case .entered:
            var fb: [String: Any] = ["mode": "entered"]
            var b = FormBaseline(mode: "entered")
            for ph in Self.phases {
                guard let v = seconds(ph.key) else { continue }
                fb[ph.key] = v
                switch ph.key {
                case "pushaway_time": b.pushaway_time = v
                case "backswing_time": b.backswing_time = v
                case "downswing_time": b.downswing_time = v
                default: b.release_time = v
                }
            }
            payload = fb
            saved = b
        }
        do {
            let p = try await model.makeClient().putProfile(["form_baseline": payload])
            onSaved(p.form_baseline ?? saved)
            dismiss()
        } catch {
            self.error = APIClient.fieldError(from: error) ?? ("form_baseline", "Couldn't save — try again.")
        }
        saving = false
    }
}
