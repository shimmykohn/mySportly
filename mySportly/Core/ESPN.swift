import Foundation

/// Teams, logos and schedules from ESPN's public site feeds. They're free and
/// need no key, but they're undocumented and ESPN's terms don't cover app use:
/// fine for personal and TestFlight builds, not for an App Store release.
/// Each device fetches and keeps its own copy; nothing is re-published.
public enum ESPN {
    public struct League: Hashable, Sendable {
        /// Matches the follow catalog's league names, so follows carry over.
        public let name: String
        /// "football/nfl"
        public let path: String
        public var id: String { "espn." + path.replacingOccurrences(of: "/", with: ".") }
        /// Soccer team schedules list results unless asked for fixtures.
        var isSoccer: Bool { path.hasPrefix("soccer/") }
        var isCollege: Bool { path.contains("college") }
    }

    public static let leagues: [League] = [
        ("NFL", "football/nfl"), ("NBA", "basketball/nba"), ("WNBA", "basketball/wnba"), ("MLB", "baseball/mlb"),
        ("NHL", "hockey/nhl"), ("MLS", "soccer/usa.1"), ("Premier League", "soccer/eng.1"),
        ("UEFA Champions League", "soccer/uefa.champions"), ("La Liga", "soccer/esp.1"), ("Bundesliga", "soccer/ger.1"),
        ("Serie A", "soccer/ita.1"), ("Ligue 1", "soccer/fra.1"), ("Liga MX", "soccer/mex.1"),
        ("College Football", "football/college-football"), ("Men's College Basketball", "basketball/mens-college-basketball"),
    ].map { League(name: $0.0, path: $0.1) }
    public static func league(id: String) -> League? { leagues.first { $0.id == id } }

    static let base = "https://site.api.espn.com/apis/site/v2/sports/"
    public static func teamsURL(_ league: League) -> URL { URL(string: base + league.path + "/teams?limit=1000")! }
    /// One day's games, by the US Eastern date ESPN files them under.
    public static func scoreboardURL(_ league: League, day: Date) -> URL {
        // FBS games for college football; the default is only ranked teams.
        URL(string: base + league.path + "/scoreboard?limit=500&dates=" + dayKey(day) + (league.path == "football/college-football" ? "&groups=80" : ""))!
    }
    /// A team's season.
    public static func scheduleURL(_ league: League, teamID: String) -> URL {
        URL(string: base + league.path + "/teams/" + teamID + "/schedule" + (league.isSoccer ? "?fixture=true" : ""))!
    }
    public static func dayKey(_ day: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public struct Team: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var shortName: String
        public var nickname: String
        public var location: String
        public var abbreviation: String
        public var color: String?
        public var logo: URL?
        public var darkLogo: URL?
    }

    public struct Event: Codable, Hashable, Sendable {
        public var id: String
        public var leagueID: String
        public var start: Double
        public var homeID: String
        public var awayID: String
        public var status: SportsGameStatus
        public var networks: [String]
    }

    // MARK: Decoding

    private struct Logo: Decodable { let href: String?; let rel: [String]? }
    private struct RawTeam: Decodable {
        let id: String?; let displayName: String?; let shortDisplayName: String?; let name: String?; let location: String?
        let abbreviation: String?; let color: String?; let logos: [Logo]?
        /// Scoreboards give one logo URL instead of the list.
        let logo: String?
    }

    /// A league's teams from its `teams` feed.
    public static func teams(_ data: Data) throws -> [Team] {
        struct Entry: Decodable { let team: RawTeam }
        struct LeagueBody: Decodable { let teams: [Entry]? }
        struct Sport: Decodable { let leagues: [LeagueBody]? }
        struct Body: Decodable { let sports: [Sport]? }
        let body = try JSONDecoder().decode(Body.self, from: data)
        return (body.sports ?? []).flatMap { $0.leagues ?? [] }.flatMap { $0.teams ?? [] }.compactMap { team($0.team) }
    }

    private static func team(_ raw: RawTeam) -> Team? {
        guard let id = raw.id, let name = raw.displayName, !id.isEmpty, !name.isEmpty else { return nil }
        let logos = raw.logos ?? []
        func logo(_ dark: Bool) -> URL? {
            logos.first { ($0.rel ?? []).contains("default") == !dark && ($0.rel ?? []).contains("dark") == dark }?.href.flatMap(URL.init(string:))
                ?? (dark ? nil : (logos.first?.href ?? raw.logo).flatMap(URL.init(string:)))
        }
        return Team(id: id, name: name, shortName: raw.shortDisplayName ?? name, nickname: raw.name ?? "", location: raw.location ?? "",
                    abbreviation: raw.abbreviation ?? "", color: raw.color, logo: logo(false), darkLogo: logo(true))
    }

