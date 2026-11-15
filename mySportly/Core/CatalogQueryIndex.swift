import Foundation

public struct CatalogMatch: Identifiable, Sendable {
    public let channel: Channel
    public let name: String
    public let program: GuideProgram?
    public var id: String { channel.id }
}

public struct SportsEvent: Identifiable, Sendable {
    public let channel: Channel
    public let channelName: String
    public let program: GuideProgram
    public var followedNames: [String] = []
    public var id: String { program.sourceID.uuidString + "|" + program.id }
}

public struct FollowedSportsChannel: Identifiable, Sendable {
    public let channel: Channel
    public let names: [String]
    public var id: String { channel.id }
}

public struct SportsSchedule: Sendable {
    public var live: [SportsEvent] = []
    public var upcoming: [SportsEvent] = []
    public var channelsWithoutListings: [FollowedSportsChannel] = []
    public init() {}
    public var isEmpty: Bool { live.isEmpty && upcoming.isEmpty }
}

public struct CatalogSearchRequest: Sendable {
    public var keywords: [String]
    public var start: Date
    public var end: Date
    public var sportsOnly: Bool
    public var favoritesOnly: Bool
    public var language: String
    public var audience: ChannelAudience
    public init(keywords: [String], start: Date, end: Date, sportsOnly: Bool = false, favoritesOnly: Bool = false, language: String = "", audience: ChannelAudience = .init()) {
        self.keywords = keywords; self.start = start; self.end = end
        self.sportsOnly = sportsOnly; self.favoritesOnly = favoritesOnly; self.language = language
        self.audience = audience
    }
}

public struct GuideCoverage: Sendable {
    public var channels = 0
    public var matched = 0
    public var onNow = 0
    public var missingID = 0
    public var unmatchedID = 0
    public var noUpcoming = 0
    public var unknownLanguage = 0
    public var automatic = 0
    public init() {}
}

public struct RecommendationPreferences: Sendable {
    public var languages: [String]
    public var regions: [String]
    public var interests: [String]
    public var following: [String]
    public var watched: Set<String>
    public init(languages: [String], regions: [String], interests: [String], following: [String], watched: Set<String>) {
        self.languages = languages; self.regions = regions; self.interests = interests; self.following = following; self.watched = watched
    }
}

public struct ChannelRecommendation: Identifiable, Sendable {
    public let channel: Channel
    public let name: String
    public let reasons: [String]
    public var id: String { channel.id }
}

/// An immutable, local index shared by browsing tasks. Build and query it off the
/// main actor. Guide titles and sports classification are computed once per
/// program, even when hundreds of channel variants share the same guide.
public struct CatalogQueryIndex: Sendable {
    private struct GuideKey: Hashable, Sendable { let source: UUID; let id: String }
    private struct GuideReference: Hashable, Sendable { let key: GuideKey; let offset: Int }
    private struct Program: Sendable {
        let value: GuideProgram
        let text: String
        let sports: Bool
        let placeholder: Bool
    }
    private struct Entry: Sendable {
        let channel: Channel
        let name: String
        let text: String
        let category: String
        let sports: Bool
        let favorite: Bool
        let language: String
        let region: String
        let guide: GuideReference
        let inactive: Bool
        let automatic: Bool
    }
    private let entries: [Entry]
    private let programs: [GuideKey: [Program]]
    private let sportsSources: [GuideReference: [Int]]
    public var channelCount: Int { entries.count }

