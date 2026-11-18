import Foundation

/// Two feeds the local rules think may be the same channel. `anchor` is the
/// group's first channel; every other member is compared against it.
public struct MergeCandidate: Hashable, Sendable {
    public let key: String
    public let anchor: Channel
    public let other: Channel
    public init(anchor: Channel, other: Channel) {
        self.anchor = anchor; self.other = other; key = FeedMerging.pairKey(anchor, other)
    }
}

/// Duplicate feeds (HD/4K/backup copies) shown as one channel with alternate
/// streams. Strict local groups apply without a model; looser candidates are
/// confirmed by the catalog pass (`CatalogPass.mergeAnswers`).
public enum FeedMerging {
    public static let maxGroup = 12
    /// Lowercased words of the locally cleaned name; quality, region prefix
    /// and backup markers removed, numbers and qualifiers kept.
    public static func base(_ name: String) -> String {
        NameCleaning.words(NameCleaning.local(name)).joined(separator: " ")
    }
    public static func pairKey(_ a: Channel, _ b: Channel) -> String {
        StableID.hash([a.id + "|" + a.name, b.id + "|" + b.name].sorted().joined(separator: "#"))
    }
    static func region(_ channel: Channel) -> String {
        channel.region.isEmpty ? (NameCleaning.regionPrefix(channel.name) ?? "") : channel.region.uppercased()
    }

    /// Channels that may be copies of one another share this: same source,
    /// region and base name. Empty-named channels end in "|" and never pair.
    public static func looseKey(_ channel: Channel) -> String {
        [channel.sourceID.uuidString, region(channel), base(channel.name)].joined(separator: "|")
    }

    /// Strict groups: same source, guide ID, quality-stripped name, language and region.
    public static func strictGroups(_ channels: [Channel]) -> [[String]] { ChannelOrganizer.variantGroups(channels) }

    /// Pairs worth asking about: same source, region and base name, not
    /// already together in a strict group.
    public static func candidates(_ channels: [Channel], strict: [[String]]) -> [MergeCandidate] {
        var component: [String: Int] = [:]
        for (index, group) in strict.enumerated() { for id in group { component[id] = index } }
        let loose = Dictionary(grouping: channels.filter { !ListingAvailability.isInactiveChannel($0.name) }, by: looseKey)
        var result: [MergeCandidate] = []
        for (key, members) in loose where members.count > 1 && members.count <= maxGroup && !key.hasSuffix("|") {
            // One representative per strict component; singletons are their own.
            var seen = Set<String>(), representatives: [Channel] = []
            for channel in members.sorted(by: { $0.id < $1.id }) {
                let id = component[channel.id].map { "s\($0)" } ?? channel.id
                if seen.insert(id).inserted { representatives.append(channel) }
            }
            guard let anchor = representatives.first else { continue }
            for other in representatives.dropFirst() { result.append(MergeCandidate(anchor: anchor, other: other)) }
        }
        return result.sorted { $0.key < $1.key }
    }

    /// Strict groups joined by every confirmed pair whose channels still exist.
    public static func groups(strict: [[String]], pairs: [[String]], present: Set<String>? = nil) -> [[String]] {
        var parent: [String: String] = [:]
        func root(_ id: String) -> String {
            var id = id
            while let next = parent[id], next != id { parent[id] = parent[next] ?? next; id = next }
            return id
        }
        func join(_ a: String, _ b: String) {
            if parent[a] == nil { parent[a] = a }
            if parent[b] == nil { parent[b] = b }
            let (x, y) = (root(a), root(b))
            if x != y { parent[max(x, y)] = min(x, y) }
        }
        for group in strict { for id in group.dropFirst() { join(group[0], id) } }
        for pair in pairs where pair.count == 2 && (present.map { $0.contains(pair[0]) && $0.contains(pair[1]) } ?? true) { join(pair[0], pair[1]) }
        let grouped = Dictionary(grouping: parent.keys) { root($0) }
        return grouped.values.filter { $0.count > 1 }.map { $0.sorted() }.sorted { $0[0] < $1[0] }
    }
}
