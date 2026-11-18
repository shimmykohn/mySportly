import Foundation

/// The catalog jobs that use the user's OpenAI key, run quietly and side by
/// side in one queue of requests: games in the guide (Decisions API), the
/// channel pass with GPT-6 Luna (names, categories, copies, numbered sets)
/// and the title pass (titles, genres, copies). Only unanswered items are
/// sent, a bounded number per run; the rest wait for the next launch or
/// refresh. Tokens are added up into an estimated cost.
extension AppStore {
    static let aiLimits = (listings: 1_000, rows: 30_000)

    /// One request in a run's queue, and what it brought back.
    private enum AIWork: Sendable { case games([GameListing]), channels([PassRow]), titles([PassRow]) }
    private enum AIAnswer: Sendable { case games([String: DetectedGame]), channels([String: PassAnswer]), titles([String: PassAnswer]) }

    func runAIJobs() {
        guard aiJobsTask == nil, catalogReady, !demo, let key = openAI.activeKey(), let query = queryIndex else { return }
        let channels = channels, reference = sportsData.reference, date = clock, start = aiResults
        let catalogCache = self.cache
        let movieTitles = vod.movies.map(\.rawTitle) + vod.versionTitles.movies, showTitles = vod.series.map(\.rawTitle) + vod.versionTitles.shows
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
        let categories = CatalogPass.categoryPaths(taxonomy)
        let limits = Self.aiLimits
        aiJobsTask = Task { [weak self] in
            var results = start
            results.startPass(CatalogPass.version)
            self?.aiActivity = "Starting…"
            defer { self?.aiJobsTask = nil; self?.aiActivity = nil; self?.aiFraction = nil }
            var tidied = 0, titlesTidied = 0, combined = 0, sorted = 0, usage = TokenUsage()
            var channelAnswers: [String: PassAnswer] = [:], titleRows: [PassRow] = [], titleAnswers: [String: PassAnswer] = [:]
            var candidates: [MergeCandidate] = [], failure: Error?
            do {
                // Everything to ask, gathered off the main actor.
                let knownListings = Set(results.games.keys), asked = results.namesAsked, titlesAsked = results.vodNamesAsked ?? []
                let pendingIDs = Set(pending.map(\.id))
                let (listings, channelRows, rows, found) = try await catalogWork {
                    (Array(try query.unresolvedGameListings(reference: reference, at: date, known: knownListings).prefix(limits.listings)),
                     groups.map { CatalogPass.channelRows(channels, groups: $0, audience: audience, asked: asked, pendingGroups: pendingIDs, limit: limits.rows) } ?? [],
                     CatalogPass.titleRows(movies: movieTitles, shows: showTitles, asked: titlesAsked, limit: limits.rows),
                     FeedMerging.candidates(channels, strict: FeedMerging.strictGroups(channels)))
                }
                titleRows = rows; candidates = found
                // Games first, as they're the most visible; all of it a dozen requests at a time.
                let work = listings.chunked(Decisions.maxQuestions / 2).map(AIWork.games)
                    + CatalogPass.chunks(channelRows).map(AIWork.channels) + CatalogPass.chunks(rows).map(AIWork.titles)
                let client = CatalogPassClient(key: key), decisions = DecisionsClient(key: key)
                var named = Set<String>(), done = 0
                if results.vodNames == nil { results.vodNames = [:] }
                if results.vodNamesAsked == nil { results.vodNamesAsked = [] }
                if results.vodGenres == nil { results.vodGenres = [:] }
                if results.families == nil { results.families = [:] }
                @MainActor func progress() {
                    self?.aiActivity = "\(min(done + 1, work.count)) of \(work.count) requests"
                    self?.aiFraction = work.isEmpty ? nil : Double(done) / Double(work.count)
                }
                progress()
                try await Self.inParallel(work, spent: { usage += $0 }) { (item: AIWork) async throws -> (AIAnswer, TokenUsage) in
                    switch item {
                    case .games(let batch):
                        let reply = try await decisions.answersAndUsage(input: GameDetection.input, questions: GameDetection.questions(batch, leagues: reference.leagues))
                        return (AIAnswer.games(GameDetection.resolve(reply.answers, listings: batch, teams: reference.teams)), reply.usage)
                    case .channels(let chunk):
                        let reply = try await client.answer(.channels, rows: chunk, categories: categories)
                        return (AIAnswer.channels(reply.answers), reply.usage)
                    case .titles(let chunk):
                        let reply = try await client.answer(.titles, rows: chunk)
                        return (AIAnswer.titles(reply.answers), reply.usage)
                    }
                } receive: { (index: Int, answer: AIAnswer) in
                    switch (work[index], answer) {
                    case (_, .games(let found)):
                        results.games.merge(found) { _, new in new }
                    case (.channels(let chunk), .channels(let answers)):
                        channelAnswers.merge(answers) { _, new in new }
                        for row in chunk {
                            guard let answer = answers[row.key] else { continue }
                            results.namesAsked.insert(row.name)
                            results.families?[row.name] = answer.family
                            // A name in several folders keeps its first answer.
                            if let name = answer.name, named.insert(row.name).inserted {
                                if name != NameCleaning.local(row.name), results.names[row.name] != name { tidied += 1 }
                                results.names[row.name] = name
                            }
                        }
                    case (.titles(let chunk), .titles(let answers)):
                        titleAnswers.merge(answers) { _, new in new }
                        for row in chunk {
                            guard let answer = answers[row.key] else { continue }
                            results.vodNamesAsked?.insert(row.name)
                            results.vodGenres?[row.name] = answer.genre
                            if let name = answer.name {
                                let title = VODTitle.clean(name).title
                                if title != VODTitle.clean(row.name).title, results.vodNames?[row.name] != title { titlesTidied += 1 }
                                results.vodNames?[row.name] = title
                            }
                        }
                    default: break
                    }
                    done += 1
                    progress()
                    if done.isMultiple(of: 12) { await self?.applyAIResults(results, cache: catalogCache) }
                }
            } catch { failure = error }
            // What was answered applies even if the run stopped early.
            if !channelAnswers.isEmpty {
                let answers = channelAnswers
                for (key, answer) in CatalogPass.mergeAnswers(candidates, answers: answers) where results.merges[key] == nil {
                    results.merges[key] = answer
                    if answer.same { combined += 1 }
                }
                if let byChannel = try? await catalogWork({ CatalogPass.channelCategories(channels, answers: answers) }) {
                    sorted = self?.savePlacements(CatalogPass.placements(pending, categories: categories, channelCategory: byChannel)) ?? 0
                }
            }
            if !titleAnswers.isEmpty {
                var copies = results.vodCopies ?? [:]
                // Answered titles get their links afresh.
                for key in titleAnswers.keys { copies[key] = nil }
                copies.merge(CatalogPass.titleCopies(titleRows, answers: titleAnswers)) { _, new in new }
                results.vodCopies = copies
            }
            // Keep what finished; a later run picks up the rest.
            results.prune(at: .now, channels: channels, candidates: candidates)
            results.pruneVOD(rawTitles: vodTitles)
            results.usage = (results.usage ?? TokenUsage()) + usage
            if usage.requests > 0 { results.lastRunUsage = usage }
            if failure == nil { results.lastRun = Date.now.timeIntervalSince1970 }
            await self?.applyAIResults(results, cache: catalogCache)
            if let failure { self?.openAI.report(failure) } else { self?.openAI.succeeded() }
            let games = max(0, results.detectedGames.count - start.detectedGames.count)
            self?.showAISummary(AppStore.aiSummaryText(names: tidied, titles: titlesTidied, feeds: combined, groups: sorted, games: games,
                                                       cost: usage.requests > 0 ? usage.dollars : nil))
        }
    }

