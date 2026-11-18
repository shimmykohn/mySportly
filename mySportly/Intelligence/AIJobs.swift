import Foundation

/// The catalog jobs that use the user's OpenAI key, run quietly: find games
/// in the guide (Decisions API), then one catalog pass with GPT-6 Luna that
/// tidies names, sorts groups into categories and links duplicate feeds,
/// then tidies movie and show titles. Only unanswered items are sent, a
/// bounded number per run; the rest wait for the next launch or refresh.
extension AppStore {
    static let aiLimits = (listings: 1_000, rows: 30_000)

    func runAIJobs() {
        guard aiJobsTask == nil, catalogReady, !demo, let key = openAI.activeKey(), let query = queryIndex else { return }
        let channels = channels, reference = sportsData.reference, date = clock, start = aiResults
        let catalogCache = self.cache
        let movieTitles = vod.movies.map(\.rawTitle), showTitles = vod.series.map(\.rawTitle)
        let vodTitles = Set(movieTitles + showTitles)
        // Groups in the lineup without a saved, current placement.
        let groups = directory?.nameGroups, audience = organizationAudience
        let pending = groups.map { index in
            index.pending(in: audience).filter { group in
                let saved: GroupPlacement? = personal.value("taxonomy.placement.\(group.id)", default: nil)
                return saved?.isReusable(for: group) != true
            }
        } ?? []
        let taxonomy = personal.has("preferences.organizationPaths") ? GroupTaxonomy(paths: organizationPaths) : (groups?.taxonomy ?? GroupTaxonomy())
        let limit = Self.aiLimits.rows
        aiJobsTask = Task { [weak self] in
            var results = start
            results.startPass(CatalogPass.version)
            self?.aiActivity = "Starting…"
            defer { self?.aiJobsTask = nil; self?.aiActivity = nil; self?.aiFraction = nil }
            @MainActor func step(_ label: String, _ index: Int, of total: Int) {
                self?.aiActivity = "\(label) · \(index + 1) of \(total)"
                self?.aiFraction = total > 0 ? Double(index) / Double(total) : nil
            }
            var tidied = 0, titlesTidied = 0, combined = 0, sorted = 0
            let client = CatalogPassClient(key: key)
            var channelAnswers: [String: PassAnswer] = [:], candidates: [MergeCandidate] = []
            var failure: Error?
            do {
                // Games: the most visible, first.
                let knownListings = Set(results.games.keys)
                let listings = try await catalogWork {
                    try query.unresolvedGameListings(reference: reference, at: date, known: knownListings)
                }
                let decisions = DecisionsClient(key: key)
                let gameBatches = Array(listings.prefix(Self.aiLimits.listings)).chunked(Decisions.maxQuestions / 2)
                for (index, batch) in gameBatches.enumerated() {
                    step("Finding games in the guide", index, of: gameBatches.count)
                    let answers = try await decisions.answers(input: GameDetection.input, questions: GameDetection.questions(batch, leagues: reference.leagues))
                    results.games.merge(GameDetection.resolve(answers, listings: batch, teams: reference.teams)) { _, new in new }
                }
                candidates = try await catalogWork { FeedMerging.candidates(channels, strict: FeedMerging.strictGroups(channels)) }
                // Channels: names, categories and copies in one pass.
                if let groups {
                    let asked = results.namesAsked, pendingIDs = Set(pending.map(\.id))
                    let categories = CatalogPass.categoryPaths(taxonomy)
                    let rows = try await catalogWork {
                        CatalogPass.channelRows(channels, groups: groups, audience: audience, asked: asked, pendingGroups: pendingIDs, limit: limit)
                    }
                    let chunks = CatalogPass.chunks(rows)
                    var named = Set<String>(), done = 0
                    if !chunks.isEmpty { step("Organizing channels", 0, of: chunks.count) }
                    try await Self.inParallel(chunks, { try await client.answer(.channels, rows: $0, categories: categories) }) { index, answers in
                        channelAnswers.merge(answers) { _, new in new }
                        for row in chunks[index] {
                            guard let answer = answers[row.key] else { continue }
                            results.namesAsked.insert(row.name)
                            if results.families == nil { results.families = [:] }
                            results.families?[row.name] = answer.family
                            // A name in several folders keeps its first answer.
                            if let name = answer.name, named.insert(row.name).inserted {
                                if name != NameCleaning.local(row.name), results.names[row.name] != name { tidied += 1 }
                                results.names[row.name] = name
                            }
                        }
                        done += 1
                        step("Organizing channels", min(done, chunks.count - 1), of: chunks.count)
                        if done.isMultiple(of: 8) { await self?.applyAIResults(results, cache: catalogCache) }
                    }
                }
            } catch { failure = error }
            // What the channel pass answered applies even if the run stopped early.
            if !channelAnswers.isEmpty {
                let answers = channelAnswers
                for (key, answer) in CatalogPass.mergeAnswers(candidates, answers: answers) where results.merges[key] == nil {
                    results.merges[key] = answer
                    if answer.same { combined += 1 }
                }
                if let byChannel = try? await catalogWork({ CatalogPass.channelCategories(channels, answers: answers) }) {
                    sorted = self?.savePlacements(CatalogPass.placements(pending, categories: CatalogPass.categoryPaths(taxonomy), channelCategory: byChannel)) ?? 0
                }
            }
            if failure == nil {
                do {
                    // Movie and show titles, once the Watch catalog is loaded.
                    let titlesAsked = results.vodNamesAsked ?? []
                    let rows = try await catalogWork {
                        CatalogPass.titleRows(movies: movieTitles, shows: showTitles, asked: titlesAsked, limit: limit)
                    }
                    let chunks = CatalogPass.chunks(rows)
                    var done = 0
                    if !chunks.isEmpty { step("Tidying movie and show titles", 0, of: chunks.count) }
                    if results.vodNames == nil { results.vodNames = [:] }
                    if results.vodNamesAsked == nil { results.vodNamesAsked = [] }
                    try await Self.inParallel(chunks, { try await client.answer(.titles, rows: $0) }) { index, answers in
                        for row in chunks[index] {
                            guard let answer = answers[row.key] else { continue }
                            results.vodNamesAsked?.insert(row.name)
                            if let name = answer.name {
                                let title = VODTitle.clean(name).title
                                if title != VODTitle.clean(row.name).title, results.vodNames?[row.name] != title { titlesTidied += 1 }
                                results.vodNames?[row.name] = title
                            }
                        }
                        done += 1
                        step("Tidying movie and show titles", min(done, chunks.count - 1), of: chunks.count)
                    }
                } catch { failure = error }
            }
            // Keep what finished; a later run picks up the rest.
            results.prune(at: .now, channels: channels, candidates: candidates)
            results.pruneVOD(rawTitles: vodTitles)
            if failure == nil { results.lastRun = Date.now.timeIntervalSince1970 }
            await self?.applyAIResults(results, cache: catalogCache)
            if let failure { self?.openAI.report(failure) } else { self?.openAI.succeeded() }
            let games = max(0, results.detectedGames.count - start.detectedGames.count)
            self?.showAISummary(AppStore.aiSummaryText(names: tidied, titles: titlesTidied, feeds: combined, groups: sorted, games: games))
        }
    }

