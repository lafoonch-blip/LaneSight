import SwiftUI

struct CaptureView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var camera = CameraController()
    @State private var busy = false      // a shot is uploading/analyzing

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
                if busy {
                    pipelineOverlay
                } else {
                    controls
                }
            }
            .padding()
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SessionView() } label: {
                    Image(systemName: "list.bullet.rectangle").foregroundStyle(.white)
                }
                .accessibilityLabel("Live session")
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stopSession() }
        .sheet(isPresented: $model.showResult) {
            if let result = model.result {
                ShotCardView(result: result)
                    .environmentObject(model)
            }
        }
    }

    // MARK: pieces

    private var topBar: some View {
        HStack {
            if camera.activeFPS > 0 {
                Label("\(Int(camera.activeFPS)) fps · \(camera.resolution)", systemImage: "video.fill")
                    .font(.caption).padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            Picker("Mode", selection: $model.captureMode) {
                Text("Shot").tag("shot")
                Text("Form").tag("form")
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                intentField("Feet", text: $model.feetBoardText)
                intentField("Arrows", text: $model.arrowsBoardText)
                intentField("Breakpoint", text: $model.breakpointBoardText)
            }

            recordButton
                .disabled(!camera.isRunnable)
                .opacity(camera.isRunnable ? 1 : 0.4)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func intentField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField("optional", text: text)
                .keyboardType(.decimalPad)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
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
    }

    private var pipelineOverlay: some View {
        VStack(spacing: 10) {
            switch model.pipeline {
            case .creatingSession:
                row(ProgressView(), "Starting session…")
            case .uploading(let frac):
                VStack(spacing: 6) {
                    Text("Uploading clip").font(.subheadline.bold())
                    ProgressView(value: frac).tint(.white)
                    Text("\(Int(frac * 100))%").font(.caption).foregroundStyle(.secondary)
                }
            case .analyzing(let state, let timings):
                VStack(spacing: 6) {
                    row(ProgressView(), "Analyzing — \(state)")
                    if !timings.isEmpty {
                        Text(timings.sorted(by: { $0.key < $1.key })
                            .map { "\($0.key) \(String(format: "%.2fs", $0.value))" }
                            .joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            case .fetching:
                row(ProgressView(), "Fetching results…")
            case .failed(let msg):
                VStack(spacing: 10) {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("Dismiss") { busy = false; model.resetPipeline() }
                        .buttonStyle(.borderedProminent)
                }
            case .done, .idle:
                EmptyView()
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func row(_ spinner: some View, _ text: String) -> some View {
        HStack(spacing: 10) { spinner.tint(.white); Text(text).font(.subheadline) }
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
        busy = true
        do {
            let url = try await camera.stopRecording()
            await model.processShot(fileURL: url)
        } catch {
            model.pipeline = .failed(error.localizedDescription)
        }
        // On success the result sheet is presented and we can reset the busy flag.
        if case .done = model.pipeline { busy = false }
        if case .failed = model.pipeline { /* keep overlay showing the error until dismissed */ }
    }
}
