import SwiftUI

/// Session summary (Summary.dc.html), shown after End → Feedback. Uses the real end-session
/// response (shot count + score brief). Fields the API doesn't return are simply omitted.
struct SummaryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let summary: EndSessionResponse?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SESSION COMPLETE").lsEyebrow()
                    Text("Practice" + (model.laneText.isEmpty ? "" : " · Lane \(model.laneText)"))
                        .font(.title2.bold()).foregroundStyle(LS.textPrimary)
                    if let n = summary?.shots {
                        Text("\(n) shot\(n == 1 ? "" : "s")").font(.callout).foregroundStyle(LS.textSecondary)
                    }
                }

                if let score = summary?.score {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LANESIGHT SCORE · BETA").lsEyebrow()
                        if score.eligible == true, let v = score.score {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(String(Int(v.rounded())))
                                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                                    .foregroundStyle(LS.textPrimary)
                                if let tier = score.tier {
                                    Text(tier.uppercased()).font(.subheadline.bold()).foregroundStyle(LS.cyan)
                                }
                            }
                        } else {
                            Label("Still building your score", systemImage: "hourglass")
                                .font(.callout).foregroundStyle(LS.textSecondary)
                        }
                    }
                    .lsCard()
                }

                Text("Full per-session KPIs and lane-transition detail arrive with the stats endpoints in a later slice.")
                    .font(.caption).foregroundStyle(LS.textFaint)

                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LSBackground())
    }
}
