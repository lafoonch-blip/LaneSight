import SwiftUI

struct CaptureView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var camera = CameraController()
    @State private var busy = false      // a shot is uploading/analyzing — drives the full-screen cover
    @State private var showTargetEditor = false

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
                chipRow
                controls
            }
            .padding()
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await camera.start(preferredFPS: Double(model.preferredFPS)) }
        .onDisappear { camera.stopSession() }
        .sheet(isPresented: $showTargetEditor) {
            TargetEditorSheet(target: $model.sessionTarget,
                              suggestedBreakpoint: model.sessionSuggested?.breakpointBoard)
                .environmentObject(model)
        }
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
                    .font(.lsCaption).padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel("Recording at \(Int(camera.activeFPS)) frames per second, \(camera.resolution)")
            }
            Spacer()
            Text(model.captureMode == "form" ? "FORM" : "SHOT")
                .font(.lsCaption2.bold()).tracking(1).padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityLabel("Mode: \(model.captureMode == "form" ? "Form" : "Shot")")
        }
    }

    /// Editable target chip + current-ball chip, shown just above the record button. The target chip
    /// opens a lightweight steppers editor so the bowler can change the carry-forward target BETWEEN
    /// shots without reopening Setup. Hidden while recording to keep the frame clean.
    private var chipRow: some View {
        HStack(spacing: 8) {
            Button { showTargetEditor = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "scope").font(.lsCaption2)
                    targetChipContent
                    Image(systemName: "slider.horizontal.3").font(.lsCaption2).foregroundStyle(LS.cyan)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel("Edit target. Current target \(targetChipAccessibility)")

            if let ball = model.currentBall {
                HStack(spacing: 6) {
                    Image(systemName: "circle.circle.fill").font(.lsCaption2).foregroundStyle(LS.blue)
                    Text(ball.displayName).font(.lsCaption.weight(.semibold)).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
                .accessibilityLabel("Current ball \(ball.displayName)")
            }
            Spacer(minLength: 0)
        }
        .opacity(camera.state == .recording ? 0 : 1)
        .animation(.easeInOut(duration: 0.15), value: camera.state)
    }

    /// Chip contents: feet/arrows boards plain, and the breakpoint tagged "suggested" (cyan + a small
    /// label) when it came from "Apply this move" and hasn't been edited yet.
    @ViewBuilder private var targetChipContent: some View {
        let t = model.sessionTarget
        if t.isEmpty {
            Text("Set target").font(.lsCaption.weight(.semibold))
        } else {
            let lead = [t.feetBoard.map { "F \(Fmt.number($0))" },
                        t.arrowsBoard.map { "A \(Fmt.number($0))" }].compactMap { $0 }.joined(separator: " · ")
            HStack(spacing: 6) {
                if !lead.isEmpty { Text(lead).font(.lsCaption.weight(.semibold)) }
                if let b = t.breakpointBoard {
                    if !lead.isEmpty { Text("·").font(.lsCaption).foregroundStyle(.white.opacity(0.5)) }
                    HStack(spacing: 3) {
                        Text("B \(Fmt.number(b))").font(.lsCaption.weight(.semibold))
                            .foregroundStyle(model.breakpointIsSuggested ? LS.cyan : .white)
                        if model.breakpointIsSuggested {
                            Text("suggested").font(.lsRoboto(8, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(LS.cyan.opacity(0.18), in: Capsule())
                                .foregroundStyle(LS.cyan)
                        }
                    }
                }
            }
        }
    }

    private var targetChipAccessibility: String {
        let t = model.sessionTarget
        if t.isEmpty { return "not set" }
        func part(_ label: String, _ v: Double?) -> String? { v.map { "\(label) \(Fmt.number($0))" } }
        var s = [part("feet", t.feetBoard), part("arrows", t.arrowsBoard),
                 part("breakpoint", t.breakpointBoard)].compactMap { $0 }.joined(separator: ", ")
        if model.breakpointIsSuggested { s += " (breakpoint suggested)" }
        return s
    }

    private var controls: some View {
        VStack(spacing: 16) {
            recordButton
                .disabled(!camera.isRunnable)
                .opacity(camera.isRunnable ? 1 : 0.4)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
            Image(systemName: "camera.metering.unknown").font(.lsLargeTitle)
            Text(reason).multilineTextAlignment(.center).font(.lsFootnote)
            Text("You can still set the API URL and Check connection in Settings.")
                .font(.lsCaption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                    if result.isForm {
                        FormCardView(result: result).environmentObject(model)
                    } else {
                        ShotCardView(result: result).environmentObject(model)
                    }
                } else {
                    stage(title: "Finishing up…")
                }

            case .failed(let msg):
                VStack(spacing: 18) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44)).foregroundStyle(LS.bestEffort)
                    Text("Shot couldn't be processed").font(.lsTitle3.bold()).foregroundStyle(LS.textPrimary)
                    Text(msg).font(.lsCallout).foregroundStyle(LS.textSecondary)
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
                    Text("Trimming…").font(.lsTitle3.bold()).foregroundStyle(LS.textPrimary)
                    Text("Cutting to the shot — full 120 fps and resolution are kept.")
                        .font(.lsCallout).foregroundStyle(LS.textSecondary)
                        .multilineTextAlignment(.center)
                }

            case .uploading(let frac):
                VStack(spacing: 14) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 44)).foregroundStyle(LS.blue)
                    Text("Uploading clip").font(.lsTitle3.bold()).foregroundStyle(LS.textPrimary)
                    ProgressView(value: frac).tint(LS.blue).frame(maxWidth: 260)
                    Text("\(Int(frac * 100))%").font(.lsHeadline.monospacedDigit()).foregroundStyle(LS.textSecondary)
                }

            case .analyzing(let state, let timings):
                VStack(spacing: 14) {
                    ProgressView().tint(LS.cyan).scaleEffect(1.3)
                    Text("Analyzing…").font(.lsTitle3.bold()).foregroundStyle(LS.textPrimary)
                    Text("Usually about 20–30s · job \(state)")
                        .font(.lsCallout).foregroundStyle(LS.textSecondary)
                    if !timings.isEmpty {
                        Text(timings.sorted(by: { $0.key < $1.key })
                            .map { "\($0.key) \(String(format: "%.2fs", $0.value))" }
                            .joined(separator: " · "))
                            .font(.lsCaption2.monospacedDigit()).foregroundStyle(LS.textFaint)
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
                .font(.lsCaption2).foregroundStyle(LS.textFaint)
                .padding(.bottom, 12)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stage(title: String, detail: String? = nil) -> some View {
        VStack(spacing: 12) {
            ProgressView().tint(LS.cyan)
            Text(title).font(.lsTitle3.bold()).foregroundStyle(LS.textPrimary)
            if let detail { Text(detail).font(.lsCallout).foregroundStyle(LS.textSecondary) }
        }
    }
}

/// Lightweight editor for the carry-forward target. Steppers change feet / arrows / breakpoint boards
/// between shots; "Clear" removes a board (skips Accuracy on it). Edits write straight to the bound
/// session target used for the NEXT shot — no need to reopen Setup.
private struct TargetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var target: ShotIntent
    /// The last applied "Apply this move" breakpoint, if any. The Breakpoint row shows a "suggested" tag
    /// while its value still equals this; the tag clears once the bowler edits it. Editing never changes
    /// the stored proposal — only `target` (the used value).
    var suggestedBreakpoint: Double? = nil

    // Sensible starting values when a board is toggled on from "off".
    private let defaults: [String: Double] = ["Feet": 15, "Arrows": 10, "Breakpoint": 8]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Change your target between shots. It carries forward until you change it again or apply a move from a shot card.")
                        .font(.lsCaption).foregroundStyle(LS.textSecondary)
                    boardRow("Feet", value: $target.feetBoard)
                    boardRow("Arrows", value: $target.arrowsBoard)
                    boardRow("Breakpoint", value: $target.breakpointBoard, suggested: suggestedBreakpoint)
                }
                .padding(16)
            }
            .background(LSBackground())
            .navigationTitle("Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }

    private func boardRow(_ title: String, value: Binding<Double?>, suggested: Double? = nil) -> some View {
        let isSuggested = suggested != nil && value.wrappedValue == suggested
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.lsSubheadline).foregroundStyle(LS.textPrimary)
                if isSuggested {
                    Text("SUGGESTED").font(.lsRoboto(9, weight: .bold)).foregroundStyle(LS.cyan)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let current = value.wrappedValue {
                Stepper(value: Binding(get: { current },
                                       set: { value.wrappedValue = max(0, min(60, $0)) }),
                        in: 0...60, step: 1) {
                    Text(Fmt.number(current)).font(.lsBody.monospacedDigit().bold())
                        .foregroundStyle(LS.textPrimary).frame(width: 40, alignment: .trailing)
                }
                .labelsHidden()
                Button("Clear") { value.wrappedValue = nil }
                    .font(.lsCaption).tint(LS.bestEffort)
            } else {
                Text("Off").font(.lsSubheadline).foregroundStyle(LS.textFaint)
                Button("Set") { value.wrappedValue = defaults[title] ?? 0 }
                    .font(.lsCaption).tint(LS.blue)
            }
        }
        .lsCard()
    }
}
