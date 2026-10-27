import SwiftUI

/// The two "Analyze" entry cards (Shot / Form) shown on Home's Performance Lab and at the top of Lab.
/// Tapping a card opens the "Choose source" sheet (v3.7 Figma 409:3335 Shot / 438:6251 Form) — Live
/// session vs Upload video — then routes to Setup (live) or the upload flow. Previously it jumped
/// straight to live Setup with no chooser.
struct AnalyzeCards: View {
    @EnvironmentObject var model: AppModel

    enum CaptureRoute: Hashable { case live(String), upload(String) }

    @State private var chooserMode: String?     // non-nil → the Choose-source sheet is open for this mode
    @State private var pending: CaptureRoute?   // choice captured in the sheet, applied after it dismisses
    @State private var route: CaptureRoute?     // drives the push onto the enclosing NavigationStack

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            card(mode: "shot", title: "Shot Analysis", desc: "Track ball motion, lane reaction and results.",
                 photo: "LabShotPhoto", action: "Start Shot Analysis", accent: LS.action)
            card(mode: "form", title: "Form Analysis", desc: "Analyze approach, timing, release and mechanics.",
                 photo: "LabFormPhoto", action: "Start Form Analysis", accent: LS.dataPurple)
        }
        .sheet(isPresented: Binding(get: { chooserMode != nil }, set: { if !$0 { chooserMode = nil } }),
               onDismiss: { if let p = pending { pending = nil; route = p } }) {
            if let m = chooserMode {
                ChooseSourceSheet(
                    mode: m,
                    onLive: { pending = .live(m); chooserMode = nil },
                    onUpload: { model.captureMode = m; pending = .upload(m); chooserMode = nil })
                .presentationDetents([.height(340), .medium])
                .presentationDragIndicator(.visible)
            }
        }
        .navigationDestination(item: $route) { r in
            switch r {
            case .live(let md): SetupView(initialMode: md)
            case .upload: UploadView()
            }
        }
    }

    private func card(mode: String, title: String, desc: String, photo: String, action: String, accent: Color) -> some View {
        Button { chooserMode = mode } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(photo).resizable().scaledToFill().frame(height: 120).frame(maxWidth: .infinity).clipped()
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(LS.textPrimary)
                    Text(desc).font(.system(size: 11)).lineSpacing(2).foregroundStyle(LS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) { Text(action); Text("›") }
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(LS.onAction)
                        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity)
                        .background(accent, in: Capsule())
                }
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LS.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// "How do you want to analyze?" source chooser (v3.7 Figma 409:3335 / 438:6251). Live counts toward
/// Stats + Score; an upload is diagnostic-only (saved under Uploads, DEC-055).
struct ChooseSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let mode: String                 // "shot" | "form"
    let onLive: () -> Void
    let onUpload: () -> Void

    private var isForm: Bool { mode == "form" }
    private var title: String { isForm ? "Form Analysis" : "Shot Analysis" }
    private var liveDesc: String {
        isForm ? "Record your delivery at the lane. Form stats are diagnostic — they don't affect your Score."
               : "Record shots at the lane. Counts toward Stats and your LaneSight Score."
    }
    private var uploadDesc: String {
        isForm ? "Analyze a clip from Photos. Saved under Uploads; diagnostic only."
               : "Analyze a clip from Photos. Saved under Uploads; doesn't count toward Stats or Score."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            Text("How do you want to analyze?").font(.system(size: 14)).foregroundStyle(LS.textSecondary)

            option(icon: "video.fill", title: "Live session", desc: liveDesc) { dismiss(); onLive() }
            option(icon: "square.and.arrow.up", title: "Upload video", desc: uploadDesc) { dismiss(); onUpload() }

            Button("Cancel") { dismiss() }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(LS.link)
                .frame(maxWidth: .infinity).frame(minHeight: 44).padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LSBackground())
    }

    private func option(icon: String, title: String, desc: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(LS.action)
                    .frame(width: 44, height: 44)
                    .background(LS.action.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text(desc).font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(LS.textFaint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
