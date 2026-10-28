import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Upload a clip (Upload.dc.html). Pick a video from Photos → POST /uploads → same analyze job →
/// Shot card. One shot per clip. All results are live from the pipeline; nothing is simulated.
struct UploadView: View {
    @EnvironmentObject var model: AppModel
    /// DEC-099: the analysis type is chosen BEFORE this screen (Lab › Shot/Form Analysis › Upload video), so
    /// Upload never asks "Shot or Form" again. "shot" | "form".
    let mode: String
    @State private var pickedURL: URL?
    @State private var pickedName: String?
    @State private var showPicker = false
    @State private var loadingClip = false
    @State private var errorText: String?

    private var busy: Bool {
        switch model.pipeline {
        case .idle, .done, .failed: return false
        default: return true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                clipCard
                if mode == "shot" { intentSection }      // Form has no target line (DEC-081)

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.lsCaption).foregroundStyle(LS.bestEffort)
                }

                Button {
                    Task { await analyze() }
                } label: {
                    HStack { Text("Analyze"); if busy { ProgressView().tint(.white) } }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(pickedURL == nil || busy)
                .opacity(pickedURL == nil || busy ? 0.5 : 1)

                Text("One shot per clip. Results in about 2 minutes. Saved under Lab › Uploads; not a session, and not counted in Stats, Score or achievements.")
                    .font(.lsCaption).foregroundStyle(LS.textFaint).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle(mode == "form" ? "Upload · Form Analysis" : "Upload · Shot Analysis")
        .onAppear { model.captureMode = mode }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .lsHidesTabBar()      // DEC-099: only Home · Stats · Lab · Coaching show the tab bar
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .videos)
        .onChange(of: pickerItem) { _, item in Task { await loadPicked(item) } }
        // The analyzing modal + the result + any failure are presented at the app root (DEC-086), so
        // this screen owns none of them — leaving Upload mid-analysis can't orphan the result.
    }

    @State private var pickerItem: PhotosPickerItem?

    private var clipCard: some View {
        Button { showPicker = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(LS.raised)
                    Image(systemName: loadingClip ? "arrow.triangle.2.circlepath" : "film")
                        .foregroundStyle(LS.textSecondary)
                }
                .frame(width: 66, height: 90)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pickedName ?? "Choose a clip").font(.lsHeadline).foregroundStyle(LS.textPrimary)
                    Text(pickedURL == nil ? "From Photos — 1080p · up to 120 fps · SDR"
                                          : "Tap to choose another")
                        .font(.lsCaption).foregroundStyle(LS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.lsFootnote).foregroundStyle(LS.textFaint)
            }
            .lsCard(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private var intentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR TARGET FOR THIS SHOT (OPTIONAL)").lsEyebrow()
            HStack(spacing: 8) {
                intentField("Feet", text: $model.feetBoardText)
                intentField("Arrows", text: $model.arrowsBoardText)
                intentField("Breakpoint", text: $model.breakpointBoardText)
            }
            Text("Without a target, Accuracy is skipped for this shot.")
                .font(.lsCaption2).foregroundStyle(LS.textFaint)
        }
    }

    private func intentField(_ title: String, text: Binding<String>) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.lsCaption2).foregroundStyle(LS.textSecondary)
            TextField("—", text: text)
                .keyboardType(.decimalPad).multilineTextAlignment(.center)
                .foregroundStyle(LS.textPrimary)
                .padding(10).frame(maxWidth: .infinity)
                .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStroke))
        }
    }

    // MARK: actions

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        loadingClip = true
        errorText = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorText = "Couldn't read that clip."; loadingClip = false; return
            }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("upload-\(UUID().uuidString).\(ext)")
            try data.write(to: url)
            pickedURL = url
            pickedName = url.lastPathComponent
        } catch {
            errorText = "Couldn't load the clip: \(error.localizedDescription)"
        }
        loadingClip = false
    }

    private func analyze() async {
        guard let url = pickedURL else { return }
        errorText = nil
        // processUpload raises the root analyzing cover; the result/failure are shown there, not inline.
        await model.processUpload(fileURL: url)
    }
}
