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
            defer { self?.aiJobsTask = nil; self?.aiActivity = nil }
            @MainActor func step(_ label: String, _ index: Int, of total: Int) { self?.aiActivity = "\(label) · \(index + 1) of \(total)" }
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
                            // A name in several folders keeps its first answer.
                            if let name = answer.name, named.insert(row.name).inserted { results.names[row.name] = name }
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
                for (key, answer) in CatalogPass.mergeAnswers(candidates, answers: answers) where results.merges[key] == nil { results.merges[key] = answer }
                if let byChannel = try? await catalogWork({ CatalogPass.channelCategories(channels, answers: answers) }) {
                    self?.savePlacements(CatalogPass.placements(pending, categories: CatalogPass.categoryPaths(taxonomy), channelCategory: byChannel))
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
                            if let name = answer.name { results.vodNames?[row.name] = VODTitle.clean(name).title }
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

    /// Saves new group placements. A group that changed meanwhile, or a
    /// manual correction or current decision, wins.
    func savePlacements(_ placements: [GroupPlacement]) {
        var updates: [String: Data?] = [:]
        for placement in placements {
            guard let current = directory?.nameGroups.byID[placement.id], current.fingerprint == placement.fingerprint else { continue }
            let key = "taxonomy.placement.\(placement.id)"
            let existing: GroupPlacement? = personal.value(key, default: nil)
            if existing?.isReusable(for: current) == true { continue }
            updates[key] = try? JSONEncoder().encode(placement)
        }
        guard !updates.isEmpty else { return }
        do { try personal.write(updates); rebuild() }
        catch { openAI.report(error) }
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
