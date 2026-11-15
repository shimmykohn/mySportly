import Foundation

/// Resolves explicit opponent names against the local sports directory. The
/// guide supplies broadcast times; these are never presented as official scores.
public struct GuideGameParser: Sendable {
    private struct TeamRule: Sendable { let team: SportsTeam; let matcher: SportsFollowMatcher }
    private let rules: [TeamRule]
    private let tokens: [String: Set<Int>]
    private let leagueNames: [String: String]
    private let leagueTerms: [(id: String, terms: [String])]
    private let teamsByLeague: [String: [Int]]
    public init(reference: SportsDataIndex) {
        var rules: [TeamRule] = [], tokens: [String: Set<Int>] = [:]
        for team in reference.catalog.teams {
            let position = rules.count
            rules.append(TeamRule(team: team, matcher: SportsFollowMatcher([team.name])))
            let names = [team.name] + (SportsFollowCatalog.choice(named: team.name)?.aliases ?? [])
            for word in names.flatMap({ SportsFollowMatcher.normalize($0).split(separator: " ").map(String.init) }) where word.count > 2 {
                tokens[word, default: []].insert(position)
            }
        }
        self.rules = rules; self.tokens = tokens; leagueNames = reference.leagues.mapValues(\.name)
        teamsByLeague = Dictionary(grouping: rules.indices) { rules[$0].team.leagueID }
        leagueTerms = reference.leagues.values.sorted { $0.id < $1.id }.map { league in
            (league.id, ([league.name] + (SportsFollowCatalog.choice(named: league.name)?.aliases ?? [])).map(SportsFollowMatcher.normalize))
        }
    }
    /// Teams a matchup-looking listing might be about, for a model to choose
    /// from: name-word hits plus every team of a league the listing names.
    public func candidates(title: String, context: String) -> [SportsTeam] {
        guard !SportsGameMatcher.isReplayOrStudio(title) else { return [] }
        let normalized = SportsFollowMatcher.normalize(title.replacingOccurrences(of: "@", with: " at "))
        guard [" vs ", " versus ", " v ", " at "].contains(where: normalized.contains) else { return [] }
        var positions = Set(normalized.split(separator: " ").flatMap { tokens[String($0)] ?? [] })
        let evidence = SportsFollowMatcher.normalize(title + " " + context)
        for league in leagueTerms where league.terms.contains(where: evidence.contains) { positions.formUnion(teamsByLeague[league.id] ?? []) }
        let teams = positions.map { rules[$0].team }.sorted { $0.id < $1.id }
        return teams.count >= 2 ? Array(teams.prefix(Decisions.maxChoices - 1)) : []
    }
    public func opponents(title: String, context: String) -> [SportsTeam]? {
        guard !SportsGameMatcher.isReplayOrStudio(title) else { return nil }
        let normalized = SportsFollowMatcher.normalize(title.replacingOccurrences(of: "@", with: " at "))
        guard [" vs ", " versus ", " v ", " at "].contains(where: normalized.contains) else { return nil }
        let candidates = Set(normalized.split(separator: " ").flatMap { tokens[String($0)] ?? [] })
        let matches = candidates.compactMap { position -> SportsTeam? in
            let rule = rules[position]
            return rule.matcher.matches(text: title, context: context).isEmpty ? nil : rule.team
        }
        // Never guess a winner among several possible opponents or sports.
        guard matches.count == 2, matches[0].leagueID == matches[1].leagueID else { return nil }
        // Historical soccer membership cannot establish today's competition
        // (promotion/relegation or a cup tie). Require the guide to name it.
        if let league = leagueNames[matches[0].leagueID], ["MLS", "Premier League"].contains(league) {
            let evidence = SportsFollowMatcher.normalize(title + " " + context)
            let names = [league] + (SportsFollowCatalog.choice(named: league)?.aliases ?? [])
            guard names.contains(where: { evidence.contains(SportsFollowMatcher.normalize($0)) }) else { return nil }
        }
        return matches.sorted { $0.id < $1.id }
    }
}

public struct GuideGameMatches: Sendable {
    public let index: SportsDataIndex
    public let links: [String: [SportsFeedLink]]
}