    /// Games from a scoreboard or a team schedule. Teams seen only here (an
    /// opponent outside the league's list) come back too, for the catalog.
    public static func events(_ data: Data, league: League) throws -> (events: [Event], teams: [Team], logo: URL?) {
        struct Named: Decodable { let names: [String]?; let media: Media? }
        struct Media: Decodable { let shortName: String? }
        struct Geo: Decodable { let media: Media? }
        struct StatusType: Decodable { let state: String?; let name: String? }
        struct Status: Decodable { let type: StatusType? }
        struct Competitor: Decodable { let homeAway: String?; let team: RawTeam? }
        struct Competition: Decodable {
            let competitors: [Competitor]?; let broadcasts: [Named]?; let geoBroadcasts: [Geo]?; let status: Status?; let date: String?
        }
        struct RawEvent: Decodable { let id: String?; let date: String?; let status: Status?; let competitions: [Competition]? }
        struct LeagueInfo: Decodable { let logos: [Logo]? }
        struct Body: Decodable { let events: [RawEvent]?; let leagues: [LeagueInfo]? }
        let body = try JSONDecoder().decode(Body.self, from: data)
        var events: [Event] = [], teams: [String: Team] = [:]
        for raw in body.events ?? [] {
            guard let id = raw.id, let competition = raw.competitions?.first,
                  let start = date(competition.date ?? raw.date ?? ""),
                  let home = competition.competitors?.first(where: { $0.homeAway == "home" })?.team.flatMap(team),
                  let away = competition.competitors?.first(where: { $0.homeAway == "away" })?.team.flatMap(team),
                  home.id != away.id else { continue }
            teams[home.id] = teams[home.id] ?? home; teams[away.id] = teams[away.id] ?? away
            let type = (competition.status ?? raw.status)?.type
            var networks: [String] = []
            for name in (competition.broadcasts ?? []).flatMap({ ($0.names ?? []) + [$0.media?.shortName].compactMap { $0 } })
                + (competition.geoBroadcasts ?? []).compactMap({ $0.media?.shortName }) where !name.isEmpty && !networks.contains(name) {
                networks.append(name)
            }
            events.append(Event(id: id, leagueID: league.id, start: start.timeIntervalSince1970, homeID: home.id, awayID: away.id,
                                status: status(state: type?.state, name: type?.name), networks: networks))
        }
        let logo = body.leagues?.first?.logos?.first?.href.flatMap(URL.init(string:))
        return (events, Array(teams.values), logo)
    }

    static func status(state: String?, name: String?) -> SportsGameStatus {
        let name = (name ?? "").uppercased()
        if name.contains("POSTPONED") || name.contains("DELAYED") { return .postponed }
        if name.contains("CANCEL") { return .cancelled }
        switch state {
        case "pre": return .scheduled
        case "in": return .live
        case "post": return .finished
        default: return .unknown
        }
    }