    /// Channels arrive in the user's chosen order, already excluding hidden
    /// channels and collapsed variants. Overrides are a value snapshot, never a
    /// SwiftData context or Keychain credentials.
    public init(channels: [Channel], programs: [GuideProgram], overrides: [String: Data] = [:], metadata: [String: ChannelMetadata] = [:], guideMatches: [String: GuideMatch] = [:]) throws {
        let decoder = JSONDecoder()
        func value<T: Decodable>(_ channel: Channel, _ field: String, _ fallback: T) -> T {
            guard let data = overrides["channel.\(channel.id).\(field)"] else { return fallback }
            return (try? decoder.decode(T.self, from: data)) ?? fallback
        }
        var entries: [Entry] = []
        entries.reserveCapacity(channels.count)
        var sources: [GuideReference: [Int]] = [:]
        var resolver = ChannelMetadataResolver()
        var guideKeys = Set<GuideKey>()
        for (position, channel) in channels.enumerated() {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            let custom = value(channel, "name", "")
            let name = custom.isEmpty ? channel.name : custom
            let details = metadata[channel.id] ?? resolver.resolve(channel)
            let category = value(channel, "category", details.category)
            let guide = GuideReference(key: GuideKey(source: channel.sourceID, id: value(channel, "guideID", guideMatches[channel.id]?.guideID ?? channel.guideID)), offset: value(channel, "guideOffset", 0))
            let sports = Self.fold(category).contains("sport")
            entries.append(Entry(channel: channel, name: name, text: Self.fold(name + " " + category + " " + channel.group), category: Self.fold(category), sports: sports,
                favorite: value(channel, "favorite", false), language: LocalePreferences.languageCode(value(channel, "language", details.language)), region: LocalePreferences.regionCode(value(channel, "region", details.region)), guide: guide, inactive: ListingAvailability.isInactiveChannel(channel.name), automatic: guideMatches[channel.id] != nil && overrides["channel.\(channel.id).guideID"] == nil))
            if !guide.key.id.isEmpty {
                guideKeys.insert(guide.key)
                sources[guide, default: []].append(position)
            }
        }
        var schedules: [GuideKey: [Program]] = [:]
        for (position, program) in programs.enumerated() {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            let key = GuideKey(source: program.sourceID, id: program.guideID)
            guard guideKeys.contains(key) else { continue }
            schedules[key, default: []].append(Program(value: program, text: Self.fold(program.title), sports: program.isSports, placeholder: ListingAvailability.isPlaceholderProgram(program.title)))
        }
        for key in schedules.keys {
            try Task.checkCancellation()
            schedules[key]?.sort { $0.value.start == $1.value.start ? $0.value.id < $1.value.id : $0.value.start < $1.value.start }
        }
        self.entries = entries; self.programs = schedules; self.sportsSources = sources
    }

    public func search(_ request: CatalogSearchRequest) throws -> [CatalogMatch] {
        let keywords = request.keywords.map(Self.fold).filter { !$0.isEmpty }
        var windows: [GuideReference: [Program]] = [:]
        var matches: [CatalogMatch] = []
        for (position, entry) in entries.enumerated() {
            if position.isMultiple(of: 128) { try Task.checkCancellation() }
            guard request.audience.includes(language: entry.language, region: entry.region) else { continue }
            if request.favoritesOnly && !entry.favorite { continue }
            if !request.language.isEmpty && entry.language != request.language { continue }
            let schedule: [Program]
            if let cached = windows[entry.guide] { schedule = cached }
            else {
                schedule = window(entry.guide, start: request.start, end: request.end)
                windows[entry.guide] = schedule
            }
            if request.sportsOnly && !entry.sports && !schedule.contains(where: \.sports) { continue }
            let missing = keywords.filter { !entry.text.contains($0) }
            guard missing.allSatisfy({ word in schedule.contains { $0.text.contains(word) } }) else { continue }
            let program = schedule.first { program in
                (!request.sportsOnly || entry.sports || program.sports) && missing.allSatisfy { program.text.contains($0) }
            }
            matches.append(CatalogMatch(channel: entry.channel, name: entry.name, program: program.map { shifted($0.value, by: entry.guide.offset) }))
        }
        try Task.checkCancellation()
        return matches
    }

