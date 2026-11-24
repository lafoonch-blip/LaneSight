import SwiftUI

/// DEC-133 · Setup quick-access recording-quality sheet (Figma 822:4081). The same format options as
/// Settings › Recording quality, as a bottom sheet from Setup's pre-flight Camera row, with "Use this format".
/// Shows only formats this phone supports; Form is 1080p / ≥60.
struct RecordingQualitySheet: View {
    let mode: String                    // "form" | "shot"
    @Environment(\.dismiss) private var dismiss
    @State private var choice: CaptureChoice

    private let options: [CaptureChoice]
    private let isForm: Bool
    private static let recommended = CaptureFormats.fallbackDefault   // 1080p120

    init(mode: String) {
        self.mode = mode
        let form = (mode == "form")
        self.isForm = form
        self.options = CaptureFormats.supported(form ? CaptureFormats.formTiers : CaptureFormats.shotTiers)
        _choice = State(initialValue: form ? CaptureFormats.savedForm() : CaptureFormats.savedShot())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recording quality").font(.system(size: 17, weight: .semibold)).foregroundStyle(LS.textPrimary)
                Spacer()
                Text(isForm ? "Form" : "Shot").font(.system(size: 12, weight: .semibold)).foregroundStyle(LS.textSecondary)
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { idx, c in
                        Button { choice = c } label: { row(c, isSelected: c == choice) }.buttonStyle(.plain)
                        if idx != options.count - 1 { Divider().overlay(LS.cardStroke).padding(.leading, 14) }
                    }
                }
                .background(LS.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.border, lineWidth: 1))
                .padding(.horizontal, 16)
                if isForm {
                    Text("Form never goes below 60 fps.").font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 8)
                }
                Text("Recorded in SDR. HDR imports are converted automatically.")
                    .font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 8)
            }

            Button {
                if isForm { CaptureFormats.saveForm(choice) } else { CaptureFormats.saveShot(choice) }
                dismiss()
            } label: {
                Text("Use this format").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(16)
        }
        .background(LSBackground())
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
        .padding(14).contentShape(Rectangle())
    }
}
