import Foundation

public struct SearchGroups: Sendable {
    public var teams: [SportsLibraryItem] = []
    public var liveNow: [CatalogMatch] = []
    public var channels: [CatalogMatch] = []
    public init() {}
    public var isEmpty: Bool { teams.isEmpty && liveNow.isEmpty && channels.isEmpty }
}

/// Search results as Teams, Live Now and Channels.
public enum SearchGrouping {
    static let teamLimit = 8

    public static func group(query: String, matches: [CatalogMatch], choices: [SportsFollowChoice], followedIDs: Set<String>, at date: Date) -> SearchGroups {
        var groups = SearchGroups()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2 {
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            groups.teams = choices
                .filter { $0.kind == .team && ([$0.name] + $0.aliases).contains { $0.range(of: text, options: options) != nil } }
                .map { SportsLibraryItem(name: $0.name, kind: .team) }
                .sorted {
                    let a = followedIDs.contains($0.id), b = followedIDs.contains($1.id)
                    return a != b ? a : $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            groups.teams = Array(groups.teams.prefix(teamLimit))
        }
        for match in matches {
            if match.program?.isLive(at: date) == true { groups.liveNow.append(match) } else { groups.channels.append(match) }
        }
        return groups
    }
}

/// The last few searches, newest first.
public enum RecentSearches {
    public static let limit = 8
    public static func adding(_ query: String, to list: [String]) -> [String] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return list }
        return Array(([text] + list.filter { $0.caseInsensitiveCompare(text) != .orderedSame }).prefix(limit))
    }
}
