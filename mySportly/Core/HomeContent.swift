import Foundation

/// What Home is built around. IDs are `SportsLibraryItem.id` values, so the
/// follow model can change without touching Home.
public struct HomeFollows: Hashable, Sendable {
    public var teamIDs: Set<String>
    public var leagueIDs: Set<String>
    public init(teamIDs: Set<String> = [], leagueIDs: Set<String> = []) { self.teamIDs = teamIDs; self.leagueIDs = leagueIDs }
    public var isEmpty: Bool { teamIDs.isEmpty && leagueIDs.isEmpty }
}

/// Games from the guide with the teams, leagues and feed links they reference.
public struct HomeSportsData: Codable, Sendable {
    public var games: [SportsGame] = []
    public var teams: [String: SportsTeam] = [:]
    public var leagues: [String: SportsLeague] = [:]
    public var links: [String: [SportsFeedLink]] = [:]
    public init() {}

    /// The part Home can show for these follows: live games, and games
    /// starting within 7 days, of followed teams or added leagues.
    public func relevant(to follows: HomeFollows, at date: Date) -> HomeSportsData {
        var result = HomeSportsData()
        result.games = games.filter { game in
            guard let state = game.homeState(at: date), state == .live || game.start < date + HomeContent.teamWindow else { return false }
            return involvesFollowedTeam(game, follows) || leagues[game.leagueID].map { follows.leagueIDs.contains($0.libraryItem.id) } == true
        }
        for game in result.games {
            for id in [game.homeID, game.awayID] { result.teams[id] = teams[id] }
            result.leagues[game.leagueID] = leagues[game.leagueID]
            result.links[game.id] = links[game.id]
        }
        return result
    }

    func involvesFollowedTeam(_ game: SportsGame, _ follows: HomeFollows) -> Bool {
        [game.homeID, game.awayID].contains { teams[$0].map { follows.teamIDs.contains($0.libraryItem.id) } == true }
    }
}

public enum HomeGameState: Hashable, Sendable { case live, upcoming }

extension SportsGame {
    /// Live while the guide window is open, upcoming before it, otherwise gone.
    public func homeState(at date: Date) -> HomeGameState? {
        if start <= date { return canWatch(at: date) ? .live : nil }
        return status == .scheduled || status == .live ? .upcoming : nil
    }
}

public struct HomeGame: Identifiable, Hashable, Sendable {
    public let game: SportsGame
    public let state: HomeGameState
    public let feedCount: Int
    public var id: String { game.id }
}

public struct HomeChannel: Identifiable, Hashable, Sendable {
    public let channelID: String
    public let program: GuideProgram?
    public init(channelID: String, program: GuideProgram?) { self.channelID = channelID; self.program = program }
    public var id: String { channelID }
}

public enum HomeHero: Identifiable, Hashable, Sendable {
    case game(HomeGame)
    case channel(HomeChannel)
    public var id: String {
        switch self {
        case .game(let game): game.id
        case .channel(let channel): "channel." + channel.channelID
        }
    }
}

public struct HomeLeagueRow: Identifiable, Hashable, Sendable {
    public let league: SportsLeague
    public let games: [HomeGame]
    public var id: String { league.id }
}

public struct HomeContent: Sendable {
    public static let heroLimit = 3
    static let teamWindow: TimeInterval = 7 * 86_400
    static let leagueWindow: TimeInterval = 24 * 3600

    public var hero: [HomeHero] = []
    public var teamGames: [HomeGame] = []
    public var leagueRows: [HomeLeagueRow] = []
    public var channels: [HomeChannel] = []
    public var showsFollowPrompt = false
    public init() {}

    public static func build(sports: HomeSportsData, follows: HomeFollows, feedCounts: [String: Int], favorites: [HomeChannel],
                             at date: Date, calendar: Calendar = .current) -> HomeContent {
        let games = sports.games.compactMap { game -> HomeGame? in
            guard let state = game.homeState(at: date), let count = feedCounts[game.id], count > 0 else { return nil }
            return HomeGame(game: game, state: state, feedCount: count)
        }
        func byLiveThenStart(_ a: HomeGame, _ b: HomeGame) -> Bool {
            a.state != b.state ? a.state == .live : a.game.start == b.game.start ? a.id < b.id : a.game.start < b.game.start
        }
        func byFeedsThenStart(_ a: HomeGame, _ b: HomeGame) -> Bool {
            a.feedCount != b.feedCount ? a.feedCount > b.feedCount : a.game.start == b.game.start ? a.id < b.id : a.game.start < b.game.start
        }
        func inAddedLeague(_ game: HomeGame) -> Bool { sports.leagues[game.game.leagueID].map { follows.leagueIDs.contains($0.libraryItem.id) } == true }
        func withinLeagueWindow(_ game: HomeGame) -> Bool { game.state == .live || game.game.start < date + leagueWindow }

        var content = HomeContent()
        content.showsFollowPrompt = follows.isEmpty
        content.channels = favorites
        content.teamGames = games.filter { sports.involvesFollowedTeam($0.game, follows) && ($0.state == .live || $0.game.start < date + teamWindow) }
            .sorted(by: byLiveThenStart)
        let teamIDs = Set(content.teamGames.map(\.id))
        let leagueGames = games.filter { inAddedLeague($0) && withinLeagueWindow($0) }
        content.leagueRows = Dictionary(grouping: leagueGames.filter { !teamIDs.contains($0.id) }, by: \.game.leagueID)
            .compactMap { leagueID, games in
                sports.leagues[leagueID].map { league in
                    HomeLeagueRow(league: league, games: games.sorted { $0.state != $1.state ? $0.state == .live : byFeedsThenStart($0, $1) })
                }
            }
            .sorted { $0.league.name.localizedStandardCompare($1.league.name) == .orderedAscending }

        var hero: [HomeHero] = [], used = Set<String>()
        func add(_ item: HomeHero) { if hero.count < heroLimit, used.insert(item.id).inserted { hero.append(item) } }
        content.teamGames.filter { $0.state == .live }.forEach { add(.game($0)) }
        content.teamGames.filter { $0.state == .upcoming && calendar.isDate($0.game.start, inSameDayAs: date) }.forEach { add(.game($0)) }
        leagueGames.filter { $0.state == .live }.sorted(by: byFeedsThenStart).forEach { add(.game($0)) }
        leagueGames.filter { $0.state == .upcoming }.sorted(by: byFeedsThenStart).forEach { add(.game($0)) }
        favorites.filter { $0.program?.isLive(at: date) == true }.forEach { add(.channel($0)) }
        content.hero = hero
        return content
    }
}
