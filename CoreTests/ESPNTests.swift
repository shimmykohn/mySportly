import Foundation
import Testing
@testable import SportlyCore

@Suite struct ESPNTests {
    private let league = ESPN.leagues.first { $0.name == "NFL" }!

    @Test func teamsDecodeWithLogosAndKeepTheAppsNames() throws {
        let json = #"{"sports":[{"leagues":[{"teams":[{"team":{"id":"6","displayName":"Dallas Cowboys","shortDisplayName":"Cowboys","name":"Cowboys","location":"Dallas","abbreviation":"DAL","color":"002a5c","logos":[{"href":"https://a.espncdn.com/i/teamlogos/nfl/500/dal.png","rel":["full","default"]},{"href":"https://a.espncdn.com/i/teamlogos/nfl/500-dark/dal.png","rel":["full","dark"]}]}}]}]}]}"#
        let teams = try ESPN.teams(Data(json.utf8))
        #expect(teams.count == 1)
        #expect(teams[0].logo?.absoluteString == "https://a.espncdn.com/i/teamlogos/nfl/500/dal.png")
        #expect(teams[0].darkLogo?.absoluteString.contains("500-dark") == true)
        var snapshot = ESPNSnapshot(); snapshot.teams[league.id] = teams
        let catalog = snapshot.catalog(over: SportsCatalog(leagues: [SportsLeague(id: "old.nfl", name: "NFL")],
                                                           teams: [SportsTeam(id: "old.dal", name: "Dallas Cowboys", leagueID: "old.nfl")]))
        // ESPN's team replaces the old one under the same name, so follows carry over.
        #expect(catalog.teams.map(\.id) == [league.id + ".6"])
        #expect(catalog.teams[0].name == "Dallas Cowboys" && catalog.leagues.map(\.id) == [league.id])
        #expect(catalog.teams[0].aliases == ["Cowboys"])
        try catalog.validate()
    }

    @Test func scoreboardTeamsKeepTheirSingleLogo() throws {
        let json = #"{"events":[{"id":"501","date":"2026-11-22T18:00Z","competitions":[{"competitors":[{"homeAway":"home","team":{"id":"6","displayName":"Dallas Cowboys","logo":"https://a.espncdn.com/i/teamlogos/nfl/500/scoreboard/dal.png"}},{"homeAway":"away","team":{"id":"10","displayName":"Tennessee Titans"}}]}]}]}"#
        let found = try ESPN.events(Data(json.utf8), league: league)
        #expect(found.teams.first { $0.id == "6" }?.logo?.absoluteString == "https://a.espncdn.com/i/teamlogos/nfl/500/scoreboard/dal.png")
        // A team saved without a logo picks one up from a later feed.
        var snapshot = ESPNSnapshot()
        snapshot.teams[league.id] = [ESPN.Team(id: "6", name: "Dallas Cowboys", shortName: "Cowboys", nickname: "Cowboys", location: "Dallas", abbreviation: "DAL")]
        snapshot.store(found, league: league, key: "day", at: .now)
        #expect(snapshot.teams[league.id]?.first { $0.id == "6" }?.logo != nil)
    }

    @Test func logosLoadOnlyFromKnownImageHosts() {
        #expect(SportsArtwork.isAllowed(URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500/dal.png")!))
        #expect(SportsArtwork.isAllowed(URL(string: "https://media.api-sports.io/basketball/teams/151.png")!))
        #expect(!SportsArtwork.isAllowed(URL(string: "http://a.espncdn.com/i/teamlogos/nfl/500/dal.png")!))
        #expect(!SportsArtwork.isAllowed(URL(string: "https://espncdn.com.example.net/logo.png")!))
        #expect(!SportsArtwork.isAllowed(URL(string: "https://example.com/logo.png")!))
    }

    @Test func scoreboardEventsDecodeStatusNetworksAndTimes() throws {
        let json = #"{"leagues":[{"logos":[{"href":"https://a.espncdn.com/i/teamlogos/leagues/500/nfl.png"}]}],"events":[{"id":"401","date":"2026-11-22T18:00Z","status":{"type":{"state":"pre","name":"STATUS_SCHEDULED"}},"competitions":[{"competitors":[{"homeAway":"home","team":{"id":"6","displayName":"Dallas Cowboys"}},{"homeAway":"away","team":{"id":"10","displayName":"Tennessee Titans"}}],"broadcasts":[{"names":["Fox"]}]}]},{"id":"402","date":"2026-11-23T01:20Z","competitions":[{"status":{"type":{"state":"post","name":"STATUS_POSTPONED"}},"competitors":[{"homeAway":"home","team":{"id":"9","displayName":"Green Bay Packers"}},{"homeAway":"away","team":{"id":"3","displayName":"Chicago Bears"}}],"broadcasts":[{"media":{"shortName":"NBC"}}]}]}]}"#
        let found = try ESPN.events(Data(json.utf8), league: league)
        #expect(found.events.count == 2)
        let first = try #require(found.events.first { $0.id == "401" })
        #expect(first.homeID == "6" && first.awayID == "10" && first.status == .scheduled && first.networks == ["Fox"])
        #expect(first.start == ISO8601DateFormatter().date(from: "2026-11-22T18:00:00Z")!.timeIntervalSince1970)
        #expect(found.events.first { $0.id == "402" }?.status == .postponed)
        #expect(found.events.first { $0.id == "402" }?.networks == ["NBC"])
        #expect(found.teams.count == 4 && found.logo != nil)

        var snapshot = ESPNSnapshot()
        snapshot.store(found, league: league, key: "day", at: .now)
        let catalog = snapshot.catalog(over: SportsCatalog())
        #expect(catalog.games.count == 2 && catalog.games.allSatisfy { $0.id.hasPrefix("espn.") })
        #expect(catalog.games.first { $0.id == "espn.401" }?.networks == ["Fox"])
        try catalog.validate()
    }

    @Test func oldGamesArePrunedAndFeedsKnowWhenTheyreFresh() {
        var snapshot = ESPNSnapshot()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        snapshot.events["old"] = ESPN.Event(id: "old", leagueID: league.id, start: now.timeIntervalSince1970 - 3 * 86_400, homeID: "1", awayID: "2", status: .finished, networks: [])
        snapshot.events["new"] = ESPN.Event(id: "new", leagueID: league.id, start: now.timeIntervalSince1970 + 3_600, homeID: "1", awayID: "2", status: .scheduled, networks: [])
        snapshot.prune(at: now)
        #expect(snapshot.events.keys.sorted() == ["new"])
        snapshot.fetched["teams"] = now.timeIntervalSince1970 - 100
        #expect(snapshot.isFresh("teams", maxAge: 3_600, at: now) && !snapshot.isFresh("teams", maxAge: 50, at: now))
        #expect(ESPN.dayKey(Date(timeIntervalSince1970: 1_795_402_800)) == "20261122")
    }
}
