import SwiftUI

/// Setup · Shot (v3.7 Figma 411:3491). The pre-shot screen: an optional board target (3 compact
/// steppers), the current ball + oil pattern, a "Ready to bowl" summary and the honest pre-flight
/// checks, then Start session. The target carries forward between shots; leaving it blank skips
/// Accuracy for the shot. Form setup shows only the pre-flight + Start (no lane target/ball/oil).
struct SetupView: View {
    @EnvironmentObject var model: AppModel
    /// Pre-selects the capture mode when opened from Lab / Home (nil = leave as-is).
    var initialMode: String? = nil
    @State private var oilPatterns: [OilPattern] = []
    @State private var oilLoadError: String?
    @State private var healthMs: Int?
    @State private var healthOK = false
    @State private var starting = false
    @State private var startError: String?
    @State private var goCapture = false
    @State private var showBallSheet = false
    @State private var showOilSheet = false

    private var isShot: Bool { model.captureMode == "shot" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isShot {
                    targetSection
                    ballAndOilSection
                } else {
                    cameraViewCard
                }
                if healthOK { readyCard }
                preflightSection
                if isShot {
                    Text("The target carries forward between shots. Change it here or on the session screen. Leave it blank to skip Accuracy.")
                        .font(.system(size: 12)).foregroundStyle(Color(hex: 0xBFCBDD))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let startError {
                    Text(startError).font(.system(size: 12)).foregroundStyle(LS.bestEffort)
                }
                Spacer(minLength: 8)
                Button { Task { await startSession() } } label: {
                    HStack(spacing: 10) {
                        Text("Start session")
                        if starting { ProgressView().tint(LS.onAction) }
                        else { Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold)) }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(starting)
            }
            .padding(17)
        }
        .background(LSBackground())
        .navigationTitle(isShot ? "Shot Analysis" : "Form Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $goCapture) { CaptureView() }
        .onAppear { if let initialMode { model.captureMode = initialMode } }
        .task {
            await loadOil()
            await loadHealth()
            #if DEBUG
            switch ProcessInfo.processInfo.environment["LS_PREVIEW_SHEET"] {
            case "ball": showBallSheet = true
            case "oil":  showOilSheet = true
            default: break
            }
            #endif
        }
    }

