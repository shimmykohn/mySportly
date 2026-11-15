import Foundation

public enum SportsFollowKind: String, CaseIterable, Codable, Sendable { case team = "Teams", league = "Leagues" }

public struct SportsLibraryItem: Codable, Identifiable, Hashable, Sendable {
    public let name: String
    public let kind: SportsFollowKind
    public var id: String { (kind == .team ? "team." : "league.") + StableID.hash(SportsFollowMatcher.normalize(name)) }
    public var league: String { SportsFollowCatalog.choice(named: name)?.league ?? "" }
    public init(name: String, kind: SportsFollowKind) {
        if let choice = SportsFollowCatalog.choice(named: name), choice.kind == kind { self.name = choice.name }
        else { self.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        self.kind = kind
    }
}

/// Explicit removals also override older follow lists received from iCloud.
public struct SportsLibraryEntry: Codable, Sendable {
    public let item: SportsLibraryItem
    public let saved: Bool
    public init(item: SportsLibraryItem, saved: Bool) { self.item = item; self.saved = saved }
}

/// League contents are derived from the directory. Only directItems are saved
/// in Library; items also includes teams available when browsing a saved league.
public struct SportsLibraryMembership: Sendable {
    public let items: [SportsLibraryItem]
    public let directItems: [SportsLibraryItem]
    public let following: [SportsLibraryItem]
    private let ids: Set<String>
    private let inherited: [String: SportsLibraryItem]

    public init(saved: [SportsLibraryItem] = [], choices: [SportsFollowChoice] = []) {
        var direct: [String: SportsLibraryItem] = [:]
        for item in saved { direct[item.id] = item }
        let leagues = direct.filter { $0.value.kind == .league }
        var all = direct, inherited: [String: SportsLibraryItem] = [:]
        for choice in choices where choice.kind == .team && !choice.league.isEmpty {
            let league = SportsLibraryItem(name: choice.league, kind: .league)
            guard let savedLeague = leagues[league.id] else { continue }
            let team = SportsLibraryItem(name: choice.name, kind: .team)
            all[team.id] = team; inherited[team.id] = savedLeague
        }
        func ordered(_ items: [SportsLibraryItem]) -> [SportsLibraryItem] {
            items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        directItems = ordered(Array(direct.values))
        items = ordered(Array(all.values)); ids = Set(all.keys); self.inherited = inherited
        // A saved league already matches its members. Avoid redundant matchers.
        following = directItems.filter { inherited[$0.id] == nil }
    }
    public func contains(_ item: SportsLibraryItem) -> Bool { ids.contains(item.id) }
    public func leagueIncluding(_ item: SportsLibraryItem) -> SportsLibraryItem? { inherited[item.id] }
}

/// An offline vocabulary, not a fixture or a source of schedules/scores.
public struct SportsFollowChoice: Identifiable, Sendable {
    public let name: String
    public let kind: SportsFollowKind
    public let league: String
    public let aliases: [String]
    public var id: String { name }
}

public enum SportsFollowCatalog {
    public static let leagues: [SportsFollowChoice] = [
        ("NFL", "National Football League"), ("NBA", "National Basketball Association"),
        ("WNBA", "Women's National Basketball Association"), ("MLB", "Major League Baseball"),
        ("NHL", "National Hockey League"), ("MLS", "Major League Soccer"),
        ("Premier League", "English Premier League"), ("UEFA Champions League", "Champions League"),
        ("Formula 1", "Formula One|F1"), ("UFC", "Ultimate Fighting Championship")
    ].map { SportsFollowChoice(name: $0.0, kind: .league, league: $0.0, aliases: $0.1.components(separatedBy: "|")) }

