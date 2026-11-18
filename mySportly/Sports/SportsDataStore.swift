import Foundation
import Observation

actor SportsRepository {
    /// The signed bundle contains public names and artwork URLs, never an API
    /// key or historical schedules. This remains available on the first offline launch.
    func load(referenceURL: URL?) throws -> SportsDataIndex {
        var catalog = SportsCatalog()
        if let referenceURL {
            let data = try Data(contentsOf: referenceURL)
            guard data.count <= 8_000_000 else { throw SportsDataError.invalidData }
            catalog = try JSONDecoder().decode(SportsCatalog.self, from: data)
            try catalog.validate()
        }
        catalog.games = []
        var leagues = Dictionary(uniqueKeysWithValues: catalog.leagues.map { ($0.libraryItem.name, $0) })
        var names = Set(catalog.teams.map { $0.libraryItem.name })
        for choice in SportsFollowCatalog.leagues where leagues[choice.name] == nil {
            leagues[choice.name] = SportsLeague(id: "local." + choice.name, name: choice.name)
        }
        for choice in SportsFollowCatalog.teams where !names.contains(choice.name) {
            guard let league = leagues[choice.league] else { continue }
            catalog.teams.append(SportsTeam(id: "local." + StableID.hash(choice.name), name: choice.name, leagueID: league.id))
            names.insert(choice.name)
        }
        catalog.leagues = leagues.values.sorted { $0.name < $1.name }
        return try SportsDataIndex(catalog)
    }
}

/// ESPN fetches and the saved copy. Public data only: no key, no account,
/// nothing about the user beyond which teams' schedules are asked for.
actor ESPNRepository {
    private static let file = URL.applicationSupportDirectory.appending(path: "espn-sports.json")

    func load() -> ESPNSnapshot {
        guard let data = try? Data(contentsOf: Self.file), data.count < 32_000_000,
              let snapshot = try? JSONDecoder().decode(ESPNSnapshot.self, from: data) else { return ESPNSnapshot() }
        return snapshot
    }
    func save(_ snapshot: ESPNSnapshot) {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: Self.file, options: .atomic) }
    }

    /// Brings the copy up to date: every league's teams weekly, followed
    /// teams' seasons daily, and the next three days of followed leagues
    /// (today every 30 minutes). Six requests at a time; a failed feed keeps
    /// its saved copy.
    func refresh(_ start: ESPNSnapshot, teams followed: [(ESPN.League, String)], leagues: Set<ESPN.League>, at date: Date) async -> ESPNSnapshot? {
        enum Feed: Sendable { case teams(ESPN.League), day(ESPN.League, Date), season(ESPN.League, String) }
        var feeds: [(String, Feed, URL)] = []
        for league in ESPN.leagues where !start.isFresh("teams.\(league.id)", maxAge: 7 * 86_400, at: date) {
            feeds.append(("teams.\(league.id)", .teams(league), ESPN.teamsURL(league)))
        }
        for (league, team) in followed where !start.isFresh("team.\(league.id).\(team)", maxAge: 86_400, at: date) {
            feeds.append(("team.\(league.id).\(team)", .season(league, team), ESPN.scheduleURL(league, teamID: team)))
        }
        for league in leagues {
            for offset in 0..<3 {
                let day = date + Double(offset) * 86_400, key = "day.\(league.id).\(ESPN.dayKey(day))"
                if !start.isFresh(key, maxAge: offset == 0 ? 1_800 : 6 * 3_600, at: date) { feeds.append((key, .day(league, day), ESPN.scoreboardURL(league, day: day))) }
            }
        }
        guard !feeds.isEmpty else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var snapshot = start
        await withTaskGroup(of: (String, Feed, Data?).self) { group in
            var next = 0
            func add() {
                let (key, feed, url) = feeds[next]; next += 1
                group.addTask {
                    guard let (data, response) = try? await session.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200 else { return (key, feed, nil) }
                    return (key, feed, data)
                }
            }
            while next < min(6, feeds.count) { add() }
            while let (key, feed, data) = await group.next() {
                if next < feeds.count { add() }
                guard let data else { continue }
                switch feed {
                case .teams(let league):
                    guard let teams = try? ESPN.teams(data), !teams.isEmpty else { continue }
                    snapshot.teams[league.id] = teams
                    snapshot.fetched[key] = date.timeIntervalSince1970
                case .day(let league, _), .season(let league, _):
                    guard let found = try? ESPN.events(data, league: league) else { continue }
                    snapshot.store(found, league: league, key: key, at: date)
                }
            }
        }
        snapshot.prune(at: date)
        save(snapshot)
        return snapshot
    }
}

@MainActor @Observable final class SportsDataStore {
    private(set) var reference = try! SportsDataIndex()
    private(set) var index = try! SportsDataIndex()
    private(set) var revision = 0
    private(set) var metadataRevision = 0
    private(set) var loaded = false
    private(set) var message: String?
    @ObservationIgnored private let repository = SportsRepository()
    @ObservationIgnored private let espn = ESPNRepository()
    /// The bundled directory, before ESPN's teams and games are laid over it.
    @ObservationIgnored private var base = SportsCatalog()
    @ObservationIgnored private var snapshot = ESPNSnapshot()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored var onUpdate: (() -> Void)?
    var updated: Date? { reference.catalog.fetchedAt > 0 ? Date(timeIntervalSince1970: reference.catalog.fetchedAt) : nil }
    func load() async {
        guard !loaded else { return }; loaded = true
        do {
            let url = Bundle.main.url(forResource: "sports-reference", withExtension: "json")
            let result = try await repository.load(referenceURL: url)
            base = result.catalog
            snapshot = await espn.load()
            let combined = (try? SportsDataIndex(snapshot.catalog(over: base))) ?? result
            reference = combined; index = combined; metadataRevision += 1; revision += 1
            if url == nil { message = "Team artwork is unavailable in this build. Your TV guide still works." }
            onUpdate?()
        } catch { message = "The saved sports directory could not be opened. Your TV guide still works." }
    }
    func showGuideGames(_ index: SportsDataIndex) { self.index = index; revision += 1 }

    /// Fetches what's due from ESPN for these follows (names, as the follow
    /// model keys them) and lays it over the directory.
    func refresh(follows: HomeFollows) {
        guard loaded, refreshTask == nil else { return }
        let teams: [(ESPN.League, String)] = reference.catalog.teams.compactMap { team in
            guard follows.teamIDs.contains(team.libraryItem.id), let league = ESPN.league(id: team.leagueID) else { return nil }
            return (league, String(team.id.dropFirst(league.id.count + 1)))
        }
        var leagues = Set(teams.map(\.0))
        for league in ESPN.leagues where follows.leagueIDs.contains(SportsLibraryItem(name: league.name, kind: .league).id) { leagues.insert(league) }
        let start = snapshot, espn = espn
        refreshTask = Task { [weak self] in
            defer { self?.refreshTask = nil }
            guard let updated = await espn.refresh(start, teams: teams, leagues: leagues, at: .now), let self else { return }
            self.snapshot = updated
            guard let combined = try? SportsDataIndex(updated.catalog(over: self.base)) else { return }
            self.reference = combined; self.metadataRevision += 1; self.revision += 1
            self.onUpdate?()
        }
    }
    #if DEBUG
    func useSample(_ catalog: SportsCatalog) throws {
        loaded = true; reference = try SportsDataIndex(catalog); index = reference
        metadataRevision += 1; revision += 1; onUpdate?()
    }
    #endif
}
