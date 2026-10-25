import SwiftUI

/// The Form card: the provisional FORM_P1 swing/approach metrics from a clip captured in FORM mode.
/// Shown instead of the ball Shot card for form results. There is deliberately NO entry board /
/// breakpoint / score / "Apply this move" here — those are ball-only. Every number is live from
/// GET /shots/{id}; a metric that couldn't be measured is shown as "—", never a fabricated value.
struct FormCardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let result: ShotResult

    /// Swing-phase keys get their own grouped section; everything else goes under approach & timing.
    private static let swingKeys: Set<String> = [
        "pushaway_time", "backswing_time", "downswing_time", "swing_time",
    ]

    private var topUnavailable: Bool { (result.formStatus ?? "").lowercased() == "unavailable" }
    private var swingMetrics: [(String, Metric)] { result.metrics.filter { Self.swingKeys.contains($0.0) } }
    private var otherMetrics: [(String, Metric)] { result.metrics.filter { !Self.swingKeys.contains($0.0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    provisionalBanner
                    viewCard
                    if topUnavailable {
                        unavailableCard
                    } else {
                        metricsSection
                    }
                }
                .padding(16)
            }
            .background(LSBackground())
            .navigationTitle("Form")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss(); model.resetPipeline() }
                }
            }
        }
    }

    // MARK: provisional banner

    /// These metrics are early (form_version 0.0.0, best-effort). Say so plainly so nothing here reads
    /// as precise.
    private var provisionalBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flask.fill").foregroundStyle(LS.bestEffort)
            VStack(alignment: .leading, spacing: 2) {
                Text("Provisional form metrics").font(.lsSubheadline.weight(.semibold)).foregroundStyle(LS.textPrimary)
                Text("Early form analysis (\(result.formVersion ?? "form-0.0.0")). Treat these as directional, not exact.")
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
        }
        .lsCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Provisional form metrics. Early form analysis, \(result.formVersion ?? "form 0.0.0"). Treat these as directional, not exact.")
    }

    // MARK: detected camera view

    private var viewCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "video.fill").foregroundStyle(LS.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("CAMERA VIEW").lsEyebrow()
                Text(viewLabel).font(.lsSubheadline.weight(.semibold)).foregroundStyle(LS.textPrimary)
            }
            Spacer()
        }
        .lsCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera view, \(viewLabel)")
    }

    private var viewLabel: String {
        switch (result.formView ?? "unknown").lowercased() {
        case "down_lane": return "Down lane"
        case "bowler_facing": return "Facing the bowler"
        case "rear": return "Rear"
        default: return "Unknown"
        }
    }

    // MARK: top-level unavailable

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(LS.bestEffort)
                Text("Form analysis unavailable").font(.lsHeadline).foregroundStyle(LS.textPrimary)
            }
            Text(unavailableReason).font(.lsCallout).foregroundStyle(LS.textSecondary)
        }
        .lsCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Form analysis unavailable. \(unavailableReason)")
    }

    /// Surface a concrete reason if any metric carries one; otherwise an honest generic explanation.
    private var unavailableReason: String {
        if let note = result.metrics.compactMap({ $0.1.note }).first(where: { !$0.isEmpty }) {
            return note
        }
        return "We couldn't measure your form from this clip. Make sure your full approach and swing are in frame, then record again."
    }

    // MARK: metrics

    @ViewBuilder private var metricsSection: some View {
        if result.metrics.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No form metrics returned for this clip.").font(.lsCallout).foregroundStyle(LS.textSecondary)
            }
            .lsCard()
        } else {
            if !swingMetrics.isEmpty { group("SWING", swingMetrics) }
            if !otherMetrics.isEmpty { group("APPROACH & TIMING", otherMetrics) }
        }
    }

    private func group(_ title: String, _ metrics: [(String, Metric)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).lsEyebrow()
            ForEach(metrics, id: \.0) { key, metric in
                FormMetricRow(key: key, metric: metric)
                if key != metrics.last?.0 { Divider().overlay(LS.cardStroke) }
            }
        }
        .lsCard()
    }
}

/// One FORM_P1 metric row with honest status treatment:
/// - unavailable → "—" and the note reason (or "Not measured"), never a fake number
/// - best_effort / low_confidence → the value plus a small "ESTIMATE" tag (no false precision)
/// - ok → plain value + unit
private struct FormMetricRow: View {
    let key: String
    let metric: Metric

    private var state: FormMetricState { FormMetricState(metric.status) }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(FormMetricDisplay.label(key)).font(.lsSubheadline).foregroundStyle(LS.textPrimary)
                subtitle
            }
            Spacer()
            trailingValue
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceLabel)
    }

    @ViewBuilder private var subtitle: some View {
        if let note = metric.note, !note.isEmpty {
            Text(note).font(.lsCaption2).foregroundStyle(LS.textSecondary)
        } else if state == .unavailable {
            Text("Not measured").font(.lsCaption2).foregroundStyle(LS.textSecondary)
        }
    }

    @ViewBuilder private var trailingValue: some View {
        if state == .unavailable {
            Text("—").font(.lsBody.monospacedDigit().weight(.semibold)).foregroundStyle(LS.unavailable)
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(FormMetricDisplay.formattedValue(key: key, metric) ?? "—")
                        .font(.lsBody.monospacedDigit().weight(.semibold)).foregroundStyle(LS.textPrimary)
                    if let unit = FormMetricDisplay.unitText(key: key, metric) {
                        Text(unit).font(.lsCaption).foregroundStyle(LS.textSecondary)
                    }
                }
                if let tag = state.tag {
                    Text(tag).font(.lsRoboto(9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(LS.bestEffort.opacity(0.18), in: Capsule())
                        .foregroundStyle(LS.bestEffort)
                }
            }
        }
    }

    private var voiceLabel: String {
        let name = FormMetricDisplay.label(key)
        switch state {
        case .unavailable:
            let reason = (metric.note?.isEmpty == false) ? metric.note! : "not measured"
            return "\(name), not measured, \(reason)"
        case .estimate:
            let v = FormMetricDisplay.formattedValue(key: key, metric) ?? "no value"
            let unit = FormMetricDisplay.unitText(key: key, metric) ?? ""
            return "\(name), \(v) \(unit), estimate"
        case .ok:
            let v = FormMetricDisplay.formattedValue(key: key, metric) ?? "no value"
            let unit = FormMetricDisplay.unitText(key: key, metric) ?? ""
            return "\(name), \(v) \(unit)"
        }
    }
}
