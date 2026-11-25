import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable

/// A picked video, imported as a FILE (not Data). Photos vends videos as files — `loadTransferable(type: Data.self)`
/// returns nil for many video assets (the clip then silently never loaded), so import via a file representation and
/// copy it to our temp dir. This is the reliable way to bring a Photos video on-device.
struct ImportedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString).\(ext)")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return ImportedMovie(url: dst)
        }
    }
}

/// Upload a clip (Upload.dc.html). Pick a video from Photos → POST /uploads → same analyze job →
/// Shot card. One shot per clip. All results are live from the pipeline; nothing is simulated.
struct UploadView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
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
                if let cap = capture { captureBadge(cap) }   // DEC-133: detected quality + lower-quality warning
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

                Text("One shot per clip. Results in about 15 seconds, analyzed on your iPhone. Saved under Lab › Uploads; not a session, and not counted in Stats, Score or achievements.")
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
    @State private var capture: CaptureProbe.CaptureInfo?   // DEC-133: detected capture of the imported clip
    @State private var captureWarn: String?                 // below-floor reason, if any

    /// DEC-133 (Figma 822:4354): the imported clip's detected quality + an amber "Lower-quality clip" badge when a
    /// metric can't be supported. HDR clips are allowed (tone-mapped on analysis); the note says so.
    private func captureBadge(_ cap: CaptureProbe.CaptureInfo) -> some View {
        let fps = Int(max(cap.fpsMeasured, cap.fpsNominal).rounded())
        let res = cap.height >= 2160 ? "4K" : "\(cap.height)p"
        let hdr = cap.dynamicRange != .sdr
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: captureWarn == nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(captureWarn == nil ? LS.success : LS.bestEffort)
                Text("\(res) · \(fps) fps\(hdr ? " · HDR" : "")")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(LS.textPrimary)
                if captureWarn != nil {
                    Text("Lower-quality clip").font(.system(size: 11, weight: .semibold)).foregroundStyle(LS.bestEffort)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(LS.bestEffort.opacity(0.14), in: Capsule())
                }
            }
            if let w = captureWarn {
                Text(w + (hdr ? " · HDR is converted to standard range automatically." : "")).font(.lsCaption)
                    .foregroundStyle(LS.textSecondary).fixedSize(horizontal: false, vertical: true)
            } else if hdr {
                Text("HDR is converted to standard range automatically.").font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard(padding: 12)
    }

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
            // Import the video as a FILE (reliable for Photos videos; Data transfer returns nil for many of them).
            guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                errorText = "Couldn't read that clip."; loadingClip = false; return
            }
            let url = movie.url
            pickedURL = url
            pickedName = url.lastPathComponent
            // DEC-133: detect the imported clip's real capture + whether it's below the floor for this mode.
            // Off the main actor — probe reads the asset synchronously and must not freeze the import UI.
            let info = await Task.detached { CaptureProbe.probe(url: url, source: "upload") }.value
            capture = info
            captureWarn = info.flatMap { CaptureProbe.floorReasons($0, formMode: mode == "form").first?.reason }
        } catch {
            errorText = "Couldn't load the clip: \(error.localizedDescription)"
        }
        loadingClip = false
    }

    private func analyze() async {
        guard let url = pickedURL else { return }
        errorText = nil
        // Pop this pushed screen FIRST so the root analyzing cover can present: a .fullScreenCover attached
        // above the NavigationStack won't reliably appear while this navigationDestination is still active
        // (the DEC-096 routing regression — the user saw only an inline busy state, no cover). After the pop
        // the cover owns the whole screen from the root (DEC-086: never orphaned), and shows result/failure.
        dismiss()
        await model.processUpload(fileURL: url)
    }
}
