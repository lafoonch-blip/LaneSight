import SwiftUI

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    /// Pre-selects the capture mode when opened from Home's Performance Lab cards (nil = leave as-is).
    var initialMode: String? = nil
    @State private var oilPatterns: [OilPattern] = []
    @State private var oilLoadError: String?
    @State private var healthText: String?
    @State private var healthOK = false
    @State private var starting = false
    @State private var startError: String?
    @State private var goCapture = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                modeSection
                if model.captureMode == "shot" { intentSection }
                ballSection
                oilSection
                preflightSection

                if let startError {
                    Text(startError).font(.lsCaption).foregroundStyle(LS.bestEffort)
                }
                Button {
                    Task { await startSession() }
                } label: {
                    HStack { Text("Start session"); if starting { ProgressView().tint(.white) } }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(starting)
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Session setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $goCapture) { CaptureView() }
        .onAppear { if let initialMode { model.captureMode = initialMode } }
        .task {
            await loadOil()
            await loadHealth()
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT ARE YOU ANALYZING?").lsEyebrow()
            modeCard("shot", title: "Shot Analysis", desc: "Ball, lane & pins. Film from any spot that sees the lane", symbol: "scope")
            modeCard("form", title: "Form Analysis", desc: "Approach & swing. Film you from any angle", symbol: "figure.bowling")
        }
    }

    private func modeCard(_ value: String, title: String, desc: String, symbol: String) -> some View {
        let selected = model.captureMode == value
        return Button { model.captureMode = value } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.lsTitle3).foregroundStyle(selected ? LS.blue : LS.textSecondary)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.lsHeadline).foregroundStyle(LS.textPrimary)
                    Text(desc).font(.lsCaption).foregroundStyle(LS.textSecondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? LS.blue : LS.textFaint)
            }
            .lsCard()
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? LS.blue : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// Target boards for this shot (optional). Collected here, BEFORE capture — not on the camera.
    /// The pipeline sends these as model intent; without them Accuracy is skipped for the shot.
    private var intentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR TARGET FOR THIS SHOT (OPTIONAL)").lsEyebrow()
            HStack(spacing: 8) {
                intentField("Feet", text: $model.feetBoardText)
                intentField("Arrows", text: $model.arrowsBoardText)
                intentField("Breakpoint", text: $model.breakpointBoardText)
            }
            Text("Set where you're aiming. Leave blank to skip Accuracy on this shot.")
                .font(.lsCaption2).foregroundStyle(LS.textFaint)
        }
        .lsCard()
    }

    private func intentField(_ title: String, text: Binding<String>) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.lsCaption2).foregroundStyle(LS.textSecondary)
            TextField("—", text: text)
                .keyboardType(.decimalPad).multilineTextAlignment(.center)
                .foregroundStyle(LS.textPrimary)
                .padding(10).frame(maxWidth: .infinity, minHeight: 44)
                .background(LS.bg, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStroke))
        }
    }

    private var ballSection: some View {
        NavigationLink { AddBallView() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current ball").font(.lsHeadline).foregroundStyle(LS.textPrimary)
                    Text(model.currentBallName ?? "Choose from catalog").font(.lsCaption)
                        .foregroundStyle(model.currentBallName == nil ? LS.textSecondary : LS.cyan)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.lsFootnote).foregroundStyle(LS.textFaint)
            }
            .lsCard()
        }
        .buttonStyle(.plain)
    }

    private var oilSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Oil pattern").font(.lsHeadline).foregroundStyle(LS.textPrimary)
            if oilPatterns.isEmpty {
                Text(oilLoadError ?? "No oil patterns in the library yet.")
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)
            } else {
                Menu {
                    ForEach(oilPatterns, id: \.identity) { p in
                        Button(p.name ?? "Unnamed") {
                            model.selectedOilPatternName = p.name
                            model.selectedOilPatternId = p.id
                        }
                    }
                } label: {
                    HStack {
                        Text(model.selectedOilPatternName ?? "Select a pattern")
                            .foregroundStyle(model.selectedOilPatternName == nil ? LS.textSecondary : LS.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.lsCaption).foregroundStyle(LS.textFaint)
                    }
                }
            }
        }
        .lsCard()
    }

    private var preflightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRE-FLIGHT CHECK").lsEyebrow()
            HStack(spacing: 8) {
                Image(systemName: healthOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(healthOK ? LS.measured : LS.bestEffort)
                Text(healthText ?? "Checking analysis host…").font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "camera.fill").foregroundStyle(LS.cyan)
                Text("Camera 1080p · \(model.preferredFPS) fps · SDR").font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
        }
        .lsCard()
    }

    private func loadOil() async {
        do { oilPatterns = try await model.makeClient().oilPatterns() }
        catch { oilLoadError = "Couldn't load oil patterns: \(error.localizedDescription)" }
    }

    private func loadHealth() async {
        let start = Date()
        do {
            let h = try await model.makeClient().health()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            healthText = "Analysis host reachable · \(ms) ms"
            healthOK = (h.status == "ok")
        } catch {
            healthText = "Host unreachable — you can still record; uploads will queue."
            healthOK = false
        }
    }

    private func startSession() async {
        starting = true
        startError = nil
        do {
            try await model.startLiveSession(mode: model.captureMode,
                                             lane: nil,
                                             oilPatternId: model.selectedOilPatternId)
            goCapture = true
        } catch { startError = error.localizedDescription }
        starting = false
    }
}
