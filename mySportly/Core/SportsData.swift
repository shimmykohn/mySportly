import Foundation

public struct SportsLeague: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var logo: URL?
    public init(id: String, name: String, logo: URL? = nil) { self.id = id; self.name = name; self.logo = logo }
    public var libraryItem: SportsLibraryItem { SportsLibraryItem(name: name, kind: .league) }
}

public struct SportsTeam: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var leagueID: String
    public var logo: URL?
    /// Other names guide listings use ("Man United"), from the schedule source.
    public var aliases: [String]?
    public init(id: String, name: String, leagueID: String, logo: URL? = nil) {
        self.id = id; self.name = name; self.leagueID = leagueID; self.logo = logo
    }
    public var libraryItem: SportsLibraryItem { SportsLibraryItem(name: name, kind: .team) }
}

public enum SportsGameStatus: String, Codable, Sendable { case scheduled, live, finished, postponed, cancelled, unknown }

public struct SportsGame: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var leagueID: String
    public var homeID: String
    public var awayID: String
    /// Unix seconds, shared with the server; never inferred from the device's calendar year.
    public var timestamp: Double
    public var status: SportsGameStatus
    public var guideEnd: Double?
    /// TV networks carrying it, from the schedule ("CBS", "ESPN2").
    public var networks: [String]?
    public init(id: String, leagueID: String, homeID: String, awayID: String, timestamp: Double, status: SportsGameStatus = .scheduled, guideEnd: Double? = nil) {
        self.id = id; self.leagueID = leagueID; self.homeID = homeID; self.awayID = awayID; self.timestamp = timestamp; self.status = status
        self.guideEnd = guideEnd
    }
    public var start: Date { Date(timeIntervalSince1970: timestamp) }
    public func canWatch(at date: Date) -> Bool {
        (status == .scheduled || status == .live) && date >= start - (guideEnd == nil ? 30 * 60 : 0) && date < min(start + 8 * 3600, guideEnd.map(Date.init(timeIntervalSince1970:)) ?? .distantFuture)
    }
}

public struct SportsCatalog: Codable, Sendable {
    public var version: Int = 1
    public var fetchedAt: Double
    public var leagues: [SportsLeague]
    public var teams: [SportsTeam]
    public var games: [SportsGame]
    public var issues: [String: String]
    public init(fetchedAt: Double = 0, leagues: [SportsLeague] = [], teams: [SportsTeam] = [], games: [SportsGame] = [], issues: [String: String] = [:]) {
        self.fetchedAt = fetchedAt; self.leagues = leagues; self.teams = teams; self.games = games; self.issues = issues
    }
    public func validate() throws {
        guard version == 1, fetchedAt.isFinite, leagues.count <= 100, teams.count <= 10_000, games.count <= 20_000,
              Set(leagues.map(\.id)).count == leagues.count, Set(teams.map(\.id)).count == teams.count,
              Set(games.map(\.id)).count == games.count else { throw SportsDataError.invalidData }
        let leagueIDs = Set(leagues.map(\.id)), teamIDs = Set(teams.map(\.id))
        guard leagues.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }),
              games.allSatisfy({ $0.timestamp.isFinite && ($0.guideEnd == nil || ($0.guideEnd!.isFinite && $0.guideEnd! > $0.timestamp)) && leagueIDs.contains($0.leagueID) && teamIDs.contains($0.homeID) && teamIDs.contains($0.awayID) && $0.homeID != $0.awayID }),
              teams.allSatisfy({ !$0.id.isEmpty && leagueIDs.contains($0.leagueID) && !$0.name.isEmpty }) else { throw SportsDataError.invalidData }
    }
}

public enum SportsDataError: Error, Sendable { case invalidData, unavailable, notConfigured, quota }

