import Foundation

/// Answers from the AI jobs. Derived from the provider catalog, so they stay on
/// this device (sealed with the catalog cache) and never sync.
public struct MergeAnswer: Codable, Hashable, Sendable {
    public var same: Bool
    public var ids: [String]
    public init(same: Bool, ids: [String]) { self.same = same; self.ids = ids }
}

public struct AIResults: Codable, Equatable, Sendable {
    public var version = 1
    /// Pair key → the model's answer about two feeds.
    public var merges: [String: MergeAnswer] = [:]
    /// Listing key → teams (empty: not a game).
    public var games: [String: DetectedGame] = [:]
    /// Raw name → model-cleaned name.
    public var names: [String: String] = [:]
    /// Raw names the model already saw (kept or rejected), so they aren't resent.
    public var namesAsked: Set<String> = []
    public init() {}

    public var detectedGames: [String: [String]] { games.filter { !$0.value.teams.isEmpty }.mapValues(\.teams) }
    public var mergedPairs: [[String]] { merges.values.filter(\.same).map(\.ids).sorted { $0.joined() < $1.joined() } }

    /// Drops games that ended and answers about channels no longer in the catalog.
    public mutating func prune(at date: Date, channels: [Channel], candidates: [MergeCandidate]) {
        games = games.filter { $0.value.expires > date.timeIntervalSince1970 }
        let pairs = Set(candidates.map(\.key))
        merges = merges.filter { pairs.contains($0.key) }
        let raw = Set(channels.map(\.name))
        names = names.filter { raw.contains($0.key) }
        namesAsked = namesAsked.intersection(raw)
    }

    /// The display name: the model's answer, else local rules.
    public func displayName(_ raw: String) -> String { names[raw] ?? NameCleaning.local(raw) }

    /// `channel.<id>.variants` values for `PreparedCatalog`. Callers merge the
    /// user's own overrides on top, so a manual split always wins.
    public static func variantOverrides(_ groups: [[String]]) -> [String: Data] {
        let encoder = JSONEncoder()
        var result: [String: Data] = [:]
        for group in groups {
            guard let data = try? encoder.encode(group) else { continue }
            for id in group { result["channel.\(id).variants"] = data }
        }
        return result
    }
}
