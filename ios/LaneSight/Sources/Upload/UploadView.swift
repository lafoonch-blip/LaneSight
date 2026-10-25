import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Upload a clip (Upload.dc.html). Pick a video from Photos → POST /uploads → same analyze job →
/// Shot card. One shot per clip. All results are live from the pipeline; nothing is simulated.
struct UploadView: View {
    @EnvironmentObject var model: AppModel
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
                modeSection
                intentSection

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(LS.bestEffort)
                }

                if busy { pipelineCard }

                Button {
                    Task { await analyze() }
                } label: {
                    HStack { Text("Analyze"); if busy { ProgressView().tint(.white) } }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(pickedURL == nil || busy)
                .opacity(pickedURL == nil || busy ? 0.5 : 1)

                Text("One shot per clip for now. Analysis runs on your Mac and takes about a minute or two.")
                    .font(.caption).foregroundStyle(LS.textFaint).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Analyze a video")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .videos)
        .onChange(of: pickerItem) { _, item in Task { await loadPicked(item) } }
        .sheet(isPresented: $model.showResult) {
            if let result = model.result {
                if result.isForm {
                    FormCardView(result: result).environmentObject(model)
                } else {
                    ShotCardView(result: result).environmentObject(model)
                }
            }
        }
    }

    @State private var pickerItem: PhotosPickerItem?

    private var clipCard: some View {
        Button { showPicker = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x1A2440))
                    Image(systemName: loadingClip ? "arrow.triangle.2.circlepath" : "film")
                        .foregroundStyle(LS.textSecondary)
                }
                .frame(width: 66, height: 90)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pickedName ?? "Choose a clip").font(.headline).foregroundStyle(LS.textPrimary)
                    Text(pickedURL == nil ? "From Photos — 1080p · up to 120 fps · SDR"
                                          : "Tap to choose another")
                        .font(.caption).foregroundStyle(LS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(LS.textFaint)
            }
            .lsCard(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT'S IN THIS CLIP?").lsEyebrow()
            HStack(spacing: 10) {
                modeButton("shot", "Shot", "Ball & lane")
                modeButton("form", "Form", "Approach & swing")
            }
        }
    }

    private func modeButton(_ value: String, _ title: String, _ sub: String) -> some View {
        let on = model.captureMode == value
        return Button { model.captureMode = value } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold()).foregroundStyle(LS.textPrimary)
                Text(sub).font(.caption2).foregroundStyle(LS.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(on ? LS.blue.opacity(0.18) : LS.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(on ? LS.blue : LS.cardStroke, lineWidth: on ? 2 : 1))
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
                .font(.caption2).foregroundStyle(LS.textFaint)
        }
    }

    private func intentField(_ title: String, text: Binding<String>) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(LS.textSecondary)
            TextField("—", text: text)
                .keyboardType(.decimalPad).multilineTextAlignment(.center)
                .foregroundStyle(LS.textPrimary)
                .padding(10).frame(maxWidth: .infinity)
                .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStroke))
        }
    }

    private var pipelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.pipeline {
            case .creatingSession: progressRow("Starting session…")
            case .uploading(let frac):
                Text("Uploading clip").font(.subheadline.bold()).foregroundStyle(LS.textPrimary)
                ProgressView(value: frac).tint(LS.blue)
                Text("\(Int(frac * 100))%").font(.caption).foregroundStyle(LS.textSecondary)
            case .analyzing(let state, _): progressRow("Analyzing on Mac — \(state)")
            case .fetching: progressRow("Fetching results…")
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(LS.bestEffort)
            default: EmptyView()
            }
        }
        .lsCard()
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: 10) { ProgressView().tint(LS.cyan); Text(text).font(.subheadline).foregroundStyle(LS.textPrimary) }
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
        await model.processUpload(fileURL: url)
        if case .failed(let msg) = model.pipeline { errorText = msg }
    }
}
