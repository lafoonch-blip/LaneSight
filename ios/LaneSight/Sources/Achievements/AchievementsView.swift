import SwiftUI

/// Achievements (Achievements.dc.html). Real data from GET /me/achievements: showcase (pinned),
/// close-to-unlocking, category filter, the full grouped list, and a "Coming later" group. Pin/unpin
/// writes through PUT /me/achievements/pins. Nothing is faked — a not-trackable achievement says so
/// with its reason, never 0% or a guess.
struct AchievementsView: View {
    @EnvironmentObject var model: AppModel
    @State private var state: Loadable<AchievementsResponse> = .idle
    @State private var pins: [AchievementPin] = []
    @State private var selectedCategory: String? = nil   // nil = All
    @State private var pinError: String?

    var body: some View {
        ScrollView {
            LoadableView(state: state, retry: { Task { await load() } }) { data in
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ACHIEVEMENTS").font(.system(size: 11, weight: .semibold)).tracking(1.1).foregroundStyle(LS.link)
                        Text("Your achievements").font(.system(size: 24, weight: .bold)).foregroundStyle(LS.textPrimary)
                    }
                    headerCard(data)
                    showcaseSection(data)
                    closeToUnlocking(data)
                    if let pinError {
                        Text(pinError).font(.lsCaption).foregroundStyle(LS.bestEffort)
                    }
                    categoryChips(data)
                    activeList(data)
                    comingLaterCard(data)
                }
                .padding(16)
            }
        }
        .background(LSBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .lsHidesTabBar()      // DEC-099: only Home · Stats · Lab · Coaching show the tab bar
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: sections

    private func headerCard(_ data: AchievementsResponse) -> some View {
        let unlocked = data.unlocked_count ?? 0
        let total = activeTotal(data)
        let frac = total > 0 ? Double(unlocked) / Double(total) : 0
        return HStack(spacing: 14) {
            Image(systemName: "rosette").font(.system(size: 40)).foregroundStyle(LS.bestEffort)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(unlocked)").font(.lsRoboto(32, weight: .bold)).foregroundStyle(LS.textPrimary)
                    Text("/ \(total) unlocked").font(.lsSubheadline).foregroundStyle(LS.textSecondary)
                }
                ProgressView(value: frac).tint(LS.cyan)
                Text("Active achievements you can earn in this build")
                    .font(.lsCaption2).foregroundStyle(LS.textSecondary)
            }
        }
        .lsCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(unlocked) of \(total) achievements unlocked")
    }

    @ViewBuilder private func showcaseSection(_ data: AchievementsResponse) -> some View {
        let showcase = pins.filter { ($0.kind ?? "showcase") == "showcase" }
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        if !showcase.isEmpty {
            Text("SHOWCASE").font(.lsCaption.weight(.semibold)).tracking(1.1).foregroundStyle(LS.cyan)
            HStack(spacing: 10) {
                ForEach(showcase) { pin in
                    if let ach = find(pin.achievement_id, in: data) {
                        VStack(spacing: 10) {
                            AchievementBadge(category: ach.category, unlocked: true, size: 52)
                            Text(ach.name ?? "").font(.lsCaption.bold()).foregroundStyle(LS.textPrimary)
                                .multilineTextAlignment(.center).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .lsCard(padding: 12)
                        .contextMenu {
                            Button("Unpin from showcase", role: .destructive) {
                                Task { await unpin(ach.id) }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func closeToUnlocking(_ data: AchievementsResponse) -> some View {
        let close = allActive(data)
            .filter { $0.progress_status == "in_progress" && ratio($0) != nil && (ratio($0) ?? 0) > 0 }
            .sorted { (ratio($0) ?? 0) > (ratio($1) ?? 0) }
            .prefix(3)
        if !close.isEmpty {
            Text("CLOSE TO UNLOCKING").font(.lsCaption.weight(.semibold)).tracking(1.1).foregroundStyle(LS.cyan)
            ForEach(Array(close)) { ach in
                NavigationLink { AchievementDetailView(achievementId: ach.id) } label: {
                    HStack(spacing: 12) {
                        AchievementBadge(category: ach.category, unlocked: false, size: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(ach.name ?? "").font(.lsSubheadline.bold()).foregroundStyle(LS.textPrimary)
                                if isPinned(ach.id) {
                                    Text("pinned").font(.lsCaption2).foregroundStyle(LS.textSecondary)
                                }
                            }
                            Text(progressText(ach)).font(.lsCaption).foregroundStyle(LS.textSecondary)
                            if let r = ratio(ach) {
                                ProgressView(value: r).tint(LS.cyan)
                            }
                        }
                    }
                    .lsCard(padding: 14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func categoryChips(_ data: AchievementsResponse) -> some View {
        let cats = (data.categories ?? [:]).keys.sorted()
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", category: nil)
                ForEach(cats, id: \.self) { c in
                    let counts = categoryCounts(data, c)
                    chip("\(c.capitalized) \(counts.0)/\(counts.1)", category: c)
                }
            }
        }
    }

    private func chip(_ label: String, category: String?) -> some View {
        let on = selectedCategory == category
        return Button { selectedCategory = category } label: {
            Text(label)
                .font(.lsCaption.weight(on ? .bold : .semibold))
                .foregroundStyle(on ? .white : LS.textSecondary)
                .padding(.horizontal, 12).frame(height: 36)
                .background(on ? LS.blue : LS.card, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : LS.cardStroke))
        }
        .buttonStyle(.plain)
    }

    private func activeList(_ data: AchievementsResponse) -> some View {
        let rows = allActive(data)
            .filter { selectedCategory == nil || $0.category == selectedCategory }
            .sorted { sortRank($0) < sortRank($1) }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, ach in
                NavigationLink { AchievementDetailView(achievementId: ach.id) } label: {
                    achievementRow(ach)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if ach.unlocked == true {
                        if isPinned(ach.id) {
                            Button("Unpin from showcase", role: .destructive) { Task { await unpin(ach.id) } }
                        } else {
                            Button("Pin to showcase") { Task { await pin(ach.id) } }
                        }
                    }
                }
                if idx != rows.count - 1 { Divider().overlay(LS.cardStroke).padding(.leading, 14) }
            }
        }
        .lsCard(padding: 0)
    }

    private func achievementRow(_ ach: Achievement) -> some View {
        HStack(spacing: 12) {
            statusDot(ach)
            VStack(alignment: .leading, spacing: 2) {
                Text(ach.name ?? "").font(.lsSubheadline.weight(.semibold)).foregroundStyle(LS.textPrimary)
                Text(ach.description ?? "").font(.lsCaption2).foregroundStyle(LS.textFaint).lineLimit(1)
            }
            Spacer()
            Text(progressText(ach))
                .font(.lsCaption).foregroundStyle(statusColor(ach))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ach.name ?? ""), \(statusLabel(ach)), \(progressText(ach))")
    }

    @ViewBuilder private func comingLaterCard(_ data: AchievementsResponse) -> some View {
        let later = allAchievements(data).filter { $0.status == "coming_later" }
        if !later.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Coming later · \(later.count)")
                    .font(.lsSubheadline.bold()).foregroundStyle(LS.textSecondary)
                Text("Game, series, strike and league achievements unlock once that data is available.")
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(LS.cardStroke))
        }
    }

    // MARK: status styling

    private func statusDot(_ ach: Achievement) -> some View {
        Group {
            switch ach.progress_status {
            case "unlocked":
                Circle().fill(LS.measured).frame(width: 10, height: 10)
            case "in_progress":
                Circle().fill(LS.cyan).frame(width: 10, height: 10)
            case "not_trackable":
                Circle().strokeBorder(LS.unavailable, style: StrokeStyle(lineWidth: 2, dash: [2]))
                    .frame(width: 10, height: 10)
            default:
                Circle().strokeBorder(LS.textFaint, lineWidth: 2).frame(width: 10, height: 10)
            }
        }
    }

    private func statusColor(_ ach: Achievement) -> Color {
        switch ach.progress_status {
        case "unlocked": return LS.measured
        case "not_trackable": return LS.unavailable
        default: return LS.textSecondary
        }
    }

    private func statusLabel(_ ach: Achievement) -> String {
        switch ach.progress_status {
        case "unlocked": return "unlocked"
        case "in_progress": return "in progress"
        case "not_trackable": return "not trackable yet"
        default: return "locked"
        }
    }

    // MARK: progress helpers (no fabricated numbers)

    private func ratio(_ ach: Achievement) -> Double? {
        guard let c = ach.current_value?.double, let t = ach.target_value?.double, t > 0 else { return nil }
        return min(max(c / t, 0), 1)
    }

    private func progressText(_ ach: Achievement) -> String {
        if ach.progress_status == "unlocked" { return "Unlocked" }
        if ach.progress_status == "not_trackable" {
            return ach.unavailable_reason ?? "Not trackable yet"
        }
        if ach.progress_status == "locked" && ach.current_value?.double == nil {
            // first-tier style: show the target tier name honestly
            if let t = ach.target_value?.display { return "Reach \(t.capitalized)" }
            return "Locked"
        }
        let isRatio = (ach.target_value?.double ?? 2) <= 1 && (ach.target_value?.double ?? 0) > 0
        let cur = ach.current_value
        let tgt = ach.target_value
        var head: String
        if isRatio, let c = cur?.double, let t = tgt?.double {
            head = "\(Int((c * 100).rounded()))% / \(Int((t * 100).rounded()))%"
        } else {
            head = "\(cur?.display ?? "0") / \(tgt?.display ?? "—")"
        }
        if let n = ach.sample_count { head += " · \(n) shots" }
        else if let q = ach.qualifying_count, q != Int(cur?.double ?? -1) { head += " · \(q) qualifying" }
        return head
    }

    // MARK: collection helpers

    private func allAchievements(_ data: AchievementsResponse) -> [Achievement] {
        (data.categories ?? [:]).values.flatMap { $0 }
    }
    private func allActive(_ data: AchievementsResponse) -> [Achievement] {
        allAchievements(data).filter { $0.status == "active" }
    }
    private func activeTotal(_ data: AchievementsResponse) -> Int { allActive(data).count }

    private func find(_ id: String, in data: AchievementsResponse) -> Achievement? {
        allAchievements(data).first { $0.id == id }
    }

    private func categoryCounts(_ data: AchievementsResponse, _ c: String) -> (Int, Int) {
        let rows = (data.categories?[c] ?? []).filter { $0.status == "active" }
        return (rows.filter { $0.unlocked == true }.count, rows.count)
    }

    private func sortRank(_ ach: Achievement) -> Int {
        switch ach.progress_status {
        case "unlocked": return 0
        case "in_progress": return 1
        case "not_trackable": return 3
        default: return 2
        }
    }

    private func isPinned(_ id: String) -> Bool { pins.contains { $0.achievement_id == id } }

    // MARK: pin mutations (PUT /me/achievements/pins)

    private func pin(_ id: String) async {
        pinError = nil
        var showcase = pins.filter { ($0.kind ?? "showcase") == "showcase" }
        guard showcase.count < 3 else { pinError = "Showcase holds up to 3 achievements. Unpin one first."; return }
        showcase.append(AchievementPin(achievement_id: id, kind: "showcase", position: showcase.count + 1))
        await savePins(showcase)
    }

    private func unpin(_ id: String) async {
        pinError = nil
        let showcase = pins.filter { ($0.kind ?? "showcase") == "showcase" && $0.achievement_id != id }
        let reindexed = showcase.enumerated().map {
            AchievementPin(achievement_id: $0.element.achievement_id, kind: "showcase", position: $0.offset + 1)
        }
        await savePins(reindexed)
    }

    private func savePins(_ showcase: [AchievementPin]) async {
        let body = showcase.map { ["achievement_id": $0.achievement_id, "kind": "showcase", "position": $0.position ?? 1] as [String: Any] }
        do {
            pins = try await model.makeClient().setPins(body)
        } catch { pinError = "Couldn't update pins: \(error.localizedDescription)" }
    }

    private func load() async {
        state = .loading
        do {
            let data = try await model.makeClient().achievements()
            pins = data.pins ?? []
            state = .loaded(data)
        } catch { state = .failed(error.localizedDescription) }
    }
}

/// Achievement detail (Achievements/{id}): progress, status and the evidence shots behind it.
struct AchievementDetailView: View {
    @EnvironmentObject var model: AppModel
    let achievementId: String
    @State private var state: Loadable<AchievementDetail> = .idle

    var body: some View {
        ScrollView {
            LoadableView(state: state, retry: { Task { await load() } }) { d in
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        AchievementBadge(category: d.category, unlocked: d.unlocked == true, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.name ?? "").font(.lsTitle3.bold()).foregroundStyle(LS.textPrimary)
                            Text((d.category ?? "").capitalized).font(.lsCaption).foregroundStyle(LS.cyan)
                        }
                    }
                    if let desc = d.description {
                        Text(desc).font(.lsCallout).foregroundStyle(LS.textSecondary)
                    }
                    progressCard(d)
                    if let ids = d.evidence_shot_ids, !ids.isEmpty {
                        evidenceCard(ids)
                    }
                    if d.status == "coming_later", let reason = d.inactive_reason {
                        Label(reason, systemImage: "hourglass").font(.lsCaption).foregroundStyle(LS.bestEffort)
                    }
                }
                .padding(16)
            }
        }
        .background(LSBackground())
        .navigationTitle("Achievement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .lsHidesTabBar()      // DEC-099: only Home · Stats · Lab · Coaching show the tab bar
        .task { await load() }
    }

    private func progressCard(_ d: AchievementDetail) -> some View {
        let p = d.progress
        return VStack(alignment: .leading, spacing: 10) {
            Text("PROGRESS").lsEyebrow()
            if d.unlocked == true {
                Label("Unlocked", systemImage: "checkmark.seal.fill").font(.lsHeadline).foregroundStyle(LS.measured)
                if let at = d.unlocked_at {
                    Text(Date(timeIntervalSince1970: at).formatted(.dateTime.month().day().year()))
                        .font(.lsCaption).foregroundStyle(LS.textSecondary)
                }
            } else if p?.status == "not_trackable" {
                Label("Not trackable yet", systemImage: "circle.dashed").font(.lsSubheadline.bold())
                    .foregroundStyle(LS.unavailable)
                Text(p?.unavailable_reason ?? "This achievement can't be measured from the current data.")
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)
            } else if let c = p?.current_value?.double, let t = p?.target_value?.double, t > 0 {
                let isRatio = t <= 1
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(isRatio ? "\(Int((c * 100).rounded()))%" : (p?.current_value?.display ?? "0"))
                        .font(.lsTitle.bold().monospacedDigit()).foregroundStyle(LS.textPrimary)
                    Text("/ \(isRatio ? "\(Int((t * 100).rounded()))%" : (p?.target_value?.display ?? "—"))")
                        .font(.lsSubheadline).foregroundStyle(LS.textSecondary)
                }
                ProgressView(value: min(max(c / t, 0), 1)).tint(LS.cyan)
                if let n = p?.sample_count { Text("\(n) comparable shots").font(.lsCaption).foregroundStyle(LS.textSecondary) }
            } else if let tgt = p?.target_value?.display {
                Text("Target: \(tgt.capitalized)").font(.lsSubheadline).foregroundStyle(LS.textSecondary)
            } else {
                Text("Locked — no progress yet.").font(.lsSubheadline).foregroundStyle(LS.textSecondary)
            }
        }
        .lsCard()
    }

    private func evidenceCard(_ ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EVIDENCE").lsEyebrow()
            Text("\(ids.count) qualifying shot\(ids.count == 1 ? "" : "s") count toward this achievement.")
                .font(.lsCaption).foregroundStyle(LS.textSecondary)
        }
        .lsCard()
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await model.makeClient().achievementDetail(achievementId)) }
        catch { state = .failed(error.localizedDescription) }
    }
}