/// Small immutable dictionaries keep logos and schedules out of SwiftUI's expensive work.
public struct SportsDataIndex: Sendable {
    public let catalog: SportsCatalog
    public let teams: [String: SportsTeam]
    public let leagues: [String: SportsLeague]
    public let games: [String: SportsGame]
    public let orderedGames: [SportsGame]
    public let choices: [SportsFollowChoice]
    private let logos: [String: URL]
    private let teamLeagues: [String: String]
    private let membership: [String: Set<String>]
    private let leagueTeams: [String: [SportsLibraryItem]]
    public init(_ catalog: SportsCatalog = SportsCatalog()) throws {
        try catalog.validate()
        self.catalog = catalog
        teams = Dictionary(uniqueKeysWithValues: catalog.teams.map { ($0.id, $0) })
        leagues = Dictionary(uniqueKeysWithValues: catalog.leagues.map { ($0.id, $0) })
        games = Dictionary(uniqueKeysWithValues: catalog.games.map { ($0.id, $0) })
        orderedGames = catalog.games.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        var logos: [String: URL] = [:], membership: [String: Set<String>] = [:], teamLeagues: [String: String] = [:]
        var choices = Dictionary(uniqueKeysWithValues: (SportsFollowCatalog.teams + SportsFollowCatalog.leagues).map { ($0.name, $0) })
        for league in catalog.leagues {
            if let logo = league.logo { logos[league.libraryItem.id] = logo }
            choices[league.libraryItem.name] = SportsFollowChoice(name: league.libraryItem.name, kind: .league, league: league.name, aliases: [])
        }
        for team in catalog.teams {
            teamLeagues[team.libraryItem.id] = leagues[team.leagueID]?.name
            if let logo = team.logo { logos[team.libraryItem.id] = logo }
            let existing = SportsFollowCatalog.choice(named: team.name)
            choices[team.libraryItem.name] = SportsFollowChoice(name: team.libraryItem.name, kind: .team, league: leagues[team.leagueID]?.name ?? "", aliases: existing?.aliases ?? [])
        }
        for game in orderedGames {
            if let home = teams[game.homeID] { membership[home.libraryItem.id, default: []].insert(game.id) }
            if let away = teams[game.awayID] { membership[away.libraryItem.id, default: []].insert(game.id) }
            if let league = leagues[game.leagueID] { membership[league.libraryItem.id, default: []].insert(game.id) }
        }
        self.logos = logos; self.membership = membership; self.teamLeagues = teamLeagues
        self.choices = choices.values.sorted { $0.name < $1.name }
        var leagueTeams: [String: [SportsLibraryItem]] = [:]
        for choice in self.choices where choice.kind == .team && !choice.league.isEmpty {
            let league = SportsLibraryItem(name: choice.league, kind: .league)
            leagueTeams[league.id, default: []].append(SportsLibraryItem(name: choice.name, kind: .team))
        }
        self.leagueTeams = leagueTeams
    }
    public func logo(for item: SportsLibraryItem) -> URL? { logos[item.id] }
    public func leagueName(for item: SportsLibraryItem) -> String { teamLeagues[item.id] ?? item.league }
    public func teams(in league: SportsLibraryItem) -> [SportsLibraryItem] { leagueTeams[league.id] ?? [] }
    public func gamesToday(for items: [SportsLibraryItem], at date: Date, calendar: Calendar = .current) -> [SportsGame] {
        guard let day = calendar.dateInterval(of: .day, for: date) else { return [] }
        return schedule(for: items, at: date).filter { game in
            guard game.status == .scheduled || game.status == .live, game.start < day.end else { return false }
            // A guide interval may cross midnight. A past scheduled start alone
            // is not evidence that an event is still live.
            return game.start >= date || (game.canWatch(at: date) && (game.guideEnd != nil || game.status == .live))
        }
    }
    public func schedule(for items: [SportsLibraryItem]?, at date: Date) -> [SportsGame] {
        let ids = items.map { Set($0.flatMap { membership[$0.id] ?? [] }) }
        return orderedGames.filter { game in
            (ids == nil || ids!.contains(game.id)) && game.start >= date - 8 * 3600 && game.start < date + 7 * 86400 && (game.guideEnd ?? .greatestFiniteMagnitude) > date.timeIntervalSince1970 && game.status != .finished && game.status != .cancelled
        }
    }
}

public struct SportsFeedLink: Codable, Hashable, Sendable {
    public var gameID: String
    public var channelID: String
    public var programID: String?
    public var validFrom: Date
    public var validUntil: Date
    public var evidence: String
    public func isValid(at date: Date) -> Bool { date >= validFrom && date < validUntil }
}

