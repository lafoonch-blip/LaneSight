import SwiftUI
import PhotosUI

/// DEC-124: the Home "Feedback" button opens this sheet. One category (required), free text (required),
/// an optional screenshot, and an "Include diagnostics" toggle (on by default). Submit writes a `general`
/// feedback row (POST /feedback) tagged with the account's real app phase. A failed send keeps the typed
/// text and lets the tester retry — feedback is never lost. Follows "01 - Design Standards".
struct GeneralFeedbackSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// The screen the tester tapped Feedback from, attached as diagnostics context. Defaults to "Home".
    var currentScreen: String = "Home"

    static let categories = ["Bug", "Wrong/missing numbers", "Confusing", "Idea", "Other"]
    private let maxChars = 2000

    @State private var category: String?
    @State private var text = ""
    @State private var includeDiagnostics = true
    @State private var photoItem: PhotosPickerItem?
    @State private var screenshotBase64: String?
    @State private var screenshotNote: String?
    @State private var submitting = false
    @State private var error: String?
    @State private var done = false

    private var canSubmit: Bool {
        category != nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !submitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if done {
                    thankYou
                } else {
                    form
                }
            }
            .background(LSBackground())
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(LS.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Tell us what you ran into, what looked wrong, or an idea. It helps us make LaneSight better.")
                .font(.lsSubheadline).foregroundStyle(LS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("WHAT KIND OF FEEDBACK?").lsEyebrow()
                FlowTags(tags: Self.categories, selected: Binding(
                    get: { category.map { [$0] } ?? [] },
                    set: { category = $0.first }))     // single-select: last tap wins
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT HAPPENED?").lsEyebrow()
                TextField("Required", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .padding(10)
                    .background(LS.card, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(LS.textPrimary)
                    .onChange(of: text) { _, v in if v.count > maxChars { text = String(v.prefix(maxChars)) } }
                Text("\(text.count)/\(maxChars)").font(.lsCaption2).foregroundStyle(LS.textFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(screenshotBase64 == nil ? "Attach a screenshot (optional)" : "Screenshot attached · change",
                          systemImage: "photo")
                        .font(.lsCallout).foregroundStyle(LS.cyan)
                }
                if let screenshotNote {
                    Text(screenshotNote).font(.lsCaption2).foregroundStyle(LS.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onChange(of: photoItem) { _, item in Task { await loadScreenshot(item) } }

            Toggle("Include diagnostics (app version, device, iOS, current screen)", isOn: $includeDiagnostics)
                .font(.lsCallout).foregroundStyle(LS.textPrimary).tint(LS.blue)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.lsCaption).foregroundStyle(LS.bestEffort)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await submit() }
            } label: {
                HStack { Text("Submit"); if submitting { ProgressView().tint(.white) } }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
        }
        .padding(16)
    }

    private var thankYou: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(LS.positive)
            Text("Thanks for the feedback!").font(.system(size: 20, weight: .bold)).foregroundStyle(LS.textPrimary)
            Text("We read every note. It won't change your results — it helps us improve LaneSight.")
                .font(.lsCallout).foregroundStyle(LS.textSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }

    private func submit() async {
        guard let category else { return }
        submitting = true; error = nil
        do {
            try await model.submitGeneralFeedback(
                category: category,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                includeDiagnostics: includeDiagnostics,
                currentScreen: currentScreen,
                screenshotJPEGBase64: includeDiagnostics ? screenshotBase64 : nil)
            withAnimation { done = true }       // keep the sheet; show the thank-you, then Done dismisses
        } catch {
            self.error = "Couldn't send that — check your connection and try again. Your note is still here."
        }
        submitting = false
    }

    /// Downscale the chosen image to a small JPEG and base64-encode it for the feedback diagnostics.
    /// (DIFFERS from DEC-124's "private bucket" — no screenshot bucket/signed-URL endpoint exists yet, so the
    /// thumbnail rides inside `diagnostics` for now; bounded in size so it can't bloat a row. See APP report.)
    private func loadScreenshot(_ item: PhotosPickerItem?) async {
        guard let item else { screenshotBase64 = nil; screenshotNote = nil; return }
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else {
            screenshotNote = "Couldn't read that image."; return
        }
        let scaled = Self.downscale(img, maxDimension: 900)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.4) else {
            screenshotNote = "Couldn't attach that image."; return
        }
        let b64 = jpeg.base64EncodedString()
        if b64.count > 360_000 {        // ~270 KB JPEG — keep feedback rows small; drop oversized attachments
            screenshotBase64 = nil
            screenshotNote = "That image is too large to attach — your text will still be sent."
        } else {
            screenshotBase64 = b64
            screenshotNote = "Screenshot will be included with your feedback."
        }
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
