import Foundation
import Testing
@testable import SportlyCore

struct AIResultsTests {
    let source = UUID()

    @Test func variantOverridesAndDisplayNames() throws {
        var results = AIResults()
        results.names["FOX SPORTS 1"] = "Fox Sports 1"
        results.merges = ["k": MergeAnswer(same: true, ids: ["a", "c"]), "n": MergeAnswer(same: false, ids: ["a", "d"])]
        #expect(results.mergedPairs == [["a", "c"]])
        let overrides = AIResults.variantOverrides([["a", "b"]])
        #expect(try JSONDecoder().decode([String].self, from: #require(overrides["channel.b.variants"])) == ["a", "b"])
        #expect(results.displayName("US| ESPN HD") == "ESPN")
        #expect(results.displayName("FOX SPORTS 1") == "Fox Sports 1")
    }

    @Test func pruneDropsEndedGamesAndVanishedChannels() {
        var results = AIResults()
        let now = Date(timeIntervalSince1970: 1_000)
        results.games = ["old": DetectedGame(teams: ["a", "b"], expires: 900), "new": DetectedGame(teams: [], expires: 2_000)]
        results.names = ["Gone": "Gone", "Kept HD": "Kept"]
        results.namesAsked = ["Gone", "Kept HD"]
        results.merges = ["stale": MergeAnswer(same: true, ids: ["x", "y"])]
        results.prune(at: now, channels: [Channel(id: "k", sourceID: source, name: "Kept HD")], candidates: [])
        #expect(Array(results.games.keys) == ["new"])
        #expect(results.names == ["Kept HD": "Kept"])
        #expect(results.namesAsked == ["Kept HD"])
        #expect(results.merges.isEmpty)
        #expect(results.detectedGames.isEmpty)
    }

    @Test func summaryCountsWhatWasFoundAndOldFilesStillDecode() throws {
        var results = AIResults()
        results.games = ["g": DetectedGame(teams: ["a", "b"], expires: 2_000), "n": DetectedGame(teams: [], expires: 2_000)]
        results.merges = ["k": MergeAnswer(same: true, ids: ["a", "c"]), "n": MergeAnswer(same: false, ids: ["a", "d"])]
        results.names = ["FOX SPORTS 1": "Fox Sports 1", "ESPN": "ESPN"]
        results.namesAsked = ["FOX SPORTS 1", "ESPN", "XYZ"]
        results.lastRun = 1_000
        let summary = results.summary
        #expect(summary == AIActivitySummary(gamesFound: 1, listingsChecked: 2, feedsCombined: 1, pairsChecked: 2,
                                             namesTidied: 1, namesChecked: 3, lastRun: Date(timeIntervalSince1970: 1_000)))
        let old = #"{"version":1,"merges":{},"games":{},"names":{},"namesAsked":[]}"#
        #expect(try JSONDecoder().decode(AIResults.self, from: Data(old.utf8)).lastRun == nil)
    }

    @Test func titleAnswersSurviveUntilTheCatalogIsLoaded() {
        var results = AIResults()
        results.vodNames = ["EN | HEAT (1995)": "Heat", "Gone": "Gone"]
        results.vodNamesAsked = ["EN | HEAT (1995)", "Gone"]
        results.pruneVOD(rawTitles: [])
        #expect(results.vodNames?.count == 2, "Not loaded yet: keep everything")
        results.pruneVOD(rawTitles: ["EN | HEAT (1995)"])
        #expect(results.vodNames == ["EN | HEAT (1995)": "Heat"])
        #expect(results.vodNamesAsked == ["EN | HEAT (1995)"])
        #expect(results.summary.namesTidied == 1)
    }
}