    public static let teams: [SportsFollowChoice] = {
        let groups: [(String, String)] = [
            ("NFL", """
            Arizona Cardinals|Cardinals
            Atlanta Falcons|Falcons
            Baltimore Ravens|Ravens
            Buffalo Bills|Bills
            Carolina Panthers|Panthers
            Chicago Bears|Bears
            Cincinnati Bengals|Bengals
            Cleveland Browns|Browns
            Dallas Cowboys|Cowboys
            Denver Broncos|Broncos
            Detroit Lions|Lions
            Green Bay Packers|Packers
            Houston Texans|Texans
            Indianapolis Colts|Colts
            Jacksonville Jaguars|Jaguars
            Kansas City Chiefs|Chiefs
            Las Vegas Raiders|Raiders
            Los Angeles Chargers|Chargers|LA Chargers
            Los Angeles Rams|Rams|LA Rams
            Miami Dolphins|Dolphins
            Minnesota Vikings|Vikings
            New England Patriots|Patriots
            New Orleans Saints|Saints
            New York Giants|Giants|NY Giants
            New York Jets|Jets|NY Jets
            Philadelphia Eagles|Eagles
            Pittsburgh Steelers|Steelers
            San Francisco 49ers|49ers|SF 49ers
            Seattle Seahawks|Seahawks
            Tampa Bay Buccaneers|Buccaneers|Bucs
            Tennessee Titans|Titans
            Washington Commanders|Commanders
            """),
            ("NBA", """
            Atlanta Hawks|Hawks
            Boston Celtics|Celtics
            Brooklyn Nets|Nets
            Charlotte Hornets|Hornets
            Chicago Bulls|Bulls
            Cleveland Cavaliers|Cavaliers|Cavs
            Dallas Mavericks|Mavericks|Mavs
            Denver Nuggets|Nuggets
            Detroit Pistons|Pistons
            Golden State Warriors|Warriors
            Houston Rockets|Rockets
            Indiana Pacers|Pacers
            LA Clippers|Clippers|Los Angeles Clippers
            Los Angeles Lakers|Lakers|LA Lakers
            Memphis Grizzlies|Grizzlies
            Miami Heat|Heat
            Milwaukee Bucks|Bucks
            Minnesota Timberwolves|Timberwolves
            New Orleans Pelicans|Pelicans
            New York Knicks|Knicks|NY Knicks
            Oklahoma City Thunder|Thunder|OKC Thunder
            Orlando Magic|Magic
            Philadelphia 76ers|76ers|Sixers
            Phoenix Suns|Suns
            Portland Trail Blazers|Trail Blazers|Blazers
            Sacramento Kings|Kings
            San Antonio Spurs|Spurs
            Toronto Raptors|Raptors
            Utah Jazz|Jazz
            Washington Wizards|Wizards
            """),
            ("MLB", """
            Arizona Diamondbacks|Diamondbacks|Dbacks
            Athletics|Oakland Athletics|A's
            Atlanta Braves|Braves
            Baltimore Orioles|Orioles
            Boston Red Sox|Red Sox
            Chicago Cubs|Cubs
            Chicago White Sox|White Sox
            Cincinnati Reds|Reds
            Cleveland Guardians|Guardians
            Colorado Rockies|Rockies
            Detroit Tigers|Tigers
            Houston Astros|Astros
            Kansas City Royals|Royals
            Los Angeles Angels|Angels|LA Angels
            Los Angeles Dodgers|Dodgers|LA Dodgers
            Miami Marlins|Marlins
            Milwaukee Brewers|Brewers
            Minnesota Twins|Twins
            New York Mets|Mets|NY Mets
            New York Yankees|Yankees|NY Yankees
            Philadelphia Phillies|Phillies
            Pittsburgh Pirates|Pirates
            San Diego Padres|Padres
            San Francisco Giants|Giants|SF Giants
            Seattle Mariners|Mariners
            St. Louis Cardinals|Cardinals
            Tampa Bay Rays|Rays
            Texas Rangers|Rangers
            Toronto Blue Jays|Blue Jays
            Washington Nationals|Nationals
            """),
            ("NHL", """
            Anaheim Ducks|Ducks
            Boston Bruins|Bruins
            Buffalo Sabres|Sabres
            Calgary Flames|Flames
            Carolina Hurricanes|Hurricanes
            Chicago Blackhawks|Blackhawks
            Colorado Avalanche|Avalanche
            Columbus Blue Jackets|Blue Jackets
            Dallas Stars|Stars
            Detroit Red Wings|Red Wings
            Edmonton Oilers|Oilers
            Florida Panthers|Panthers
            Los Angeles Kings|Kings|LA Kings
            Minnesota Wild|Wild
            Montreal Canadiens|Canadiens|Habs
            Nashville Predators|Predators
            New Jersey Devils|Devils|NJ Devils
            New York Islanders|Islanders|NY Islanders
            New York Rangers|Rangers|NY Rangers
            Ottawa Senators|Senators
            Philadelphia Flyers|Flyers
            Pittsburgh Penguins|Penguins
            San Jose Sharks|Sharks
            Seattle Kraken|Kraken
            St. Louis Blues|Blues
            Tampa Bay Lightning|Lightning
            Toronto Maple Leafs|Maple Leafs
            Utah Mammoth|Mammoth
            Vancouver Canucks|Canucks
            Vegas Golden Knights|Golden Knights
            Washington Capitals|Capitals
            Winnipeg Jets|Jets
            """)
        ]
        return groups.flatMap { league, rows in
            rows.split(separator: "\n").map { row in
                let parts = row.components(separatedBy: "|")
                return SportsFollowChoice(name: parts[0], kind: .team, league: league, aliases: Array(parts.dropFirst()))
            }
        }.sorted { $0.name < $1.name }
    }()

