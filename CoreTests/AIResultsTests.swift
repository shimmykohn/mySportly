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
}
