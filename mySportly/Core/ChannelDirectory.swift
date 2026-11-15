import Foundation

public struct ChannelBrowseRequest: Hashable, Sendable {
    public var query = ""
    public var category = "All"
    public var includeHidden = false
    public var favoritesOnly = false
    public var collapseVariants = false
    public var sportsOnly = false
    public var sport: ChannelSport? = nil
    public var providerGroup: String? = nil
    public var taxonomyPath: [String]? = nil
    public var nameGroupID: String? = nil
    public var preferredLanguagesOnly = false
    public var ranked = false
    public var excludeInactive = false
    public var audience = ChannelAudience()
    public init() {}
}

/// A value snapshot for channel-only screens. Never decode personal records,
/// sort a catalog, or normalize thousands of names in a SwiftUI body.
public struct ChannelDirectory: Sendable {
    private struct Entry: Sendable {
        var channel: Channel
        var name: String
        var text: String
        var category: String
        var language: String
        var region: String
        var hidden: Bool
        var favorite: Bool
        var representative: Bool
        var inactive: Bool
    }
    private let entries: [Entry]
    public let categories: [String]
    public let visibleCategories: [String]
    public let sourceCounts: [UUID: Int]
    public let channels: [Channel]
    public let lineup: [Channel]
    public let favorites: [Channel]
    public let metadata: [String: ChannelMetadata]
    private let providerLabels: [String: String]
    public let nameGroups: CatalogGroupIndex

    /// `resolvedMetadata` is the raw `ChannelMetadataResolver` output for these
    /// channels (see `PreparedStages`); channels missing from it are resolved here.
    public init(channels: [Channel], overrides: [String: Data] = [:], resolvedMetadata: [String: ChannelMetadata] = [:]) throws {
        let decoder = JSONDecoder()
        func value<T: Decodable>(_ channel: Channel, _ field: String, _ fallback: T) -> T {
            guard let data = overrides["channel.\(channel.id).\(field)"] else { return fallback }
            return (try? decoder.decode(T.self, from: data)) ?? fallback
        }
        var seenIDs = Set<String>()
        var sortable: [(channel: Channel, name: String, order: Int)] = []
        for (position, channel) in channels.enumerated() {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            guard seenIDs.insert(channel.id).inserted else { continue }
            let custom = value(channel, "name", "")
            sortable.append((channel, custom.isEmpty ? channel.name : custom, value(channel, "order", Int.max)))
        }
        sortable.sort {
            if $0.order != $1.order { return $0.order < $1.order }
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.channel.id < $1.channel.id : comparison == .orderedAscending
        }
        try Task.checkCancellation()
        var variants = Set<String>()
        var resolver = ChannelMetadataResolver()
        var metadata: [String: ChannelMetadata] = [:]
        var providerLabels: [String: String] = [:]
        var entries: [Entry] = []
        entries.reserveCapacity(sortable.count)
        for (position, item) in sortable.enumerated() {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            let channel = item.channel
            let hidden = value(channel, "hidden", false)
            let group = value(channel, "variants", [channel.id]).sorted().joined(separator: "|")
            let representative = !hidden && variants.insert(group).inserted
            var details = resolvedMetadata[channel.id] ?? resolver.resolve(channel)
            details.category = value(channel, "category", details.category)
            if details.category != ChannelCategory.sports.rawValue { details.sport = nil }
            details.language = LocalePreferences.languageCode(value(channel, "language", details.language))
            details.region = LocalePreferences.regionCode(value(channel, "region", details.region))
            metadata[channel.id] = details
            if let sport = details.sport {
                providerLabels[channel.id] = ProviderChannelLabel.resolve(name: item.name, group: channel.group, region: details.region, sport: sport)
            }
            entries.append(Entry(channel: channel, name: item.name, text: Self.fold(item.name + " " + details.category + " " + channel.group), category: details.category,
                language: details.language, region: details.region,
                hidden: hidden, favorite: value(channel, "favorite", false), representative: representative, inactive: ListingAvailability.isInactiveChannel(channel.name)))
        }
        let nameGroups = try CatalogGroupIndex(channels: entries.map(\.channel), metadata: metadata, placements: CatalogGroupIndex.savedPlacements(overrides))
        for position in entries.indices {
            let channel = entries[position].channel
            guard !value(channel, "manual.category", false),
                  let groupID = nameGroups.channelGroup[channel.id], let group = nameGroups.byID[groupID],
                  let placement = nameGroups.placements[groupID], placement.applies(to: group),
                  let category = nameGroups.paths[groupID]?.first else { continue }
            entries[position].category = category
            entries[position].text = Self.fold(entries[position].name + " " + channel.group + " " + placement.path.joined(separator: " "))
            metadata[channel.id]?.category = category
            metadata[channel.id]?.sport = category == "Sports" ? ChannelSport.allCases.first { (nameGroups.paths[groupID] ?? []).dropFirst().contains($0.title) } : nil
        }
        self.nameGroups = nameGroups
        self.entries = entries
        self.metadata = metadata
        self.providerLabels = providerLabels
        self.channels = entries.map(\.channel)
        self.lineup = entries.filter(\.representative).map(\.channel)
        self.favorites = entries.filter { $0.favorite && !$0.hidden }.map(\.channel)
        self.categories = Array(Set(entries.map(\.category))).sorted()
        self.visibleCategories = Array(Set(entries.filter(\.representative).map(\.category))).sorted()
        self.sourceCounts = entries.reduce(into: [:]) { $0[$1.channel.sourceID, default: 0] += 1 }
    }

