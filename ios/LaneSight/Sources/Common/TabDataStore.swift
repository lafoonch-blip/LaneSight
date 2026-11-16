import SwiftUI

/// Friendly, user-facing copy for a failed section load — never a raw server body / status / HTML, and never
/// the "analysis host" for a non-analysis call (P0 2026-10-29). APIError already maps 5xx/HTML/transport.
func friendlyError(_ error: Error) -> String {
    (error as? APIError)?.userMessage ?? "Couldn't load this. Please try again."
}

/// Retry a request a couple of times with short backoff, but ONLY for transient server problems (5xx / HTML
/// 5xx page / transport). A 4xx or decode error fails fast — retrying it won't help. Keeps a flaky single
/// Cloud Run instance (deploy rollover / brief overload) from surfacing as a section error on launch.
func withRetry<T>(_ attempts: Int = 3, _ op: @Sendable () async throws -> T) async throws -> T {
    var last: Error?
    for i in 0..<attempts {
        do { return try await op() }
        catch {
            last = error
            let transient = (error as? APIError)?.isTransientServerProblem ?? false
            if !transient || i == attempts - 1 { throw error }
            try? await Task.sleep(nanoseconds: UInt64(i + 1) * 500_000_000)   // 0.5s, 1.0s
        }
    }
    throw last!
}

/// DEC-099 — seamless tab loading. One store holds the data for the three data tabs (Home · Stats · Lab):
///  • Each page fetches ALL its sections concurrently and publishes them in ONE update, so the page appears
///    at once instead of section by section (before: Home awaited 4 requests one after another and each card
///    popped in separately; Lab's session rings arrived card by card).
///  • A revisit keeps the data already on screen and refreshes it silently (stale-while-revalidate) — no
///    spinner flash, and a failed refresh never replaces good data with an error.
///  • Stats and Lab are prefetched in the background right after sign-in, so the first visit is instant.
///  • Concurrent requests for the same page are coalesced into one fetch.
/// Every value is still live from the API; nothing is cached across sign-outs (`reset()`).
@MainActor
final class TabDataStore: ObservableObject {
    struct Home {
        var score: Loadable<ScoreResponse> = .idle
        var history: [ScoreResponse] = []
        var sessions: Loadable<[SessionRow]> = .idle
        var activity: Loadable<[ActivityItem]> = .idle
        var focus: FocusResponse? = nil
    }
    struct Stats {
        var score: Loadable<ScoreResponse> = .idle
        var history: [ScoreResponse] = []
        var breakdown: ScoreBreakdown? = nil
        var throwStats: Loadable<StatsResponse> = .idle
        var formStats: Loadable<StatsResponse> = .idle
        var equipment: Loadable<EquipmentStats> = .idle
    }
    struct Lab {
        var sessions: Loadable<[SessionRow]> = .idle
        var uploads: Loadable<[UploadRow]> = .idle
        var summaries: [String: SessionSummary] = [:]     // session id → mini-ring summary
    }

    @Published private(set) var home = Home()
    @Published private(set) var stats = Stats()
    @Published private(set) var lab = Lab()
    /// True once a page's first load has finished (success or failure) — drives the one page-level spinner.
    @Published private(set) var homeReady = false
    @Published private(set) var statsReady = false
    @Published private(set) var labReady = false

    enum Page: Hashable { case home, stats, lab }
    private var inflight: [Page: Task<Void, Never>] = [:]
    /// Bumped on reset so a fetch that started before sign-out can't publish into the next account.
    private var generation = 0

    /// Number of Lab session cards whose rings are fetched up front (the rest load as they scroll in).
    private static let labSummaryPrefetch = 12

    func reset() {
        generation += 1
        inflight.values.forEach { $0.cancel() }
        inflight = [:]
        home = Home(); stats = Stats(); lab = Lab()
        homeReady = false; statsReady = false; labReady = false
    }

    /// Loads (first visit) or silently refreshes (revisit / pull-to-refresh) one page.
    func load(_ page: Page, model: AppModel) async {
        if let running = inflight[page] { await running.value; return }
        let gen = generation
        let task = Task { [weak self] in
            guard let self else { return }
            switch page {
            case .home:  await self.fetchHome(model, gen: gen)
            case .stats: await self.fetchStats(model, gen: gen)
            case .lab:   await self.fetchLab(model, gen: gen)
            }
        }
        inflight[page] = task
        await task.value
        if generation == gen { inflight[page] = nil }
    }

    /// Background warm-up of the tabs the bowler hasn't opened yet (called once Home is up).
    func prefetchOtherTabs(model: AppModel) async {
        async let s: Void = load(.stats, model: model)
        async let l: Void = load(.lab, model: model)
        _ = await (s, l)
    }

