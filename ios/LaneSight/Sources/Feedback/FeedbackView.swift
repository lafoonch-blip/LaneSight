import SwiftUI

/// Session feedback sheet (Feedback.dc.html). Shown at session end before the summary.
/// Rating + tags + free text + diagnostics (on by default). Skip is allowed.
struct FeedbackView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let onFinish: () -> Void

    @State private var rating = 0
    @State private var selectedTags: Set<String> = []
    @State private var text = ""
    @State private var diagnostics = true
    @State private var submitting = false
    @State private var error: String?

    private let tags = ["Bug", "Metric looked wrong", "Advice", "Camera / upload", "Workflow", "Idea"]
    private let ratingWords = ["", "Rough", "Meh", "OK", "Good", "Great"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("How was this session in the app?")
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(LS.textPrimary)

                    // Numbered 1–5 rating circles (v3.7), with Rough / Great anchors.
                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            ForEach(1...5, id: \.self) { i in
                                Button { rating = i } label: {
                                    Text("\(i)")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(i == rating ? LS.onAction : LS.textPrimary)
                                        .frame(maxWidth: .infinity).frame(height: 56)
                                        .background(i == rating ? LS.action : LS.card, in: RoundedRectangle(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(i == rating ? .clear : LS.cardStrokeBright, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(i) of 5\(i == rating ? ", selected" : "")")
                            }
                        }
                        HStack {
                            Text("Rough").font(.system(size: 11)).foregroundStyle(LS.textSecondary)
                            Spacer()
                            Text("Great").font(.system(size: 11)).foregroundStyle(LS.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's this about? (pick any)")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(LS.textPrimary)
                        FlowTags(tags: tags, selected: $selectedTags)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("FEEDBACK, BUGS OR OBSERVATIONS").lsEyebrow()
                        TextField("Optional", text: $text, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(10)
                            .background(LS.card, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(LS.textPrimary)
                    }

                    Toggle("Attach session diagnostics (timings, errors, versions)", isOn: $diagnostics)
                        .font(.lsCallout).foregroundStyle(LS.textPrimary).tint(LS.blue)

                    if let error { Text(error).font(.lsCaption).foregroundStyle(LS.bestEffort) }

                    Button {
                        Task { await submit(skip: false) }
                    } label: {
                        HStack { Text("Submit"); if submitting { ProgressView().tint(.white) } }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(submitting || rating == 0)

                    Button("Skip") { Task { await submit(skip: true) } }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(submitting)
                }
                .padding(16)
            }
            .background(LSBackground())
            .navigationTitle("Session feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func submit(skip: Bool) async {
        submitting = true
        error = nil
        do {
            if !skip {
                try await model.submitSessionFeedback(rating: rating, tags: Array(selectedTags),
                                                      text: text, diagnostics: diagnostics)
            }
            dismiss()
            onFinish()
        } catch {
            self.error = error.localizedDescription
        }
        submitting = false
    }
}

/// Simple wrapping tag selector.
struct FlowTags: View {
    let tags: [String]
    @Binding var selected: Set<String>

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                let on = selected.contains(tag)
                Button {
                    if on { selected.remove(tag) } else { selected.insert(tag) }
                } label: {
                    Text(tag).font(.lsCaption).foregroundStyle(on ? .white : LS.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(on ? LS.blue : Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
