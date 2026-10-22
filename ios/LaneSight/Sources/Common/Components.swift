import SwiftUI

// MARK: - Loadable state for API-backed screens

enum Loadable<T> {
    case idle
    case loading
    case loaded(T)
    case failed(String)
}

/// Renders a Loadable: spinner while loading, the content when loaded, an honest error with Retry on failure.
struct LoadableView<T, Content: View>: View {
    let state: Loadable<T>
    let retry: () -> Void
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView().tint(LS.cyan)
                .frame(maxWidth: .infinity, minHeight: 120)
        case .loaded(let value):
            content(value)
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark").font(.title2).foregroundStyle(LS.bestEffort)
                Text("Couldn't reach the analysis host").font(.subheadline.bold()).foregroundStyle(LS.textPrimary)
                Text(message).font(.caption).foregroundStyle(LS.textSecondary)
                    .multilineTextAlignment(.center).lineLimit(4)
                Button("Retry", action: retry)
                    .buttonStyle(.bordered).tint(LS.blue)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(LS.blue.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(LS.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.white.opacity(configuration.isPressed ? 0.04 : 0.08),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LS.cardStroke))
    }
}

// MARK: - Status chip

struct StatusChip: View {
    let status: MetricStatus
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbol).font(.system(size: 7))
            Text(status.label.uppercased())
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(status.color)
        .accessibilityHidden(true)      // the parent row voices status in its label
    }
}

// MARK: - Metric formatting helpers

enum Fmt {
    static func value(_ m: Metric) -> String {
        guard let v = m.value else { return "—" }
        return number(v)
    }

    static func number(_ v: Double) -> String {
        if abs(v.rounded() - v) < 0.001 { return String(Int(v.rounded())) }
        return String(format: "%.1f", v)
    }

    /// Score sub-parts arrive as 0…10 components; present them on the familiar 0…100 scale.
    static func part(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(Int((v * 10).rounded()))
    }

    static func intStr(_ v: Double?) -> String { v.map { String(Int($0.rounded())) } ?? "—" }
}

// MARK: - A single metric row (value + status), used on Shot / Form / Session

struct MetricRow: View {
    let name: String
    let metric: Metric?

    private var status: MetricStatus { MetricStatus(metric?.status) }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline).foregroundStyle(LS.textPrimary)
                if let note = metric?.note, !note.isEmpty {
                    Text(note).font(.caption2).foregroundStyle(LS.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(metric.map(Fmt.value) ?? "—")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(LS.textPrimary)
                    if let unit = metric?.unit, !unit.isEmpty, metric?.value != nil {
                        Text(unit).font(.caption).foregroundStyle(LS.textSecondary)
                    }
                }
                StatusChip(status: status)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceLabel)
    }

    private var voiceLabel: String {
        let val = metric?.value != nil ? "\(Fmt.value(metric!)) \(metric?.unit ?? "")" : "no value"
        return "\(name), \(val), \(status.label)"
    }
}

// MARK: - KPI tile

struct KPITile: View {
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(LS.textPrimary)
                if let unit { Text(unit).font(.caption).foregroundStyle(LS.textSecondary) }
            }
            Text(label.uppercased()).font(.caption2.weight(.medium)).foregroundStyle(LS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value) \(unit ?? "")")
    }
}
