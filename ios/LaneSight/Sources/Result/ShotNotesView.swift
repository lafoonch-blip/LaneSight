import SwiftUI

// MARK: - Your notes on this shot (Shot.dc.html / DEC-058 — design 3.6)
//
// Free-text + quick tags the bowler records about the shot, autosaved to the retained feedback store
// (`POST /feedback`, source "shot_note"). Autosave re-sends the SAME note id so the row updates in
// place. Tags toggle-save immediately; text saves shortly after typing stops. The footer reports an
// honest state: idle / "Saving…" / "Saved automatically · <time>" / an error if the save failed.
struct ShotNotesView: View {
    @EnvironmentObject var model: AppModel
    let shotId: String
    let isUpload: Bool

    /// The quick tags from the design (order preserved).
    private static let allTags = [
        "Hit my target", "Missed left", "Missed right", "Pocket",
        "Light", "High", "Felt good", "Pulled it",
    ]

    // One stable note id for this shot card instance → every autosave updates the same row.
    @State private var noteId = UUID().uuidString
    @State private var text = ""
    @State private var selectedTags: Set<String> = []

    private enum SaveState: Equatable { case idle, saving, saved(Date), failed(String) }
    @State private var saveState: SaveState = .idle
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your notes on this shot").font(.lsHeadline).foregroundStyle(LS.textPrimary)
            Text("What did you see and feel? Saved with this shot and compared with the measured results.")
                .font(.lsCaption).foregroundStyle(LS.textSecondary)

            tagsFlow

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("e.g. Felt late at the line, ball hooked early, looked light from where I stood")
                        .font(.lsBody).foregroundStyle(LS.textFaint)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.lsBody)
                    .foregroundStyle(LS.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 104)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .background(LS.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(LS.borderStrong, lineWidth: 1))
            .onChange(of: text) { _, _ in scheduleTextSave() }

            HStack {
                statusLabel
                Spacer()
                Text("Voice dictation works here").font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
        }
        .lsCard()
    }

    // MARK: tags

    private var tagsFlow: some View {
        FlowLayout(spacing: 8) {
            ForEach(Self.allTags, id: \.self) { tag in
                let on = selectedTags.contains(tag)
                Button {
                    if on { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                    save()     // tag changes save immediately
                } label: {
                    Text(tag)
                        .font(.lsCaption.weight(.semibold))
                        .foregroundStyle(LS.textPrimary)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(on ? LS.selected : LS.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? LS.action : LS.borderStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick tags, optional")
    }

    // MARK: save state line

    @ViewBuilder private var statusLabel: some View {
        switch saveState {
        case .idle:
            Text("Saved automatically").font(.lsCaption).foregroundStyle(LS.textSecondary)
        case .saving:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(LS.textSecondary)
                Text("Saving…").font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
        case .saved(let when):
            Label("Saved automatically · \(Self.timeFmt.string(from: when))", systemImage: "checkmark.circle.fill")
                .font(.lsCaption).foregroundStyle(LS.measured)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.lsCaption).foregroundStyle(LS.bestEffort).lineLimit(2)
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    // MARK: saving

    /// Debounce text edits; save ~1.1s after the bowler stops typing.
    private func scheduleTextSave() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            if Task.isCancelled { return }
            save()
        }
    }

    private func save() {
        // Nothing to persist yet (no text and no tags) → stay idle, don't create an empty row on open.
        if text.isEmpty && selectedTags.isEmpty { saveState = .idle; return }
        saveState = .saving
        let snapshotText = text
        let snapshotTags = Self.allTags.filter { selectedTags.contains($0) }   // stable order
        Task {
            do {
                try await ShotNoteClient(model: model)
                    .save(noteId: noteId, shotId: shotId, text: snapshotText, tags: snapshotTags, isUpload: isUpload)
                saveState = .saved(Date())
            } catch {
                saveState = .failed("Couldn't save — will retry when you edit again")
            }
        }
    }
}

// MARK: - Simple wrapping flow layout (for the quick-tag chips)

/// Minimal left-to-right wrapping layout so the quick tags wrap like the design's flex row. Uses the
/// SwiftUI `Layout` protocol; no external dependency.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxWidth {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxWidth {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            v.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
