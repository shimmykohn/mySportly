import Foundation

/// A sports listing that looks like a matchup the local parser couldn't
/// resolve. One answer covers every channel carrying the same title and summary.
public struct GameListing: Hashable, Sendable {
    public let key: String
    public let title: String
    public let summary: String
    public let context: String
    public let candidates: [SportsTeam]
    public let end: Date
}

/// Teams a listing is about (sorted by ID, like the local parser), or none
/// when the model said it isn't a known game. Dropped after `expires`.
public struct DetectedGame: Codable, Hashable, Sendable {
    public var teams: [String]
    public var expires: Double
    public init(teams: [String], expires: Double) { self.teams = teams; self.expires = expires }
}

public enum GameDetection {
    static let input = "Identify the two teams in TV guide listings for sports broadcasts. Each pair of questions is about one independent listing."
    /// Listings further ahead than this wait for a later run.
    public static let horizon: TimeInterval = 3 * 86400

    public static func key(title: String, summary: String) -> String {
        StableID.hash(SportsFollowMatcher.normalize(title) + "|" + SportsFollowMatcher.normalize(summary))
    }

    public static func questions(_ listings: [GameListing], leagues: [String: SportsLeague]) -> [DecisionQuestion] {
        listings.flatMap { listing -> [DecisionQuestion] in
            var choices = listing.candidates.map { team in
                DecisionChoice(value: team.id, description: [team.name, leagues[team.leagueID]?.name].compactMap { $0 }.joined(separator: " · "))
            }
            choices.append(DecisionChoice(value: "none", description: "Not a game between two of these teams (studio show, replay, other sport or team)."))
            let data = DecisionPart.json(.object(["title": .string(listing.title), "description": .string(listing.summary), "channel": .string(listing.context)]))
            return [
                DecisionQuestion(name: listing.key + ".1", instructions: [.text("Which team is named first in this listing's matchup?"), data], choices: choices),
                DecisionQuestion(name: listing.key + ".2", instructions: [.text("Which team is named second in this listing's matchup?"), data], choices: choices),
            ]
        }
    }

    /// Both answers must be confident, different teams of one league.
    /// Refused listings are left unanswered so a later run can ask again.
    public static func resolve(_ answers: [String: DecisionAnswer], listings: [GameListing], teams: [String: SportsTeam]) -> [String: DetectedGame] {
        func confident(_ answer: DecisionAnswer) -> Bool { answer.confidence >= 0.70 && answer.probability >= 0.80 }
        var result: [String: DetectedGame] = [:]
        for listing in listings {
            guard let first = answers[listing.key + ".1"], let second = answers[listing.key + ".2"] else { continue }
            let expires = listing.end.timeIntervalSince1970
            guard confident(first), confident(second), first.choice != "none", second.choice != "none", first.choice != second.choice,
                  let a = teams[first.choice], let b = teams[second.choice], a.leagueID == b.leagueID else {
                result[listing.key] = DetectedGame(teams: [], expires: expires); continue
            }
            result[listing.key] = DetectedGame(teams: [a.id, b.id].sorted(), expires: expires)
        }
        return result
    }
}
