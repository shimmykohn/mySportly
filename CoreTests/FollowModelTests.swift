import Foundation
import Testing
@testable import SportlyCore

struct FollowModelTests {
    let encoder = JSONEncoder(), decoder = JSONDecoder()
    func data<T: Encodable>(_ value: T) throws -> Data { try encoder.encode(value) }

    @Test func legacyListsBecomeEntries() throws {
        let updates = FollowMigration.updates(values: ["preferences.teams": try data(["New York Knicks"]), "preferences.leagues": try data(["NBA"])])
        let knicks = SportsLibraryItem(name: "New York Knicks", kind: .team), nba = SportsLibraryItem(name: "NBA", kind: .league)
        let team = try decoder.decode(SportsLibraryEntry.self, from: try #require(updates["sports.library.\(knicks.id)"] ?? nil))
        #expect(team.saved && team.item == knicks)
        #expect(updates["sports.library.\(nba.id)"] != nil)
        #expect(updates[FollowMigration.flag] != nil)
    }

    @Test func explicitRemovalWins() throws {
        let knicks = SportsLibraryItem(name: "New York Knicks", kind: .team)
        let updates = FollowMigration.updates(values: ["preferences.teams": try data(["New York Knicks"]),
                                                      "sports.library.\(knicks.id)": try data(SportsLibraryEntry(item: knicks, saved: false))])
        #expect(updates["sports.library.\(knicks.id)"] == nil)
    }

    @Test func savedChannelBecomesFavorite() throws {
        let bookmark = LibraryBookmark(kind: .channel, reference: "ch1", name: "News")
        let category = LibraryBookmark.category(["Sports"])
        let updates = FollowMigration.updates(values: ["library.item.\(bookmark.id)": try data(bookmark), "library.item.\(category.id)": try data(category)])
        #expect(try decoder.decode(Bool.self, from: try #require(updates["channel.ch1.favorite"] ?? nil)))
        #expect(updates.keys.filter { $0.hasPrefix("channel.") }.count == 1)
    }

    @Test func flagMakesItIdempotent() throws {
        let updates = FollowMigration.updates(values: [FollowMigration.flag: try data(true), "preferences.teams": try data(["New York Knicks"])])
        #expect(updates.isEmpty)
    }

    // MARK: Game alerts

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func sports() -> HomeSportsData {
        var data = HomeSportsData()
        let knicks = SportsTeam(id: "knicks", name: "New York Knicks", leagueID: "nba"), celtics = SportsTeam(id: "celtics", name: "Boston Celtics", leagueID: "nba")
        data.teams = ["knicks": knicks, "celtics": celtics]
        data.leagues = ["nba": SportsLeague(id: "nba", name: "NBA")]
        data.games = [
            SportsGame(id: "past", leagueID: "nba", homeID: "celtics", awayID: "knicks", timestamp: (now - 3600).timeIntervalSince1970),
            SportsGame(id: "soon", leagueID: "nba", homeID: "celtics", awayID: "knicks", timestamp: (now + 3600).timeIntervalSince1970),
            SportsGame(id: "far", leagueID: "nba", homeID: "knicks", awayID: "celtics", timestamp: (now + 8 * 86_400).timeIntervalSince1970),
        ]
        return data
    }

    @Test func alertsOnlyForOptedInFutureGames() {
        let knicks = SportsTeam(id: "knicks", name: "New York Knicks", leagueID: "nba")
        let alerts = GameAlerts.plan(sports: sports(), notifyTeamIDs: [knicks.libraryItem.id], now: now)
        #expect(alerts.map(\.gameID) == ["soon"])
        #expect(alerts.first?.title == "New York Knicks at Boston Celtics")
        #expect(alerts.first?.id == "game.soon")
        #expect(GameAlerts.plan(sports: sports(), notifyTeamIDs: [], now: now).isEmpty)
    }

    @Test func alertsDedupeAndCap() {
        var data = sports()
        let both: Set<String> = [data.teams["knicks"]!.libraryItem.id, data.teams["celtics"]!.libraryItem.id]
        #expect(GameAlerts.plan(sports: data, notifyTeamIDs: both, now: now).count == 1)
        data.games = (0..<80).map { SportsGame(id: "g\($0)", leagueID: "nba", homeID: "celtics", awayID: "knicks", timestamp: (now + Double($0 + 1) * 600).timeIntervalSince1970) }
        let capped = GameAlerts.plan(sports: data, notifyTeamIDs: both, now: now)
        #expect(capped.count == GameAlerts.limit)
        #expect(capped.first?.gameID == "g0")
    }
}
