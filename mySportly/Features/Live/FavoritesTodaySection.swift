import SwiftUI

struct FavoritesTodayRequest: Equatable {
    let catalog: Int; let sports: Int; let minute: Int; let favorites: [SportsLibraryItem]; let audience: ChannelAudience
}

@MainActor @Observable final class FavoritesTodayModel {
    private(set) var listings: [FavoriteSportsListing] = []
    private(set) var isUpdating = false
    @ObservationIgnored private var completed: FavoritesTodayRequest?
    @ObservationIgnored private var activeRequest: UUID?
    func update(_ request: FavoritesTodayRequest, store: AppStore) async {
        guard completed != request else { return }
        guard !request.favorites.isEmpty, let index = store.queryIndex else { listings = []; completed = request; return }
        let token = UUID()
        activeRequest = token; isUpdating = true
        defer { if activeRequest == token { isUpdating = false; activeRequest = nil } }
        let sports = store.sportsData.index, calendar = Calendar.current, date = store.clock
        let games = sports.gamesToday(for: request.favorites, at: date, calendar: calendar).filter { !store.feeds(for: $0.id).isEmpty }
        let matched = Set(games.flatMap { store.gameLinks[$0.id] ?? [] }.compactMap(\.programID))
        do {
            let result = try await catalogWork {
                let end = calendar.dateInterval(of: .day, for: date)?.end ?? date
                let schedule = try index.sports(at: date, following: request.favorites.map(\.name), followedOnly: true, audience: request.audience, until: end, includeUnscheduledChannels: false)
                return FavoriteSportsToday.listings(games: games, schedule: schedule, matchedPrograms: matched, at: date, calendar: calendar)
            }
            try Task.checkCancellation(); listings = result; completed = request
        } catch { }
    }
}

struct FavoritesTodaySection: View {
    let listings: [FavoriteSportsListing]
    @State private var limit = 6
    var body: some View {
        if !listings.isEmpty {
            Section {
                ForEach(listings.prefix(limit)) { listing in
                    switch listing {
                    case .game(let game): SportsGameRow(game: game, showsTodayStatus: true)
                    case .program(let event): SportsEventRow(event: event)
                    }
                }
                if listings.count > limit { Button("Show More Today") { limit += 6 } }
            } header: { Text("Favorites Today") } footer: {
                Text("On now and coming up today, from your TV guide. Times can change.")
            }
        }
    }
}
