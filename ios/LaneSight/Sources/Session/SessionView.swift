import SwiftUI

/// Live session screen. Per-shot rows aren't yet exposed by the API (no list-shots endpoint in this
/// slice), so we show the live counters we hold in-app and the end-of-session flow. No fabricated KPIs.
struct SessionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showFeedback = false
    @State private var showSummary = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                kpis
                shotsNote
                Spacer(minLength: 8)
                Button("Record next shot") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("End session") { showFeedback = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.activeSessionId == nil)
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Live session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showFeedback) {
            FeedbackView(onFinish: { endAndSummarize() })
                .environmentObject(model)
        }
        .fullScreenCover(isPresented: $showSummary) {
            SummaryView(summary: model.endSummary)
                .environmentObject(model)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Practice" + (model.laneText.isEmpty ? "" : " · Lane \(model.laneText)"))
                .font(.title3.bold()).foregroundStyle(LS.textPrimary)
            Text((model.captureMode == "form" ? "Form Analysis" : "Shot Analysis")
                 + (model.selectedOilPatternName.map { " · \($0)" } ?? ""))
                .font(.caption).foregroundStyle(LS.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    private var kpis: some View {
        HStack {
            KPITile(label: "Shots", value: "\(model.shotCount)")
            Divider().frame(height: 36).overlay(LS.cardStroke)
            KPITile(label: "Mode", value: model.captureMode == "form" ? "Form" : "Shot")
        }
        .lsCard()
    }

    private var shotsNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SHOTS").lsEyebrow()
            Text("Each shot's full result (metrics, status and the sensor question) opens right after you record it. A per-shot session list is coming in a later slice.")
                .font(.caption).foregroundStyle(LS.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    private func endAndSummarize() {
        Task {
            try? await model.endCurrentSession()
            showSummary = true
        }
    }
}