    /// Runs requests a few at a time and hands each answer back as it
    /// arrives. A request whose answer stays unusable is skipped, so its
    /// items wait for the next run; key, quota and network failures stop it.
    private static func inParallel<Input: Sendable, Output: Sendable>(
        _ inputs: [Input], width: Int = CatalogPass.parallel, _ work: @escaping @Sendable (Input) async throws -> Output,
        receive: (Int, Output) async -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: (Int, Output?).self) { group in
            var next = 0
            func start() {
                let index = next, input = inputs[index]
                next += 1
                group.addTask {
                    do { return (index, try await work(input)) }
                    catch DecisionsFailure.invalidResponse { return (index, nil) }
                }
            }
            while next < min(width, inputs.count) { start() }
            while let (index, output) = try await group.next() {
                try Task.checkCancellation()
                if let output { await receive(index, output) }
                if next < inputs.count { start() }
            }
        }
    }

    /// "AI tidied 1,240 names · combined 85 feeds", or nil when nothing changed.
    static func aiSummaryText(names: Int, titles: Int, feeds: Int, groups: Int, games: Int) -> String? {
        let parts = [(groups, "sorted %@ groups"), (names, "tidied %@ channel names"), (feeds, "combined %@ duplicate feeds"),
                     (titles, "tidied %@ titles"), (games, "found %@ games")]
            .filter { $0.0 > 0 }.map { String(format: $0.1, $0.0.formatted()) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Shows what a run changed on Home for a few seconds.
    func showAISummary(_ text: String?) {
        guard let text else { return }
        aiSummary = text
        Task {
            try? await Task.sleep(for: .seconds(6))
            if aiSummary == text { aiSummary = nil }
        }
    }

    /// Saves new group placements and returns how many. A group that changed
    /// meanwhile, or a manual correction or current decision, wins.
    @discardableResult func savePlacements(_ placements: [GroupPlacement]) -> Int {
        var updates: [String: Data?] = [:]
        for placement in placements {
            guard let current = directory?.nameGroups.byID[placement.id], current.fingerprint == placement.fingerprint else { continue }
            let key = "taxonomy.placement.\(placement.id)"
            let existing: GroupPlacement? = personal.value(key, default: nil)
            if existing?.isReusable(for: current) == true { continue }
            updates[key] = try? JSONEncoder().encode(placement)
        }
        guard !updates.isEmpty else { return 0 }
        do { try personal.write(updates); rebuild(); return updates.count }
        catch { openAI.report(error); return 0 }
    }

    /// Saves new answers and refreshes only what they change.
    func applyAIResults(_ results: AIResults, cache: CatalogCache) async {
        let previous = aiResults
        guard results != previous else { return }
        aiResults = results
        try? await cache.saveAIResults(results)
        if results.names != previous.names { resetDisplayNames() }
        if results.vodNames != previous.vodNames { await vod.retitle(results.vodNames ?? [:]) }
        if results.mergedPairs != previous.mergedPairs { rebuild(force: true) }
        else if results.detectedGames != previous.detectedGames { matchSportsGames() }
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
