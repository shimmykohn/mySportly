import Foundation
import Testing
@testable import SportlyCore

struct SearchGroupingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let source = UUID()
    let choices = [
        SportsFollowChoice(name: "New York Knicks", kind: .team, league: "NBA", aliases: ["Knicks"]),
        SportsFollowChoice(name: "New York Jets", kind: .team, league: "NFL", aliases: ["Jets"]),
        SportsFollowChoice(name: "New York Giants", kind: .team, league: "NFL", aliases: ["Giants"]),
        SportsFollowChoice(name: "NBA", kind: .league, league: "NBA", aliases: []),
    ]

    func match(_ id: String, live: Bool) -> CatalogMatch {
        let program = live ? GuideProgram(id: "p\(id)", sourceID: source, guideID: id, title: "Show", start: now - 60, end: now + 60) : nil
        return CatalogMatch(channel: Channel(id: id, sourceID: source, name: id), name: id, program: program)
    }

    @Test func teamsMatchNicknameAndFollowedComeFirst() {
        let knicks = SearchGrouping.group(query: "knicks", matches: [], choices: choices, followedIDs: [], at: now)
        #expect(knicks.teams.map(\.name) == ["New York Knicks"])
        let giants = SportsLibraryItem(name: "New York Giants", kind: .team)
        let newYork = SearchGrouping.group(query: "new york", matches: [], choices: choices, followedIDs: [giants.id], at: now)
        #expect(newYork.teams.map(\.name) == ["New York Giants", "New York Jets", "New York Knicks"])
        #expect(!newYork.teams.contains { $0.kind == .league })
    }

    @Test func shortQueriesSkipTeams() {
        #expect(SearchGrouping.group(query: "n", matches: [], choices: choices, followedIDs: [], at: now).teams.isEmpty)
    }

    @Test func liveMatchesGoToLiveNowOnly() {
        let groups = SearchGrouping.group(query: "news", matches: [match("a", live: false), match("b", live: true), match("c", live: false)], choices: [], followedIDs: [], at: now)
        #expect(groups.liveNow.map(\.id) == ["b"])
        #expect(groups.channels.map(\.id) == ["a", "c"])
    }

    @Test func recentsDedupeAndCap() {
        var list: [String] = []
        for query in ["nba", "News", " NBA ", ""] { list = RecentSearches.adding(query, to: list) }
        #expect(list == ["NBA", "News"])
        for index in 0..<12 { list = RecentSearches.adding("q\(index)", to: list) }
        #expect(list.count == RecentSearches.limit)
        #expect(list.first == "q11")
    }
}
