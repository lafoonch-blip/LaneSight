import SwiftUI

/// Live session screen (Session.dc.html). Live KPIs + per-shot rows from GET /sessions/{id}/shots with
/// upload/analyze/fail states. Rows poll while a shot is still analyzing. No fabricated KPIs — every
/// number is either a count or a mean of measured values from the live rows.
struct SessionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var rows: Loadable<[SessionShotRow]> = .idle
    @State private var showFeedback = false
    @State private var showSummary = false

    /// When set, the screen reviews a specific (usually ended) session read-only instead of the live one.
    var reviewSessionId: String? = nil
    /// Read-only review (design SessionReview / 6a): no Record / End, no live polling. Notes stay editable
    /// (they live on each shot card). Defaults to false → the normal live-session behavior.
    var readOnly: Bool = false

    private var effectiveSessionId: String? { reviewSessionId ?? model.activeSessionId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                kpis
                shotsSection
                Spacer(minLength: 8)
                if !readOnly {
                    Button("Record next shot") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("End session") { showFeedback = true }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.activeSessionId == nil)
                }
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle(readOnly ? "Session review" : "Live session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await pollLoop() }
        .refreshable { await load() }
        .sheet(isPresented: $showFeedback) {
            FeedbackView(onFinish: { endAndSummarize() })
                .environmentObject(model)
        }
        .fullScreenCover(isPresented: $showSummary) {
            SummaryView(summary: model.endSummary).environmentObject(model)
        }
    }

    private var currentRows: [SessionShotRow] {
        if case .loaded(let r) = rows { return r }
        return []
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Practice")
                    .font(.lsTitle3.bold()).foregroundStyle(LS.textPrimary)
                Text((model.captureMode == "form" ? "Form Analysis" : "Shot Analysis")
                     + (model.selectedOilPatternName.map { " · \($0)" } ?? ""))
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            Spacer()
            if !readOnly, model.activeSessionId != nil {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: 0xFF4D5E)).frame(width: 8, height: 8)
                    Text("LIVE").font(.lsCaption2.bold()).foregroundStyle(LS.textPrimary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(LS.raised, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    private var kpis: some View {
        let analyzed = currentRows.filter { $0.state == "analyzed" }
        let speeds = analyzed.compactMap { $0.metrics?.ball_speed }
        let avgSpeed = speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count)
        return HStack {
            KPITile(label: "Shots", value: "\(currentRows.count)")
            Divider().frame(height: 36).overlay(LS.cardStroke)
            KPITile(label: "Analyzed", value: "\(analyzed.count)")
            Divider().frame(height: 36).overlay(LS.cardStroke)
            KPITile(label: "Avg speed", value: avgSpeed.map(Fmt.number) ?? "—", unit: avgSpeed != nil ? "mph" : nil)
        }
        .lsCard()
    }

    private var shotsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SHOTS").lsEyebrow()
            LoadableView(state: rows, retry: { Task { await load() } }) { list in
                if list.isEmpty {
                    Text("No shots yet. Record a delivery and it shows up here as it uploads and analyzes.")
                        .font(.lsCaption).foregroundStyle(LS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).lsCard()
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(list.sorted { ($0.created_at ?? 0) > ($1.created_at ?? 0) }.enumerated()),
                                id: \.element.id) { idx, row in
                            ShotRow(row: row, number: list.count - idx)
                        }
                    }
                }
            }
        }
    }

    private func endAndSummarize() {
        Task {
            try? await model.endCurrentSession()
            showSummary = true
        }
    }

    // MARK: polling — refresh while any shot is still pending

    private func pollLoop() async {
        await load()
        if readOnly { return }                  // ended session → one load, no live polling
        while !Task.isCancelled {
            let pending = currentRows.contains { $0.state == "pending" }
            if !pending && !currentRows.isEmpty { break }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { break }
            await load()
        }
    }

    private func load() async {
        guard let sid = effectiveSessionId else { rows = .loaded([]); return }
        if case .loaded = rows {} else { rows = .loading }
        do { rows = .loaded(try await model.makeClient().sessionShots(sid)) }
        catch { rows = .failed(error.localizedDescription) }
    }
}

/// One row in the live session shot list. State drives the look: pending (uploading/analyzing),
/// analyzed (metrics + classification), failed (reason).
private struct ShotRow: View {
    let row: SessionShotRow
    let number: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)").font(.lsHeadline.monospacedDigit()).foregroundStyle(LS.textPrimary).frame(width: 24)
            switch row.state {
            case "analyzed": analyzed
            case "failed": failed
            default: pending
            }
        }
        .lsCard(padding: 12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
            row.state == "failed" ? LS.borderStrong : .clear, lineWidth: 1))
    }

    private var analyzed: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text((row.classification ?? "Analyzed").capitalized)
                    .font(.lsSubheadline.weight(.semibold)).foregroundStyle(LS.textPrimary)
                Text(metricLine).font(.lsCaption2).foregroundStyle(LS.textSecondary).lineLimit(1)
            }
            Spacer()
            if let src = row.source, src == "upload" {
                Text("UPLOAD").font(.lsCaption2.bold()).foregroundStyle(LS.cyan)
            }
        }
    }

    private var pending: some View {
        HStack(spacing: 10) {
            Text("Analyzing…").font(.lsSubheadline).foregroundStyle(LS.textPrimary)
            Spacer()
            ProgressView().tint(LS.cyan)
        }
    }

    private var failed: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Couldn't analyze").font(.lsSubheadline.weight(.semibold)).foregroundStyle(LS.textPrimary)
                Text("This shot didn't produce metrics.").font(.lsCaption2).foregroundStyle(LS.textPrimary)
            }
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(LS.bestEffort)
        }
    }

    private var metricLine: String {
        var parts: [String] = []
        if let s = row.metrics?.ball_speed { parts.append("\(Fmt.number(s)) mph") }
        if let r = row.metrics?.rev_rate { parts.append("\(Fmt.number(r)) rpm") }
        if let e = row.metrics?.entry_board { parts.append("entry \(Fmt.number(e))") }
        if let a = row.metrics?.entry_angle { parts.append("\(Fmt.number(a))°") }
        return parts.isEmpty ? "No measured metrics" : parts.joined(separator: " · ")
    }
}
