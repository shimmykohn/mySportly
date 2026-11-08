import Foundation
import Observation

struct SportsScreenRequest: Hashable, Sendable {
    let catalog: Int
    let links: Int
    let minute: Int
    let followedOnly: Bool
    let following: [SportsLibraryItem]
    let audience: ChannelAudience
}

struct SportsScreenResult: Sendable {
    var schedule = SportsSchedule()
    var games: [SportsGame] = []
    var groups: [TaxonomyBrowseGroup] = []
}

/// Owned by the app, so leaving a tab never discards its prepared results.
@MainActor @Observable final class SportsScreenModel {
    private(set) var all = SportsScreenResult()
    private(set) var mine = SportsScreenResult()
    private(set) var loaded = Set<Bool>()
    private(set) var loading = Set<Bool>()
    private(set) var computationCount = 0
    @ObservationIgnored private var keys: [Bool: SportsScreenRequest] = [:]
    @ObservationIgnored private var tasks: [Bool: Task<Void, Never>] = [:]
    @ObservationIgnored private var requests: [Bool: SportsScreenRequest] = [:]

    func isCurrent(_ request: SportsScreenRequest) -> Bool { keys[request.followedOnly] == request }
    func result(followedOnly: Bool) -> SportsScreenResult { followedOnly ? mine : all }

    func update(_ request: SportsScreenRequest, index: CatalogQueryIndex, directory: ChannelDirectory,
                sports: SportsDataIndex, matched: Set<String>, availableGames: Set<String>, at date: Date) async {
        let scope = request.followedOnly
        if keys[scope] == request { return }
        if requests[scope] == request { await tasks[scope]?.value; return }
        tasks[scope]?.cancel()
        if let previous = keys[scope], previous.catalog != request.catalog || previous.audience != request.audience || previous.following != request.following {
            if scope { mine = SportsScreenResult() } else { all = SportsScreenResult() }
            loaded.remove(scope)
        }
        requests[scope] = request; loading.insert(scope)
        let task = Task { [weak self] in
            do {
                let value = try await catalogWork {
                    var schedule = try index.sports(at: date, following: request.following.map(\.name), followedOnly: scope,
                        audience: request.audience, includeUnscheduledChannels: false)
                    schedule.live.removeAll { matched.contains($0.id) }
                    schedule.upcoming.removeAll { matched.contains($0.id) }
                    var browse = ChannelBrowseRequest(); browse.sportsOnly = true; browse.audience = request.audience
                    browse.collapseVariants = true; browse.excludeInactive = true
                    let groups = scope ? [] : try directory.groupedTaxonomy(in: directory.browse(browse), under: ["Sports"]).groups
                    return SportsScreenResult(schedule: schedule,
                        games: sports.schedule(for: scope ? request.following : nil, at: date).filter { availableGames.contains($0.id) }, groups: groups)
                }
                guard !Task.isCancelled, let self, self.requests[scope] == request else { return }
                if scope { self.mine = value } else { self.all = value }
                self.keys[scope] = request; self.loaded.insert(scope); self.computationCount += 1
                self.loading.remove(scope); self.tasks[scope] = nil
            } catch {
                guard let self, self.requests[scope] == request else { return }
                self.loading.remove(scope); self.tasks[scope] = nil; self.requests[scope] = nil
            }
        }
        tasks[scope] = task
        await task.value
    }
}
