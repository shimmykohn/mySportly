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

@MainActor @Observable final class SportsDataStore {
    private(set) var reference = try! SportsDataIndex()
    private(set) var index = try! SportsDataIndex()
    private(set) var revision = 0
    private(set) var metadataRevision = 0
    private(set) var loaded = false
    private(set) var message: String?
    @ObservationIgnored private let repository = SportsRepository()
    @ObservationIgnored var onUpdate: (() -> Void)?
    var updated: Date? { reference.catalog.fetchedAt > 0 ? Date(timeIntervalSince1970: reference.catalog.fetchedAt) : nil }
    func load() async {
        guard !loaded else { return }; loaded = true
        do {
            let url = Bundle.main.url(forResource: "sports-reference", withExtension: "json")
            let result = try await repository.load(referenceURL: url)
            reference = result; index = result; metadataRevision += 1; revision += 1
            if url == nil { message = "Team artwork is unavailable in this build. Your TV guide still works." }
            onUpdate?()
        } catch { message = "The saved sports directory could not be opened. Your TV guide still works." }
    }
    func showGuideGames(_ index: SportsDataIndex) { self.index = index; revision += 1 }
    #if DEBUG
    func useSample(_ catalog: SportsCatalog) throws {
        loaded = true; reference = try SportsDataIndex(catalog); index = reference
        metadataRevision += 1; revision += 1; onUpdate?()
    }
    #endif
}
