import SwiftUI

/// Lab (v3.7 Figma 407:3179): the Analyze entry cards (Shot / Form), the month-grouped Sessions list
/// (each card shows the session's mini rings from GET /sessions/{id}/summary), and the Uploads list
/// (standalone clip analyses — not in Stats or the Score). Every number is live.
struct LabView: View {
    @EnvironmentObject var model: AppModel
    // DEC-099: sessions, uploads AND each session card's rings load together (shared tab store).
    @EnvironmentObject var tabs: TabDataStore
    private var sessions: Loadable<[SessionRow]> { tabs.lab.sessions }
    private var uploads: Loadable<[UploadRow]> { tabs.lab.uploads }
    @State private var showUploadResult = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LSTabHeader(title: "Lab")
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        analyzeSection
                        if !tabs.labReady {
                            LSPageLoading()
                        } else {
                            sessionsSection
                            uploadsSection
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(16)
                }
                .task { await loadAll() }
                .refreshable { await loadAll() }
            }
            .background(LSBackground())
            .navigationBarHidden(true)
            .sheet(isPresented: $showUploadResult) {
                if let result = model.result {
                    if result.isForm { FormCardView(result: result).environmentObject(model) }
                    else { ShotCardView(result: result).environmentObject(model) }
                }
            }
        }
    }

    // MARK: Analyze

    private var analyzeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analyze").font(.system(size: 20, weight: .bold)).foregroundStyle(LS.textPrimary)
                    Text("Pick Shot or Form, then record live or upload a video.")
                        .font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                }
                Spacer()
            }
            AnalyzeCards()
        }
    }

    // MARK: Sessions (month-grouped)

    private struct MonthGroup: Identifiable { let id: String; let rows: [SessionRow] }

    private func grouped(_ rows: [SessionRow]) -> [MonthGroup] {
        let sorted = rows.sorted { ($0.started_at ?? 0) > ($1.started_at ?? 0) }
        var order: [String] = []
        var map: [String: [SessionRow]] = [:]
        for s in sorted {
            let key = monthKey(s.started_at)
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(s)
        }
        return order.map { MonthGroup(id: $0, rows: map[$0] ?? []) }
    }
    private func monthKey(_ t: Double?) -> String {
        guard let t else { return "Earlier" }
        return Date(timeIntervalSince1970: t).formatted(.dateTime.month(.wide).year()).uppercased()
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sessions").font(.system(size: 20, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
                Text("Practice only").font(.system(size: 11, weight: .medium)).foregroundStyle(LS.link)
            }
            LoadableView(state: sessions, retry: { Task { await loadAll() } }) { rows in
                if rows.isEmpty {
                    Text("No sessions yet. Start a live session and it shows up here.")
                        .font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(grouped(rows)) { g in
                            Text(g.id).font(.system(size: 11, weight: .semibold)).tracking(0.5)
                                .foregroundStyle(LS.textSecondary).padding(.top, 4)
                            ForEach(g.rows) { s in
                                NavigationLink { SessionView(reviewSessionId: s.id, readOnly: true) } label: {
                                    LabSessionCard(session: s, prefetched: tabs.lab.summaries[s.id])
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Uploads

    private var uploadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Uploads").font(.system(size: 20, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
                Text("Not in Stats or Score").font(.system(size: 11, weight: .medium)).foregroundStyle(LS.link)
            }
            Text("Quick analysis of a single video. Start a session to track your progress over time.")
                .font(.system(size: 12)).foregroundStyle(LS.textSecondary).fixedSize(horizontal: false, vertical: true)
            LoadableView(state: uploads, retry: { Task { await loadAll() } }) { rows in
                if rows.isEmpty {
                    Text("No uploads yet. Analyze a clip from Photos to see it here.")
                        .font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
                } else {
                    VStack(spacing: 10) {
                        ForEach(rows) { row in
                            if row.isFailed {
                                // No result to open; offer a fresh analyze run (the clip isn't kept server-side).
                                NavigationLink { UploadView(mode: row.capture_mode == "form" ? "form" : "shot") } label: { UploadRowCard(upload: row) }
                                    .buttonStyle(.plain)
                            } else if row.isAnalyzing {
                                UploadRowCard(upload: row)      // in-flight — nothing to open yet
                            } else {
                                Button {
                                    Task { if await model.loadShotResult(shotId: row.id, captureModeHint: row.capture_mode) { showUploadResult = true } }
                                } label: { UploadRowCard(upload: row) }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadAll() async { await tabs.load(.lab, model: model) }
}

/// A Lab session card: flame glyph + "Practice Session" + date · pattern + N shots, with the session's
/// four mini rings. The rings + shot count come from GET /sessions/{id}/summary, fetched lazily when the
/// card appears. Accuracy needs per-shot targets → "—" when they weren't set.
struct LabSessionCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tabs: TabDataStore
    let session: SessionRow
    /// DEC-099: rings fetched with the Lab page (nil for cards beyond the prefetched set → fetched here once).
    var prefetched: SessionSummary? = nil
    @State private var fetched: SessionSummary?
    private var summary: SessionSummary? { prefetched ?? fetched }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().fill(LS.success.opacity(0.14)).frame(width: 34, height: 34)
                    Image(systemName: "flame.fill").font(.system(size: 15)).foregroundStyle(LS.success)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.mode == "form" ? "Form Session" : "Practice Session")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(LS.textPrimary)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(LS.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(summary?.n_shots.map(String.init) ?? "—")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(LS.textPrimary)
                    Text("shots").font(.system(size: 10)).foregroundStyle(LS.textSecondary)
                }
                Text("›").font(.system(size: 18)).foregroundStyle(LS.textSecondary)
            }
            HStack(alignment: .top, spacing: 6) {
                ring("Rev Rate", summary?.mean("rev_rate"), unit: "rpm", lo: 100, hi: 600, color: LS.dataPurple)
                ring("Speed", summary?.mean("ball_speed"), unit: "mph", lo: 8, hi: 24, color: LS.action)
                ring("Accuracy", nil, unit: "%", lo: 0, hi: 100, color: LS.success)
                ring("Consistency", summary?.consistency?.repeatability_score, unit: "%", lo: 0, hi: 100, color: LS.dataYellow)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
        .task {
            guard prefetched == nil, fetched == nil else { return }
            if let s = try? await model.makeClient().sessionSummary(session.id) {
                fetched = s
                tabs.storeSummary(s, for: session.id)
            }
        }
    }

    private var subtitle: String {
        session.started_at.map { Date(timeIntervalSince1970: $0).formatted(.dateTime.month().day().year()) } ?? "—"
    }

    private func ring(_ label: String, _ value: Double?, unit: String, lo: Double, hi: Double, color: Color) -> some View {
        let valueStr = value.map { String(format: $0 >= 100 ? "%.0f" : "%.1f", $0) } ?? "—"
        return MetricRing(label: label, value: valueStr, unit: value == nil ? "" : unit,
                          fraction: value.map { ($0 - lo) / (hi - lo) } ?? 0, color: color)
    }
}

/// One Lab › Uploads row (v3.7): date + shot/form summary, a SHOT/FORM chip and a chevron. The original
/// filename isn't stored server-side, so the row leads with "Upload · {date}".
struct UploadRowCard: View {
    let upload: UploadRow

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(LS.textPrimary)
                Text(subtitle).font(.system(size: 11))
                    .foregroundStyle(upload.isFailed ? LS.bestEffort : LS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    @ViewBuilder private var trailing: some View {
        if upload.isAnalyzing {
            ProgressView().tint(LS.textSecondary)
        } else if upload.isFailed {
            Text("Retry").font(.system(size: 11, weight: .semibold)).foregroundStyle(LS.link)
            Text("›").font(.system(size: 18)).foregroundStyle(LS.textSecondary)
        } else {
            Text(isForm ? "FORM" : "SHOT")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(LS.link)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(LS.link.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            Text("›").font(.system(size: 18)).foregroundStyle(LS.textSecondary)
        }
    }

    private var isForm: Bool { upload.capture_mode == "form" }
    private var title: String {
        let date = upload.created_at.map { " · " + Date(timeIntervalSince1970: $0).formatted(.dateTime.month().day()) } ?? ""
        if upload.isFailed { return (upload.failure_title ?? "Couldn't analyze") + date }
        return "Upload\(date)"
    }
    private var subtitle: String {
        if upload.isAnalyzing { return "Analyzing…" }
        // DEC-086: failed rows show the server's friendly, actionable copy (never a raw code).
        if upload.isFailed { return upload.failure_message ?? "We couldn't analyze this clip. Tap to try another." }
        if isForm { return "Form Analysis · 1 delivery" }
        var parts = ["Shot Analysis"]
        if let sp = upload.metrics?.ball_speed { parts.append(String(format: "%.1f mph", sp)) }
        if let eb = upload.metrics?.entry_board { parts.append("entry \(Int(eb.rounded()))") }
        return parts.joined(separator: " · ")
    }
}
