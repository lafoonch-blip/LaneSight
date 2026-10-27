import SwiftUI

struct CaptureView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()
    @State private var busy = false      // a shot is uploading/analyzing — drives the full-screen cover
    @State private var showTargetEditor = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .ready, .recording:
                CameraPreview(session: camera.session).ignoresSafeArea()
            case .needsPermission:
                CameraPermissionView(mode: .prompt,
                                     onPrimary: { Task { await camera.requestAccess() } },
                                     onSecondary: { dismiss() })
            case .denied:
                CameraPermissionView(mode: .denied,
                                     onPrimary: { openSettings() },
                                     onSecondary: { dismiss() })
            case .unavailable(let reason):
                unavailableView(reason)
            case .idle:
                ProgressView("Starting camera…").tint(.white).foregroundStyle(.white)
            }

            if camera.isRunnable {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    chipRow.padding(.bottom, 10)
                    zoomBar.padding(.bottom, 14)
                    bottomBar
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await camera.start(preferredFPS: Double(model.preferredFPS)) }
        // Keep the screen awake for the whole capture flow (recording, trimming, upload, analysis).
        // Auto-Lock otherwise sleeps the phone mid-shot.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; model.prewarm() }   // warm the analyzer
        .onDisappear {
            camera.stopSession()
            if !busy { UIApplication.shared.isIdleTimerDisabled = false }
        }
        .sheet(isPresented: $showTargetEditor) {
            TargetEditorSheet(target: $model.sessionTarget,
                              suggestedBreakpoint: model.sessionSuggested?.breakpointBoard)
                .environmentObject(model)
        }
        // A shot that's processing takes over the WHOLE screen (camera + tab bar) so the user stays
        // in the capture context — they never see the live preview or a highlighted Home tab mid-shot.
        .fullScreenCover(isPresented: $busy) {
            ProcessingCover(busy: $busy).environmentObject(model)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }

    // MARK: pieces

    /// v3.7 top controls (Figma 412:3617): torch (left), the read-only resolution·fps chip (center),
    /// a mode indicator (right). Resolution/fps are set in Setup; this surfaces what the camera locked in.
    private var topBar: some View {
        HStack {
            Button { camera.toggleTorch() } label: {
                Image(systemName: camera.torchOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(camera.torchOn ? LS.dataYellow : .white)
                    .frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(camera.torchOn ? "Turn flash off" : "Turn flash on")
            Spacer()
            if camera.activeFPS > 0 {
                Text("\(resolutionTier) · \(Int(camera.activeFPS))")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(LS.dataYellow)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel("\(resolutionTier), \(Int(camera.activeFPS)) frames per second")
            }
            Spacer()
            Text(model.captureMode == "form" ? "FORM" : "SHOT")
                .font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityLabel("Mode: \(model.captureMode == "form" ? "Form" : "Shot")")
        }
    }

    /// "4K" / "1080p" / "720p" from the locked resolution string ("WxH").
    private var resolutionTier: String {
        let h = camera.resolution.split(separator: "x").last.flatMap { Int($0) } ?? 0
        if h >= 2160 { return "4K" }
        if h >= 1080 { return "1080p" }
        if h >= 720 { return "720p" }
        return camera.resolution
    }

    /// Zoom presets (.5 / 1× / 2 / 5), the active one highlighted. .5 maps to 1× when the device has no
    /// ultra-wide (we only use the wide camera), so it reads as the minimum.
    private var zoomBar: some View {
        HStack(spacing: 8) {
            ForEach([(".5", 1.0), ("1×", 1.0), ("2", 2.0), ("5", 5.0)], id: \.0) { label, z in
                Button { camera.setZoom(z) } label: {
                    Text(label).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(abs(camera.zoomFactor - z) < 0.05 ? LS.dataYellow : .white)
                        .frame(width: 44, height: 36)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(camera.state == .recording ? 0 : 1)
    }

    /// Bottom bar (Figma 412:3617): last-shot thumbnail · record · Done.
    private var bottomBar: some View {
        HStack {
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08))
                .frame(width: 56, height: 56)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.2), lineWidth: 1))
                .overlay(Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(.white.opacity(0.5)))
                .accessibilityHidden(true)
            Spacer()
            recordButton
                .disabled(!camera.isRunnable).opacity(camera.isRunnable ? 1 : 0.4)
            Spacer()
            Button("Done") { dismiss(); model.resetPipeline() }
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 56)
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

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
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
struct ProcessingCover: View {
    @EnvironmentObject var model: AppModel
    @Binding var busy: Bool
    /// Label for the button shown on a failure. Live capture returns to the camera; an upload just closes.
    var failButtonLabel: String = "Back to camera"

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
                    Text("We couldn't analyze this clip").font(.lsTitle3.bold()).foregroundStyle(LS.textPrimary)
                    Text(msg).font(.lsCallout).foregroundStyle(LS.textSecondary)
                        .multilineTextAlignment(.center)
                    Button(failButtonLabel) { model.resetPipeline(); busy = false }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(32)

            default:
                processing
            }
        }
    }

    /// v3.7 Analyzing modal (Figma 412:3784): one card with a Trimmed / Uploaded / Analyzing checklist
    /// that fills in as the pipeline advances, an overall bar, and Cancel. Driven by `model.pipeline`.
    private enum StepState { case pending, active, done }

    private var processing: some View {
        let r = pipelineRank
        return VStack(spacing: 14) {
            ProgressView().tint(LS.action).scaleEffect(1.2).padding(.top, 4)
            Text(model.captureMode == "form" ? "Analyzing your delivery" : "Analyzing your shot")
                .font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            Text("Usually about a minute. The screen stays on and controls are locked. Your results open as soon as it finishes.")
                .font(.system(size: 12)).foregroundStyle(LS.textSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 8)
            VStack(alignment: .leading, spacing: 12) {
                stepRow("Trimmed", r > 1 ? .done : (r == 1 ? .active : .pending))
                stepRow("Uploaded", r > 2 ? .done : (r == 2 ? .active : .pending), detail: uploadDetail)
                stepRow("Analyzing", r >= 4 ? .done : (r == 3 ? .active : .pending))
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            ProgressView(value: overallFrac).tint(LS.action)
            Button("Cancel analysis") { model.resetPipeline(); busy = false }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(LS.link).padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
        .padding(.horizontal, 28)
    }

    private func stepRow(_ label: String, _ state: StepState, detail: String? = nil) -> some View {
        HStack(spacing: 10) {
            ZStack {
                switch state {
                case .done:
                    Circle().fill(LS.positive).frame(width: 20, height: 20)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(LS.onAction)
                case .active:
                    ProgressView().controlSize(.small).tint(LS.action)
                case .pending:
                    Circle().strokeBorder(LS.border, lineWidth: 2).frame(width: 20, height: 20)
                }
            }
            .frame(width: 20, height: 20)
            Text(label).font(.system(size: 14, weight: .medium))
                .foregroundStyle(state == .pending ? LS.textSecondary : LS.textPrimary)
            Spacer()
            if let detail, state == .active { Text(detail).font(.system(size: 12)).foregroundStyle(LS.textSecondary) }
        }
    }

    /// 0=session 1=trim 2=upload 3=analyze/fetch 4=done. Drives which checklist steps are done/active.
    private var pipelineRank: Int {
        switch model.pipeline {
        case .creatingSession: return 0
        case .trimming: return 1
        case .uploading: return 2
        case .analyzing, .fetching: return 3
        case .done: return 4
        default: return 1
        }
    }
    private var uploadDetail: String? {
        if case .uploading(let f) = model.pipeline { return "\(Int(f * 100))%" }
        return nil
    }
    private var overallFrac: Double {
        switch model.pipeline {
        case .creatingSession: return 0.08
        case .trimming: return 0.25
        case .uploading(let f): return 0.33 + f * 0.3
        case .analyzing: return 0.78
        case .fetching: return 0.92
        case .done: return 1
        default: return 0.3
        }
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
