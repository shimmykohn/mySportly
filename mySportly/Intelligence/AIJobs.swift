import Foundation

/// The three catalog jobs that use the user's OpenAI key, run quietly with
/// group sorting: detect games, merge duplicate feeds, clean names. Only
/// unanswered items are sent, a bounded number per run; the rest wait for the
/// next launch, foreground or refresh.
extension AppStore {
    static let aiLimits = (listings: 1_000, pairs: 4_000, names: 2_000)

    func runAIJobs() {
        guard aiJobsTask == nil, catalogReady, !demo, let key = openAI.activeKey(), let query = queryIndex else { return }
        let channels = channels, reference = sportsData.reference, date = clock, start = aiResults
        let catalogCache = self.cache
        aiJobsTask = Task { [weak self] in
            var results = start
            self?.aiActivity = "Starting…"
            defer { self?.aiJobsTask = nil; self?.aiActivity = nil }
            @MainActor func step(_ label: String, _ index: Int, of total: Int) { self?.aiActivity = "\(label) · \(index + 1) of \(total)" }
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
                // Duplicate feeds.
                let candidates = try await catalogWork { FeedMerging.candidates(channels, strict: FeedMerging.strictGroups(channels)) }
                let unasked = candidates.filter { results.merges[$0.key] == nil }
                let pairBatches = Array(unasked.prefix(Self.aiLimits.pairs)).chunked(Decisions.maxQuestions)
                for (index, batch) in pairBatches.enumerated() {
                    step("Checking duplicate feeds", index, of: pairBatches.count)
                    let answers = try await decisions.answers(input: FeedMerging.input, questions: FeedMerging.questions(batch))
                    for candidate in batch {
                        guard let answer = answers[candidate.key] else { continue }
                        results.merges[candidate.key] = MergeAnswer(same: FeedMerging.accepted(answer), ids: [candidate.anchor.id, candidate.other.id])
                    }
                }
                // Names local rules leave looking like provider codes.
                let answered = Set(results.names.keys).union(results.namesAsked)
                let leftovers = try await catalogWork {
                    Set(channels.map(\.name)).subtracting(answered).filter { NameCleaning.needsModel(NameCleaning.local($0)) }.sorted()
                }
                let names = NameCleanupClient(key: key)
                let nameBatches = Array(leftovers.prefix(Self.aiLimits.names)).chunked(NameCleanupClient.batchSize)
                for (index, batch) in nameBatches.enumerated() {
                    step("Tidying channel names", index, of: nameBatches.count)
                    results.names.merge(try await names.clean(batch)) { _, new in new }
                    results.namesAsked.formUnion(batch)
                }
                results.prune(at: .now, channels: channels, candidates: candidates)
                results.lastRun = Date.now.timeIntervalSince1970
                await self?.applyAIResults(results, cache: catalogCache)
                self?.openAI.succeeded()
            } catch {
                // Keep what finished; a later run picks up the rest.
                await self?.applyAIResults(results, cache: catalogCache)
                self?.openAI.report(error)
            }
        }
    }

    /// Saves new answers and refreshes only what they change.
    func applyAIResults(_ results: AIResults, cache: CatalogCache) async {
        let previous = aiResults
        guard results != previous else { return }
        aiResults = results
        try? await cache.saveAIResults(results)
        if results.names != previous.names { resetDisplayNames() }
        if results.mergedPairs != previous.mergedPairs { rebuild(force: true) }
        else if results.detectedGames != previous.detectedGames { matchSportsGames() }
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