    public func sports(at date: Date, following: [String] = [], followedOnly: Bool = false, audience: ChannelAudience = .init(), until: Date? = nil, includeUnscheduledChannels: Bool = true) throws -> SportsSchedule {
        let followed = SportsFollowMatcher(following)
        if followedOnly && followed.isEmpty { return SportsSchedule() }
        var unique: [String: (event: SportsEvent, order: Int)] = [:]
        for (guide, candidates) in sportsSources {
            try Task.checkCancellation()
            let eligible = candidates.filter { !entries[$0].inactive && audience.includes(language: entries[$0].language, region: entries[$0].region) }
            guard let first = eligible.first else { continue }
            let sports = eligible.first { entries[$0].sports }
            for program in window(guide, start: date, end: until ?? date.addingTimeInterval(48 * 3600)) {
                guard !program.placeholder else { continue }
                guard program.sports || sports != nil else { continue }
                let order = program.sports ? first : sports!
                let entry = entries[order]
                let names = followed.isEmpty ? [] : followed.matches(text: program.value.title + " " + program.value.summary, context: program.value.categories.joined(separator: " ") + " " + entry.channel.group + " " + entry.name)
                if followedOnly && names.isEmpty { continue }
                let event = SportsEvent(channel: entry.channel, channelName: entry.name, program: shifted(program.value, by: guide.offset), followedNames: names)
                // Deduplicate before sorting, including feeds with different time offsets.
                if let old = unique[event.id], old.event.program.start < event.program.start ||
                    (old.event.program.start == event.program.start && old.order <= order) { continue }
                unique[event.id] = (event, order)
            }
        }
        let ordered = unique.values.sorted { a, b in
            if a.event.program.start != b.event.program.start { return a.event.program.start < b.event.program.start }
            if a.order != b.order { return a.order < b.order }
            return a.event.id < b.event.id
        }
        try Task.checkCancellation()
        var result = SportsSchedule()
        for item in ordered {
            if item.event.program.isLive(at: date) { result.live.append(item.event) }
            else if item.event.program.start > date { result.upcoming.append(item.event) }
        }
        if followedOnly && includeUnscheduledChannels {
            for (position, entry) in entries.enumerated() {
                if position.isMultiple(of: 256) { try Task.checkCancellation() }
                guard !entry.inactive, audience.includes(language: entry.language, region: entry.region),
                      window(entry.guide, start: date, end: date + 48 * 3600).allSatisfy(\.placeholder) else { continue }
                let names = followed.matches(text: entry.name, context: entry.channel.group)
                if !names.isEmpty { result.channelsWithoutListings.append(FollowedSportsChannel(channel: entry.channel, names: names)) }
            }
        }
        return result
    }

    public func recommendations(at date: Date, preferences: RecommendationPreferences, audience: ChannelAudience = .init()) throws -> [ChannelRecommendation] {
        var windows: [GuideReference: [Program]] = [:]
        let interests = preferences.interests.map(Self.fold)
        let following = SportsFollowMatcher(preferences.following)
        var followedGuides: [GuideReference: [String]] = [:]
        var bestByGuide: [GuideReference: ChannelRecommendation] = [:]
        func precedes(_ a: ChannelRecommendation, _ b: ChannelRecommendation) -> Bool {
            let aFollowed = a.reasons.contains { $0.hasPrefix("Following:") }, bFollowed = b.reasons.contains { $0.hasPrefix("Following:") }
            if aFollowed != bFollowed { return aFollowed }
            if a.reasons.count != b.reasons.count { return a.reasons.count > b.reasons.count }
            if a.name != b.name { return a.name < b.name }
            return a.id < b.id
        }
        for (position, entry) in entries.enumerated() {
            if position.isMultiple(of: 128) { try Task.checkCancellation() }
            guard !entry.inactive, audience.includes(language: entry.language, region: entry.region) else { continue }
            let schedule: [Program]
            if let cached = windows[entry.guide] { schedule = cached }
            else {
                schedule = window(entry.guide, start: date, end: date.addingTimeInterval(0.001))
                windows[entry.guide] = schedule
            }
            guard let program = schedule.first(where: { !$0.placeholder }), shifted(program.value, by: entry.guide.offset).isLive(at: date) else { continue }
            var reasons: [String] = []
            if entry.favorite { reasons.append("One of your favorites") }
            if preferences.languages.contains(entry.language) { reasons.append("Preferred language") }
            if preferences.regions.contains(entry.region) { reasons.append("Preferred region") }
            if interests.contains(where: { entry.category.contains($0) }) { reasons.append("Matches your interests") }
            if !following.isEmpty, program.sports || entry.sports {
                let names: [String]
                if let cached = followedGuides[entry.guide] { names = cached }
                else {
                    names = following.matches(text: program.value.title + " " + program.value.summary, context: program.value.categories.joined(separator: " ") + " " + entry.channel.group + " " + entry.name)
                    followedGuides[entry.guide] = names
                }
                if !names.isEmpty { reasons.insert("Following: " + names.joined(separator: ", "), at: 0) }
            }
            if preferences.watched.contains(entry.channel.id) { reasons.append("Recently watched") }
            guard !reasons.isEmpty else { continue }
            let candidate = ChannelRecommendation(channel: entry.channel, name: entry.name, reasons: reasons)
            if let previous = bestByGuide[entry.guide], !precedes(candidate, previous) { continue }
            bestByGuide[entry.guide] = candidate
        }
        return Array(bestByGuide.values.sorted(by: precedes).prefix(10))
    }

