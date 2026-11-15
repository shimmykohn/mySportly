import Foundation

/// One-time move to Follow (teams), Add (leagues) and Favorite (channels).
/// Saved teams and leagues already live in `sports.library.*`; stars always
/// came with a save. What remains: legacy name lists become explicit
/// entries, and channels saved as Library items become favorites. Nothing
/// is deleted, and an explicit removal is never undone.
public enum FollowMigration {
    public static let flag = "migration.followModel.v1"

    public static func updates(values: [String: Data]) -> [String: Data?] {
        guard values[flag] == nil else { return [:] }
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        var updates: [String: Data?] = [:]
        for (key, kind) in [("preferences.teams", SportsFollowKind.team), ("preferences.leagues", .league)] {
            guard let data = values[key], let names = try? decoder.decode([String].self, from: data) else { continue }
            for name in names {
                let item = SportsLibraryItem(name: name, kind: kind)
                let entryKey = "sports.library.\(item.id)"
                guard item.name.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains), values[entryKey] == nil, updates[entryKey] == nil else { continue }
                updates[entryKey] = try? encoder.encode(SportsLibraryEntry(item: item, saved: true))
            }
        }
        for (key, data) in values where key.hasPrefix("library.item.") {
            guard let bookmark = try? decoder.decode(LibraryBookmark.self, from: data), bookmark.kind == .channel else { continue }
            updates["channel.\(bookmark.reference).favorite"] = try? encoder.encode(true)
        }
        updates[flag] = try? encoder.encode(true)
        return updates
    }
}

public struct GameAlert: Hashable, Sendable {
    public let id: String
    public let gameID: String
    public let date: Date
    public let title: String
}

/// Notifications for followed teams' games, opted in per team.
public enum GameAlerts {
    public static let limit = 50
    static let window: TimeInterval = 7 * 86_400

    public static func plan(sports: HomeSportsData, notifyTeamIDs: Set<String>, now: Date) -> [GameAlert] {
        guard !notifyTeamIDs.isEmpty else { return [] }
        let games = sports.games.filter { game in
            game.start > now && game.start < now + window && (game.status == .scheduled || game.status == .live) &&
                [game.homeID, game.awayID].contains { sports.teams[$0].map { notifyTeamIDs.contains($0.libraryItem.id) } == true }
        }
        var seen = Set<String>()
        return games.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
            .filter { seen.insert($0.id).inserted }
            .prefix(limit)
            .map { game in
                let away = sports.teams[game.awayID]?.libraryItem.name ?? "Away", home = sports.teams[game.homeID]?.libraryItem.name ?? "Home"
                return GameAlert(id: "game." + game.id, gameID: game.id, date: game.start, title: "\(away) at \(home)")
            }
    }
}
