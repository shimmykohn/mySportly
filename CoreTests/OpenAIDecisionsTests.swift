import Foundation
import Testing
@testable import SportlyCore

struct OpenAIDecisionsTests {
    func question(_ name: String) -> DecisionQuestion {
        DecisionQuestion(name: name, instructions: [.text("Pick one")], choices: [DecisionChoice(value: "a"), DecisionChoice(value: "b")])
    }

    @Test func requestMatchesTheDocumentedShape() throws {
        let request = DecisionsRequest(input: "context", questions: [DecisionQuestion(name: "q", instructions: [.text("Which?"), .json(.object(["name": .string("ESPN")]))],
                                                                                   choices: [DecisionChoice(value: "a", description: "first"), DecisionChoice(value: "b")])])
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(json["model"] as? String == "gpt-6-luna")
        #expect(json["input"] as? String == "context")
        let question = try #require((json["questions"] as? [[String: Any]])?.first)
        #expect(question["type"] as? String == "choice")
        #expect(question["name"] as? String == "q")
        let parts = try #require(question["instructions"] as? [[String: Any]])
        #expect(parts.map { $0["type"] as? String } == ["input_text", "input_json"])
        #expect((parts[1]["data"] as? [String: String])?["name"] == "ESPN")
        let choices = try #require(question["choices"] as? [[String: Any]])
        #expect(choices.first?["value"] as? String == "a" && choices.first?["description"] as? String == "first")
    }

    @Test func answersDecodeInOrderAndRefusalsAreSkipped() throws {
        let request = DecisionsRequest(input: "x", questions: [question("one"), question("two")])
        let body = #"{"model":"gpt-6-luna","answers":[{"type":"choice","name":"one","choice":"b","confidence":0.8,"probabilities":[{"value":"a","probability":0.1},{"value":"b","probability":0.9}]},{"type":"refusal","name":"two"}],"usage":{"input_tokens":1,"input_tokens_details":{"cached_tokens":0,"cache_write_tokens":0},"output_tokens":0,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":1}}"#
        let answers = try DecisionsClient.decode(Data(body.utf8), for: request)
        #expect(answers["one"] == DecisionAnswer(name: "one", choice: "b", confidence: 0.8, probability: 0.9))
        #expect(answers["two"] == nil)
    }

    @Test func malformedProbabilitiesAndMismatchedNamesAreRejected() {
        let request = DecisionsRequest(input: "x", questions: [question("one")])
        let badSum = #"{"answers":[{"type":"choice","name":"one","choice":"a","confidence":0.8,"probabilities":[{"value":"a","probability":0.5},{"value":"b","probability":0.2}]}]}"#
        let wrongName = #"{"answers":[{"type":"choice","name":"other","choice":"a","confidence":0.8,"probabilities":[{"value":"a","probability":1}]}]}"#
        #expect(throws: DecisionsFailure.self) { try DecisionsClient.decode(Data(badSum.utf8), for: request) }
        #expect(throws: DecisionsFailure.self) { try DecisionsClient.decode(Data(wrongName.utf8), for: request) }
    }

    @Test func groupQuestionsRejectTooManyChoices() throws {
        let source = UUID()
        let channels = ["Golf 01", "Golf 02"].enumerated().map { Channel(id: "c\($0.offset)", sourceID: source, name: $0.element, group: "Sports", language: "en", region: "US") }
        var resolver = ChannelMetadataResolver()
        let metadata = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, resolver.resolve($0)) })
        let group = try #require(try CatalogGroupIndex(channels: channels, metadata: metadata, placements: [:]).groups.first)
        let choices = GroupTaxonomy(paths: (0..<254).map { ["Category \($0)"] }).children(of: [])
        #expect(throws: GroupDecisionFailure.self) { try OpenAIGroupModel.questions([GroupDecisionInput(group: group, parent: [], choices: choices)]) }
    }
}