    /// Matchup-looking sports listings in the next `GameDetection.horizon`
    /// that local parsing can't resolve, one per title and summary.
    public func unresolvedGameListings(reference: SportsDataIndex, at date: Date, known: Set<String>) throws -> [GameListing] {
        let parser = GuideGameParser(reference: reference)
        var result: [String: GameListing] = [:]
        for (guide, positions) in sportsSources {
            try Task.checkCancellation()
            let eligible = positions.filter { !entries[$0].inactive }
            guard let first = eligible.first else { continue }
            let entry = entries[first]
            for program in window(guide, start: date, end: date + GameDetection.horizon) where !program.placeholder {
                let value = shifted(program.value, by: guide.offset)
                guard value.end > date, value.end.timeIntervalSince(value.start) <= 8 * 3600, !SportsGameMatcher.isReplayOrStudio(value.title) else { continue }
                let key = GameDetection.key(title: value.title, summary: value.summary)
                guard result[key] == nil, !known.contains(key) else { continue }
                let context = value.categories.joined(separator: " ") + " " + entry.channel.group + " " + entry.name
                let sports = program.sports || entry.sports
                guard parser.opponents(title: value.title, context: context) == nil,
                      !sports || parser.opponents(title: value.summary, context: value.title + " " + context) == nil else { continue }
                var candidates = parser.candidates(title: value.title, context: context)
                if candidates.isEmpty, sports { candidates = parser.candidates(title: value.summary, context: value.title + " " + context) }
                guard !candidates.isEmpty else { continue }
                result[key] = GameListing(key: key, title: value.title, summary: String(value.summary.prefix(400)), context: entry.name + " · " + entry.channel.group,
                                          candidates: candidates, end: value.end)
            }
        }
        return result.values.sorted { $0.key < $1.key }
    }

