import Foundation

/// The small slice of a prepared catalog that the first screen needs:
/// favorites, recently watched, the feeds of Home's games, and the head of the
/// lineup, with their listings for the next day, plus Home's games. It is read before the full catalog on launch.
/// Channels carry stream URLs, so the file must be stored sealed.
public struct LaunchSnapshot: Codable, Sendable {
    public static let channelLimit = 300
    public static let window: TimeInterval = 24 * 3600

    public var createdAt: Date
    public var channels: [Channel]
    public var favoriteIDs: [String]
    public var lineupIDs: [String]
    public var guide: [String: [GuideProgram]]
    public var guideMatches: [String: GuideMatch]
    /// Home's games with their feed links. Absent in files from older builds.
    public var sports: HomeSportsData?

    public init(prepared: PreparedCatalog, recentIDs: [String], manualGuideIDs: [String: String] = [:], now: Date) {
        self.init(favorites: prepared.directory.favorites, recentIDs: recentIDs, lineup: prepared.directory.lineup, channelsByID: prepared.channelsByID,
                  guide: prepared.guide, guideMatches: prepared.guideMappings.matches, manualGuideIDs: manualGuideIDs, now: now)
    }

    /// Channels in priority order: favorites, recents, the feeds of Home's
    /// games, then the head of the lineup.
    public init(favorites: [Channel], recentIDs: [String], lineup: [Channel], channelsByID: [String: Channel], guide fullGuide: [String: [GuideProgram]],
                guideMatches matches: [String: GuideMatch], manualGuideIDs: [String: String] = [:], sports: HomeSportsData? = nil, now: Date) {
        var seen = Set<String>(), chosen: [Channel] = []
        func add(_ channel: Channel?) {
            guard let channel, chosen.count < Self.channelLimit, seen.insert(channel.id).inserted else { return }
            chosen.append(channel)
        }
        favorites.forEach(add)
        recentIDs.forEach { add(channelsByID[$0]) }
        if let sports {
            for game in sports.games.sorted(by: { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }) {
                for link in sports.links[game.id] ?? [] where link.validUntil > now { add(channelsByID[link.channelID]) }
            }
        }
        for channel in lineup where chosen.count < Self.channelLimit { add(channel) }

        var guide: [String: [GuideProgram]] = [:], kept: [String: GuideMatch] = [:]
        let end = now + Self.window
        for channel in chosen {
            if let match = matches[channel.id] { kept[channel.id] = match }
            for guideID in Set([manualGuideIDs[channel.id], matches[channel.id]?.guideID, channel.guideID].compactMap { $0 }) where !guideID.isEmpty {
                let key = channel.sourceID.uuidString + "|" + guideID
                guard guide[key] == nil, let programs = fullGuide[key] else { continue }
                let upcoming = programs.filter { $0.end > now && $0.start < end }
                if !upcoming.isEmpty { guide[key] = upcoming }
            }
        }
        createdAt = now
        channels = chosen
        favoriteIDs = favorites.map(\.id).filter(seen.contains)
        lineupIDs = lineup.map(\.id).filter(seen.contains)
        self.guide = guide
        guideMatches = kept
        self.sports = sports.map { Self.keepingLinks(in: $0, to: seen) }
    }

    static func keepingLinks(in sports: HomeSportsData, to channelIDs: Set<String>) -> HomeSportsData {
        var copy = sports
        copy.links = sports.links.compactMapValues { links in
            let kept = links.filter { channelIDs.contains($0.channelID) }
            return kept.isEmpty ? nil : kept
        }
        return copy
    }

    /// Drops channels from sources that no longer exist and listings that ended.
    public func active(sources: Set<UUID>, now: Date) -> LaunchSnapshot {
        var copy = self
        copy.channels = channels.filter { sources.contains($0.sourceID) }
        let ids = Set(copy.channels.map(\.id))
        copy.favoriteIDs = favoriteIDs.filter(ids.contains)
        copy.lineupIDs = lineupIDs.filter(ids.contains)
        copy.guideMatches = guideMatches.filter { ids.contains($0.key) }
        let prefixes = Set(sources.map(\.uuidString))
        copy.guide = guide.compactMapValues { programs in
            let live = programs.filter { $0.end > now }
            return live.isEmpty ? nil : live
        }.filter { key, _ in prefixes.contains(String(key.prefix { $0 != "|" })) }
        if var sports {
            sports.games.removeAll { $0.homeState(at: now) == nil }
            let games = Set(sports.games.map(\.id))
            sports.links = sports.links.filter { games.contains($0.key) }
            copy.sports = Self.keepingLinks(in: sports, to: ids)
        }
        return copy
    }
}
