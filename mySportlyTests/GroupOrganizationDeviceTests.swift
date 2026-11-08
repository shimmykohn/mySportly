import Foundation
import Testing
@testable import mySportly

@MainActor @Suite(.serialized) struct GroupOrganizationDeviceTests {
    @Test func sportsScreenCachesBothScopesAndInvalidatesOnChange() async throws {
        let store = AppStore(inMemory: true); await store.loadDemo()
        let directory = try #require(store.directory), index = try #require(store.queryIndex)
        let date = store.clock
        let request = SportsScreenRequest(catalog: store.queryRevision, links: store.sportsLinkRevision, minute: Int(date.timeIntervalSince1970 / 60), followedOnly: false, following: [], audience: store.audience)
        for _ in 0..<3 {
            await store.sportsScreen.update(request, index: index, directory: directory, sports: store.sportsData.index, matched: [], availableGames: [], at: date)
        }
        #expect(store.sportsScreen.computationCount == 1)
        #expect(store.sportsScreen.loaded.contains(false))
        let changed = SportsScreenRequest(catalog: request.catalog, links: request.links, minute: request.minute + 1, followedOnly: false, following: [], audience: request.audience)
        await store.sportsScreen.update(changed, index: index, directory: directory, sports: store.sportsData.index, matched: [], availableGames: [], at: date + 60)
        #expect(store.sportsScreen.computationCount == 2)
        let mySports = SportsScreenRequest(catalog: request.catalog, links: request.links, minute: request.minute + 1, followedOnly: true, following: [.init(name: "NBA", kind: .league)], audience: request.audience)
        await store.sportsScreen.update(mySports, index: index, directory: directory, sports: store.sportsData.index, matched: [], availableGames: [], at: date + 60)
        #expect(store.sportsScreen.computationCount == 3)
        #expect(store.sportsScreen.isCurrent(changed))
    }
    @Test func savedCatalogSportsRepeatVisitIsImmediate() async throws {
        // Read the encrypted cache directly. A second live AppStore would open
        // another CloudKit mirroring delegate for the app host's same store.
        let catalog = try await CatalogCache().load()
        #expect(!catalog.channels.isEmpty, "Expected the connected device’s saved catalog")
        let prepared = try await catalogWork {
            try PreparedCatalog(channels: catalog.channels, programs: catalog.programs,
                activeSources: Set(catalog.channels.map(\.sourceID)), overrides: [:], guideChannels: catalog.guideChannels)
        }
        let sports = SportsDataStore(); await sports.load()
        let reference = sports.reference, date = Date.now
        let matches = try await catalogWork { try prepared.query.guideGames(reference: reference, refreshed: catalog.refreshed, at: date) }
        let model = SportsScreenModel()
        for followedOnly in [false, true] {
            let request = SportsScreenRequest(catalog: 1, links: 1, minute: Int(date.timeIntervalSince1970 / 60), followedOnly: followedOnly,
                following: [.init(name: "NBA", kind: .league), .init(name: "NFL", kind: .league)], audience: ChannelAudience(scope: .preferred, languages: ["en"], regions: ["US"]))
            let available = Set(matches.links.keys), matched = Set(matches.links.values.flatMap { $0.compactMap(\.programID) })
            let clock = ContinuousClock(), start = ContinuousClock.now
            await model.update(request, index: prepared.query, directory: prepared.directory, sports: matches.index, matched: matched, availableGames: available, at: date)
            let cold = start.duration(to: clock.now), revisitStart = clock.now
            for _ in 0..<20 {
                await model.update(request, index: prepared.query, directory: prepared.directory, sports: matches.index, matched: matched, availableGames: available, at: date)
            }
            let repeated = revisitStart.duration(to: clock.now)
            #expect(cold < .seconds(5)); #expect(repeated < .milliseconds(100))
            print("SPORTS_CACHE_VERIFIED channels=\(catalog.channels.count) my_sports=\(followedOnly) first=\(cold) twenty_revisits=\(repeated)")
        }
        #expect(model.computationCount == 2)
    }
    @Test func groupCorrectionPersistsThroughRebuildAndEmptyFavoritesStayEmpty() async throws {
        let store = AppStore(inMemory: true); await store.loadDemo()
        let group = try #require(store.directory?.nameGroups.groups.first)
        store.setGroupPath(group, path: ["Learning", "Space"])
        await store.waitForCatalog()
        #expect(store.directory?.nameGroups.paths[group.id] == ["Learning", "Space"])
        #expect(store.categories.contains("Learning"))
        let request = FavoritesTodayRequest(catalog: store.queryRevision, sports: store.sportsLinkRevision,
            minute: Int(store.clock.timeIntervalSince1970 / 60), favorites: [.init(name: "Dallas Cowboys", kind: .team)], audience: store.audience)
        await store.favoritesToday.update(request, store: store)
        #expect(store.favoritesToday.listings.isEmpty)
    }
}