    /// `detected` holds model answers by `GameDetection.key`; they fill in only
    /// where local parsing found no opponents.
    public func guideGames(reference: SportsDataIndex, refreshed: [UUID: Date], at date: Date, timeZone: TimeZone = .current, detected: [String: [String]] = [:]) throws -> GuideGameMatches {
        struct Listing {
            let program: GuideProgram
            let teams: [SportsTeam]
            let positions: [Int]
        }
        let parser = GuideGameParser(reference: reference)
        var byOpponents: [String: [Listing]] = [:]
        for (guide, positions) in sportsSources {
            try Task.checkCancellation()
            let eligible = positions.filter { !entries[$0].inactive }
            guard let first = eligible.first else { continue }
            let entry = entries[first]
            for program in window(guide, start: date, end: date + 7 * 86400) where !program.placeholder {
                let value = shifted(program.value, by: guide.offset)
                guard value.end > value.start, value.end.timeIntervalSince(value.start) <= 8 * 3600,
                      !SportsGameMatcher.isReplayOrStudio(value.title) else { continue }
                let context = value.categories.joined(separator: " ") + " " + entry.channel.group + " " + entry.name
                // Generic titles such as "NFL Football" often put the matchup
                // in the description. Only use it for a sports listing.
                let teams = parser.opponents(title: value.title, context: context) ??
                    ((program.sports || entry.sports) ? parser.opponents(title: value.summary, context: value.title + " " + context) : nil) ??
                    detected[GameDetection.key(title: value.title, summary: value.summary)].flatMap { ids -> [SportsTeam]? in
                        let found = ids.compactMap { reference.teams[$0] }
                        return found.count == 2 && found[0].leagueID == found[1].leagueID ? found : nil
                    }
                guard let teams else { continue }
                let pair = teams.map(\.id).joined(separator: "|")
                byOpponents[pair, default: []].append(Listing(program: value, teams: teams, positions: eligible))
            }
        }
        var games: [SportsGame] = [], links: [String: [String: SportsFeedLink]] = [:]
        for (pair, listings) in byOpponents {
            try Task.checkCancellation()
            let ordered = listings.sorted { $0.program.start == $1.program.start ? $0.program.id < $1.program.id : $0.program.start < $1.program.start }
            var current: SportsGame?
            for listing in ordered {
                let program = listing.program
                // Broadcasts within 15 minutes share a game. A later doubleheader
                // gets its own identity and cannot inherit the earlier feeds.
                if current == nil || program.start.timeIntervalSince(current!.start) > 15 * 60 {
                    if let current { games.append(current) }
                    let id = "guide." + StableID.hash(pair + "|" + String(Int(program.start.timeIntervalSince1970 / 60)))
                    current = SportsGame(id: id, leagueID: listing.teams[0].leagueID, homeID: listing.teams[0].id, awayID: listing.teams[1].id,
                        timestamp: program.start.timeIntervalSince1970, guideEnd: program.end.timeIntervalSince1970)
                }
                guard var game = current else { continue }
                game.guideEnd = max(game.guideEnd ?? 0, program.end.timeIntervalSince1970); current = game
                for position in listing.positions {
                    let channel = entries[position].channel
                    links[game.id, default: [:]][channel.id] = SportsFeedLink(gameID: game.id, channelID: channel.id,
                        programID: program.sourceID.uuidString + "|" + program.id, validFrom: program.start, validUntil: program.end, evidence: "TV guide")
                }
            }
            if let current { games.append(current) }
        }
        var catalog = reference.catalog; catalog.games = games
        let index = try SportsDataIndex(catalog), matcher = SportsGameMatcher(index: index)
        for (position, entry) in entries.enumerated() {
            if position.isMultiple(of: 128) { try Task.checkCancellation() }
            guard let game = matcher.matchChannel(name: entry.name, group: entry.channel.group, refreshed: refreshed[entry.channel.sourceID], at: date, timeZone: timeZone),
                  links[game.id]?[entry.channel.id] == nil,
                  window(entry.guide, start: game.start, end: game.start + 60).allSatisfy(\.placeholder) else { continue }
            links[game.id, default: [:]][entry.channel.id] = SportsFeedLink(gameID: game.id, channelID: entry.channel.id, programID: nil,
                validFrom: game.start, validUntil: min(game.start + 5 * 3600, Date(timeIntervalSince1970: game.guideEnd ?? 0)), evidence: "Channel name and guide time")
        }
        return GuideGameMatches(index: index, links: links.mapValues { $0.values.sorted { $0.channelID < $1.channelID } })
    }

