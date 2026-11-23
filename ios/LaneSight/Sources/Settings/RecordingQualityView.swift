import SwiftUI

/// DEC-133 · Settings › Recording quality (Figma 822:4216). Lets the bowler choose the in-app recording format for
/// Shot and Form, listing ONLY the formats this phone supports (4K / 240 hidden when unavailable). Default is
/// 1080p120 SDR; Form never goes below 60. Capture is always SDR (HDR is tone-mapped on import, not recorded).
struct RecordingQualityView: View {
    @State private var shot = CaptureFormats.savedShot()
    @State private var form = CaptureFormats.savedForm()

    private let shotOptions = CaptureFormats.supported(CaptureFormats.shotTiers)
    private let formOptions = CaptureFormats.supported(CaptureFormats.formTiers)
    private static let recommended = CaptureFormats.fallbackDefault   // 1080p120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                group(title: "Shot", options: shotOptions, selected: shot) { c in
                    shot = c; CaptureFormats.saveShot(c)
                }
                group(title: "Form", options: formOptions, selected: form,
                      footer: "Form never goes below 60 fps — the swing timing needs it.") { c in
                    form = c; CaptureFormats.saveForm(c)
                }
                VStack(alignment: .leading, spacing: 6) {
                    note("Recorded in standard range (SDR). HDR clips you import are converted automatically.")
                    note("Dark lanes: at high frame rates a dim house can look noisy — drop to 60 fps if a clip comes out dark.")
                }
                .padding(.top, 2)
            }
            .padding(16)
        }
        .background(LS.bg.ignoresSafeArea())
        .navigationTitle("Recording quality")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func group(title: String, options: [CaptureChoice], selected: CaptureChoice,
                       footer: String? = nil, pick: @escaping (CaptureChoice) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(0.6)
                .foregroundStyle(LS.textSecondary)
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, c in
                    Button { pick(c) } label: { row(c, isSelected: c == selected) }
                        .buttonStyle(.plain)
                    if idx != options.count - 1 { Divider().overlay(LS.cardStroke).padding(.leading, 14) }
                }
            }
            .background(LS.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.border, lineWidth: 1))
            if let footer {
                Text(footer).font(.system(size: 12)).foregroundStyle(LS.textSecondary)
            }
        }
    }

    private func row(_ c: CaptureChoice, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(c.label).font(.system(size: 16, weight: .semibold)).foregroundStyle(LS.textPrimary)
                    if c == Self.recommended {
                        Text("Recommended").font(.system(size: 11, weight: .semibold)).foregroundStyle(LS.success)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(LS.success.opacity(0.12), in: Capsule())
                    }
                }
                Text(c.tradeoff).font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20)).foregroundStyle(isSelected ? LS.action : LS.borderStrong)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(LS.textSecondary).padding(.top, 1)
            Text(text).font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
