import SwiftUI

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var lane: Int = 1
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
                laneSection
                ballSection
                oilSection
                preflightSection

                if let startError {
                    Text(startError).font(.caption).foregroundStyle(LS.bestEffort)
                }
                Button {
                    Task { await startSession() }
                } label: {
                    HStack { Text("Set up camera"); if starting { ProgressView().tint(.white) } }
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
                Image(systemName: symbol).font(.title3).foregroundStyle(selected ? LS.blue : LS.textSecondary)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(LS.textPrimary)
                    Text(desc).font(.caption).foregroundStyle(LS.textSecondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? LS.blue : LS.textFaint)
            }
            .lsCard()
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? LS.blue : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var laneSection: some View {
        HStack {
            Text("Lane").font(.headline).foregroundStyle(LS.textPrimary)
            Spacer()
            Stepper(value: $lane, in: 1...99) {
                Text("\(lane)").font(.title3.bold().monospacedDigit()).foregroundStyle(LS.textPrimary)
            }
            .labelsHidden().fixedSize()
            Text("\(lane)").font(.title3.bold().monospacedDigit()).foregroundStyle(LS.textPrimary)
                .frame(minWidth: 36)
        }
        .lsCard()
        .onChange(of: lane) { _, newValue in model.laneText = String(newValue) }
    }

    private var ballSection: some View {
        NavigationLink { AddBallView() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current ball").font(.headline).foregroundStyle(LS.textPrimary)
                    Text(model.currentBallName ?? "Choose from catalog").font(.caption)
                        .foregroundStyle(model.currentBallName == nil ? LS.textSecondary : LS.cyan)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(LS.textFaint)
            }
            .lsCard()
        }
        .buttonStyle(.plain)
    }

    private var oilSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Oil pattern").font(.headline).foregroundStyle(LS.textPrimary)
            if oilPatterns.isEmpty {
                Text(oilLoadError ?? "No oil patterns in the library yet.")
                    .font(.caption).foregroundStyle(LS.textSecondary)
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
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(LS.textFaint)
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
                Text(healthText ?? "Checking analysis host…").font(.caption).foregroundStyle(LS.textSecondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "camera.fill").foregroundStyle(LS.cyan)
                Text("Camera 1080p · up to 120 fps · SDR").font(.caption).foregroundStyle(LS.textSecondary)
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
                                             lane: String(lane),
                                             oilPatternId: model.selectedOilPatternId)
            goCapture = true
        } catch { startError = error.localizedDescription }
        starting = false
    }
}