/// Index candidate games by team words, then require both participants and time
/// evidence. A network name or league name alone never becomes a game link.
public struct SportsGameMatcher: Sendable {
    private struct Candidate: Sendable {
        let game: SportsGame
        let home: SportsFollowMatcher
        let away: SportsFollowMatcher
    }
    private let candidates: [Candidate]
    private let tokens: [String: Set<Int>]
    private static let clockPattern = try! NSRegularExpression(pattern: #"(?i)\b(\d{1,2}):(\d{2})\s*(am|pm)?\b"#)
    private static let datePattern = try! NSRegularExpression(pattern: #"\b(20\d{2})-(\d{1,2})-(\d{1,2})\b|\b(\d{1,2})/(\d{1,2})(?:/(\d{4}))?\b"#)
    public init(index: SportsDataIndex) {
        var candidates: [Candidate] = [], tokens: [String: Set<Int>] = [:]
        for game in index.orderedGames where game.status == .scheduled || game.status == .live {
            guard let home = index.teams[game.homeID], let away = index.teams[game.awayID] else { continue }
            let position = candidates.count
            candidates.append(Candidate(game: game, home: SportsFollowMatcher([home.name]), away: SportsFollowMatcher([away.name])))
            for team in [home, away] {
                let aliases = [team.name] + (SportsFollowCatalog.choice(named: team.name)?.aliases ?? [])
                for word in aliases.flatMap({ SportsFollowMatcher.normalize($0).split(separator: " ").map(String.init) }) where word.count > 2 {
                    tokens[word, default: []].insert(position)
                }
            }
        }
        self.candidates = candidates; self.tokens = tokens
    }
    public func match(title: String, context: String, start: Date, end: Date) -> SportsGame? {
        guard end > start, !Self.isReplayOrStudio(title) else { return nil }
        let possible = matchingParticipants(title: title, context: context).filter {
            abs($0.start.timeIntervalSince(start)) <= 90 * 60 && end > $0.start + 10 * 60
        }.sorted { abs($0.start.timeIntervalSince(start)) < abs($1.start.timeIntervalSince(start)) }
        guard let first = possible.first else { return nil }
        if possible.count > 1, abs(abs(possible[1].start.timeIntervalSince(start)) - abs(first.start.timeIntervalSince(start))) < 30 * 60 { return nil }
        return first
    }
    public func matchChannel(name: String, group: String, refreshed: Date?, at date: Date, timeZone: TimeZone) -> SportsGame? {
        guard name.contains(":"), !candidates.isEmpty, let refreshed, date.timeIntervalSince(refreshed) >= -300, date.timeIntervalSince(refreshed) < 6 * 3600 else { return nil }
        let ns = name as NSString
        let clockMatches = Self.clockPattern.matches(in: name, range: NSRange(location: 0, length: ns.length))
        // Most catalogs use prefixes such as "US:". A colon alone is not a
        // clock; reject those before normalizing names or allocating calendars.
        guard !clockMatches.isEmpty, !ListingAvailability.isInactiveChannel(name), !Self.isReplayOrStudio(name) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard !Self.hasConflictingDate(name, date: date, calendar: calendar) else { return nil }
        // Require an explicit start time. Reused slots without a time stay unmatched.
        let participants = matchingParticipants(title: name, context: group)
        guard !participants.isEmpty else { return nil }
        let clocks = clockMatches.compactMap { result -> Int? in
            guard let rawHour = Int(ns.substring(with: result.range(at: 1))), let minute = Int(ns.substring(with: result.range(at: 2))), minute < 60 else { return nil }
            var hour = rawHour
            if result.range(at: 3).location != NSNotFound {
                guard (1...12).contains(hour) else { return nil }
                hour %= 12
                if ns.substring(with: result.range(at: 3)).lowercased() == "pm" { hour += 12 }
            }
            guard hour < 24 else { return nil }; return hour * 60 + minute
        }
        guard !clocks.isEmpty else { return nil }
        let matches = participants.filter { game in
            guard calendar.isDate(game.start, inSameDayAs: date), game.start > date - 8 * 3600 else { return false }
            let components = calendar.dateComponents([.hour, .minute], from: game.start)
            let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            return clocks.contains { abs($0 - minutes) <= 15 }
        }
        return matches.count == 1 ? matches.first : nil
    }
    private func matchingParticipants(title: String, context: String) -> [SportsGame] {
        let words = SportsFollowMatcher.normalize(title).split(separator: " ").map(String.init)
        let ids = Set(words.flatMap { tokens[$0] ?? [] })
        return ids.compactMap { position in
            let candidate = candidates[position]
            // Context is provider evidence only, never the candidate's guessed league.
            guard !candidate.home.matches(text: title, context: context).isEmpty,
                  !candidate.away.matches(text: title, context: context).isEmpty else { return nil }
            return candidate.game
        }
    }
    private static func hasConflictingDate(_ title: String, date: Date, calendar: Calendar) -> Bool {
        let expected = calendar.dateComponents([.year, .month, .day], from: date), ns = title as NSString
        for match in datePattern.matches(in: title, range: NSRange(location: 0, length: ns.length)) {
            func number(_ part: Int) -> Int? {
                let range = match.range(at: part)
                return range.location == NSNotFound ? nil : Int(ns.substring(with: range))
            }
            let iso = number(1) != nil
            if let year = number(iso ? 1 : 6), year != expected.year { return true }
            if number(iso ? 2 : 4) != expected.month || number(iso ? 3 : 5) != expected.day { return true }
        }
        return false
    }
    static func isReplayOrStudio(_ text: String) -> Bool {
        let value = SportsFollowMatcher.normalize(text)
        return [" replay ", " highlights ", " classic ", " pregame ", " pre game ", " postgame ", " post game ", " preview "].contains(where: value.contains)
    }
}
