import SwiftUI

// MARK: - Loadable state for API-backed screens

enum Loadable<T> {
    case idle
    case loading
    case loaded(T)
    case failed(String)

    var value: T? { if case .loaded(let v) = self { return v }; return nil }
}

extension Loadable {
    /// Stale-while-revalidate: a refresh that fails keeps the data already on screen (only a first load
    /// with nothing to show surfaces the error). Keeps tab revisits seamless — no spinner/error flash.
    func keepingLoaded(over old: Loadable<T>) -> Loadable<T> {
        if case .failed = self, old.value != nil { return old }
        return self
    }
}

extension View {
    /// DEC-099: only the four primary tabs (Home · Stats · Lab · Coaching) show the bottom tab bar. Every
    /// screen pushed on top of a tab (Profile, Settings, Setup, sessions, details…) hides it, so a pushed
    /// screen can never be left "open" underneath another tab.
    func lsHidesTabBar() -> some View { toolbar(.hidden, for: .tabBar) }
}

/// One page-level loading state for a tab's FIRST load (DEC-099): the whole page appears at once instead of
/// section by section.
struct LSPageLoading: View {
    var body: some View {
        ProgressView().tint(LS.cyan).controlSize(.large)
            .frame(maxWidth: .infinity, minHeight: 320)
    }
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
            // Generic, honest copy for ANY section — never "analysis host" (this loads home/score/sessions
            // too, not just analysis). `message` is already the friendly APIError.userMessage (P0 2026-10-29).
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark").font(.lsTitle2).foregroundStyle(LS.bestEffort)
                Text("Couldn't load this").font(.lsSubheadline.bold()).foregroundStyle(LS.textPrimary)
                Text(message).font(.lsCaption).foregroundStyle(LS.textSecondary)
                    .multilineTextAlignment(.center).lineLimit(4)
                Button("Retry", action: retry)
                    .buttonStyle(.bordered).tint(LS.blue)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

// MARK: - 3.0 tab header (Main.dc.html)

/// Shared main-tab header: Settings (left, 44 pt) · center · Profile (right, 44 pt), on the canvas.
/// Home passes the stacked logo as its center; Stats and Lab pass their tab name. Matches the
/// Home header pattern in Main.dc.html (design README 3.0). Must live inside a NavigationStack.
struct LSTabHeader<Center: View>: View {
    @EnvironmentObject var model: AppModel
    @ViewBuilder var center: () -> Center

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink { SettingsView() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(LS.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(LS.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(LS.border, lineWidth: 1))
            }
            .accessibilityLabel("Settings")

            Spacer(minLength: 0)
            center()
            Spacer(minLength: 0)

            NavigationLink { ProfileView() } label: {
                Group {
                    if let avatar = model.avatarImage {
                        Image(uiImage: avatar).resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(LS.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(LS.selected)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(LS.action, lineWidth: 2))
            }
            .accessibilityLabel("Profile")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

extension LSTabHeader where Center == LSTabTitle {
    /// Tab-name header (Stats, Lab).
    init(title: String) { self.init { LSTabTitle(title: title) } }
}

/// Centered tab-name title used by Stats/Lab headers.
struct LSTabTitle: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.lsRoboto(24, weight: .semibold))     // Heading/Screen (v3.7)
            .foregroundStyle(LS.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.lsRoboto(21, weight: .semibold, relativeTo: .title3))  // Action/Label (v3.7)
            .foregroundStyle(LS.onAction)                       // text/on-accent on action/primary
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(LS.action.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))  // pill (v3.7)
    }
}

/// A button title that stays centered and shows a trailing spinner when busy — the spinner is an
/// overlay, so the label never shifts left while the action runs.
struct LoadingLabel: View {
    let title: String
    let busy: Bool
    init(_ title: String, busy: Bool) { self.title = title; self.busy = busy }
    var body: some View {
        Text(title)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                if busy {
                    ProgressView().tint(.white).padding(.trailing, 4)
                        .transition(.opacity)
                }
            }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.lsHeadline)
            .foregroundStyle(LS.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(LS.textSecondary.opacity(configuration.isPressed ? 0.08 : 0),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(LS.textSecondary, lineWidth: 1.5))   // #BFCBDD outline (3.0 Welcome)
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
        .font(.lsCaption2.weight(.semibold))
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

    /// The "± band" shown beside a best-effort value when the server provides an uncertainty
    /// (e.g. rev rate "359 ±16"). Nil when there's no value or no uncertainty — never fabricated.
    static func band(_ m: Metric?) -> String? {
        guard let m, m.value != nil, let u = m.uncertainty, u > 0 else { return nil }
        return "±\(number(u))"
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
                Text(name).font(.lsSubheadline).foregroundStyle(LS.textPrimary)
                if let note = metric?.note, !note.isEmpty {
                    Text(note).font(.lsCaption2).foregroundStyle(LS.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    // UNAVAILABLE never shows a number (design 3.7 metric-status rule) — only "—".
                    Text(hideValue ? "—" : (metric.map(Fmt.value) ?? "—"))
                        .font(.lsBody.monospacedDigit().weight(.semibold))
                        .foregroundStyle(LS.textPrimary)
                    if !hideValue, let band = Fmt.band(metric) {
                        Text(band).font(.lsCaption).foregroundStyle(LS.textSecondary)
                    }
                    if !hideValue, let unit = metric?.unit, !unit.isEmpty, metric?.value != nil {
                        Text(unit).font(.lsCaption).foregroundStyle(LS.textSecondary)
                    }
                }
                StatusChip(status: status)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceLabel)
    }

    /// Hide the number when the metric is unavailable or carries no value.
    private var hideValue: Bool { status == .unavailable || metric?.value == nil }

    private var voiceLabel: String {
        let val = !hideValue ? "\(Fmt.value(metric!)) \(metric?.unit ?? "")" : "no value"
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
                Text(value).font(.lsTitle2.weight(.bold).monospacedDigit()).foregroundStyle(LS.textPrimary)
                if let unit { Text(unit).font(.lsCaption).foregroundStyle(LS.textSecondary) }
            }
            Text(label.uppercased()).font(.lsCaption2.weight(.medium)).foregroundStyle(LS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value) \(unit ?? "")")
    }
}