    /// "2026-11-22T18:00Z", with or without seconds.
    static func date(_ text: String) -> Date? {
        for format in ["yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

/// What a device has fetched from ESPN, saved between launches.
public struct ESPNSnapshot: Codable, Sendable {
    public var teams: [String: [ESPN.Team]] = [:]
    public var leagueLogos: [String: URL] = [:]
    public var events: [String: ESPN.Event] = [:]
    /// Feed key ("teams.<league>", "day.<league>.<yyyymmdd>", "team.<league>.<id>") → when it was fetched.
    public var fetched: [String: Double] = [:]
    public init() {}

    public func isFresh(_ key: String, maxAge: TimeInterval, at date: Date) -> Bool {
        fetched[key].map { date.timeIntervalSince1970 - $0 < maxAge } ?? false
    }

    /// Adds a feed's events, replacing the ones it already had.
    public mutating func store(_ found: (events: [ESPN.Event], teams: [ESPN.Team], logo: URL?), league: ESPN.League, key: String, at date: Date) {
        for event in found.events { events[event.id] = event }
        var known = Dictionary((teams[league.id] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for team in found.teams {
            if known[team.id] == nil { known[team.id] = team }
            // A team first seen without a logo takes one from a later feed.
            else if known[team.id]?.logo == nil, let logo = team.logo { known[team.id]?.logo = logo }
        }
        teams[league.id] = Array(known.values)
        if let logo = found.logo { leagueLogos[league.id] = logo }
        fetched[key] = date.timeIntervalSince1970
    }

    /// Drops games that ended more than two days ago.
    public mutating func prune(at date: Date) {
        events = events.filter { $0.value.start > date.timeIntervalSince1970 - 2 * 86_400 }
    }

    /// The bundled directory with ESPN's teams, logos and games laid over it.
    /// A league ESPN covers takes ESPN's teams; a team keeps the name the app
    /// already knew it by, so follows and favorites carry over.
    public func catalog(over reference: SportsCatalog) -> SportsCatalog {
        var catalog = reference
        let covered = ESPN.leagues.filter { !(teams[$0.id] ?? []).isEmpty }
        let replaced = Set(catalog.leagues.filter { league in covered.contains { $0.name == league.name } }.map(\.id))
        catalog.leagues.removeAll { replaced.contains($0.id) }
        catalog.teams.removeAll { replaced.contains($0.leagueID) }
        var usedNames = Set(catalog.teams.map(\.name))
        for league in covered {
            catalog.leagues.append(SportsLeague(id: league.id, name: league.name, logo: leagueLogos[league.id]))
            for team in (teams[league.id] ?? []).sorted(by: { $0.id < $1.id }) {
                var name = SportsFollowCatalog.knownName(for: team, league: league.name)
                // Two teams can't share a name: the follow model keys on it.
                if usedNames.contains(name) { name += " (\(league.name))" }
                guard !usedNames.contains(name) else { continue }
                usedNames.insert(name)
                var entry = SportsTeam(id: league.id + "." + team.id, name: name, leagueID: league.id, logo: team.logo)
                let aliases = [team.shortName, team.name].filter { $0 != name && $0.count > 3 }
                entry.aliases = aliases.isEmpty ? nil : aliases
                catalog.teams.append(entry)
            }
        }
        let teamIDs = Set(catalog.teams.map(\.id))
        catalog.games = events.values.compactMap { event -> SportsGame? in
            let home = event.leagueID + "." + event.homeID, away = event.leagueID + "." + event.awayID
            guard teamIDs.contains(home), teamIDs.contains(away) else { return nil }
            var game = SportsGame(id: "espn." + event.id, leagueID: event.leagueID, homeID: home, awayID: away, timestamp: event.start, status: event.status)
            game.networks = event.networks.isEmpty ? nil : event.networks
            return game
        }.sorted { $0.id < $1.id }
        return catalog
    }
}

extension SportsFollowCatalog {
    /// The name the follow catalog already uses for an ESPN team, matched by
    /// full name, "location nickname", short name or alias in its league; else
    /// ESPN's own display name.
    static func knownName(for team: ESPN.Team, league: String) -> String {
        let candidates = [team.name, team.location + " " + team.nickname, team.shortName, team.nickname]
            .map(GroupNames.normalized).filter { !$0.isEmpty }
        let choices = teams.filter { $0.league == league }
        for candidate in candidates {
            if let choice = choices.first(where: { GroupNames.normalized($0.name) == candidate }) { return choice.name }
        }
        for candidate in candidates.prefix(2) {
            if let choice = choices.first(where: { $0.aliases.contains { GroupNames.normalized($0) == candidate } }) { return choice.name }
        }
        return team.name
    }
}

/// Hosts the app loads team and league logos from. Logos come from public
/// data files, so only these known image hosts are fetched.
public enum SportsArtwork {
    public static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "media.api-sports.io" || host == "espncdn.com" || host.hasSuffix(".espncdn.com")
    }
}

/// Matching a schedule's TV network to a channel name.
public enum SportsNetworks {
    /// ESPN's short names for networks whose channels go by their full name.
    static let aliases: [String: String] = [
        "usanet": "usanetwork", "nflnet": "nflnetwork", "mlbn": "mlbnetwork", "nhlnet": "nhlnetwork", "nhln": "nhlnetwork",
        "cbssn": "cbssportsnetwork", "secn": "secnetwork", "accn": "accnetwork", "btn": "bigtennetwork", "fs1": "foxsports1",
        "fs2": "foxsports2", "nbatv": "nbatv", "golf": "golfchannel", "tsn": "tsn1", "abc": "abc", "espnu": "espnu",
    ]
    /// Letters and digits of the locally cleaned name, lowercased, without a
    /// trailing East/West; a known short name maps to the full one.
    public static func key(_ name: String) -> String {
        var words = GroupNames.normalized(NameCleaning.local(name)).split(separator: " ").map(String.init)
        if let last = words.last, ["east", "west", "hd", "us", "usa"].contains(last), words.count > 1 { words.removeLast() }
        let joined = words.joined()
        return aliases[joined] ?? joined
    }
}
