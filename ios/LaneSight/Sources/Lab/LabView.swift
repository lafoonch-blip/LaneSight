import SwiftUI

struct LabView: View {
    @EnvironmentObject var model: AppModel
    @State private var sessions: Loadable<[SessionRow]> = .idle
    @State private var uploads: Loadable<[UploadRow]> = .idle
    @State private var showUploadResult = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LSTabHeader(title: "Lab")
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        NavigationLink { SetupView() } label: {
                            actionTile("Start Live Session", "Shot or Form · record each delivery",
                                       symbol: "record.circle", tint: LS.blue)
                        }

                        NavigationLink { UploadView() } label: {
                            actionTile("Upload Video", "Analyze a clip from Photos",
                                       symbol: "square.and.arrow.up", tint: LS.cyan)
                        }

                        // Disabled per design — must not open an empty view (App Review).
                        actionTile("Compare to a PBA Pro", "COMING SOON", symbol: "person.2.fill", tint: LS.textFaint)
                            .opacity(0.5)

                        sessionsList
                        uploadsList
                        Spacer(minLength: 8)
                    }
                    .padding(16)
                }
                .task { await loadAll() }
                .refreshable { await loadAll() }
            }
            .background(LSBackground())
            .navigationBarHidden(true)
            // A tapped upload row opens its shot result (DEC-055), same card the pipeline presents.
            .sheet(isPresented: $showUploadResult) {
                if let result = model.result {
                    if result.isForm {
                        FormCardView(result: result).environmentObject(model)
                    } else {
                        ShotCardView(result: result).environmentObject(model)
                    }
                }
            }
        }
    }

    private func actionTile(_ title: String, _ subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.lsTitle2).foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.lsHeadline).foregroundStyle(LS.textPrimary)
                Text(subtitle).font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.lsFootnote).foregroundStyle(LS.textFaint)
        }
        .lsCard()
    }

    private var sessionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SESSIONS").lsEyebrow()
            LoadableView(state: sessions, retry: { Task { await loadSessions() } }) { rows in
                if rows.isEmpty {
                    Text("No sessions yet.").font(.lsCallout).foregroundStyle(LS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).lsCard()
                } else {
                    VStack(spacing: 10) {
                        ForEach(rows.sorted(by: { ($0.started_at ?? 0) > ($1.started_at ?? 0) })) { s in
                            SessionRowCard(session: s)
                        }
                    }
                }
            }
        }
    }

    /// Lab › Uploads (DEC-055): standalone upload analyses, below Sessions. Each row opens its result.
    /// Not in Stats or the LaneSight Score.
    private var uploadsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("UPLOADS").lsEyebrow()
                Spacer()
                Text("Not in Stats or Score").font(.lsCaption2).foregroundStyle(LS.textFaint)
            }
            LoadableView(state: uploads, retry: { Task { await loadUploads() } }) { rows in
                if rows.isEmpty {
                    Text("No uploads yet. Analyze a clip from Photos to see it here.")
                        .font(.lsCallout).foregroundStyle(LS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).lsCard()
                } else {
                    VStack(spacing: 10) {
                        ForEach(rows) { row in
                            Button {
                                Task { if await model.loadShotResult(shotId: row.id, captureModeHint: row.capture_mode) { showUploadResult = true } }
                            } label: {
                                UploadRowCard(upload: row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func loadAll() async {
        await loadSessions()
        await loadUploads()
    }

    private func loadSessions() async {
        sessions = .loading
        do {
            sessions = .loaded(try await model.makeClient().listSessions())
        } catch { sessions = .failed(error.localizedDescription) }
    }

    private func loadUploads() async {
        uploads = .loading
        do {
            uploads = .loaded(try await model.makeClient().listUploads())
        } catch { uploads = .failed(error.localizedDescription) }
    }
}

/// One Lab › Uploads row (Lab.dc.html): date + shot summary on the left, a SHOT/FORM badge on the right.
struct UploadRowCard: View {
    let upload: UploadRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.lsSubheadline.bold()).foregroundStyle(LS.textPrimary)
                Text(subtitle).font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            Spacer()
            Text(isForm ? "FORM" : "SHOT")
                .font(.lsCaption2.bold()).foregroundStyle(LS.blue)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(LS.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
        .lsCard(padding: 12)
    }

    private var isForm: Bool { upload.capture_mode == "form" }

    private var title: String {
        var s = "Upload"
        if let t = upload.created_at {
            s += " · " + Date(timeIntervalSince1970: t).formatted(.dateTime.month().day())
        }
        return s
    }

    private var subtitle: String {
        switch upload.state {
        case "pending": return "Analyzing…"
        case "failed":  return "Analysis didn't complete"
        default: break
        }
        if isForm { return "1 delivery" }
        var parts = ["1 shot"]
        if let sp = upload.metrics?.ball_speed { parts.append(String(format: "%.1f mph", sp)) }
        if let eb = upload.metrics?.entry_board { parts.append("entry \(Int(eb.rounded()))") }
        return parts.joined(separator: " · ")
    }
}
