import Foundation
import Testing
@testable import SportlyCore

struct GameDetectionTests {
    private let source = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func reference() throws -> SportsDataIndex {
        try SportsDataIndex(SportsCatalog(fetchedAt: start.timeIntervalSince1970,
            leagues: [.init(id: "nfl", name: "NFL"), .init(id: "nba", name: "NBA")],
            teams: [.init(id: "dal", name: "Dallas Cowboys", leagueID: "nfl"), .init(id: "gb", name: "Green Bay Packers", leagueID: "nfl"),
                    .init(id: "lal", name: "Los Angeles Lakers", leagueID: "nba"), .init(id: "bos", name: "Boston Celtics", leagueID: "nba")]))
    }
    private func query(_ title: String, summary: String = "", group: String = "NBA") throws -> CatalogQueryIndex {
        let channel = Channel(id: "c", sourceID: source, name: "Sports 1", group: group, guideID: "g")
        let program = GuideProgram(id: "p", sourceID: source, guideID: "g", title: title, summary: summary, start: start + 600, end: start + 3 * 3600, categories: ["Sports"])
        return try CatalogQueryIndex(channels: [channel], programs: [program])
    }
    private func answer(_ name: String, _ choice: String, _ confidence: Double = 0.95) -> DecisionAnswer {
        DecisionAnswer(name: name, choice: choice, confidence: confidence, probability: confidence)
    }

    @Test func abbreviatedMatchupsBecomeCandidatesOfTheNamedLeague() throws {
        let listings = try query("LAL @ BOS").unresolvedGameListings(reference: reference(), at: start, known: [])
        let listing = try #require(listings.first)
        #expect(listings.count == 1)
        #expect(Set(listing.candidates.map(\.id)) == ["lal", "bos"])
        #expect(try query("LAL @ BOS").unresolvedGameListings(reference: reference(), at: start, known: [listing.key]).isEmpty)
    }

    @Test func listingsTheParserResolvesOrThatArentMatchupsAreSkipped() throws {
        #expect(try query("Cowboys at Packers", group: "NFL").unresolvedGameListings(reference: reference(), at: start, known: []).isEmpty)
        #expect(try query("SportsCenter").unresolvedGameListings(reference: reference(), at: start, known: []).isEmpty)
        #expect(try query("LAL @ BOS Highlights").unresolvedGameListings(reference: reference(), at: start, known: []).isEmpty)
    }

    @Test func confidentDistinctSameLeagueAnswersBecomeGames() throws {
        let data = try reference()
        let listing = try #require(try query("LAL @ BOS").unresolvedGameListings(reference: data, at: start, known: []).first)
        let questions = GameDetection.questions([listing], leagues: data.leagues)
        #expect(questions.count == 2)
        #expect(questions[0].choices.last?.value == "none")
        let good = GameDetection.resolve([listing.key + ".1": answer("1", "lal"), listing.key + ".2": answer("2", "bos")], listings: [listing], teams: data.teams)
        #expect(good[listing.key]?.teams == ["bos", "lal"])
        let unsure = GameDetection.resolve([listing.key + ".1": answer("1", "lal", 0.5), listing.key + ".2": answer("2", "bos")], listings: [listing], teams: data.teams)
        #expect(unsure[listing.key]?.teams == [])
        let mixed = GameDetection.resolve([listing.key + ".1": answer("1", "lal"), listing.key + ".2": answer("2", "dal")], listings: [listing], teams: data.teams)
        #expect(mixed[listing.key]?.teams == [])
        let refused = GameDetection.resolve([listing.key + ".1": answer("1", "lal")], listings: [listing], teams: data.teams)
        #expect(refused[listing.key] == nil)
    }

    @Test func detectedTeamsFeedGuideGames() throws {
        let data = try reference()
        let index = try query("LAL @ BOS")
        #expect(try index.guideGames(reference: data, refreshed: [:], at: start).index.games.isEmpty)
        let key = GameDetection.key(title: "LAL @ BOS", summary: "")
        let result = try index.guideGames(reference: data, refreshed: [:], at: start, detected: [key: ["bos", "lal"]])
        let game = try #require(result.index.orderedGames.first)
        #expect(Set([game.homeID, game.awayID]) == ["bos", "lal"])
        #expect(result.links[game.id]?.map(\.channelID) == ["c"])
    }
}
