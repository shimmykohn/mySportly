import Foundation
import Testing
@testable import SportlyCore

struct HomeContentTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!; return calendar }

    let nba = SportsLeague(id: "nba", name: "NBA"), nfl = SportsLeague(id: "nfl", name: "NFL")
    let knicks = SportsTeam(id: "knicks", name: "New York Knicks", leagueID: "nba")
    let celtics = SportsTeam(id: "celtics", name: "Boston Celtics", leagueID: "nba")
    let lakers = SportsTeam(id: "lakers", name: "Los Angeles Lakers", leagueID: "nba")
    let cowboys = SportsTeam(id: "cowboys", name: "Dallas Cowboys", leagueID: "nfl")
    let giants = SportsTeam(id: "giants", name: "New York Giants", leagueID: "nfl")

    func game(_ id: String, _ home: SportsTeam, _ away: SportsTeam, at offset: TimeInterval, end: TimeInterval? = nil) -> SportsGame {
        SportsGame(id: id, leagueID: home.leagueID, homeID: home.id, awayID: away.id, timestamp: (now + offset).timeIntervalSince1970,
                   guideEnd: end.map { (now + $0).timeIntervalSince1970 })
    }
    func sports(_ games: [SportsGame]) -> HomeSportsData {
        var data = HomeSportsData()
        data.games = games
        data.teams = Dictionary(uniqueKeysWithValues: [knicks, celtics, lakers, cowboys, giants].map { ($0.id, $0) })
        data.leagues = ["nba": nba, "nfl": nfl]
        data.links = Dictionary(uniqueKeysWithValues: games.map { ($0.id, [SportsFeedLink(gameID: $0.id, channelID: "ch.\($0.id)", programID: nil, validFrom: now - 86_400, validUntil: now + 8 * 86_400, evidence: "test")]) })
        return data
    }
    func follows(teams: [SportsTeam] = [], leagues: [SportsLeague] = []) -> HomeFollows {
        HomeFollows(teamIDs: Set(teams.map(\.libraryItem.id)), leagueIDs: Set(leagues.map(\.libraryItem.id)))
    }
    func counts(_ games: [SportsGame], _ value: Int = 1) -> [String: Int] { Dictionary(uniqueKeysWithValues: games.map { ($0.id, value) }) }
    func liveFavorite() -> HomeChannel {
        HomeChannel(channelID: "fav", program: GuideProgram(id: "p", sourceID: UUID(), guideID: "g", title: "News", start: now - 600, end: now + 600))
    }

    @Test func heroPrefersFollowedLiveThenTodayThenLeagueThenChannel() {
        let live = game("knicksLive", knicks, celtics, at: -600, end: 3 * 3600)
        let tonight = game("knicksTonight", knicks, lakers, at: 5 * 3600)
        let league = game("lakersCeltics", lakers, celtics, at: -300, end: 3 * 3600)
        var feeds = counts([live, tonight]); feeds[league.id] = 5
        let content = HomeContent.build(sports: sports([live, tonight, league]), follows: follows(teams: [knicks], leagues: [nba]),
                                        feedCounts: feeds, favorites: [liveFavorite()], at: now, calendar: calendar)
        #expect(content.hero.map(\.id) == ["knicksLive", "knicksTonight", "lakersCeltics"])
        let fewer = HomeContent.build(sports: sports([league]), follows: follows(leagues: [nba]), feedCounts: feeds, favorites: [liveFavorite()], at: now, calendar: calendar)
        #expect(fewer.hero.map(\.id) == ["lakersCeltics", "channel.fav"])
    }

    @Test func followedTeamGameIsNotRepeatedInLeagueRow() {
        let knicksGame = game("knicksLive", knicks, celtics, at: -600, end: 3 * 3600)
        let other = game("lakersCeltics", lakers, celtics, at: 3600)
        let content = HomeContent.build(sports: sports([knicksGame, other]), follows: follows(teams: [knicks], leagues: [nba]),
                                        feedCounts: counts([knicksGame, other]), favorites: [], at: now, calendar: calendar)
        #expect(content.teamGames.map(\.id) == ["knicksLive"])
        #expect(content.leagueRows.map(\.league.id) == ["nba"])
        #expect(content.leagueRows.first?.games.map(\.id) == ["lakersCeltics"])
    }

    @Test func gamesWithoutFeedsAreHidden() {
        let knicksGame = game("knicksLive", knicks, celtics, at: -600, end: 3 * 3600)
        let content = HomeContent.build(sports: sports([knicksGame]), follows: follows(teams: [knicks], leagues: [nba]),
                                        feedCounts: [:], favorites: [], at: now, calendar: calendar)
        #expect(content.teamGames.isEmpty && content.leagueRows.isEmpty && content.hero.isEmpty)
    }

    @Test func stateFollowsTheClock() {
        let knicksGame = game("knicksGame", knicks, celtics, at: 0, end: 3 * 3600)
        func state(at date: Date) -> HomeGameState? {
            HomeContent.build(sports: sports([knicksGame]), follows: follows(teams: [knicks]), feedCounts: counts([knicksGame]),
                              favorites: [], at: date, calendar: calendar).teamGames.first?.state
        }
        #expect(state(at: now - 60) == .upcoming)
        #expect(state(at: now + 60) == .live)
        #expect(state(at: now + 3 * 3600 + 60) == nil)
        #expect(knicksGame.homeState(at: now + 60) == .live)
    }

    @Test func leagueRowWindowIs24Hours() {
        let later = game("knicksLater", knicks, lakers, at: 25 * 3600)
        let leagueOnly = HomeContent.build(sports: sports([later]), follows: follows(leagues: [nba]), feedCounts: counts([later]), favorites: [], at: now, calendar: calendar)
        #expect(leagueOnly.leagueRows.isEmpty)
        let followed = HomeContent.build(sports: sports([later]), follows: follows(teams: [knicks], leagues: [nba]), feedCounts: counts([later]), favorites: [], at: now, calendar: calendar)
        #expect(followed.teamGames.map(\.id) == ["knicksLater"])
    }

    @Test func leagueRowOrdersLiveFirstThenFeedsThenStart() {
        let soon = game("soon", lakers, celtics, at: 3600)
        let popular = game("popular", celtics, lakers, at: 7200)
        let live = game("live", knicks, lakers, at: -600, end: 3 * 3600)
        var feeds = counts([soon, live]); feeds[popular.id] = 4
        let content = HomeContent.build(sports: sports([soon, popular, live]), follows: follows(leagues: [nba]), feedCounts: feeds, favorites: [], at: now, calendar: calendar)
        #expect(content.leagueRows.first?.games.map(\.id) == ["live", "popular", "soon"])
    }

    @Test func nothingFollowedShowsPromptAndChannels() {
        let content = HomeContent.build(sports: HomeSportsData(), follows: HomeFollows(), feedCounts: [:], favorites: [liveFavorite()], at: now, calendar: calendar)
        #expect(content.showsFollowPrompt)
        #expect(content.channels.count == 1)
        #expect(content.hero.map(\.id) == ["channel.fav"])
    }

    @Test func relevantKeepsOnlyFollowedGamesAndTheirReferences() {
        let nbaGame = game("nbaGame", lakers, celtics, at: 3600)
        let nflGame = game("nflGame", cowboys, giants, at: 3600)
        let relevant = sports([nbaGame, nflGame]).relevant(to: follows(leagues: [nba]), at: now)
        #expect(relevant.games.map(\.id) == ["nbaGame"])
        #expect(relevant.teams["cowboys"] == nil && relevant.teams["lakers"] != nil)
        #expect(relevant.leagues.keys.sorted() == ["nba"])
        #expect(relevant.links.keys.sorted() == ["nbaGame"])
    }
}
