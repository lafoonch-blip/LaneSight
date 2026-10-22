import SwiftUI

struct ResultView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let result: ShotResult

    @State private var rating = 0
    @State private var feedbackText = ""
    @State private var feedbackSent = false
    @State private var feedbackError: String?

    var body: some View {
        NavigationStack {
            List {
                scoreSection
                metricsSection
                feedbackSection
            }
            .navigationTitle("Shot Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss(); model.resetPipeline() }
                }
            }
        }
    }

    // MARK: score

    private var scoreSection: some View {
        Section("LaneSight Score") {
            let s = result.score
            if s.eligible == true, let value = s.score {
                HStack(alignment: .firstTextBaseline) {
                    Text(fmtInt(value)).font(.system(size: 44, weight: .bold, design: .rounded))
                    VStack(alignment: .leading) {
                        if let tier = s.tier { Text(tier.capitalized).font(.headline) }
                        if let fv = s.formula_version { Text(fv).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer()
                }
                partsGrid(s)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Building your LaneSight Score", systemImage: "hourglass")
                        .font(.headline)
                    Text("All four parts need enough measured shots before a score appears.")
                        .font(.caption).foregroundStyle(.secondary)
                    eligibilityList(s)
                    partsGrid(s)
                }
            }
        }
    }

    private func partsGrid(_ s: ScoreResponse) -> some View {
        let parts: [(String, Double?)] = [
            ("Performance", s.s_perf), ("Accuracy", s.a_acc),
            ("Consistency", s.c_cons), ("Power", s.p_power),
        ]
        return VStack(spacing: 6) {
            ForEach(parts, id: \.0) { name, val in
                HStack {
                    Text(name).font(.subheadline)
                    Spacer()
                    Text(val.map { fmtInt($0) } ?? "building")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(val == nil ? .secondary : .primary)
                }
            }
        }
    }

    private func eligibilityList(_ s: ScoreResponse) -> some View {
        Group {
            if let elig = s.eligibility, !elig.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(elig.sorted(by: { $0.key < $1.key }), id: \.key) { key, e in
                        HStack {
                            Image(systemName: e.met == true ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(e.met == true ? .green : .secondary)
                            Text(MetricDisplay.humanize(key)).font(.caption)
                            Spacer()
                            Text("\(e.have ?? 0)/\(e.need ?? 0)").font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: metrics

    private var metricsSection: some View {
        Section("Measured metrics") {
            if result.metrics.isEmpty {
                Text("No metrics returned for this shot.").foregroundStyle(.secondary)
            } else {
                ForEach(result.metrics, id: \.0) { name, metric in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MetricDisplay.humanize(name)).font(.subheadline)
                            if let note = metric.note, !note.isEmpty {
                                Text(note).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(valueString(metric)).font(.body.monospacedDigit().bold())
                            Text(statusLabel(metric)).font(.caption2)
                                .foregroundStyle(statusColor(metric))
                        }
                    }
                }
            }
        }
    }

    // MARK: feedback

    private var feedbackSection: some View {
        Section("Feedback") {
            HStack {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                        .onTapGesture { rating = i }
                }
            }
            TextField("Optional note", text: $feedbackText, axis: .vertical)
                .lineLimit(1...3)
            Button {
                Task { await sendFeedback() }
            } label: {
                if feedbackSent { Label("Sent", systemImage: "checkmark") } else { Text("Submit feedback") }
            }
            .disabled(rating == 0 || feedbackSent)
            if let err = feedbackError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func sendFeedback() async {
        feedbackError = nil
        do {
            try await model.submitFeedback(rating: rating, text: feedbackText)
            feedbackSent = true
        } catch {
            feedbackError = error.localizedDescription
        }
    }

    // MARK: formatting

    private func fmtInt(_ d: Double) -> String { String(Int(d.rounded())) }

    private func valueString(_ m: Metric) -> String {
        guard let v = m.value else { return "—" }
        let num: String
        if abs(v.rounded() - v) < 0.001 { num = String(Int(v.rounded())) }
        else { num = String(format: "%.2f", v) }
        if let unit = m.unit, !unit.isEmpty { return "\(num) \(unit)" }
        return num
    }

    private func statusLabel(_ m: Metric) -> String {
        var parts: [String] = []
        if let s = m.status { parts.append(s) }
        if let c = m.confidence { parts.append("conf \(String(format: "%.0f%%", c * 100))") }
        return parts.joined(separator: " · ")
    }

    private func statusColor(_ m: Metric) -> Color {
        switch m.status {
        case "ok": return .green
        case "best_effort": return .orange
        case nil: return .secondary
        default: return .secondary
        }
    }
}
