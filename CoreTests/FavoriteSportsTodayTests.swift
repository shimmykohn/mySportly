import Foundation
import Testing
@testable import SportlyCore

struct FavoriteSportsTodayTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "America/New_York")!; return value
    }
    @Test func favoritesIncludeLiveAndTodayOnlyAndDeduplicateLeagueAndTeam() throws {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let end = calendar.dateInterval(of: .day, for: date)!.end
        func game(_ id: String, start: Date, finish: Date?, status: SportsGameStatus = .scheduled) -> SportsGame {
            SportsGame(id: id, leagueID: "nba", homeID: "ny", awayID: "bos", timestamp: start.timeIntervalSince1970, status: status, guideEnd: finish?.timeIntervalSince1970)
        }
        let index = try SportsDataIndex(SportsCatalog(leagues: [.init(id: "nba", name: "NBA")], teams: [
            .init(id: "ny", name: "New York Knicks", leagueID: "nba"), .init(id: "bos", name: "Boston Celtics", leagueID: "nba")], games: [
                game("live", start: date - 3600, finish: date + 3600),
                game("tonight", start: end - 3600, finish: end + 3600),
                game("tomorrow", start: end, finish: end + 3600),
                game("ended", start: date - 7200, finish: date),
                game("postponed", start: date + 3600, finish: nil, status: .postponed),
                game("cancelled", start: date + 3600, finish: nil, status: .cancelled),
                game("unconfirmed", start: date - 3600, finish: nil)]))
        let items = [SportsLibraryItem(name: "NBA", kind: .league), SportsLibraryItem(name: "Knicks", kind: .team)]
        #expect(index.gamesToday(for: items, at: date, calendar: calendar).map(\.id) == ["live", "tonight"])
        #expect(index.gamesToday(for: [], at: date, calendar: calendar).isEmpty)
        #expect(index.gamesToday(for: [SportsLibraryItem(name: "NFL", kind: .league)], at: date, calendar: calendar).isEmpty)
        let midnight = end + 60
        #expect(index.gamesToday(for: items, at: midnight, calendar: calendar).map(\.id) == ["tonight", "tomorrow"])
    }

    @Test func guideOnlySportsRespectDayBoundaryAndDoNotRepeatGroupedGames() throws {
        let source = UUID(), date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 18))!
        let end = calendar.dateInterval(of: .day, for: date)!.end
        let channel = Channel(id: "c", sourceID: source, name: "Sports", group: "Sports", guideID: "g", language: "en", region: "US")
        func program(_ id: String, _ title: String, _ start: Date, _ finish: Date) -> GuideProgram {
            GuideProgram(id: id, sourceID: source, guideID: "g", title: title, start: start, end: finish, categories: ["Sports"])
        }
        let query = try CatalogQueryIndex(channels: [channel], programs: [
            program("p", "Formula 1 Racing", date - 60, date + 3600),
            program("nba", "NBA Knicks vs Celtics", date + 3600, date + 7200),
            program("later", "Formula 1 Qualifying", end - 600, end),
            program("tomorrow", "Formula 1 Racing", end, end + 3600)])
        let schedule = try query.sports(at: date, following: ["Formula 1", "NBA"], followedOnly: true, until: end, includeUnscheduledChannels: false)
        #expect(schedule.live.map(\.program.id) == ["p"])
        #expect(schedule.upcoming.map(\.program.id) == ["nba", "later"])
        #expect(schedule.channelsWithoutListings.isEmpty)
        let listings = FavoriteSportsToday.listings(games: [], schedule: schedule, matchedPrograms: [source.uuidString + "|nba"], at: date, calendar: calendar)
        #expect(listings.map(\.id) == ["program." + source.uuidString + "|p", "program." + source.uuidString + "|later"])
    }
}
