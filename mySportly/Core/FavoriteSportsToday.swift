import Foundation

public enum FavoriteSportsListing: Identifiable, Sendable {
    case game(SportsGame)
    case program(SportsEvent)
    public var id: String {
        switch self { case .game(let game): "game." + game.id; case .program(let event): "program." + event.id }
    }
    public var start: Date {
        switch self { case .game(let game): game.start; case .program(let event): event.program.start }
    }
}

public enum FavoriteSportsToday {
    /// Games are already deduplicated by participants and broadcast time.
    /// Keep unmatched guide events too (for example tennis or motorsport).
    public static func listings(games: [SportsGame], schedule: SportsSchedule, matchedPrograms: Set<String>, at date: Date, calendar: Calendar = .current) -> [FavoriteSportsListing] {
        guard let day = calendar.dateInterval(of: .day, for: date) else { return [] }
        let programs = (schedule.live + schedule.upcoming).filter {
            !matchedPrograms.contains($0.id) && $0.program.end > date && $0.program.start < day.end
        }
        let result = games.map(FavoriteSportsListing.game) + programs.map(FavoriteSportsListing.program)
        return result.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
}