    /// Runs requests `CatalogPass.parallel` at a time and hands each answer
    /// back as it arrives, with the tokens every request used. A request
    /// whose answer stays unusable is skipped, so its items wait for the next
    /// run; key, quota and network failures stop the run.
    private static func inParallel<Input: Sendable, Output: Sendable>(
        _ inputs: [Input], width: Int = CatalogPass.parallel, spent: (TokenUsage) -> Void,
        _ work: @escaping @Sendable (Input) async throws -> (Output, TokenUsage),
        receive: (Int, Output) async -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: (Int, Output?, TokenUsage).self) { group in
            var next = 0
            func start() {
                let index = next, input = inputs[index]
                next += 1
                group.addTask {
                    do { let (output, usage) = try await work(input); return (index, output, usage) }
                    catch let failure as PassFailure { return (index, nil, failure.usage) }
                    catch DecisionsFailure.invalidResponse { return (index, nil, TokenUsage(requests: 1)) }
                }
            }
            while next < min(width, inputs.count) { start() }
            while let (index, output, usage) = try await group.next() {
                try Task.checkCancellation()
                spent(usage)
                if let output { await receive(index, output) }
                if next < inputs.count { start() }
            }
        }
    }

    /// "AI tidied 1,240 names · combined 85 feeds", or nil when nothing changed.
    static func aiSummaryText(names: Int, titles: Int, feeds: Int, groups: Int, games: Int, cost: Double? = nil) -> String? {
        let parts = [(groups, "sorted %@ groups"), (names, "tidied %@ channel names"), (feeds, "combined %@ duplicate feeds"),
                     (titles, "tidied %@ titles"), (games, "found %@ games")]
            .filter { $0.0 > 0 }.map { String(format: $0.1, $0.0.formatted()) }
        guard !parts.isEmpty else { return nil }
        return (parts + [cost.map { "cost about \($0.dollarText)" }].compactMap { $0 }).joined(separator: " · ")
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
        if results.vod != previous.vod { await vod.apply(results.vod) }
        if results.mergedPairs != previous.mergedPairs { rebuild(force: true) }
        else if results.detectedGames != previous.detectedGames { matchSportsGames() }
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
