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

    private let tags = ["Analysis accuracy", "Camera/framing", "Upload speed", "Advice quality", "App bug", "Other"]
    private let ratingWords = ["", "Rough", "Meh", "OK", "Good", "Great"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("How was this session in the app?").font(.lsTitle3.bold()).foregroundStyle(LS.textPrimary)

                    HStack {
                        Text("Rough").font(.lsCaption).foregroundStyle(LS.textSecondary)
                        Spacer()
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= rating ? "star.fill" : "star")
                                .font(.lsTitle2).foregroundStyle(LS.bestEffort)
                                .onTapGesture { rating = i }
                                .accessibilityLabel("\(i) star")
                        }
                        Spacer()
                        Text("Great").font(.lsCaption).foregroundStyle(LS.textSecondary)
                    }
                    if rating > 0 {
                        Text(ratingWords[rating]).font(.lsCaption).foregroundStyle(LS.cyan)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHAT'S THIS ABOUT? (PICK ANY)").lsEyebrow()
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
