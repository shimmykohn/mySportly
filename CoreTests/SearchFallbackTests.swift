import Foundation
import Testing
@testable import SportlyCore

struct SearchFallbackTests {
    func answer(_ name: String, _ choice: String, _ confidence: Double = 0.9) -> DecisionAnswer {
        DecisionAnswer(name: name, choice: choice, confidence: confidence, probability: 0.9)
    }

    @Test func questionsCarryTheQueryAsDataWithAFallbackChoice() throws {
        let questions = SearchFallback.questions(query: "knicks tonight", teams: ["New York Knicks"], leagues: ["NBA"], languages: ["en", "es"])
        #expect(questions.map(\.name) == ["sport", "league", "team", "time", "language"])
        #expect(questions.first { $0.name == "team" }?.choices.map(\.value) == ["New York Knicks", "none"])
        #expect(questions.first { $0.name == "time" }?.choices.last?.value == "any")
        let json = String(decoding: try JSONEncoder().encode(DecisionsRequest(input: SearchFallback.input, questions: questions)), as: UTF8.self)
        #expect(json.contains(#""query":"knicks tonight""#))
        #expect(json.contains(#""type":"input_json""#))
    }

    @Test func teamBeatsLeagueAndTimeAndLanguageCarryOver() {
        let intent = SearchFallback.intent(from: ["team": answer("team", "New York Knicks"), "league": answer("league", "NBA"),
                                                  "time": answer("time", "tonight"), "language": answer("language", "es")])
        #expect(intent == SearchIntent(keywords: ["New York Knicks"], time: "tonight", language: "es"))
    }

    @Test func lowConfidenceAndNoneGiveNoIntent() {
        #expect(SearchFallback.intent(from: ["team": answer("team", "New York Knicks", 0.4), "sport": answer("sport", "none")]) == nil)
        #expect(SearchFallback.intent(from: ["sport": answer("sport", "Basketball"), "time": answer("time", "any")])?.time == "now")
    }

    @Test func emptyListsDropTheirQuestion() {
        #expect(!SearchFallback.questions(query: "x", teams: [], leagues: [], languages: []).contains { $0.name == "team" })
    }
}