    private static let lookup: (names: [String: SportsFollowChoice], aliases: [String: SportsFollowChoice]) = {
        var names: [String: SportsFollowChoice] = [:], aliases: [String: SportsFollowChoice] = [:]
        var ambiguous = Set<String>()
        for choice in teams + leagues {
            names[SportsFollowMatcher.normalize(choice.name)] = choice
            for alias in Set(choice.aliases.map(SportsFollowMatcher.normalize)) {
                if let previous = aliases[alias], previous.name != choice.name { ambiguous.insert(alias) }
                aliases[alias] = choice
            }
        }
        for alias in ambiguous { aliases.removeValue(forKey: alias) }
        return (names, aliases)
    }()
    public static func choice(named name: String) -> SportsFollowChoice? {
        let value = SportsFollowMatcher.normalize(name)
        return lookup.names[value] ?? lookup.aliases[value]
    }
}

/// Whole phrases prevent NBA matching WNBA, or "Mets" matching "Comets".
/// Ambiguous nicknames (Giants, Jets, etc.) need the correct sport/league context.
public struct SportsFollowMatcher: Sendable {
    private struct Rule: Sendable {
        let name: String
        let direct: [String]
        let contextual: [String]
        let context: [String]
        func matches(_ text: String, context: String) -> Bool {
            direct.contains(where: text.contains) ||
                (contextual.contains(where: text.contains) && self.context.contains(where: context.contains))
        }
    }
    private struct Follow: Sendable { let name: String; let rules: [Rule]; let league: Bool }
    private let follows: [Follow]
    public var isEmpty: Bool { follows.isEmpty }
    private static let ambiguous: Set<String> = ["cardinals", "panthers", "giants", "jets", "kings", "rangers", "heat", "magic", "jazz", "wild", "stars", "blues", "athletics"]

    public init(_ names: [String]) {
        var seen = Set<String>()
        follows = names.compactMap { input in
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let choice = SportsFollowCatalog.choice(named: trimmed) else {
                let key = Self.normalize(trimmed)
                guard trimmed.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains), seen.insert(key).inserted else { return nil }
                return Follow(name: trimmed, rules: [Rule(name: trimmed, direct: [key], contextual: [], context: [])], league: false)
            }
            guard seen.insert(choice.name).inserted else { return nil }
            var rules = [Self.rule(choice)]
            if choice.kind == .league { rules += SportsFollowCatalog.teams.filter { $0.league == choice.name }.map(Self.rule) }
            return Follow(name: choice.name, rules: rules, league: choice.kind == .league)
        }
    }
    public func matches(text: String, context: String = "") -> [String] {
        let body = Self.normalize(text), surroundings = Self.normalize(text + " " + context)
        return follows.compactMap { follow in
            follow.rules.contains { $0.matches(follow.league ? surroundings : body, context: surroundings) } ? follow.name : nil
        }
    }
    public static func normalize(_ text: String) -> String {
        " " + text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ") + " "
    }
    private static func rule(_ choice: SportsFollowChoice) -> Rule {
        let words = [choice.name] + choice.aliases
        let conditional = words.filter { ambiguous.contains($0.lowercased()) }
        let sport = ["NFL": "football", "NBA": "basketball", "MLB": "baseball", "NHL": "hockey"][choice.league] ?? ""
        return Rule(name: choice.name, direct: words.filter { !conditional.contains($0) }.map(normalize), contextual: conditional.map(normalize), context: [choice.league, sport].filter { !$0.isEmpty }.map(normalize))
    }
}