    public func browse(_ request: ChannelBrowseRequest, preferences: RecommendationPreferences? = nil) throws -> [Channel] {
        let query = Self.fold(request.query.trimmingCharacters(in: .whitespacesAndNewlines))
        var matches: [(channel: Channel, score: Int, position: Int)] = []
        for (position, entry) in entries.enumerated() {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            guard (request.includeHidden || !entry.hidden), (!request.collapseVariants || entry.representative),
                  (!request.excludeInactive || !entry.inactive),
                  (!request.favoritesOnly || entry.favorite), (request.category == "All" || entry.category == request.category),
                  (!request.sportsOnly || entry.category.localizedCaseInsensitiveContains("sport")),
                  (request.sport == nil || metadata[entry.channel.id]?.sport == request.sport),
                  (request.providerGroup == nil || providerLabels[entry.channel.id] == request.providerGroup),
                  (request.nameGroupID == nil || nameGroups.channelGroup[entry.channel.id] == request.nameGroupID),
                  (request.taxonomyPath == nil || taxonomyPath(for: entry.channel.id).starts(with: request.taxonomyPath!)),
                  request.audience.includes(language: entry.language, region: entry.region),
                  (query.isEmpty || entry.text.contains(query)) else { continue }
            if request.preferredLanguagesOnly && !entry.favorite && !entry.language.isEmpty && !(preferences?.languages.contains(entry.language) ?? false) { continue }
            var score = 0
            if request.ranked, let preferences {
                score = entry.favorite ? 1000 : 0
                if let index = preferences.languages.firstIndex(of: entry.language) { score += max(1, 20 - index) }
                if preferences.regions.contains(entry.region) { score += 10 }
                if preferences.interests.contains(entry.category) { score += 5 }
                if preferences.watched.contains(entry.channel.id) { score += 2 }
            }
            matches.append((entry.channel, score, position))
        }
        if request.ranked { matches.sort { $0.score == $1.score ? $0.position < $1.position : $0.score > $1.score } }
        try Task.checkCancellation()
        return matches.map(\.channel)
    }

    public var visibleNames: [(id: String, name: String)] { entries.filter { !$0.hidden }.map { ($0.channel.id, $0.name) } }
    public func categories(for channels: [Channel]) -> [String] { Array(Set(channels.compactMap { metadata[$0.id]?.category })).sorted() }
    public func groupedSports(in channels: [Channel], minimumCount: Int = 2) throws -> (groups: [SportChannelGroup], remaining: [Channel]) {
        var counts: [ChannelSport: Int] = [:]
        for (position, channel) in channels.enumerated() {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            if let sport = metadata[channel.id]?.sport { counts[sport, default: 0] += 1 }
        }
        let grouped = Set(counts.filter { $0.value >= minimumCount }.map(\.key))
        let groups = grouped.map { SportChannelGroup(sport: $0, count: counts[$0, default: 0]) }
            .sorted { $0.sport.title.localizedStandardCompare($1.sport.title) == .orderedAscending }
        let remaining = channels.filter { channel in
            guard let sport = metadata[channel.id]?.sport else { return true }
            return !grouped.contains(sport)
        }
        try Task.checkCancellation()
        return (groups, remaining)
    }
    public func groupedProviderLabels(in channels: [Channel]) throws -> (groups: [ProviderChannelGroup], remaining: [Channel]) {
        var counts: [String: Int] = [:]
        for (position, channel) in channels.enumerated() {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            if let label = providerLabels[channel.id] { counts[label, default: 0] += 1 }
        }
        let labels = Set(counts.filter { $0.value >= 2 }.map(\.key))
        let remaining = channels.filter { !labels.contains(providerLabels[$0.id] ?? "") }
        // One folder containing the entire screen adds a tap without reducing
        // scrolling. Keep those feeds directly visible instead.
        guard labels.count > 1 || (!labels.isEmpty && !remaining.isEmpty) else { return ([], channels) }
        let groups = labels.sorted().map { ProviderChannelGroup(label: $0, count: counts[$0, default: 0]) }
        try Task.checkCancellation()
        return (groups, remaining)
    }
    public func homeCategories(in channels: [Channel], interests: [String]) throws -> [CategoryChannelGroup] {
        let categories = Dictionary(grouping: channels) { metadata[$0.id]?.category ?? ChannelCategory.unknown.rawValue }
        let interests = Set(interests)
        return try categories.map { category, channels in
            try Task.checkCancellation()
            let interested = interests.contains(category)
            let sports = interested && category == ChannelCategory.sports.rawValue ? try groupedSports(in: channels) : (groups: [], remaining: channels)
            let children = interested ? try groupedTaxonomy(in: channels, under: [category]) : (groups: [], remaining: channels)
            return CategoryChannelGroup(category: category, count: channels.count, interested: interested,
                preview: interested ? Array(children.remaining.prefix(5)) : [], sports: sports.groups, subcategories: children.groups)
        }.sorted {
            if $0.interested != $1.interested { return $0.interested }
            return $0.category.localizedStandardCompare($1.category) == .orderedAscending
        }
    }
    private static func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
}

