import Foundation

/// A browsing group, never a merged/replaced playable stream. Its identity has
/// no provider stream ID, URL, ordinal, quality, or process-random hash in it.
public struct CatalogNameGroup: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let fingerprint: String
    public let channelIDs: [String]
    public let titles: [String]
    public let providerGroups: [String]
    public let language: String
    public let region: String
    public let localPath: [String]
    public let family: Bool
    public func sampleTitles(limit: Int = 8) -> [String] {
        guard limit > 1, titles.count > limit else { return Array(titles.prefix(max(0, limit))) }
        return (0..<limit).map { titles[$0 * (titles.count - 1) / (limit - 1)] }
    }
}

public enum GroupPlacementStatus: String, Codable, Sendable { case classified, needsReview, needsName }
public struct GroupPlacement: Codable, Identifiable, Sendable {
    public static let currentDecisionVersion = 5
    public let id: String
    public let fingerprint: String
    public var path: [String]
    public var confidence: Double
    public var status: GroupPlacementStatus
    public var origin: String
    public var proposedName: String?
    public var manual: Bool
    public var family: Bool?
    public var decisionVersion: Int?
    public init(group: CatalogNameGroup, path: [String], confidence: Double, status: GroupPlacementStatus, origin: String, proposedName: String? = nil, manual: Bool = false) {
        id = group.id; fingerprint = group.fingerprint; self.path = path; self.confidence = confidence
        self.status = status; self.origin = origin; self.proposedName = proposedName; self.manual = manual
        family = group.family; decisionVersion = Self.currentDecisionVersion
    }
    public func applies(to group: CatalogNameGroup) -> Bool {
        isReusable(for: group) && status == .classified && !path.isEmpty
    }
    public func isReusable(for group: CatalogNameGroup) -> Bool {
        id == group.id && (manual || (fingerprint == group.fingerprint && decisionVersion == Self.currentDecisionVersion))
    }
}

public struct TaxonomyNode: Identifiable, Hashable, Codable, Sendable {
    public let path: [String]
    public var label: String { path.last ?? "" }
    public var id: String { Self.id(for: path) }
    public var parentID: String? { path.count > 1 ? Self.id(for: Array(path.dropLast())) : nil }
    public static func id(for path: [String]) -> String { "node." + StableID.hash(path.map(GroupNames.normalized).joined(separator: "/")) }
}

