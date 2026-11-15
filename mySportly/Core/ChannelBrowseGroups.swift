import Foundation

public struct CategoryChannelGroup: Identifiable, Sendable {
    public let category: String
    public let count: Int
    public let interested: Bool
    public let preview: [Channel]
    public let sports: [SportChannelGroup]
    public var subcategories: [TaxonomyBrowseGroup] = []
    public var id: String { category }
}

public struct ProviderChannelGroup: Identifiable, Sendable {
    public let label: String
    public let count: Int
    public var id: String { label }
}

/// Derives repeatable labels from provider naming conventions. There is no
/// league allowlist: new prefixes become groups when multiple feeds use them.
enum ProviderChannelLabel {
    private static let formatting: Set<String> = ["US", "USA", "UK", "EN", "ENGLISH", "HD", "FHD", "UHD", "SD", "4K", "8K", "HEVC", "TV", "LIVE", "SPORT", "SPORTS", "CHANNEL", "CHANNELS", "STREAM", "STREAMS", "FEED", "FEEDS", "EVENT", "EVENTS"]

    static func resolve(name: String, group: String, region: String, sport: ChannelSport) -> String? {
        let sportWords = Set((sport.rawValue + " " + sport.title).uppercased().components(separatedBy: .whitespaces))
        func label(_ text: String) -> String? {
            let tokens = text.uppercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            for token in tokens {
                if formatting.contains(token) || sportWords.contains(token) || (!region.isEmpty && token == region) { continue }
                guard token.first?.isLetter == true else { return nil }
                let letters = String(token.prefix(while: \.isLetter))
                let candidate = letters.count >= 2 ? letters : token
                if sportWords.contains(candidate) { continue }
                guard (2...24).contains(candidate.count) else { return nil }
                return candidate
            }
            return nil
        }
        return label(name) ?? label(group)
    }
}

public struct TaxonomyBrowseGroup: Identifiable, Sendable {
    public let path: [String]
    public let count: Int
    public var id: String { TaxonomyNode.id(for: path) }
    public var name: String { path.last ?? "" }
}

extension ChannelDirectory {
    public func taxonomyPath(for channelID: String) -> [String] {
        let path = nameGroups.path(for: channelID)
        guard let details = metadata[channelID] else { return [] }
        // A channel-level manual correction remains stronger than its family.
        if path.first != details.category { return [details.category] + (details.sport.map { [$0.title] } ?? []) }
        return path
    }
    public func groupedTaxonomy(in channels: [Channel], under parent: [String]) throws -> (groups: [TaxonomyBrowseGroup], remaining: [Channel]) {
        var counts: [[String]: Int] = [:], remaining: [Channel] = []
        for (offset, channel) in channels.enumerated() {
            if offset.isMultiple(of: 256) { try Task.checkCancellation() }
            let path = taxonomyPath(for: channel.id)
            if path.starts(with: parent), path.count > parent.count {
                counts[Array(path.prefix(parent.count + 1)), default: 0] += 1
            } else { remaining.append(channel) }
        }
        return (counts.map { TaxonomyBrowseGroup(path: $0.key, count: $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, remaining)
    }
}