public struct PreparedCatalog: Sendable {
    public let directory: ChannelDirectory
    public let channelsByID: [String: Channel]
    public let guide: [String: [GuideProgram]]
    public let guideIDs: [UUID: [String]]
    public let guideMappings: GuideMappingResolver
    public let playbackAlternatives: [String: [String]]
    public let query: CatalogQueryIndex
    /// Set when any stage was recomputed instead of reused; save it for next time.
    public let freshStages: PreparedStages?

    public init(channels: [Channel], programs: [GuideProgram], activeSources: Set<UUID>, overrides: [String: Data], guideChannels: [GuideChannel] = [], stages: PreparedStages? = nil) throws {
        let active = channels.filter { activeSources.contains($0.sourceID) }
        let metadataFingerprint = PreparedStages.metadataFingerprint(active)
        let reuseMetadata = stages?.metadataFingerprint == metadataFingerprint
        let resolved = try reuseMetadata ? stages?.metadata ?? [:] : PreparedStages.resolveMetadata(active)
        directory = try ChannelDirectory(channels: active, overrides: overrides, resolvedMetadata: resolved)
        channelsByID = Dictionary(uniqueKeysWithValues: directory.channels.map { ($0.id, $0) })
        var guide: [String: [GuideProgram]] = [:]
        var ids: [UUID: Set<String>] = [:]
        for (position, program) in programs.enumerated() where activeSources.contains(program.sourceID) {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            guide[program.sourceID.uuidString + "|" + program.guideID, default: []].append(program)
            ids[program.sourceID, default: []].insert(program.guideID)
        }
        for key in guide.keys { try Task.checkCancellation(); guide[key]?.sort { $0.start < $1.start } }
        self.guide = guide
        self.guideIDs = ids.mapValues { $0.sorted() }
        let guideFingerprint = PreparedStages.guideFingerprint(channels: directory.channels, metadata: directory.metadata, guideIDs: self.guideIDs, guideChannels: guideChannels)
        let reuseGuide = stages?.guideFingerprint == guideFingerprint
        if reuseGuide, let stages {
            guideMappings = GuideMappingResolver(matches: stages.guideMatches, ambiguous: stages.ambiguousGuideMatches)
        } else {
            guideMappings = try GuideMappingResolver(channels: directory.channels, guideIDs: self.guideIDs, guideChannels: guideChannels, metadata: directory.metadata)
        }
        freshStages = reuseMetadata && reuseGuide ? nil : PreparedStages(metadataFingerprint: metadataFingerprint, metadata: resolved, guideFingerprint: guideFingerprint,
                                                                        guideMatches: guideMappings.matches, ambiguousGuideMatches: guideMappings.ambiguous)
        playbackAlternatives = PlaybackAlternatives.groups(directory.lineup)
        query = try CatalogQueryIndex(channels: directory.lineup, programs: programs, overrides: overrides, metadata: directory.metadata, guideMatches: guideMappings.matches)
    }
}

/// Keep the outgoing snapshot alive through UI publication, then release its
/// large arrays on an actor executor. Destructing an old 200k-program search
/// index on the main actor can itself drop frames even after computation moved.
public actor CatalogSnapshotLifetime {
    private var held: PreparedCatalog?
    private var revision = -1
    public init() {}
    public func retain(_ snapshot: PreparedCatalog, revision: Int) {
        guard revision > self.revision else { return }
        self.revision = revision
        held = snapshot
    }
}