    // MARK: Target (3 compact steppers)

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Your target (optional)", action: anyTargetSet ? "Clear" : nil) { clearTarget() }
            HStack(spacing: 10) {
                TargetStepper(label: "FEET", value: boardBinding($model.feetBoardText), start: 25, range: 1...60)
                TargetStepper(label: "ARROWS", value: boardBinding($model.arrowsBoardText), start: 15, range: 1...39)
                TargetStepper(label: "BREAKPOINT", value: boardBinding($model.breakpointBoardText), start: 7, range: 1...39)
            }
        }
    }

    private var anyTargetSet: Bool {
        [model.feetBoardText, model.arrowsBoardText, model.breakpointBoardText].contains { !$0.isEmpty }
    }
    private func clearTarget() {
        model.feetBoardText = ""; model.arrowsBoardText = ""; model.breakpointBoardText = ""
    }

    /// Bridges a stored "25"/"" text field to an optional Int the stepper edits.
    private func boardBinding(_ text: Binding<String>) -> Binding<Int?> {
        Binding(
            get: { Int(text.wrappedValue.trimmingCharacters(in: .whitespaces)) },
            set: { text.wrappedValue = $0.map(String.init) ?? "" }
        )
    }

    // MARK: Ball and oil

    private var ballAndOilSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Ball and oil", action: "From your last session") { loadFromLastSession() }
            Button { showBallSheet = true } label: { rowCard(title: ballTitle, subtitle: ballSubtitle) }
                .buttonStyle(.plain)
            oilRow
        }
        .sheet(isPresented: $showBallSheet) {
            NavigationStack { BallPickerSheet() }.environmentObject(model).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showOilSheet) {
            OilPatternSheet(patterns: oilPatterns,
                            selectedName: $model.selectedOilPatternName, selectedId: $model.selectedOilPatternId)
                .presentationDetents([.medium, .large])
        }
    }

    private var ballTitle: String { model.currentBall?.displayName ?? model.currentBallName ?? "Current ball" }
    private var ballSubtitle: String {
        guard let b = model.currentBall else { return "Tap to choose from your arsenal" }
        let parts = [b.surface, b.weight_lb.map { "\(Int($0.rounded())) lb" }].compactMap { $0 }
        return parts.isEmpty ? "Current ball" : parts.joined(separator: " · ")
    }

    @ViewBuilder private var oilRow: some View {
        if oilPatterns.isEmpty {
            rowCard(title: "Oil pattern", subtitle: oilLoadError ?? "No patterns in the library yet", chevron: false)
        } else {
            Button { showOilSheet = true } label: {
                rowCard(title: "Oil pattern · \(model.selectedOilPatternName ?? "Choose")", subtitle: oilSubtitle)
            }
            .buttonStyle(.plain)
        }
    }

    private var oilSubtitle: String {
        guard let name = model.selectedOilPatternName,
              let p = oilPatterns.first(where: { $0.name == name }) else { return "Tap to select a pattern" }
        let parts = [p.length.map { "~\(Int($0.rounded())) ft" }, p.source].compactMap { $0 }
        return parts.isEmpty ? "Selected" : parts.joined(separator: " · ")
    }

    // MARK: Camera view (Form) — guidance on which angle to film from (Figma 411:3583)

    private var cameraViewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera view").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            Text("Film from the side or from behind. LaneSight detects which one and shows the metrics that view supports.")
                .font(.system(size: 12)).foregroundStyle(Color(hex: 0xB9C6D9)).fixedSize(horizontal: false, vertical: true)
            viewTip("Side view · best for timing and posture",
                    "1.5–2.5 lanes away, phone at hip height, last two steps and the foul line in frame.")
            viewTip("From behind · best for drift and swing line",
                    "4–6 m back, phone at chest height, whole approach in frame.")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0x04213F), Color(hex: 0x031B35)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.heroStroke, lineWidth: 1))
    }

    private func viewTip(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(LS.link)
            Text(detail).font(.system(size: 12)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Ready + pre-flight

    private var readyCard: some View {
        HStack(spacing: 10) {
            Circle().fill(LS.positive).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Ready to bowl").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Text("Camera, connection and analysis service checked.")
                    .font(.system(size: 11)).foregroundStyle(Color(hex: 0xB9C6D9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.positive.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.positive.opacity(0.6), lineWidth: 1))
    }

    private var preflightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Pre-flight check", action: nil) {}
            VStack(alignment: .leading, spacing: 10) {
                checkRow(ok: healthOK, title: "Analysis service reachable",
                         detail: healthMs.map { "\($0) ms · first result ~1 min" } ?? "Checking…")
                checkRow(ok: true, title: "Camera", detail: "\(model.preferredFPS) fps · SDR")
                checkRow(ok: healthOK, title: healthOK ? "Connected" : "Cellular only",
                         detail: healthOK ? "Uploads send now" : "Uploads may queue")
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LS.border, lineWidth: 1))
        }
    }

    private func checkRow(ok: Bool, title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill((ok ? LS.positive : LS.dataYellow).opacity(0.18))
                    .frame(width: 16, height: 16)
                Text(ok ? "✓" : "!").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ok ? LS.positive : LS.dataYellow)
            }
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            Spacer(minLength: 8)
            Text(detail).font(.system(size: 11)).foregroundStyle(Color(hex: 0xB9C6D9))
        }
    }

    // MARK: shared bits

    private func sectionHeading(_ title: String, action: String?, _ tap: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            if let action {
                Button(action: tap) {
                    Text(action).font(.system(size: 11, weight: .medium)).foregroundStyle(LS.link)
                }
            }
        }
    }

    private func rowCard(title: String, subtitle: String, chevron: Bool = true) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Color(hex: 0xB9C6D9)).lineLimit(1)
            }
            Spacer(minLength: 8)
            if chevron { Text("›").font(.system(size: 20)).foregroundStyle(.white) }
        }
        .padding(.horizontal, 16).frame(height: 72)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private func loadFromLastSession() { Task { await applyLastSetup() } }

    /// "From your last session" (MVP-09): pull the ball / oil / target from GET /me/last-setup into Setup.
    private func applyLastSetup() async {
        guard let ls = try? await model.makeClient().lastSetup() else { return }
        if let bid = ls.user_ball_id { try? await model.setCurrentBall(id: bid) }
        if let oid = ls.oil_pattern_id {
            model.selectedOilPatternId = oid
            model.selectedOilPatternName = oilPatterns.first(where: { $0.id == oid })?.name
        }
        if let it = ls.intent {
            func board(_ v: Double?) -> String { v.map { String(Int($0.rounded())) } ?? "" }
            model.feetBoardText = board(it.feet_board)
            model.arrowsBoardText = board(it.arrows_board)
            model.breakpointBoardText = board(it.breakpoint_board)
        }
    }

    // MARK: data

    private func loadOil() async {
        do { oilPatterns = try await model.makeClient().oilPatterns() }
        catch { oilLoadError = "Couldn't load patterns" }
    }

    private func loadHealth() async {
        let start = Date()
        do {
            let h = try await model.makeClient().health()
            healthMs = Int(Date().timeIntervalSince(start) * 1000)
            healthOK = (h.status == "ok")
        } catch {
            healthMs = nil
            healthOK = false
        }
    }

    private func startSession() async {
        starting = true; startError = nil
        do {
            try await model.startLiveSession(mode: model.captureMode, lane: nil,
                                             oilPatternId: model.selectedOilPatternId)
            goCapture = true
        } catch { startError = error.localizedDescription }
        starting = false
    }
}

/// A compact FEET / ARROWS / BREAKPOINT board stepper: label on top, − value + below. Edits an optional
/// Int; blank shows "—" and the first +/- seeds a sensible starting board. Matches Figma 411:3514.
/// Shared by Setup and the Active Session target block.
struct TargetStepper: View {
    let label: String
    @Binding var value: Int?
    let start: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(Color(hex: 0xD0DEEC))
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 2) {
                chip("−") { step(-1) }
                Text(value.map(String.init) ?? "—")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                chip("+") { step(1) }
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LS.border, lineWidth: 1))
    }

    private func chip(_ glyph: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(glyph).font(.system(size: 20)).foregroundStyle(.white)
                .frame(width: 28, height: 30)
                .background(LS.raised, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func step(_ delta: Int) {
        let next = (value ?? start - delta) + delta       // first tap lands on `start`
        value = min(range.upperBound, max(range.lowerBound, next))
    }
}
