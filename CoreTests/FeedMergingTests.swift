import Foundation
import Testing
@testable import SportlyCore

struct FeedMergingTests {
    let source = UUID()
    func channel(_ id: String, _ name: String, guide: String = "", region: String = "") -> Channel {
        Channel(id: id, sourceID: source, name: name, guideID: guide, region: region)
    }

    @Test func baseKeepsNumbersAndDropsQualityAndPrefix() {
        #expect(FeedMerging.base("US| ESPN 2 FHD") == "espn 2")
        #expect(FeedMerging.base("ESPN 2 HD (B)") == "espn 2")
        #expect(FeedMerging.base("ESPN") == "espn")
    }

    @Test func candidatesPairLooseCopiesButNotDifferentNumbersOrRegions() {
        let channels = [
            channel("a", "US| ESPN FHD", guide: "espn.us"), channel("b", "US| ESPN HD", guide: "espn.us"),
            channel("c", "US| ESPN BACKUP"), channel("d", "US| ESPN 2 HD"), channel("e", "UK| ESPN HD"),
        ]
        let strict = FeedMerging.strictGroups(channels)
        #expect(strict == [["a", "b"]])
        let pairs = FeedMerging.candidates(channels, strict: strict)
        // a/b already strict: one representative of them against c only.
        #expect(pairs.count == 1)
        #expect(Set([pairs[0].anchor.id, pairs[0].other.id]) == ["a", "c"])
    }

    @Test func confirmedPairsJoinStrictGroups() {
        let channels = [channel("a", "ESPN FHD", guide: "x"), channel("b", "ESPN HD", guide: "x"), channel("c", "ESPN BACKUP")]
        let strict = FeedMerging.strictGroups(channels)
        let pairs = FeedMerging.candidates(channels, strict: strict)
        #expect(FeedMerging.groups(strict: strict, pairs: []) == [["a", "b"]])
        let confirmed = pairs.map { [$0.anchor.id, $0.other.id] }
        #expect(FeedMerging.groups(strict: strict, pairs: confirmed) == [["a", "b", "c"]])
        #expect(FeedMerging.groups(strict: strict, pairs: confirmed, present: ["a", "b"]) == [["a", "b"]])
    }

    @Test func largeOrNamelessGroupsAreNotAsked() {
        let many = (0..<20).map { channel("m\($0)", "Event HD") }
        #expect(FeedMerging.candidates(many, strict: []).isEmpty)
    }

    @Test func onlyConfidentSameAnswersCount() {
        #expect(FeedMerging.accepted(DecisionAnswer(name: "k", choice: "same", confidence: 0.9, probability: 0.9)))
        #expect(!FeedMerging.accepted(DecisionAnswer(name: "k", choice: "same", confidence: 0.6, probability: 0.9)))
        #expect(!FeedMerging.accepted(DecisionAnswer(name: "k", choice: "different", confidence: 0.99, probability: 0.99)))
    }

    @Test func questionsAreTwoWayChoices() {
        let pair = MergeCandidate(anchor: channel("a", "ESPN"), other: channel("b", "ESPN HD"))
        let question = FeedMerging.questions([pair])[0]
        #expect(question.name == pair.key)
        #expect(question.choices.map(\.value) == ["same", "different"])
    }
}