/// The initial choices are seeds. Accepted new paths extend the same tree; no
/// model response is decoded into a fixed category or sport enum.
public struct GroupTaxonomy: Sendable {
    public private(set) var nodes: [String: TaxonomyNode] = [:]
    public init(paths: [[String]] = []) {
        for path in paths { add(path) }
    }
    public func canonical(_ path: [String]) -> [String] {
        var result: [String] = []
        for label in path {
            let next = result + [label.trimmingCharacters(in: .whitespacesAndNewlines)]
            result = nodes[TaxonomyNode.id(for: next)]?.path ?? next
        }
        return result
    }
    public mutating func add(_ path: [String]) {
        guard !path.isEmpty, path.count <= 4, path.allSatisfy(GroupNames.validLabel) else { return }
        for count in 1...path.count {
            let node = TaxonomyNode(path: canonical(Array(path.prefix(count))))
            if nodes[node.id] == nil { nodes[node.id] = node }
        }
    }
    public func children(of path: [String]) -> [TaxonomyNode] {
        let parent = path.isEmpty ? nil : TaxonomyNode.id(for: path)
        return nodes.values.filter { $0.parentID == parent }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
    public static var seedPaths: [[String]] {
        ChannelCategory.allCases.filter { $0 != .unknown }.map { [$0.rawValue] } +
        ChannelSport.allCases.map { ["Sports", $0.title] }
    }
}

public enum GroupNames {
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    public static func clean(_ text: String) -> String {
        String(text.replacingOccurrences(of: #"(?i)(?:https?://|www\.)\S+|\b(?:apikey_|sk-)[A-Za-z0-9_-]+"#,
            with: "", options: .regularExpression).unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(180))
    }
    public static func validLabel(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= 48 && value == clean(value) && !value.contains("/") &&
            value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || " &'-".unicodeScalars.contains($0) }
    }
    static let regions = Set(Locale.Region.isoRegions.map { $0.identifier.lowercased() })
    static let formatting: Set<String> = ["hd", "fhd", "uhd", "sd", "4k", "8k", "hevc", "h264", "h265"]
    static let coverageFormatting: Set<String> = ["ppv", "live", "replay", "backup", "alt", "exclusive", "raw"]
    static func base(_ name: String) -> String {
        normalized(clean(name)).split(separator: " ").map(String.init).filter { !formatting.contains($0) }.joined(separator: " ")
    }
    private static let slotPatterns = [
        #"^(?:[A-Z]{2}\s+)?\(?([\p{L}][\p{L}& +\-]{1,23}?)\s+\d{1,4}\s*\)?\s*[:|]"#,
        #"^(?:[A-Z]{2}\s+)?([\p{L}][\p{L}& +\-]{1,23}?)\s*:\s*\d{1,4}\s+(?:name|live|start)\s*:"#,
        #":\s*([\p{L}][\p{L}& +\-]{1,23}?)\s+\d{1,3}(?:\s+(?:HD|FHD|UHD|4K))?\s*$"#
    ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    /// Explicit sports-slot syntax supplies identity, while the changing event
    /// remains evidence for game matching. No league-name allowlist is used.
    static func slotFamily(_ title: String, sports: Bool) -> String? {
        guard sports else { return nil }
        let clean = clean(title)
        for pattern in slotPatterns {
            guard let match = pattern.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
                  let range = Range(match.range(at: 1), in: clean) else { continue }
            let label = base(String(clean[range]))
            if !label.isEmpty, !regions.contains(label), label.count <= 24 { return label }
        }
        return nil
    }
}

public struct CatalogGroupIndex: Sendable {
    public let groups: [CatalogNameGroup]
    public let byID: [String: CatalogNameGroup]
    public let channelGroup: [String: String]
    public let placements: [String: GroupPlacement]
    public let paths: [String: [String]]
    public let taxonomy: GroupTaxonomy
    public init(channels: [Channel], metadata: [String: ChannelMetadata], placements: [String: GroupPlacement] = [:]) throws {
        struct Candidate {
            let channel: Channel; let details: ChannelMetadata; let base: String; let numbered: String?; let prefix: String?; let slot: String?
            var edition: String { details.region + "|" + details.language }
        }
        var candidates: [Candidate] = [], numberedCounts: [String: Set<String>] = [:], prefixCounts: [String: Set<String>] = [:]
        for (offset, channel) in channels.enumerated() {
            if offset.isMultiple(of: 256) { try Task.checkCancellation() }
            guard let details = metadata[channel.id] else { continue }
            let base = GroupNames.base(channel.name), words = base.split(separator: " ").map(String.init)
            let numbered = words.count > 1 && words.last!.allSatisfy(\.isNumber) && words.last!.count <= 3 ? words.dropLast().joined(separator: " ") : nil
            // Only an explicit provider prefix ("NFL | ...") is a family.
            // Ordinary first words such as "New York" never merge unrelated names.
            let segment = channel.name.components(separatedBy: CharacterSet(charactersIn: "|:")).first ?? ""
            let prefixValue = GroupNames.base(segment)
            let prefix = channel.name.contains("|") && (2...24).contains(prefixValue.count) && !GroupNames.regions.contains(prefixValue) ? prefixValue : nil
            let candidate = Candidate(channel: channel, details: details, base: base, numbered: numbered, prefix: prefix,
                slot: GroupNames.slotFamily(channel.name, sports: details.category == "Sports"))
            candidates.append(candidate)
            if let numbered { numberedCounts[candidate.edition + "|" + numbered, default: []].insert(base) }
            if let prefix { prefixCounts[candidate.edition + "|" + prefix, default: []].insert(base) }
        }
        var buckets: [String: [Candidate]] = [:]
        for candidate in candidates {
            let base: String
            if let slot = candidate.slot { base = slot }
            else if let numbered = candidate.numbered, (numberedCounts[candidate.edition + "|" + numbered, default: []].count >= 2 || placements["names.v1." + StableID.hash(candidate.edition + "|" + numbered)]?.family == true) { base = numbered }
            else if let prefix = candidate.prefix, (prefixCounts[candidate.edition + "|" + prefix, default: []].count >= 2 || placements["names.v1." + StableID.hash(candidate.edition + "|" + prefix)]?.family == true) { base = prefix }
            else { base = candidate.base }
            // Empty names are not reliable evidence for combining streams.
            let identity = base.isEmpty ? candidate.channel.id : base
            buckets[candidate.edition + "|" + identity, default: []].append(candidate)
        }
        var groups: [CatalogNameGroup] = [], channelGroup: [String: String] = [:], paths: [String: [String]] = [:]
        var taxonomy = GroupTaxonomy(paths: GroupTaxonomy.seedPaths)
        for (identity, members) in buckets {
            try Task.checkCancellation()
            let first = members[0], id = "names.v1." + StableID.hash(identity)
            let base = identity.components(separatedBy: "|").last ?? first.base
            let originalWords = GroupNames.clean(first.channel.name).components(separatedBy: CharacterSet.alphanumerics.inverted)
            let name = base.split(separator: " ").map { word -> String in
                if let original = originalWords.first(where: { GroupNames.normalized($0) == word }), original == original.uppercased() { return original }
                return word.capitalized
            }.joined(separator: " ")
            let categories = Set(members.map { $0.details.category })
            let sports = Set(members.compactMap { $0.details.sport })
            var local: [String] = []
            if categories.count == 1, let category = categories.first, category != "Unsorted" {
                local = [category]
                if category == "Sports", sports.count == 1, let sport = sports.first { local.append(sport.title) }
            }
            let labelWords = name.split(separator: " ").map(String.init).filter {
                let normalized = GroupNames.normalized($0)
                return !GroupNames.regions.contains(normalized) && !GroupNames.coverageFormatting.contains(normalized)
            }
            let label = labelWords.joined(separator: " ")
            if local.count == 2, members.count > 1, labelWords.count <= 2,
               label.count <= 24, !label.contains(where: \.isNumber),
               !local.contains(where: { GroupNames.normalized($0) == GroupNames.normalized(label) }), GroupNames.validLabel(label) {
                local.append(label)
            }
            let providers = Array(Set(members.map { GroupNames.clean($0.channel.group) })).sorted()
            let fingerprint = StableID.hash(identity + "|" + providers.map(GroupNames.normalized).joined(separator: "|"))
            let group = CatalogNameGroup(id: id, name: name, fingerprint: fingerprint,
                channelIDs: members.map { $0.channel.id }.sorted(), titles: Array(Set(members.map { GroupNames.clean($0.channel.name) })).sorted(),
                providerGroups: providers, language: first.details.language, region: first.details.region, localPath: local,
                family: members.contains { $0.slot == base || $0.numbered == base || $0.prefix == base })
            groups.append(group)
            let placement = placements[id]
            let path = taxonomy.canonical(placement?.applies(to: group) == true ? placement!.path : local)
            taxonomy.add(path); paths[id] = path
            for member in members { channelGroup[member.channel.id] = id }
        }
        self.groups = groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        byID = Dictionary(uniqueKeysWithValues: self.groups.map { ($0.id, $0) })
        self.channelGroup = channelGroup; self.placements = placements; self.paths = paths; self.taxonomy = taxonomy
    }
    public func path(for channelID: String) -> [String] { channelGroup[channelID].flatMap { paths[$0] } ?? [] }
    public func pending(in audience: ChannelAudience) -> [CatalogNameGroup] {
        groups.filter { group in
            audience.includes(language: group.language, region: group.region) &&
            placements[group.id]?.isReusable(for: group) != true
        }
    }
    public static func savedPlacements(_ values: [String: Data]) -> [String: GroupPlacement] {
        let decoder = JSONDecoder()
        return values.filter { $0.key.hasPrefix("taxonomy.placement.") }.values.reduce(into: [:]) { result, data in
            if let placement = try? decoder.decode(GroupPlacement.self, from: data) { result[placement.id] = placement }
        }
    }
}
