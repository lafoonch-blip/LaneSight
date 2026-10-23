import SwiftUI

struct CaptureView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var camera = CameraController()
    @State private var busy = false      // a shot is uploading/analyzing — drives the full-screen cover

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .ready, .recording:
                CameraPreview(session: camera.session).ignoresSafeArea()
            case .unavailable(let reason):
                unavailableView(reason)
            case .idle:
                ProgressView("Starting camera…").tint(.white).foregroundStyle(.white)
            }

            VStack {
                topBar
                Spacer()
                controls
            }
            .padding()
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await camera.start(preferredFPS: Double(model.preferredFPS)) }
        .onDisappear { camera.stopSession() }
        // A shot that's processing takes over the WHOLE screen (camera + tab bar) so the user stays
        // in the capture context — they never see the live preview or a highlighted Home tab mid-shot.
        .fullScreenCover(isPresented: $busy) {
            ProcessingCover(busy: $busy).environmentObject(model)
        }
    }

    // MARK: pieces

    /// Read-only active fps / resolution. The value is CHANGED in Setup (capture frame rate); this
    /// only surfaces what the camera actually locked in.
    private var topBar: some View {
        HStack {
            if camera.activeFPS > 0 {
                Label("\(Int(camera.activeFPS)) fps · \(camera.resolution)", systemImage: "video.fill")
                    .font(.caption).padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel("Recording at \(Int(camera.activeFPS)) frames per second, \(camera.resolution)")
            }
            Spacer()
            Text(model.captureMode == "form" ? "FORM" : "SHOT")
                .font(.caption2.bold()).tracking(1).padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityLabel("Mode: \(model.captureMode == "form" ? "Form" : "Shot")")
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            recordButton
                .disabled(!camera.isRunnable)
                .opacity(camera.isRunnable ? 1 : 0.4)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var recordButton: some View {
        Button {
            if camera.state == .recording {
                Task { await stopAndProcess() }
            } else {
                camera.startRecording()
            }
        } label: {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: camera.state == .recording ? 6 : 32)
                    .fill(.red)
                    .frame(width: camera.state == .recording ? 34 : 62,
                           height: camera.state == .recording ? 34 : 62)
                    .animation(.easeInOut(duration: 0.15), value: camera.state)
            }
        }
        .accessibilityLabel(camera.state == .recording ? "Stop recording" : "Start recording")
    }

    private func unavailableView(_ reason: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.unknown").font(.largeTitle)
            Text(reason).multilineTextAlignment(.center).font(.footnote)
            Text("You can still set the API URL and Check connection in Settings.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding()
    }

    // MARK: actions

    private func stopAndProcess() async {
        busy = true     // presents the full-screen Uploading/Analyzing cover
        do {
            let url = try await camera.stopRecording()
            await model.processShot(fileURL: url)
        } catch {
            model.pipeline = .failed(error.localizedDescription)
        }
        // Success → the cover shows the Shot card (pipeline == .done); failure → it shows the error.
        // The cover's own actions dismiss it, so we do not clear `busy` here.
    }
}

/// Full-screen takeover shown while a shot uploads → analyzes → returns. Covers the camera preview
/// and the tab bar. On success it presents the Shot card in place; on failure, an inline error.
private struct ProcessingCover: View {
    @EnvironmentObject var model: AppModel
    @Binding var busy: Bool

    var body: some View {
        ZStack {
            LSBackground().ignoresSafeArea()

            switch model.pipeline {
            case .done:
                if let result = model.result {
                    ShotCardView(result: result).environmentObject(model)
                } else {
                    stage(title: "Finishing up…")
                }

            case .failed(let msg):
                VStack(spacing: 18) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44)).foregroundStyle(LS.bestEffort)
                    Text("Shot couldn't be processed").font(.title3.bold()).foregroundStyle(LS.textPrimary)
                    Text(msg).font(.callout).foregroundStyle(LS.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Back to camera") { model.resetPipeline(); busy = false }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(32)

            default:
                processing
            }
        }
    }

    private var processing: some View {
        VStack(spacing: 24) {
            Spacer()
            switch model.pipeline {
            case .creatingSession:
                stage(title: "Starting session…")

            case .trimming:
                VStack(spacing: 14) {
                    Image(systemName: "scissors")
                        .font(.system(size: 40)).foregroundStyle(LS.cyan)
                    Text("Trimming…").font(.title3.bold()).foregroundStyle(LS.textPrimary)
                    Text("Cutting to the shot — full 120 fps and resolution are kept.")
                        .font(.callout).foregroundStyle(LS.textSecondary)
                        .multilineTextAlignment(.center)
                }

            case .uploading(let frac):
                VStack(spacing: 14) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 44)).foregroundStyle(LS.blue)
                    Text("Uploading clip").font(.title3.bold()).foregroundStyle(LS.textPrimary)
                    ProgressView(value: frac).tint(LS.blue).frame(maxWidth: 260)
                    Text("\(Int(frac * 100))%").font(.headline.monospacedDigit()).foregroundStyle(LS.textSecondary)
                }

            case .analyzing(let state, let timings):
                VStack(spacing: 14) {
                    ProgressView().tint(LS.cyan).scaleEffect(1.3)
                    Text("Analyzing…").font(.title3.bold()).foregroundStyle(LS.textPrimary)
                    Text("Usually about 20–30s · job \(state)")
                        .font(.callout).foregroundStyle(LS.textSecondary)
                    if !timings.isEmpty {
                        Text(timings.sorted(by: { $0.key < $1.key })
                            .map { "\($0.key) \(String(format: "%.2fs", $0.value))" }
                            .joined(separator: " · "))
                            .font(.caption2.monospacedDigit()).foregroundStyle(LS.textFaint)
                            .multilineTextAlignment(.center)
                    }
                }

            case .fetching:
                stage(title: "Fetching results…")

            default:
                EmptyView()
            }
            Spacer()
            Text("Keep the app open — this finishes on your Mac.")
                .font(.caption2).foregroundStyle(LS.textFaint)
                .padding(.bottom, 12)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stage(title: String, detail: String? = nil) -> some View {
        VStack(spacing: 12) {
            ProgressView().tint(LS.cyan)
            Text(title).font(.title3.bold()).foregroundStyle(LS.textPrimary)
            if let detail { Text(detail).font(.callout).foregroundStyle(LS.textSecondary) }
        }
    }
}
