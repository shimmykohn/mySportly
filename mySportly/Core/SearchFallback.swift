import Foundation

/// What an AI-interpreted search asks local search to do.
public struct SearchIntent: Equatable, Sendable {
    public var keywords: [String]
    public var time: String
    public var language: String?
}

/// Interprets a search the local matcher couldn't, using Decisions API choice
/// questions over known values only. The query is sent as data.
public enum SearchFallback {
    public static let input = "Interpret a TV search typed by a viewer. Answer each question only from its listed choices."
    public static let times = ["now", "tonight", "tomorrow", "weekend", "any"]
    static let threshold = 0.6

    public static func questions(query: String, teams: [String], leagues: [String], languages: [String]) -> [DecisionQuestion] {
        let data = DecisionPart.json(.object(["query": .string(query)]))
        func ask(_ name: String, _ text: String, _ values: [String], fallback: String) -> DecisionQuestion? {
            let unique = Array(NSOrderedSet(array: values.filter { !$0.isEmpty && $0 != fallback }).array as! [String]).prefix(Decisions.maxChoices - 1)
            guard !unique.isEmpty else { return nil }
            return DecisionQuestion(name: name, instructions: [.text(text), data], choices: unique.map { DecisionChoice(value: $0) } + [DecisionChoice(value: fallback)])
        }
        return [
            ask("sport", "Which sport is the viewer looking for, if any?", ChannelSport.allCases.map(\.title), fallback: "none"),
            ask("league", "Which league is the viewer looking for, if any?", leagues, fallback: "none"),
            ask("team", "Which team is the viewer looking for, if any?", teams, fallback: "none"),
            ask("time", "When does the viewer want to watch?", times.filter { $0 != "any" }, fallback: "any"),
            ask("language", "Which audio language does the viewer want, if stated?", languages, fallback: "any"),
        ].compactMap { $0 }
    }

    /// The most specific confident subject (team, then league, then sport).
    /// Nil when nothing confident was found.
    public static func intent(from answers: [String: DecisionAnswer]) -> SearchIntent? {
        func value(_ name: String, unless fallback: String) -> String? {
            guard let answer = answers[name], answer.confidence >= threshold, answer.choice != fallback else { return nil }
            return answer.choice
        }
        guard let subject = value("team", unless: "none") ?? value("league", unless: "none") ?? value("sport", unless: "none") else { return nil }
        return SearchIntent(keywords: [subject], time: value("time", unless: "any") ?? "now", language: value("language", unless: "any"))
    }
}