    public func gameFeeds(index: SportsDataIndex, refreshed: [UUID: Date], at date: Date, timeZone: TimeZone = .current) throws -> [String: [SportsFeedLink]] {
        let matcher = SportsGameMatcher(index: index)
        var links: [String: [String: SportsFeedLink]] = [:]
        for (guide, positions) in sportsSources {
            try Task.checkCancellation()
            let eligible = positions.filter { !entries[$0].inactive }
            guard let first = eligible.first else { continue }
            let entry = entries[first]
            for program in window(guide, start: date - 8 * 3600, end: date + 7 * 86400) where !program.placeholder {
                let shifted = shifted(program.value, by: guide.offset)
                guard let game = matcher.match(title: shifted.title,
                    context: shifted.categories.joined(separator: " ") + " " + entry.channel.group + " " + entry.name,
                    start: shifted.start, end: shifted.end) else { continue }
                for position in eligible {
                    let channel = entries[position].channel
                    links[game.id, default: [:]][channel.id] = SportsFeedLink(gameID: game.id, channelID: channel.id,
                        programID: program.value.sourceID.uuidString + "|" + program.value.id,
                        validFrom: max(game.start - 30 * 60, shifted.start), validUntil: min(game.start + 8 * 3600, shifted.end), evidence: "TV guide")
                }
            }
        }
        for (position, entry) in entries.enumerated() {
            if position.isMultiple(of: 128) { try Task.checkCancellation() }
            guard let game = matcher.matchChannel(name: entry.name, group: entry.channel.group, refreshed: refreshed[entry.channel.sourceID], at: date, timeZone: timeZone),
                  links[game.id]?[entry.channel.id] == nil else { continue }
            // An explicit, conflicting guide is stronger than a reusable channel name.
            let actual = window(entry.guide, start: game.start, end: game.start + 60).filter { !$0.placeholder }
            guard actual.isEmpty else { continue }
            links[game.id, default: [:]][entry.channel.id] = SportsFeedLink(gameID: game.id, channelID: entry.channel.id, programID: nil,
                validFrom: game.start - 15 * 60, validUntil: game.start + 5 * 3600, evidence: "Channel name and start time")
        }
        return links.mapValues { $0.values.sorted { $0.channelID < $1.channelID } }
    }

    public func coverage(at date: Date, audience: ChannelAudience = .init()) throws -> GuideCoverage {
        var result = GuideCoverage()
        var status: [GuideReference: (matched: Bool, live: Bool, future: Bool)] = [:]
        for (position, entry) in entries.enumerated() {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            guard audience.includes(language: entry.language, region: entry.region) else { continue }
            result.channels += 1
            if entry.automatic { result.automatic += 1 }
            if entry.language.isEmpty { result.unknownLanguage += 1 }
            guard !entry.guide.key.id.isEmpty else { result.missingID += 1; continue }
            let state: (matched: Bool, live: Bool, future: Bool)
            if let cached = status[entry.guide] { state = cached }
            else {
                let listings = programs[entry.guide.key] ?? []
                let at = date - Double(entry.guide.offset) * 60
                state = (!listings.isEmpty, listings.contains { $0.value.isLive(at: at) }, listings.contains { $0.value.end > at })
                status[entry.guide] = state
            }
            if state.matched { result.matched += 1 } else { result.unmatchedID += 1 }
            if state.live { result.onNow += 1 }
            if state.matched && !state.future { result.noUpcoming += 1 }
        }
        return result
    }

    public func channelsWithListings(from start: Date, to end: Date) throws -> Set<String> {
        var status: [GuideReference: Bool] = [:]
        var result = Set<String>()
        for (position, entry) in entries.enumerated() {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            let hasListings: Bool
            if let cached = status[entry.guide] { hasListings = cached }
            else {
                hasListings = !window(entry.guide, start: start, end: end).isEmpty
                status[entry.guide] = hasListings
            }
            if hasListings { result.insert(entry.channel.id) }
        }
        return result
    }

    private func window(_ guide: GuideReference, start: Date, end: Date) -> [Program] {
        let offset = Double(guide.offset) * 60
        let from = start.addingTimeInterval(-offset), to = end.addingTimeInterval(-offset)
        return (programs[guide.key] ?? []).filter { $0.value.end > from && $0.value.start < to }
    }
    private func shifted(_ program: GuideProgram, by minutes: Int) -> GuideProgram {
        guard minutes != 0 else { return program }
        var result = program; result.start += Double(minutes) * 60; result.end += Double(minutes) * 60
        return result
    }
    private static func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
}

/// Detached CPU work must follow the owning view's cancellation. Otherwise each
/// keystroke leaves an obsolete full-catalog query running in the background.
public func catalogWork<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
    let worker = Task.detached(priority: .userInitiated, operation: operation)
    return try await withTaskCancellationHandler {
        try Task.checkCancellation()
        return try await worker.value
    } onCancel: { worker.cancel() }
}
