import Foundation

/// Follow a team, add a league, favorite a channel. Teams and leagues use the
/// existing `sports.library.*` entries; favorites use `channel.<id>.favorite`.
extension AppStore {
    var followedTeams: [SportsLibraryItem] { sportsLibrary.filter { $0.kind == .team } }
    var addedLeagues: [SportsLibraryItem] { sportsLibrary.filter { $0.kind == .league } }
    func isFollowing(_ item: SportsLibraryItem) -> Bool { hasSportsItem(item) }
    func follow(_ item: SportsLibraryItem) { saveSportsItem(item); scheduleGameAlerts(); refreshSchedules() }
    func unfollow(_ item: SportsLibraryItem) { removeSportsItem(item); scheduleGameAlerts() }

    func notifiesGameStart(_ team: SportsLibraryItem) -> Bool { personal.value("sports.notify.\(team.id)", default: false) }
    func setNotifiesGameStart(_ team: SportsLibraryItem, _ enabled: Bool) async {
        if enabled, !(await GameAlertScheduler.requestAuthorization()) {
            inform("Notifications are off", "Allow notifications for mySportly in Settings to hear when games start.")
            return
        }
        set("sports.notify.\(team.id)", enabled)
        scheduleGameAlerts()
    }

    func scheduleGameAlerts() {
        guard !demo else { return }
        let notify = Set(followedTeams.filter(notifiesGameStart).map(\.id))
        let alerts = GameAlerts.plan(sports: homeSports, notifyTeamIDs: notify, now: .now).map { alert in
            let feed = feeds(for: alert.gameID).first
            return (alert: alert, channelID: feed?.id, channelName: feed.map(name))
        }
        Task { await GameAlertScheduler.update(alerts) }
    }

    /// One-time move to the follow model; see `FollowMigration`.
    func runFollowMigration() {
        let updates = FollowMigration.updates(values: personal.snapshotValues())
        guard !updates.isEmpty else { return }
        do { try personal.write(updates); rebuild() }
        catch { inform("Changes weren’t saved", error.localizedDescription) }
    }
}

extension AppStore {
    /// Live and next-7-day games for a team or league that have a feed in the lineup.
    /// A team's season from the schedule, upcoming games first, whether or
    /// not the lineup carries them.
    func season(for team: SportsLibraryItem) -> [SportsGame] {
        let index = sportsData.reference, now = clock
        let ids = Set(index.catalog.teams.filter { $0.libraryItem.id == team.id }.map(\.id))
        guard !ids.isEmpty else { return [] }
        return index.orderedGames.filter { (ids.contains($0.homeID) || ids.contains($0.awayID)) && $0.start > now - 4 * 3600 && $0.status != .cancelled }
    }

    func upcomingGames(for item: SportsLibraryItem) -> [HomeGame] {
        let date = clock
        return homeSports.games.compactMap { game -> HomeGame? in
            guard let state = game.homeState(at: date), state == .live || game.start < date + 7 * 86_400 else { return nil }
            let matches = item.kind == .team
                ? [game.homeID, game.awayID].contains { homeSports.teams[$0]?.libraryItem.id == item.id }
                : homeSports.leagues[game.leagueID]?.libraryItem.id == item.id
            guard matches else { return nil }
            let count = feeds(for: game.id).count
            return count > 0 ? HomeGame(game: game, state: state, feedCount: count) : nil
        }
        .sorted { $0.state != $1.state ? $0.state == .live : $0.game.start < $1.game.start }
    }
    func logo(for item: SportsLibraryItem) -> URL? { sportsData.index.logo(for: item) }
}

extension AppStore {
    var recentSearches: [String] { personal.value("search.recent", default: [String]()) }
    func addRecentSearch(_ query: String) {
        let updated = RecentSearches.adding(query, to: recentSearches)
        if updated != recentSearches { set("search.recent", updated) }
    }
    func clearRecentSearches() { set("search.recent", [String]()) }
}