    // MARK: fetches — every section in parallel, one publish at the end

    private func fetchHome(_ model: AppModel, gen: Int) async {
        guard let client = try? model.makeClient() else { return }
        async let s = withRetry { try await client.score() }
        async let h = withRetry { try await client.scoreHistory() }
        async let ss = withRetry { try await client.listSessions() }
        async let a = withRetry { try await client.activity() }
        async let f = try? client.focus()
        async let av: Void = model.refreshAvatar()          // header photo arrives with the page, not after

        var next = home
        do {
            let (sv, hv) = try await (s, h)
            next.score = .loaded(sv); next.history = hv
        } catch { next.score = Loadable<ScoreResponse>.failed(friendlyError(error)).keepingLoaded(over: home.score) }
        do { next.sessions = .loaded(try await ss) }
        catch { next.sessions = Loadable<[SessionRow]>.failed(friendlyError(error)).keepingLoaded(over: home.sessions) }
        do { next.activity = .loaded(try await a) }
        catch { next.activity = Loadable<[ActivityItem]>.failed(friendlyError(error)).keepingLoaded(over: home.activity) }
        if let fv = await f { next.focus = fv }
        _ = await av

        guard gen == generation else { return }
        home = next
        homeReady = true
    }

    private func fetchStats(_ model: AppModel, gen: Int) async {
        guard let client = try? model.makeClient() else { return }
        async let s = withRetry { try await client.score() }
        async let h = withRetry { try await client.scoreHistory() }
        async let b = try? client.scoreBreakdown()          // nil until deployed → rows show "—"
        async let t = withRetry { try await client.stats(view: "throw", range: nil) }
        async let fm = withRetry { try await client.stats(view: "form", range: nil) }
        async let e = withRetry { try await client.equipmentStats() }

        var next = stats
        do {
            let (sv, hv) = try await (s, h)
            next.score = .loaded(sv); next.history = hv
        } catch { next.score = Loadable<ScoreResponse>.failed(friendlyError(error)).keepingLoaded(over: stats.score) }
        if let bv = await b { next.breakdown = bv }
        do { next.throwStats = .loaded(try await t) }
        catch { next.throwStats = Loadable<StatsResponse>.failed(friendlyError(error)).keepingLoaded(over: stats.throwStats) }
        do { next.formStats = .loaded(try await fm) }
        catch { next.formStats = Loadable<StatsResponse>.failed(friendlyError(error)).keepingLoaded(over: stats.formStats) }
        do { next.equipment = .loaded(try await e) }
        catch { next.equipment = Loadable<EquipmentStats>.failed(friendlyError(error)).keepingLoaded(over: stats.equipment) }

        guard gen == generation else { return }
        stats = next
        statsReady = true
    }

    private func fetchLab(_ model: AppModel, gen: Int) async {
        guard let client = try? model.makeClient() else { return }
        async let ss = withRetry { try await client.listSessions() }
        async let us = withRetry { try await client.listUploads() }

        var next = lab
        do { next.sessions = .loaded(try await ss) }
        catch { next.sessions = Loadable<[SessionRow]>.failed(friendlyError(error)).keepingLoaded(over: lab.sessions) }
        do { next.uploads = .loaded(try await us) }
        catch {
            // DEC-086: a response we can't read is our problem, not a scary host/status string.
            let msg: String
            if case APIError.decoding = error { msg = "Couldn't load your uploads. Pull to refresh." }
            else { msg = friendlyError(error) }
            next.uploads = Loadable<[UploadRow]>.failed(msg).keepingLoaded(over: lab.uploads)
        }

        // The session cards' mini rings, fetched together with the list so the cards arrive complete.
        if let rows = next.sessions.value {
            let ids = rows.sorted { ($0.started_at ?? 0) > ($1.started_at ?? 0) }
                .prefix(Self.labSummaryPrefetch).map(\.id)
            var sums = next.summaries
            await withTaskGroup(of: (String, SessionSummary?).self) { group in
                for id in ids {
                    group.addTask { (id, try? await client.sessionSummary(id)) }
                }
                for await (id, summary) in group {
                    if let summary { sums[id] = summary }
                }
            }
            next.summaries = sums
        }

        guard gen == generation else { return }
        lab = next
        labReady = true
    }

    /// A Lab card outside the prefetched set loads its own rings and stores them here (so a revisit is instant).
    func storeSummary(_ summary: SessionSummary, for sessionId: String) {
        lab.summaries[sessionId] = summary
    }
}
