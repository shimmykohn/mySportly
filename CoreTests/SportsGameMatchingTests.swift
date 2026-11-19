import Foundation
import Testing
@testable import SportlyCore

struct SportsGameMatchingTests {
    private let source = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func index(extra: [SportsGame] = []) throws -> SportsDataIndex {
        try SportsDataIndex(SportsCatalog(fetchedAt: start.timeIntervalSince1970,
            leagues: [.init(id: "nfl", name: "NFL"), .init(id: "mlb", name: "MLB")],
            teams: [.init(id: "dal", name: "Dallas Cowboys", leagueID: "nfl"), .init(id: "gb", name: "Green Bay Packers", leagueID: "nfl"),
                    .init(id: "nyg", name: "New York Giants", leagueID: "nfl"), .init(id: "az", name: "Arizona Cardinals", leagueID: "nfl")],
            games: [.init(id: "game", leagueID: "nfl", homeID: "gb", awayID: "dal", timestamp: start.timeIntervalSince1970),
                    .init(id: "ambiguous", leagueID: "nfl", homeID: "nyg", awayID: "az", timestamp: start.timeIntervalSince1970)] + extra))
    }
    @Test func requiresOpponentsAndTimeAndRejectsStudioShows() throws {
        let matcher = SportsGameMatcher(index: try index())
        #expect(matcher.match(title: "Cowboys at Packers", context: "NFL", start: start, end: start + 3 * 3600)?.id == "game")
        #expect(matcher.match(title: "Dallas Cowboys", context: "NFL", start: start, end: start + 3 * 3600) == nil)
        #expect(matcher.match(title: "Cowboys at Packers", context: "NFL", start: start - 86400, end: start - 80000) == nil)
        #expect(matcher.match(title: "Cowboys at Packers Highlights", context: "NFL", start: start, end: start + 3600) == nil)
        #expect(matcher.match(title: "Giants vs Cardinals", context: "MLB", start: start, end: start + 3 * 3600) == nil)
        #expect(matcher.match(title: "Giants vs Cardinals", context: "NFL", start: start, end: start + 3 * 3600)?.id == "ambiguous")
    }
    @Test func ambiguousDoubleheaderDoesNotGuess() throws {
        let other = SportsGame(id: "second", leagueID: "nfl", homeID: "gb", awayID: "dal", timestamp: start.timeIntervalSince1970 + 20 * 60)
        let matcher = SportsGameMatcher(index: try index(extra: [other]))
        #expect(matcher.match(title: "Cowboys at Packers", context: "NFL", start: start + 10 * 60, end: start + 3 * 3600) == nil)
    }
    @Test func nameOnlyNeedsFreshCatalogAndExactTime() throws {
        let matcher = SportsGameMatcher(index: try index())
        let zone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter(); formatter.timeZone = zone; formatter.dateFormat = "HH:mm"
        let name = "NFL | Cowboys at Packers \(formatter.string(from: start))"
        #expect(matcher.matchChannel(name: name, group: "NFL", refreshed: start, at: start, timeZone: zone)?.id == "game")
        #expect(matcher.matchChannel(name: name, group: "NFL", refreshed: start - 7 * 3600, at: start, timeZone: zone) == nil)
        #expect(matcher.matchChannel(name: "Cowboys at Packers", group: "NFL", refreshed: start, at: start, timeZone: zone) == nil)
        #expect(matcher.matchChannel(name: name, group: "NFL", refreshed: start + 86400, at: start + 86400, timeZone: zone) == nil)
    }
    @Test func groupsQualityFeedsWithCorrectedGuideTimeAndExpiresLinks() throws {
        let channels = [Channel(id: "hd", sourceID: source, name: "NFL HD", guideID: "nfl"), Channel(id: "sd", sourceID: source, name: "NFL SD", guideID: "nfl")]
        let program = GuideProgram(id: "p", sourceID: source, guideID: "nfl", title: "Cowboys at Packers", start: start - 3 * 3600, end: start, categories: ["NFL"])
        let overrides = ["channel.hd.guideOffset": try JSONEncoder().encode(180), "channel.sd.guideOffset": try JSONEncoder().encode(180)]
        let query = try CatalogQueryIndex(channels: channels, programs: [program], overrides: overrides)
        let links = try query.gameFeeds(index: index(), refreshed: [source: start], at: start)
        #expect(Set(links["game", default: []].map(\.channelID)) == ["hd", "sd"])
        #expect(links["game"]?.first?.isValid(at: start + 600) == true)
        #expect(links["game"]?.first?.isValid(at: start + 4 * 3600) == false)
    }
    @Test func conflictingEPGWinsOverChannelName() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter(); formatter.timeZone = zone; formatter.dateFormat = "HH:mm"
        let channel = Channel(id: "reused", sourceID: source, name: "Cowboys at Packers \(formatter.string(from: start))", group: "NFL", guideID: "slot")
        let program = GuideProgram(id: "p", sourceID: source, guideID: "slot", title: "Sports News", start: start - 600, end: start + 3600)
        let query = try CatalogQueryIndex(channels: [channel], programs: [program])
        #expect(try query.gameFeeds(index: index(), refreshed: [source: start], at: start, timeZone: zone).isEmpty)
    }
    @Test func libraryIDsSurviveProviderIdentityAndEmptySchedules() throws {
        let data = try index()
        let item = SportsLibraryItem(name: "Cowboys", kind: .team)
        #expect(data.teams["dal"]?.libraryItem.id == item.id)
        #expect(data.schedule(for: [item], at: start).map(\.id) == ["game"])
        #expect(data.schedule(for: [SportsLibraryItem(name: "MLB", kind: .league)], at: start).isEmpty)
        #expect(try SportsDataIndex().schedule(for: nil, at: start).isEmpty)
    }
    @Test func guideBuildGroupsFeedsWithoutNeedingAnExternalSchedule() throws {
        let channels = [Channel(id: "hd", sourceID: source, name: "NBC HD", guideID: "hd"), Channel(id: "sd", sourceID: source, name: "NBC SD", guideID: "sd")]
        let programs = [
            GuideProgram(id: "a", sourceID: source, guideID: "hd", title: "NFL Football", summary: "Dallas Cowboys at Green Bay Packers", start: start, end: start + 3 * 3600),
            GuideProgram(id: "b", sourceID: source, guideID: "sd", title: "Cowboys at Packers", start: start + 300, end: start + 3 * 3600, categories: ["NFL"])
        ]
        var reference = try index().catalog; reference.games = []
        let query = try CatalogQueryIndex(channels: channels, programs: programs)
        let result = try query.guideGames(reference: SportsDataIndex(reference), refreshed: [source: start], at: start)
        #expect(result.index.games.count == 1)
        let game = try #require(result.index.orderedGames.first)
        #expect(game.start == start)
        #expect(game.guideEnd == (start + 3 * 3600).timeIntervalSince1970)
        #expect(Set(result.links[game.id, default: []].map(\.channelID)) == ["hd", "sd"])
        #expect(result.index.schedule(for: [SportsLibraryItem(name: "Cowboys", kind: .team)], at: start).count == 1)
        #expect(!game.canWatch(at: start - 60))
        #expect(!game.canWatch(at: start + 3 * 3600))
    }
    @Test func guideRejectsReplaysAndAmbiguousMatchesAndKeepsDoubleheadersSeparate() throws {
        let channel = Channel(id: "sports", sourceID: source, name: "Sports", group: "NFL", guideID: "sports")
        let programs = [
            GuideProgram(id: "a", sourceID: source, guideID: "sports", title: "Cowboys at Packers", start: start, end: start + 3600),
            GuideProgram(id: "b", sourceID: source, guideID: "sports", title: "Cowboys at Packers", start: start + 4 * 3600, end: start + 7 * 3600),
            GuideProgram(id: "c", sourceID: source, guideID: "sports", title: "Cowboys at Packers Highlights", start: start, end: start + 3600),
            GuideProgram(id: "d", sourceID: source, guideID: "sports", title: "Cowboys vs Packers vs Giants", start: start, end: start + 3600)
        ]
        let query = try CatalogQueryIndex(channels: [channel], programs: programs)
        var unscheduled = try index().catalog; unscheduled.games = []
        let result = try query.guideGames(reference: SportsDataIndex(unscheduled), refreshed: [source: start], at: start)
        #expect(result.index.games.count == 2)
        #expect(Set(result.links.values.flatMap { $0.compactMap(\.programID) }) == [source.uuidString + "|a", source.uuidString + "|b"])
        let parser = GuideGameParser(reference: try index())
        #expect(parser.opponents(title: "Giants vs Cardinals", context: "MLB") == nil)
        #expect(parser.opponents(title: "Cowboys and Packers discuss the draft", context: "NFL") == nil)
    }
    @Test func scheduledGamesAdoptGuideFeedsAndGetNetworkChannels() throws {
        var scheduled = SportsGame(id: "espn.1", leagueID: "nfl", homeID: "gb", awayID: "dal", timestamp: start.timeIntervalSince1970)
        scheduled.networks = ["Fox"]
        var reference = try index().catalog; reference.games = [scheduled]
        let channels = [Channel(id: "sports", sourceID: source, name: "Sports", group: "NFL", guideID: "sports"),
                        Channel(id: "fox", sourceID: source, name: "US| FOX HD", group: "USA"),
                        Channel(id: "fox5", sourceID: source, name: "US| FOX 5 New York", group: "USA")]
        let programs = [GuideProgram(id: "a", sourceID: source, guideID: "sports", title: "Cowboys at Packers", start: start + 300, end: start + 3 * 3600, categories: ["NFL"])]
        let query = try CatalogQueryIndex(channels: channels, programs: programs)
        let result = try query.guideGames(reference: SportsDataIndex(reference), refreshed: [source: start], at: start)
        // The guide's game takes the schedule's identity instead of becoming a second one.
        #expect(result.index.games.keys.sorted() == ["espn.1"])
        #expect(result.index.games["espn.1"]?.guideEnd == (start + 3 * 3600).timeIntervalSince1970)
        let links = result.links["espn.1", default: []]
        #expect(Set(links.map(\.channelID)) == ["sports", "fox"])
        #expect(links.first { $0.channelID == "fox" }?.evidence == "TV network")
    }
    @Test func networkNamesMatchChannelNames() {
        #expect(SportsNetworks.key("US| ESPN 2 HD") == SportsNetworks.key("ESPN2"))
        #expect(SportsNetworks.key("USA Network") == SportsNetworks.key("USA Net"))
        #expect(SportsNetworks.key("CBS (East)") == SportsNetworks.key("CBS"))
        #expect(SportsNetworks.key("FOX 5 New York") != SportsNetworks.key("Fox"))
    }
    @Test func reusedChannelDateCannotOverrideToday() throws {
        let matcher = SportsGameMatcher(index: try index())
        let zone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter(); formatter.timeZone = zone; formatter.dateFormat = "HH:mm"
        let name = "NFL 2022-01-01 Cowboys at Packers \(formatter.string(from: start))"
        #expect(matcher.matchChannel(name: name, group: "NFL", refreshed: start, at: start, timeZone: zone) == nil)
    }
    @Test func historicalSoccerMembershipDoesNotInventTodaysCompetition() throws {
        let catalog = SportsCatalog(leagues: [.init(id: "epl", name: "Premier League")], teams: [
            .init(id: "a", name: "Arsenal", leagueID: "epl"), .init(id: "b", name: "Liverpool", leagueID: "epl")])
        let parser = GuideGameParser(reference: try SportsDataIndex(catalog))
        #expect(parser.opponents(title: "Arsenal vs Liverpool", context: "FA Cup") == nil)
        #expect(parser.opponents(title: "Arsenal vs Liverpool", context: "Premier League")?.count == 2)
    }
    @Test func rejectsDuplicateAndDanglingRecords() throws {
        var catalog = try index().catalog
        catalog.games.append(catalog.games[0])
        #expect(throws: SportsDataError.self) { try SportsDataIndex(catalog) }
        catalog.games.removeLast(); catalog.teams.removeAll()
        #expect(throws: SportsDataError.self) { try SportsDataIndex(catalog) }
    }
}
