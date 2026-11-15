import Foundation
import Testing
@testable import SportlyCore

struct LaunchSnapshotTests {
    let source = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func prepared() throws -> PreparedCatalog {
        let channels = (0..<400).map { Channel(id: "c\(String(format: "%03d", $0))", sourceID: source, name: "Channel \(String(format: "%03d", $0))", guideID: "g\($0)", language: "en", region: "US") }
        var programs: [GuideProgram] = []
        for index in 0..<400 {
            programs.append(GuideProgram(id: "ended\(index)", sourceID: source, guideID: "g\(index)", title: "Ended", start: now - 7200, end: now - 60))
            programs.append(GuideProgram(id: "live\(index)", sourceID: source, guideID: "g\(index)", title: "Live", start: now - 600, end: now + 1200))
            programs.append(GuideProgram(id: "late\(index)", sourceID: source, guideID: "g\(index)", title: "Late", start: now + 30 * 3600, end: now + 31 * 3600))
        }
        let encoder = JSONEncoder()
        var overrides: [String: Data] = [:]
        for id in ["c390", "c391", "c392"] { overrides["channel.\(id).favorite"] = try encoder.encode(true) }
        return try PreparedCatalog(channels: channels, programs: programs, activeSources: [source], overrides: overrides)
    }

    @Test func favoritesComeFirstAndLimitHolds() throws {
        let snapshot = LaunchSnapshot(prepared: try prepared(), recentIDs: [], now: now)
        #expect(snapshot.channels.count == LaunchSnapshot.channelLimit)
        #expect(snapshot.favoriteIDs == ["c390", "c391", "c392"])
        #expect(Array(snapshot.channels.prefix(3).map(\.id)) == snapshot.favoriteIDs)
        #expect(Set(snapshot.channels.map(\.id)).count == snapshot.channels.count)
    }

    @Test func recentsFollowFavorites() throws {
        let snapshot = LaunchSnapshot(prepared: try prepared(), recentIDs: ["c350", "c390", "missing"], now: now)
        #expect(snapshot.channels[3].id == "c350")
        #expect(snapshot.lineupIDs.allSatisfy { id in snapshot.channels.contains { $0.id == id } })
    }

    @Test func guideOnlyCoversSnapshotChannelsWithinWindow() throws {
        let snapshot = LaunchSnapshot(prepared: try prepared(), recentIDs: [], now: now)
        let keys = Set(snapshot.channels.map { $0.sourceID.uuidString + "|" + $0.guideID })
        #expect(Set(snapshot.guide.keys).isSubset(of: keys))
        let all = snapshot.guide.values.flatMap { $0 }
        #expect(!all.isEmpty)
        #expect(all.allSatisfy { $0.end > now && $0.start < now + LaunchSnapshot.window })
    }

    @Test func manualGuideMappingIsIncluded() throws {
        let snapshot = LaunchSnapshot(prepared: try prepared(), recentIDs: [], manualGuideIDs: ["c390": "g5"], now: now)
        #expect(snapshot.guide[source.uuidString + "|g5"]?.map(\.id) == ["live5"])
    }

    @Test func activeDropsRemovedSourcesAndEndedListings() throws {
        let snapshot = LaunchSnapshot(prepared: try prepared(), recentIDs: [], now: now)
        let removed = snapshot.active(sources: [], now: now)
        #expect(removed.channels.isEmpty && removed.lineupIDs.isEmpty && removed.favoriteIDs.isEmpty && removed.guide.isEmpty)
        let later = snapshot.active(sources: [source], now: now + 25 * 3600)
        #expect(later.channels.count == snapshot.channels.count)
        #expect(later.guide.isEmpty)
    }

    @Test func roundTripsThroughCatalogCodec() throws {
        let snapshot = try withSports(recentIDs: ["c350"])
        let decoded = try CatalogCodec.decode(LaunchSnapshot.self, from: CatalogCodec.encode(snapshot))
        #expect(decoded.channels == snapshot.channels)
        #expect(decoded.guide == snapshot.guide)
        #expect(decoded.lineupIDs == snapshot.lineupIDs)
        #expect(decoded.sports?.games == snapshot.sports?.games)
        #expect(decoded.sports?.links == snapshot.sports?.links)
    }

    // MARK: Home sports data

    var game: SportsGame { SportsGame(id: "game", leagueID: "nba", homeID: "knicks", awayID: "celtics", timestamp: (now - 600).timeIntervalSince1970, guideEnd: (now + 3 * 3600).timeIntervalSince1970) }

    func sports(feed: String) -> HomeSportsData {
        var data = HomeSportsData()
        data.games = [game]
        data.teams = ["knicks": SportsTeam(id: "knicks", name: "New York Knicks", leagueID: "nba"), "celtics": SportsTeam(id: "celtics", name: "Boston Celtics", leagueID: "nba")]
        data.leagues = ["nba": SportsLeague(id: "nba", name: "NBA")]
        data.links = ["game": [SportsFeedLink(gameID: "game", channelID: feed, programID: nil, validFrom: now - 3600, validUntil: now + 4 * 3600, evidence: "test")]]
        return data
    }

    func withSports(recentIDs: [String] = [], favorites: [Channel]? = nil, feed: String = "c250") throws -> LaunchSnapshot {
        let prepared = try prepared()
        return LaunchSnapshot(favorites: favorites ?? prepared.directory.favorites, recentIDs: recentIDs, lineup: prepared.directory.lineup,
                              channelsByID: prepared.channelsByID, guide: prepared.guide, guideMatches: prepared.guideMappings.matches,
                              sports: sports(feed: feed), now: now)
    }

    @Test func decodesSnapshotWithoutSportsKey() throws {
        let snapshot = try withSports()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        json.removeValue(forKey: "sports")
        let decoded = try CatalogCodec.decode(LaunchSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.sports == nil)
        #expect(decoded.channels.map(\.id) == snapshot.channels.map(\.id))
    }

    @Test func feedChannelsFollowRecentsAndPrecedeLineup() throws {
        let ids = try withSports(recentIDs: ["c350"]).channels.map(\.id)
        #expect(Array(ids.prefix(6)) == ["c390", "c391", "c392", "c350", "c250", "c000"])
    }

    @Test func linksToChannelsOverTheLimitAreDropped() throws {
        let prepared = try prepared()
        let favorites = Array(prepared.directory.lineup.prefix(LaunchSnapshot.channelLimit))
        let snapshot = try withSports(favorites: favorites, feed: "c399")
        #expect(snapshot.sports?.links.isEmpty == true)
        #expect(snapshot.sports?.games.map(\.id) == ["game"])
    }

    @Test func activeDropsEndedGamesAndMissingChannels() throws {
        let snapshot = try withSports()
        let later = snapshot.active(sources: [source], now: now + 3 * 3600 + 60)
        #expect(later.sports?.games.isEmpty == true)
        #expect(later.sports?.links.isEmpty == true)
        let removed = snapshot.active(sources: [], now: now)
        #expect(removed.sports?.links.isEmpty == true)
        #expect(snapshot.active(sources: [source], now: now).sports?.links["game"]?.count == 1)
    }
}
